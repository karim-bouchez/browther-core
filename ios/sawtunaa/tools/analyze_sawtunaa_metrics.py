#!/usr/bin/env python3
"""
Sawtunaa metrics analyzer.

Parses [METRIC] {json} lines from a captured iOS device log and produces a
structured report covering:
- Pipeline lifecycle (script init, page reset, refresh, video changes,
  pause/resume, seek, init segment)
- Sessions (each page_reset starts a new session — refresh / SPA / etc.)
- NSNet2 processing performance
- Audio playback coverage and underruns
- Sync (video <-> audio) drift
- Engine/handler errors
- Anomalies (stale audio playing across refresh, cache not cleared, etc.)

Usage:
  python3 analyze_sawtunaa_metrics.py <log_file>
  python3 analyze_sawtunaa_metrics.py <log_file> --json   # raw JSON output
  python3 analyze_sawtunaa_metrics.py <log_file> --lifecycle   # full timeline
"""

import argparse
import json
import re
import statistics
import sys
from collections import Counter, defaultdict


METRIC_RE = re.compile(r"\[METRIC\]\s+(\{.*\})")


# Events that are part of the high-level lifecycle of a session.
LIFECYCLE_EVENTS = [
    # JS-side
    "script_init",
    "page_reset_sent",
    "pagehide",
    "pageshow",
    "visibility_change",
    "url_changed",
    "video_change_reset",
    "init_seg_content_change",
    "init_segment",
    "decoder_ready",
    "decoder_error",
    "auto_activate",
    "seek_detected",
    "video_paused",
    "video_resumed",
    "script_abort",
    # Swift-side
    "handler_init",
    "handler_create_player",
    "handler_page_reset",
    "handler_clear_chunks",
    "handler_activated",
    "handler_deinit",
    "model_load_start",
    "model_load_done",
    "engine_start",
    "engine_stop",
    "first_chunk_played",
    "clear_chunks",
    "seek_to",
    "pause_audio",
    "resume_audio",
]


def parse_log(path):
    events = []
    with open(path, "r", errors="replace") as f:
        for line in f:
            m = METRIC_RE.search(line)
            if not m:
                continue
            try:
                obj = json.loads(m.group(1))
                events.append(obj)
            except json.JSONDecodeError:
                continue
    return events


def percentile(values, p):
    if not values:
        return None
    s = sorted(values)
    k = (len(s) - 1) * (p / 100.0)
    f = int(k)
    c = min(f + 1, len(s) - 1)
    if f == c:
        return s[f]
    return s[f] + (s[c] - s[f]) * (k - f)


def stats(values, label="ms"):
    if not values:
        return "none"
    avg = statistics.mean(values)
    p50 = percentile(values, 50)
    p99 = percentile(values, 99)
    return (
        f"avg={avg:.0f}{label} p50={p50:.0f}{label} p99={p99:.0f}{label} "
        f"max={max(values)}{label} (n={len(values)})"
    )


def fmt_kvs(e, exclude=("t", "event", "src")):
    parts = []
    for k, v in e.items():
        if k in exclude:
            continue
        parts.append(f"{k}={v}")
    return " ".join(parts)


def split_sessions(events):
    """A session starts at the beginning of the run and at every handler_page_reset.
    Returns a list of (start_t, end_t, [events]).
    """
    sessions = []
    current_start = events[0]["t"] if events else 0
    current_events = []
    last_t = current_start
    for e in events:
        # handler_page_reset is the canonical session boundary on Swift side.
        # We use it (not page_reset_sent) so we count actual server-side resets.
        if e.get("event") == "handler_page_reset" and current_events:
            sessions.append((current_start, e["t"], current_events))
            current_start = e["t"]
            current_events = []
        current_events.append(e)
        last_t = e["t"]
    if current_events:
        sessions.append((current_start, last_t, current_events))
    return sessions


def session_label(idx, sess_events):
    # Try to extract URL or video id from the first script_init / page_reset_sent
    url = None
    for e in sess_events:
        if e.get("event") in ("script_init", "page_reset_sent", "handler_page_reset"):
            url = e.get("url") or e.get("data")
            if url:
                break
    label = f"Session {idx}"
    if url:
        # Compress youtube URLs
        m = re.search(r"v=([^&]+)", url)
        if m:
            label += f" [v={m.group(1)}]"
        else:
            label += f" [{url[:60]}{'...' if len(url) > 60 else ''}]"
    return label


