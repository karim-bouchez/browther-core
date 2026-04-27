#!/usr/bin/env python3
"""
Sawtunaa metrics analyzer.

Parses [METRIC] {json} lines from a captured iOS device log and produces a
structured report covering:
- Pipeline activation timeline
- NSNet2 processing performance
- Audio playback coverage and underruns
- Sync (video <-> audio) drift
- Buffer queue depth over time
- Engine/handler errors

Usage:
  python3 analyze_sawtunaa_metrics.py <log_file>
  python3 analyze_sawtunaa_metrics.py <log_file> --json   # raw JSON output
"""

import argparse
import json
import re
import statistics
import sys
from collections import Counter, defaultdict


METRIC_RE = re.compile(r"\[METRIC\]\s+(\{.*\})")


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


def fmt_ms(v):
    if v is None:
        return "n/a"
    if isinstance(v, float):
        return f"{v:.0f}ms"
    return f"{v}ms"


def stats(values, label="ms"):
    if not values:
        return f"none"
    avg = statistics.mean(values)
    p50 = percentile(values, 50)
    p99 = percentile(values, 99)
    return f"avg={avg:.0f}{label} p50={p50:.0f}{label} p99={p99:.0f}{label} max={max(values)}{label} (n={len(values)})"


def analyze(events):
    if not events:
        print("no metrics found in log")
        return

    by_event = defaultdict(list)
    for e in events:
        by_event[e.get("event", "?")].append(e)

    test_start = events[0]["t"]
    test_end = events[-1]["t"]
    test_duration = test_end - test_start

    print("=" * 60)
    print("Sawtunaa iOS — Test Report")
    print("=" * 60)
    print(f"Test duration:           {test_duration}ms ({test_duration / 1000:.1f}s)")
    print(f"Total events:            {len(events)}")
    print()

    # Timeline
    print("== Timeline ==")
    timeline_events = [
        "handler_init",
        "handler_create_player",
        "model_load_done",
        "script_init",
        "decoder_ready",
        "auto_activate",
        "engine_start",
        "first_chunk_played",
        "handler_clear_chunks",
        "seek_detected",
    ]
    for name in timeline_events:
        if name in by_event:
            for e in by_event[name][:3]:  # show up to 3 occurrences
                t = e["t"]
                extras = {k: v for k, v in e.items() if k not in ("t", "event", "src")}
                extras_str = " ".join(f"{k}={v}" for k, v in extras.items())
                print(f"  T+{t:>6}ms  {name:<25} {extras_str}")
    print()

    # Activation timing
    print("== Activation latency ==")
    if by_event.get("handler_create_player") and by_event.get("model_load_done"):
        load_ms = by_event["model_load_done"][0].get("load_ms", "?")
        print(f"  NSNet2 model load:        {load_ms}ms")
    if by_event.get("decoder_ready"):
        dec_ms = by_event["decoder_ready"][0].get("load_ms", "?")
        print(f"  Opus decoder load:        {dec_ms}ms")
    if by_event.get("auto_activate") and by_event.get("first_chunk_played"):
        activate_t = by_event["auto_activate"][0]["t"]
        first_play_t = by_event["first_chunk_played"][0]["t"]
        print(f"  Activation -> first play: {first_play_t - activate_t}ms")
    print()

    # NSNet2 performance
    print("== NSNet2 performance ==")
    nsnet2_times = [e.get("nsnet2_ms", 0) for e in by_event.get("chunk_preprocess_done", [])]
    if nsnet2_times:
        print(f"  Chunks processed:         {len(nsnet2_times)}")
        print(f"  Per-chunk:                {stats(nsnet2_times)}")
        if len(nsnet2_times) >= 1:
            print(f"  First chunk (warmup):     {nsnet2_times[0]}ms")
        if len(nsnet2_times) > 5:
            steady = nsnet2_times[5:]
            print(f"  Steady-state (skip 5):    {stats(steady)}")
    drops = by_event.get("chunk_preprocess_drop", [])
    if drops:
        reasons = Counter(e.get("reason", "?") for e in drops)
        print(f"  Dropped chunks:           {len(drops)} ({dict(reasons)})")
    print()

    # Playback coverage
    print("== Playback coverage ==")
    plays_full = by_event.get("chunk_play_full", [])
    plays_trim = by_event.get("chunk_play_trim", [])
    plays_total = len(plays_full) + len(plays_trim)
    skipped = by_event.get("chunk_skip_old", [])
    underruns = by_event.get("underrun", [])

    audio_ms_played = 0
    for e in plays_full:
        audio_ms_played += int(e.get("frames", 0)) / 48
    for e in plays_trim:
        audio_ms_played += int(e.get("remaining_samples", 0)) / 48

    if test_duration > 0:
        coverage = (audio_ms_played / test_duration) * 100
    else:
        coverage = 0

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
    lags_full = [e.get("lag_ms", 0) for e in plays_full if "lag_ms" in e]
    if lags_full:
        print(f"  Video-audio lag (full):   {stats(lags_full)}")
    skip_lags = [e.get("lag_ms", 0) for e in skipped]
    if skip_lags:
        print(f"  Skip lags:                {stats(skip_lags)}")

    # Engine state samples
    print()
    print("== Engine state (1Hz polling) ==")
    states = by_event.get("engine_state", [])
    if states:
        running_off = sum(1 for s in states if not s.get("engine_running", True))
        player_off = sum(1 for s in states if not s.get("player_playing", True))
        queue_depths = [s.get("queue_depth", 0) for s in states]
        print(f"  Samples:                  {len(states)}")
        print(f"  Engine off:               {running_off} samples ({running_off}s)")
        print(f"  Player off:               {player_off} samples ({player_off}s)")
        print(f"  Queue depth:              {stats(queue_depths, label='')}")
    print()

    # JS-side metrics
    print("== JS pipeline ==")
    sends = by_event.get("chunk_send", [])
    decodes = by_event.get("decode_done", [])
    if decodes:
        decode_ms = [e.get("decode_ms", 0) for e in decodes]
        samples = [e.get("samples", 0) for e in decodes]
        print(f"  Segments decoded:         {len(decodes)}")
        print(f"  Decode time:              {stats(decode_ms)}")
        print(f"  Samples per segment:      avg={int(statistics.mean(samples)) if samples else 0}")
    if sends:
        print(f"  Chunks sent to Swift:     {len(sends)}")
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
    ]
    any_error = False
    for name in error_events:
        for e in by_event.get(name, []):
            if name == "engine_start" and e.get("success", True):
                continue
            any_error = True
            t = e["t"]
            extras = {k: v for k, v in e.items() if k not in ("t", "event", "src")}
            print(f"  T+{t:>6}ms  {name}  {extras}")
    if not any_error:
        print("  none")
    print()

    # Verdict heuristics
    print("== Verdict ==")
    issues = []
    if coverage < 80:
        issues.append(f"LOW COVERAGE: only {coverage:.1f}% of test had scheduled audio (target >80%)")
    if underruns:
        issues.append(f"UNDERRUNS: {len(underruns)} events — buffer ran dry")
    if lags_full and percentile(lags_full, 99) and percentile(lags_full, 99) > 200:
        p99 = percentile(lags_full, 99)
        issues.append(f"HIGH LAG: p99 video-audio lag = {p99:.0f}ms (target <200ms)")
    if nsnet2_times:
        max_ns = max(nsnet2_times)
        if max_ns > 1000:
            issues.append(f"NSNET2 SPIKE: max processing time = {max_ns}ms")
    if any_error:
        issues.append("ERROR EVENTS detected — see above")
    if states and any(not s.get("engine_running", True) for s in states):
        issues.append("ENGINE STOPPED at some point during test")

    if issues:
        for i in issues:
            print(f"  FAIL: {i}")
    else:
        print("  PASS: all primary metrics within target")
    print()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("log_file")
    ap.add_argument("--json", action="store_true", help="output raw events as JSON")
    args = ap.parse_args()

    events = parse_log(args.log_file)
    if args.json:
        json.dump(events, sys.stdout, indent=2)
        return
    analyze(events)


if __name__ == "__main__":
    main()