def print_lifecycle(events, full=False):
    """Print every lifecycle event with timestamp + key details. If full=False,
    cap each event type to first 5 occurrences."""
    print("== Lifecycle ==")
    counter = Counter()
    last_t = -1
    for e in events:
        ev = e.get("event", "?")
        if ev not in LIFECYCLE_EVENTS:
            continue
        if not full and counter[ev] >= 10:
            continue
        counter[ev] += 1
        t = e["t"]
        gap = t - last_t if last_t >= 0 else 0
        last_t = t
        kvs = fmt_kvs(e)
        gap_str = f"(+{gap}ms)" if gap > 0 else "      "
        print(f"  T+{t:>7}ms {gap_str:<10} {ev:<25} {kvs}")
    skipped = {ev: c for ev, c in counter.items() if c >= 10}
    if skipped and not full:
        print(f"  (use --lifecycle to see all occurrences; capped types: {list(skipped.keys())})")
    print()


def analyze_session(idx, start_t, end_t, sess_events, label):
    duration = end_t - start_t
    print(f"-- {label}  T+{start_t/1000:.1f}s → T+{end_t/1000:.1f}s  ({duration/1000:.1f}s) --")
    by_event = defaultdict(list)
    for e in sess_events:
        by_event[e.get("event", "?")].append(e)

    # Activation latency
    if by_event.get("auto_activate") and by_event.get("first_chunk_played"):
        first_play = by_event["first_chunk_played"][0]["t"] - start_t
        activate_t = by_event["auto_activate"][0]["t"] - start_t
        print(f"  activation: T+{activate_t}ms  first_chunk_played: T+{first_play}ms")

    nsnet2_times = [e.get("nsnet2_ms", 0) for e in by_event.get("chunk_preprocess_done", [])]
    plays_full = by_event.get("chunk_play_full", [])
    plays_trim = by_event.get("chunk_play_trim", [])
    skipped = by_event.get("chunk_skip_old", [])
    audio_ms_played = sum(int(e.get("frames", 0)) / 48 for e in plays_full)
    audio_ms_played += sum(
        int(e.get("remaining_samples", e.get("frames", 0))) / 48 for e in plays_trim
    )
    coverage = (audio_ms_played / duration * 100) if duration > 0 else 0
    print(
        f"  chunks: {len(plays_full)} full, {len(plays_trim)} trimmed, "
        f"{len(skipped)} skipped → {audio_ms_played:.0f}ms audio ({coverage:.1f}% coverage)"
    )
    if nsnet2_times:
        print(f"  nsnet2: {stats(nsnet2_times)}")

    # Drift in this session
    drifts = [
        s.get("drift_ms")
        for s in by_event.get("engine_state", [])
        if s.get("drift_ms", -99999) != -99999
    ]
    if drifts:
        print(f"  drift: {stats(drifts)}")

    # Local lifecycle highlights for this session
    sess_highlights = []
    for ev in (
        "url_changed",
        "video_paused",
        "video_resumed",
        "seek_detected",
        "init_segment",
    ):
        cnt = len(by_event.get(ev, []))
        if cnt:
            sess_highlights.append(f"{ev}={cnt}")
    if sess_highlights:
        print(f"  events: {', '.join(sess_highlights)}")
    print()
    return {
        "duration": duration,
        "audio_ms": audio_ms_played,
        "coverage": coverage,
        "plays": len(plays_full) + len(plays_trim),
        "skipped": len(skipped),
        "drifts": drifts,
        "nsnet2_times": nsnet2_times,
    }


def detect_anomalies(events, sessions):
    """Returns a list of anomaly strings."""
    anomalies = []
    by_event = defaultdict(list)
    for e in events:
        by_event[e.get("event", "?")].append(e)

    play_events = [e for e in events if e.get("event") in ("chunk_play_full", "chunk_play_trim")]

    # 1. Out-of-order scheduling
    prev_ts = -1
    out_of_order = []
    for e in play_events:
        ts = e.get("chunk_ts", 0)
        if ts < prev_ts:
            out_of_order.append((e["t"], prev_ts, ts))
        prev_ts = ts
    if out_of_order:
        anomalies.append(
            f"OUT-OF-ORDER scheduling: {len(out_of_order)} occurrences "
            f"(e.g. T+{out_of_order[0][0]}ms played ts={out_of_order[0][2]} "
            f"after ts={out_of_order[0][1]})"
        )

    # 2. Discontinuities scheduling (scheduling gap > 100ms between consecutive chunks)
    discontinuities = []
    prev_end = -1
    for e in play_events:
        ts = e.get("chunk_ts", 0)
        frames = e.get("frames", e.get("remaining_samples", 48000))
        end = ts + frames / 48
        if prev_end > 0 and abs(ts - prev_end) > 100:
            discontinuities.append((e["t"], prev_end, ts, ts - prev_end))
        prev_end = end
    big_jumps = [d for d in discontinuities if d[3] > 5000]
    if discontinuities:
        anomalies.append(
            f"DISCONTINUITIES in scheduling: {len(discontinuities)} (biggest: "
            f"{[f'{d[3]/1000:.1f}s' for d in sorted(discontinuities, key=lambda x:-abs(x[3]))[:5]]})"
        )
        for d in big_jumps[:3]:
            anomalies.append(
                f"  → BIG JUMP at T+{d[0]/1000:.1f}s: prev_end={d[1]:.0f}ms "
                f"next_ts={d[2]:.0f}ms (jump {d[3]/1000:+.1f}s)"
            )

    # 3. Cache holes
    states_with_holes = [
        s for s in by_event.get("engine_state", []) if s.get("cache_holes", 0) > 0
    ]
    if states_with_holes:
        last_state = states_with_holes[-1]
        max_holes = max(s.get("cache_holes", 0) for s in states_with_holes)
        max_hole_ms = max(s.get("cache_hole_ms", 0) for s in states_with_holes)
        anomalies.append(
            f"CACHE HOLES detected: max {max_holes} holes ({max_hole_ms}ms total). "
            f"Last state: {last_state.get('cache_holes')} holes/{last_state.get('cache_hole_ms')}ms"
        )

    # 4. Cache wipe destructeur (massive loss)
    for e in by_event.get("cache_sync_cleanup", []):
        if e.get("removed", 0) > 5 and e.get("kept", 0) == 0:
            anomalies.append(
                f"CACHE WIPED at T+{e['t']/1000:.1f}s: removed={e.get('removed')} kept=0"
            )

    # 5. clear_chunks right after seek_to (cache should have been preserved)
    seeks = sorted(by_event.get("seek_to", []), key=lambda e: e["t"])
    clears = sorted(by_event.get("clear_chunks", []), key=lambda e: e["t"])
    for seek in seeks:
        for clear in clears:
            if 0 < clear["t"] - seek["t"] < 2000 and clear.get("dropped_cache", 0) > 0:
                anomalies.append(
                    f"CACHE CLEARED right after seek: T+{seek['t']/1000:.1f}s seek "
                    f"to {seek.get('target_ms')}ms → T+{clear['t']/1000:.1f}s clear "
                    f"dropped {clear.get('dropped_cache')} chunks"
                )
                break

    # 6. Drift trend
    drifts_with_t = [
        (s["t"], s.get("drift_ms"))
        for s in by_event.get("engine_state", [])
        if s.get("drift_ms", -99999) != -99999
    ]
    if len(drifts_with_t) > 30:
        first_third = drifts_with_t[: len(drifts_with_t) // 3]
        last_third = drifts_with_t[-len(drifts_with_t) // 3 :]
        if first_third and last_third:
            avg_first = statistics.mean(d for _, d in first_third)
            avg_last = statistics.mean(d for _, d in last_third)
            if abs(avg_last - avg_first) > 100:
                anomalies.append(
                    f"DRIFT TREND: drift avg first 1/3 = {avg_first:.0f}ms vs "
                    f"last 1/3 = {avg_last:.0f}ms (Δ={avg_last - avg_first:+.0f}ms)"
                )

    # 7. STALE AUDIO ACROSS REFRESH: chunks scheduled within 2s after a
    #    handler_page_reset belonging to an old timestamp range. Detected
    #    via `chunk_play_*` events whose chunk_ts is older than the new
    #    session's first preprocessed chunk_ts. Strong signal that the
    #    Swift cache was not properly cleared, causing the "double audio"
    #    bug the user described.
    resets = sorted(by_event.get("handler_page_reset", []), key=lambda e: e["t"])
    for i, reset in enumerate(resets):
        reset_t = reset["t"]
        # Find the first preprocessed chunk that comes from the NEW session
        # (i.e. after this reset). Anything scheduled before its ts in source
        # time is suspicious.
        next_reset_t = resets[i + 1]["t"] if i + 1 < len(resets) else float("inf")
        new_chunks = [
            e
            for e in by_event.get("chunk_preprocess_done", [])
            if reset_t < e["t"] < next_reset_t
        ]
        if not new_chunks:
            continue
        new_min_ts = min(e.get("chunk_ts", 0) for e in new_chunks)
        suspicious = [
            e
            for e in play_events
            if reset_t < e["t"] < next_reset_t
            and e.get("chunk_ts", 0) + 200 < new_min_ts
        ]
        if suspicious:
            anomalies.append(
                f"STALE AUDIO AFTER RESET at T+{reset_t/1000:.1f}s: "
                f"{len(suspicious)} chunks played with ts < new session min "
                f"({new_min_ts}ms). Likely 'double audio' / refresh leak."
            )
            for s in suspicious[:3]:
                anomalies.append(
                    f"  → at T+{s['t']/1000:.1f}s played chunk_ts={s.get('chunk_ts')}ms "
                    f"(new session starts at ts={new_min_ts}ms)"
                )

    # 8. Stale-epoch drops (good signal, race detected and prevented)
    stale_drops = [
        e for e in by_event.get("chunk_preprocess_drop", [])
        if e.get("reason") == "stale_epoch"
    ]
    if stale_drops:
        anomalies.append(
            f"STALE EPOCH DROPS: {len(stale_drops)} chunks dropped post-reset "
            f"(in-flight preprocess from old session — race correctly handled)"
        )

    # 9. Multiple page_resets in short window (could indicate refresh storm)
    if len(resets) >= 3:
        for i in range(len(resets) - 2):
            window = resets[i + 2]["t"] - resets[i]["t"]
            if window < 5000:
                anomalies.append(
                    f"RESET STORM: 3+ page_resets in {window}ms window "
                    f"(starting at T+{resets[i]['t']/1000:.1f}s)"
                )
                break

    # 10. Cache survives reset (cache_size > 0 in engine_state right after a
    #     reset, before any new preprocess could have repopulated it)
    for reset in resets:
        reset_t = reset["t"]
        next_preprocess = next(
            (
                e["t"]
                for e in by_event.get("chunk_preprocess_done", [])
                if e["t"] > reset_t
            ),
            float("inf"),
        )
        # Look at engine_state samples between reset and next preprocess
        for s in by_event.get("engine_state", []):
            if reset_t < s["t"] < next_preprocess and s.get("cache_size", 0) > 0:
                anomalies.append(
                    f"CACHE SURVIVED RESET at T+{reset_t/1000:.1f}s: engine_state "
                    f"at T+{s['t']/1000:.1f}s shows cache_size={s.get('cache_size')} "
                    f"with no preprocess between reset and now"
                )
                break

    # 11. Preprocess but no playback
    if by_event.get("chunk_preprocess_done") and not play_events:
        anomalies.append(
            f"NO PLAYBACK: {len(by_event['chunk_preprocess_done'])} chunks "
            f"preprocessed but 0 played — engine never started or playerNode stuck"
        )

    return anomalies


def analyze(events, full_lifecycle=False):
    if not events:
        print("no metrics found in log")
        return

    by_event = defaultdict(list)
    for e in events:
        by_event[e.get("event", "?")].append(e)

    test_start = events[0]["t"]
    test_end = events[-1]["t"]
    test_duration = test_end - test_start

    print("=" * 70)
    print("Sawtunaa iOS — Test Report")
    print("=" * 70)
    print(f"Test duration:           {test_duration}ms ({test_duration / 1000:.1f}s)")
    print(f"Total events:            {len(events)}")
    print(f"Page resets:             {len(by_event.get('handler_page_reset', []))}")
    print()

    # Lifecycle
    print_lifecycle(events, full=full_lifecycle)

    # Sessions
    sessions = split_sessions(events)
    print("== Sessions ==")
    if len(sessions) == 1:
        print("  (single session, no page reset detected)")
    else:
        print(f"  {len(sessions)} sessions detected — segmented by handler_page_reset")
    print()
    session_summaries = []
    for i, (start_t, end_t, sess_events) in enumerate(sessions, 1):
        label = session_label(i, sess_events)
        summary = analyze_session(i, start_t, end_t, sess_events, label)
        session_summaries.append(summary)

    # NSNet2 performance
    print("== NSNet2 performance (across run) ==")
    nsnet2_times = [
        e.get("nsnet2_ms", 0) for e in by_event.get("chunk_preprocess_done", [])
    ]
    if nsnet2_times:
        print(f"  Chunks processed:         {len(nsnet2_times)}")
        print(f"  Per-chunk:                {stats(nsnet2_times)}")
        if len(nsnet2_times) > 5:
            steady = nsnet2_times[5:]
            print(f"  Steady-state (skip 5):    {stats(steady)}")
    drops = by_event.get("chunk_preprocess_drop", [])
    if drops:
        reasons = Counter(e.get("reason", "?") for e in drops)
        print(f"  Dropped chunks:           {len(drops)} ({dict(reasons)})")
    print()

    # Playback coverage (across run)
    print("== Playback coverage (across run) ==")
    plays_full = by_event.get("chunk_play_full", [])
    plays_trim = by_event.get("chunk_play_trim", [])
    skipped = by_event.get("chunk_skip_old", [])
    underruns = by_event.get("underrun", [])

    audio_ms_played = sum(int(e.get("frames", 0)) / 48 for e in plays_full)
    audio_ms_played += sum(
        int(e.get("remaining_samples", e.get("frames", 0))) / 48 for e in plays_trim
    )
    coverage = (audio_ms_played / test_duration * 100) if test_duration > 0 else 0

    print(f"  Chunks played (full):     {len(plays_full)}")
    print(f"  Chunks played (trimmed):  {len(plays_trim)}")
    print(f"  Chunks skipped (too old): {len(skipped)}")
    print(f"  Audio scheduled:          {audio_ms_played:.0f}ms ({coverage:.1f}% of test)")
    print(f"  Underrun events:          {len(underruns)}")
    if underruns:
        underrun_times = [e["t"] for e in underruns]
        print(f"  Underrun timestamps:      {[f'{t}ms' for t in underrun_times[:10]]}")
    print()

    # Sync
    print("== Sync (video <-> audio) ==")
    drifts_with_t = [
        (s["t"], s.get("drift_ms"))
        for s in by_event.get("engine_state", [])
        if s.get("drift_ms", -99999) != -99999
    ]
    if drifts_with_t:
        drifts_only = [d for _, d in drifts_with_t]
        print(f"  Drift video-audio:        {stats(drifts_only)}")
        # First/last third comparison
        if len(drifts_with_t) > 30:
            first_third = drifts_with_t[: len(drifts_with_t) // 3]
            last_third = drifts_with_t[-len(drifts_with_t) // 3 :]
            avg_first = statistics.mean(d for _, d in first_third)
            avg_last = statistics.mean(d for _, d in last_third)
            print(
                f"  Drift trend:              first 1/3 avg={avg_first:.0f}ms "
                f"vs last 1/3 avg={avg_last:.0f}ms (Δ={avg_last - avg_first:+.0f}ms)"
            )
    skip_lags = [e.get("lag_ms", 0) for e in skipped]
    if skip_lags:
        print(f"  Skip lags:                {stats(skip_lags)}")

    # Engine state
    print()
    print("== Engine state (1Hz polling) ==")
    states = by_event.get("engine_state", [])
    if states:
        running_off = sum(1 for s in states if not s.get("engine_running", True))
        player_off = sum(1 for s in states if not s.get("player_playing", True))
        print(f"  Samples:                  {len(states)}")
        print(f"  Engine off:               {running_off} samples ({running_off}s)")
        print(f"  Player off:               {player_off} samples ({player_off}s)")
        cache_sizes = [s.get("cache_size", 0) for s in states]
        if cache_sizes:
            print(f"  Cache size:               {stats(cache_sizes, label='')}")
    print()

    # JS pipeline
    print("== JS pipeline ==")
    sends = by_event.get("chunk_send", [])
    decodes = by_event.get("decode_done", [])
    if decodes:
        decode_ms = [e.get("decode_ms", 0) for e in decodes]
        samples = [e.get("samples", 0) for e in decodes]
        print(f"  Segments decoded:         {len(decodes)}")
        print(f"  Decode time:              {stats(decode_ms)}")
        print(
            f"  Samples per segment:      avg={int(statistics.mean(samples)) if samples else 0}"
        )
    if sends:
        print(f"  Chunks sent to Swift:     {len(sends)}")
    seeks = by_event.get("seek_detected", [])
    pauses = by_event.get("video_paused", [])
    resumes = by_event.get("video_resumed", [])
    inits = by_event.get("init_segment", [])
    print(
        f"  Lifecycle:                {len(inits)} init_segment, {len(seeks)} seek, "
        f"{len(pauses)} pause, {len(resumes)} resume"
    )
    print()

    # Anomalies
    print("== Anomalies détectées ==")
    anomalies = detect_anomalies(events, sessions)
    if anomalies:
        for a in anomalies:
            print(f"  ⚠ {a}")
    else:
        print("  ✓ aucune anomalie détectée")
    print()

    # Errors
    print("== Errors / abnormal events ==")
    error_events = [
        "engine_start",  # check success=false
        "handler_model_not_found",
        "handler_playat_invalid",
        "handler_unknown_action",
        "play_chunks_engine_failed",
        "decoder_error",
        "decode_error",
        "chunk_send_error",
        "script_abort",
        "preprocess_invalid_ts",
    ]
    any_error = False
    for name in error_events:
        for e in by_event.get(name, []):
            if name == "engine_start" and e.get("success", True):
                continue
            any_error = True
            t = e["t"]
            extras = fmt_kvs(e)
            print(f"  T+{t:>6}ms  {name}  {extras}")
    if not any_error:
        print("  none")
    print()

    # Verdict
    print("== Verdict ==")
    issues = []
    if coverage < 80:
        issues.append(
            f"LOW COVERAGE: only {coverage:.1f}% of test had scheduled audio (target >80%)"
        )
    if underruns:
        issues.append(f"UNDERRUNS: {len(underruns)} events — buffer ran dry")
    if drifts_with_t:
        max_drift = max(abs(d) for _, d in drifts_with_t)
        if max_drift > 500:
            issues.append(f"HIGH DRIFT: max |drift| = {max_drift}ms")
    if nsnet2_times:
        max_ns = max(nsnet2_times)
        if max_ns > 1000:
            issues.append(f"NSNET2 SPIKE: max processing time = {max_ns}ms")
    if any_error:
        issues.append("ERROR EVENTS detected — see above")
    if states and any(not s.get("engine_running", True) for s in states):
        issues.append("ENGINE STOPPED at some point during test")
    if anomalies:
        # Some anomalies are auto-handled (stale_epoch drops are info-only),
        # but stale audio after reset is a real bug to flag
        for a in anomalies:
            if a.startswith("STALE AUDIO"):
                issues.append(a)
            elif a.startswith("CACHE SURVIVED"):
                issues.append(a)
            elif a.startswith("NO PLAYBACK"):
                issues.append(a)

    if issues:
        for i in issues:
            print(f"  FAIL: {i}")
    else:
        print("  PASS: all primary metrics within target")
    print()


def main():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("log_file")
    ap.add_argument("--json", action="store_true", help="output raw events as JSON")
    ap.add_argument(
        "--lifecycle",
        action="store_true",
        help="print full lifecycle (no per-event cap)",
    )
    args = ap.parse_args()

    events = parse_log(args.log_file)
    if args.json:
        json.dump(events, sys.stdout, indent=2)
        return
    analyze(events, full_lifecycle=args.lifecycle)


if __name__ == "__main__":
    main()
