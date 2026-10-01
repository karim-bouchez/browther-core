// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// Sawtunaa: MSE SourceBuffer interception + Opus decode + native NSNet2 playback.
// This script intercepts audio data from YouTube's MediaSource Extensions,
// decodes Opus packets via WASM, and sends stereo PCM to Swift for noise suppression.

window.__firefox__.includeOnce("SawtunaaScript", function($) {
  'use strict';

  function send(action, data) {
    try {
      $.postNativeMessage('$<message_handler>', {
        securityToken: SECURITY_TOKEN,
        action: action,
        data: data || ''
      });
    } catch(e) {}
  }

  function LOG(msg) { send('log', '' + msg); }

  // Structured metric logger. Emits one JSON event with relative timestamp.
  // Format: forwarded to Swift, which prints "[METRIC] {json}" to stdout.
  var sessionStart = (typeof performance !== 'undefined' && performance.now) ? performance.now() : Date.now();
  function metric(event, kvs) {
    var now = (typeof performance !== 'undefined' && performance.now) ? performance.now() : Date.now();
    var obj = { t: Math.round(now - sessionStart), event: event, src: 'js' };
    if (kvs) for (var k in kvs) if (kvs.hasOwnProperty(k)) obj[k] = kvs[k];
    try { send('metric', JSON.stringify(obj)); } catch(e) {}
  }

  var hasMS = typeof MediaSource !== 'undefined';
  var hasMMS = typeof ManagedMediaSource !== 'undefined';
  if (!hasMS && !hasMMS) {
    metric('script_abort', { reason: 'no_mse' });
    return;
  }

  var hasOpus = typeof OpusDecoderLib !== 'undefined';
  if (!hasOpus) {
    metric('script_abort', { reason: 'no_opus' });
    return;
  }

  metric('script_init', {
    hasMS: hasMS,
    hasMMS: hasMMS,
    url: location.href,
    isYoutube: /(?:youtube\.com|youtu\.be)/.test(location.host)
  });

  // ─── Page lifecycle ───
  // The Swift SawtunaaScriptHandler is bound to the WKWebView/tab, NOT the JS
  // context. On a page refresh, SPA-navigation back-forward, etc., the JS context
  // is re-created (or restarted from bfcache) but the Swift handler keeps its
  // audioCache, scheduler state and AVAudioEngine queue. Without an explicit
  // signal, audio from the previous page would keep playing on top of the new
  // page's audio. We send `pageReset` at every script init to drop the stale
  // state on Swift side.
  send('pageReset', location.href);
  metric('page_reset_sent', { url: location.href });

  // Extract the YouTube video id from a URL — used to detect a true video
  // change vs an in-page state update (timestamp param, sidebar open, etc.)
  // that should NOT trigger a cache reset.
  function extractVideoId(url) {
    if (!url) return null;
    var m = /[?&]v=([^&#]+)/.exec(url);
    if (m) return m[1];
    m = /youtu\.be\/([^?&#\/]+)/.exec(url);
    if (m) return m[1];
    m = /\/shorts\/([^?&#\/]+)/.exec(url);
    if (m) return m[1];
    m = /\/embed\/([^?&#\/]+)/.exec(url);
    if (m) return m[1];
    return null;
  }

  // Track URL/video-id changes. SPA navigation on YouTube changes the URL
  // via history.pushState/replaceState (and popstate on back/forward), all
  // without re-creating the JS context — so our pageReset would never fire
  // from script_init or pagehide. We hook those three APIs (script runs at
  // atDocumentStart so we override them before any YouTube script can store
  // a reference). When the video id actually changes (A -> B), we send
  // pageReset so Swift drops the previous video's cache. Without this, B's
  // chunks arrive at timestamps near 0ms and collide with A's chunks at the
  // same timestamps in the cache — causing the "first ms of A then
  // alternating A/B then B" bug.
  var __sawtunaaLastUrl = location.href;
  var __sawtunaaLastVideoId = extractVideoId(location.href);
  function onUrlChangeCheck() {
    var newUrl = location.href;
    if (newUrl === __sawtunaaLastUrl) return;
    var newVideoId = extractVideoId(newUrl);
    var videoChanged = newVideoId !== __sawtunaaLastVideoId;
    metric('url_changed', {
      from: __sawtunaaLastUrl,
      to: newUrl,
      from_video: __sawtunaaLastVideoId,
      to_video: newVideoId,
      video_changed: videoChanged
    });
    __sawtunaaLastUrl = newUrl;
    if (videoChanged) {
      __sawtunaaLastVideoId = newVideoId;
      send('pageReset', 'video_change:' + (newVideoId || 'null'));
      metric('video_change_reset', { video_id: newVideoId });
    }
  }
  try {
    var origPush = history.pushState;
    history.pushState = function() {
      var ret = origPush.apply(this, arguments);
      try { onUrlChangeCheck(); } catch(e) {}
      return ret;
    };
    var origReplace = history.replaceState;
    history.replaceState = function() {
      var ret = origReplace.apply(this, arguments);
      try { onUrlChangeCheck(); } catch(e) {}
      return ret;
    };
    window.addEventListener('popstate', function() {
      try { onUrlChangeCheck(); } catch(e) {}
    });
  } catch(e) {
    metric('history_hook_error', { msg: e.message });
  }

  // ─── User mark gesture (debug) ───
  // 3-finger touch on the screen emits a `user_mark` metric with the
  // current video time and URL. Lets the user flag the precise moment
  // they observed a bug (audio glitch, sync issue, …) for later analysis
  // — instead of having to describe the symptom by hand.
  // Capture phase + non-passive listener so YouTube can't preventDefault.
  try {
    var __sawtunaaLastMarkAt = 0;
    document.addEventListener('touchstart', function(e) {
      if (!e.touches || e.touches.length !== 3) return;
      var now = Date.now();
      // Debounce: a single 3-finger touch fires multiple touchstart events
      // as fingers land sequentially. Only emit one mark per ~1s window.
      if (now - __sawtunaaLastMarkAt < 1000) return;
      __sawtunaaLastMarkAt = now;
      var v = document.querySelector('video');
      metric('user_mark', {
        video_ms: v ? Math.round(v.currentTime * 1000) : -1,
        url: location.href,
        cache_chunks: decodedSegments.length
      });
    }, { capture: true, passive: true });
  } catch(e) {}

  // pagehide fires before the page goes into bfcache or is unloaded. Mirror
  // it so the Swift side can drop stale audio if the user navigates away.
  try {
    window.addEventListener('pagehide', function(e) {
      metric('pagehide', { persisted: !!(e && e.persisted) });
      send('pageReset', 'pagehide');
    });
    window.addEventListener('pageshow', function(e) {
      metric('pageshow', { persisted: !!(e && e.persisted) });
      // If restored from bfcache, the JS context is alive but Swift was reset
      // by our pagehide. Re-init by sending pageReset (idempotent on Swift).
      if (e && e.persisted) {
        send('pageReset', 'pageshow_bfcache');
      }
    });
    document.addEventListener('visibilitychange', function() {
      metric('visibility_change', { hidden: document.hidden });
    });
  } catch(e) {}

  // ─── EBML Parser ───
  function readVint(data, offset) {
    var first = data[offset];
    var len = 1, mask = 0x80;
    while (len <= 8 && !(first & mask)) { len++; mask >>= 1; }
    var value = first & (mask - 1);
    for (var i = 1; i < len; i++) value = (value * 256) + data[offset + i];
    return { value: value, length: len };
  }

  function readElementId(data, offset) {
    var first = data[offset];
    var len = 1;
    if (first & 0x80) len = 1;
    else if (first & 0x40) len = 2;
    else if (first & 0x20) len = 3;
    else if (first & 0x10) len = 4;
    var id = first;
    for (var i = 1; i < len; i++) id = (id * 256) + data[offset + i];
    return { id: id, length: len };
  }

  function readUint(data, offset, size) {
    var val = 0;
    for (var i = 0; i < size; i++) val = (val * 256) + data[offset + i];
    return val;
  }

  var MASTER_IDS = [0x1A45DFA3, 0x18538067, 0x1654AE6B, 0xAE, 0xE1, 0x1F43B675];
  var ID_CODEC_PRIVATE = 0x63A2;

  function parseInitSegment(buf) {
    var data = new Uint8Array(buf);
    var result = { channels: 2, sampleRate: 48000, preSkip: 0 };
    var pos = 0;
    while (pos < data.length - 2) {
      var eid = readElementId(data, pos); pos += eid.length;
      if (pos >= data.length) break;
      var esize = readVint(data, pos); pos += esize.length;
      var maxVal = Math.pow(2, 7 * esize.length) - 1;
      var isUnknown = (esize.value === maxVal);
      if (MASTER_IDS.indexOf(eid.id) >= 0 || isUnknown) continue;
      if (eid.id === ID_CODEC_PRIVATE && esize.value >= 19) {
        var cp = data.subarray(pos, pos + esize.value);
        if (cp[0] === 0x4F) {
          result.channels = cp[9];
          result.preSkip = cp[10] | (cp[11] << 8);
          LOG('OpusHead: ch=' + result.channels + ' preSkip=' + result.preSkip);
        }
      }
      pos += esize.value;
    }
    return result;
  }

  function parseMediaSegment(buf) {
    var data = new Uint8Array(buf);
    var packets = [];
    var clusterTimestampMs = -1;
    var firstBlockRelativeTs = -1;
    // Un 0xE7 n'est un horodatage de Cluster que juste après l'en-tête d'un
    // Cluster. Cherché n'importe où, il se trouvait aussi DANS les paquets
    // Opus : un morceau de segment sans en-tête (YouTube en envoie) recevait
    // un horodatage faux de quelques secondes (journaux iPhone 2026-10-01 :
    // blocs datés 7 897, 28 897… bien loin de la vidéo → silence).
    var seenCluster = false;
    var pos = 0;

    while (pos < data.length - 4) {
      if (data[pos] === 0xA3) {
        var sizeInfo = readVint(data, pos + 1);
        var blockSize = sizeInfo.value;
        var blockStart = pos + 1 + sizeInfo.length;
        if (blockSize >= 10 && blockSize <= 1500 &&
            blockStart + blockSize <= data.length &&
            data[blockStart] === 0x81) {
          var relTsRaw = (data[blockStart + 1] << 8) | data[blockStart + 2];
          var relTs = relTsRaw > 32767 ? relTsRaw - 65536 : relTsRaw;
          if (firstBlockRelativeTs < 0) firstBlockRelativeTs = relTs;
          var opusStart = blockStart + 4;
          var opusLen = blockSize - 4;
          if (opusLen >= 3 && opusLen <= 1400) {
            packets.push(data.slice(opusStart, opusStart + opusLen));
          }
          pos = blockStart + blockSize;
          continue;
        }
        pos++;
        continue;
      } else if (pos + 4 <= data.length &&
                 data[pos] === 0x1F && data[pos+1] === 0x43 &&
                 data[pos+2] === 0xB6 && data[pos+3] === 0x75) {
        var csInfo = readVint(data, pos + 4);
        pos = pos + 4 + csInfo.length;
        seenCluster = true;
        continue;
      } else if (seenCluster && clusterTimestampMs < 0 && data[pos] === 0xE7 && pos + 1 < data.length) {
        var tsInfo = readVint(data, pos + 1);
        if (tsInfo.value <= 8 && pos + 1 + tsInfo.length + tsInfo.value <= data.length) {
          clusterTimestampMs = readUint(data, pos + 1 + tsInfo.length, tsInfo.value);
          pos = pos + 1 + tsInfo.length + tsInfo.value;
          continue;
        }
      }
      pos++;
    }

    var startTimeMs = -1;
    if (clusterTimestampMs >= 0) {
      startTimeMs = clusterTimestampMs + (firstBlockRelativeTs >= 0 ? firstBlockRelativeTs : 0);
    }
    return { packets: packets, startTimeMs: startTimeMs };
  }

  // ─── Veille / activation (2026-10-01) ───
  // Le script est injecté sur TOUTES les pages, Sawtunaa allumé ou non : il
  // doit être en place AVANT que la page crée son MediaSource, sinon rien
  // n'est interceptable sans recharger (et recharger renvoie la vidéo à 0).
  // Éteint (`enabled === false`) = VEILLE : on ne fait que garder une copie
  // de l'audio Opus COMPRESSÉ (`standby*`, quelques centaines de Ko), sans
  // décodage, sans NSNet2, sans couper le son. À l'allumage
  // (`__sawtunaaSetEnabled(true)`, appelé par le natif), on décode cette copie
  // à partir de la position courante. L'état initial est gravé à l'injection
  // (variante du WKUserScript) pour qu'une page chargée Sawtunaa allumé ne
  // laisse jamais passer la musique en attendant une réponse du natif.
  var enabled = $<sawtunaa_enabled>;
  // Dernier segment d'init (en-tête Opus) et segments médias analysés
  // (paquets compressés + horodatage), dans l'ordre d'arrivée.
  var standbyInit = null;
  var standbySegments = [];
  var standbyBytes = 0;
  var STANDBY_BEHIND_MS = 10000;          // gardé derrière la lecture
  var STANDBY_MAX_BYTES = 4 * 1024 * 1024; // filet (YouTube : ~20 Ko/s)
  // Incrémenté à chaque (dés)activation : un décodeur dont le `ready` arrive
  // après une extinction ne doit rien relancer.
  var decoderGeneration = 0;

  function segmentBytes(parsed) {
    var n = 0;
    for (var i = 0; i < parsed.packets.length; i++) n += parsed.packets[i].byteLength;
    return n;
  }

  // Fin (ms, temps de PRÉSENTATION) du dernier segment média ajouté.
  var appendLastEndMs = -1;
  var lastLoggedOffsetMs = 0;

  // Date un segment média en temps de présentation, dans TOUS les modes :
  // - `timestampOffset` du SourceBuffer ajouté (règle MSE : présentation =
  //   horodatage codé + offset ; ignoré avant le 2026-10-01) ;
  // - un morceau sans en-tête de Cluster (YouTube coupe parfois un segment en
  //   plusieurs `appendBuffer`) prolonge le précédent. En veille, ces morceaux
  //   étaient JETÉS faute d'horodatage : 13 → 20 s manquaient à l'allumage.
  function dateMediaSegment(parsed, sb) {
    var offMs = Math.round(((sb && sb.timestampOffset) || 0) * 1000);
    if (offMs !== lastLoggedOffsetMs) {
      metric('sb_timestamp_offset', { from_ms: lastLoggedOffsetMs, to_ms: offMs });
      lastLoggedOffsetMs = offMs;
    }
    var raw = parsed.startTimeMs;
    var continued = false;
    if (raw >= 0 && isFinite(raw)) {
      parsed.startTimeMs = raw + offMs;
    } else if (appendLastEndMs >= 0) {
      parsed.startTimeMs = appendLastEndMs;
      continued = true;
    }
    if (parsed.startTimeMs >= 0 && parsed.packets.length > 0) {
      appendLastEndMs = parsed.startTimeMs + parsed.packets.length * 20;
    }
    var v = document.querySelector('video');
    metric('append', {
      raw_ts: raw,
      ts: parsed.startTimeMs,
      off_ms: offMs,
      packets: parsed.packets.length,
      cont: continued,
      enabled: enabled,
      video_ms: v ? Math.round(v.currentTime * 1000) : -1
    });
  }

  function standbyStore(parsed) {
    if (parsed.packets.length === 0 || parsed.startTimeMs < 0
        || !isFinite(parsed.startTimeMs) || parsed.startTimeMs > 24 * 3600 * 1000) return;
    parsed.endTimeMs = parsed.startTimeMs + parsed.packets.length * 20;
    parsed.bytes = segmentBytes(parsed);
    standbySegments.push(parsed);
    standbyBytes += parsed.bytes;
    var v = document.querySelector('video');
    var oldest = v ? v.currentTime * 1000 - STANDBY_BEHIND_MS : -Infinity;
    standbySegments = standbySegments.filter(function(s) {
      var keep = s.endTimeMs >= oldest;
      if (!keep) standbyBytes -= s.bytes;
      return keep;
    });
    while (standbyBytes > STANDBY_MAX_BYTES && standbySegments.length > 1) {
      standbyBytes -= standbySegments.shift().bytes;
    }
  }

  function standbyEvict(startMs, endMs) {
    standbySegments = standbySegments.filter(function(s) {
      var keep = s.endTimeMs <= startMs || s.startTimeMs >= endMs;
      if (!keep) standbyBytes -= s.bytes;
      return keep;
    });
  }

  function standbyClear() {
    standbySegments = [];
    standbyBytes = 0;
  }

  // ─── State ───
  var audioBuffers = [];
  var initInfo = null;
  var opusDecoder = null;
  var segmentCount = 0;
  var sbPatched = false;
  var isActive = false;
  var schedulerInterval = null;
  var lastVideoTimeMs = -1;
  var CHUNK_SAMPLES = 48000;
  var decodedSegments = [];
  var lastEstimatedEndMs = 0;
  var pendingSegments = [];
  var decoderInitializing = false;
  var audioPaused = false;
  // Détection de la vidéo qui cale (cf. scheduler).
  var STALL_MS = 300;
  var lastSeenTimeMs = -1;
  var lastAdvanceWallMs = 0;

  // Aggregation buffers: accumulate PCM until we can send a full 1s chunk.
  // Smooths out YouTube's micro-segments (22% are <100ms) which would otherwise
  // create many tiny scheduleBuffer calls and audible micro-glitches.
  //
  // ⚠️ STEREO (2026-08-29): we used to downmix to mono here, which collapsed the
  // stereo image of every single video. NSNet2 still runs ONCE per frame (the
  // mask is computed on the spectral downmix, native side) and is only APPLIED
  // per channel — same as macOS. So the inference cost is unchanged; what
  // doubles is the PCM shipped over the bridge, which the chunked base64 below
  // more than pays back.
  var pendingL = new Float32Array(CHUNK_SAMPLES * 2);
  var pendingR = new Float32Array(CHUNK_SAMPLES * 2);
  var pendingLen = 0;
  var pendingStartMs = 0;
  var pendingEndMs = 0;

  function flushPending() {
    if (pendingLen <= 0) return;
    sendChunkToSwift(pendingL, pendingR, pendingLen, pendingStartMs);
    decodedSegments.push({ startTimeMs: pendingStartMs, durationMs: pendingLen / 48 });
    pendingLen = 0;
  }

  // ─── Send stereo PCM chunk to Swift for NSNet2 processing ───
  // Wire format: base64 of PLANAR float32 — all of L, then all of R (the layout
  // Nsnet2Stream uses on macOS, and what AVAudioPCMBuffer wants on the other
  // side). No per-chunk log here: each chunk is already traced by Swift's
  // chunk_preprocess_done. Only the error path emits a metric.
  var B64_BLOCK = 8192;  // fromCharCode.apply is ~10x faster than the per-byte
                         // loop, but blows the stack past ~100k arguments.
  function bytesToBase64(bytes) {
    var parts = [];
    for (var off = 0; off < bytes.length; off += B64_BLOCK) {
      parts.push(String.fromCharCode.apply(
        null, bytes.subarray(off, Math.min(off + B64_BLOCK, bytes.length))));
    }
    return btoa(parts.join(''));
  }

  function sendChunkToSwift(left, right, frames, timestampMs) {
    try {
      var planar = new Float32Array(frames * 2);
      planar.set(left.subarray(0, frames), 0);
      planar.set(right.subarray(0, frames), frames);
      var bytes = new Uint8Array(planar.buffer, planar.byteOffset, planar.byteLength);
      send('preprocess', Math.round(timestampMs) + '|' + bytesToBase64(bytes));
    } catch(e) {
      metric('chunk_send_error', { msg: e.message });
    }
  }

  // ─── Force-mute video element via volumechange listener ───
  // Approach: instead of overriding `volume`/`muted` setters via defineProperty
  // (which causes YouTube's UI to break — it reads its own setter result and
  // can't tell that the set was silently blocked, leading to "controls
  // disappear" / "click toggles play" mode), we listen to `volumechange`
  // events and re-mute via the native prototype setter. YouTube's UI gets
  // a coherent reflection (set → fire volumechange → value rolled back).
  //
  // We also re-apply on every video element we see: YouTube may swap the
  // <video> instance on SPA navigation or fullscreen transitions, and our
  // listener must follow.
  var nativeMutedDesc = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'muted');
  var nativeVolDesc = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'volume');

  function nativeSetMuted(v, val) {
    if (nativeMutedDesc && nativeMutedDesc.set) nativeMutedDesc.set.call(v, val);
    else v.muted = val;
  }
  function nativeSetVolume(v, val) {
    if (nativeVolDesc && nativeVolDesc.set) nativeVolDesc.set.call(v, val);
    else v.volume = val;
  }
  function nativeGetMuted(v) {
    return nativeMutedDesc && nativeMutedDesc.get ? nativeMutedDesc.get.call(v) : v.muted;
  }
  function nativeGetVolume(v) {
    return nativeVolDesc && nativeVolDesc.get ? nativeVolDesc.get.call(v) : v.volume;
  }

  // Vidéos actuellement coupées par nous : à l'extinction, on leur rend leur
  // son d'avant (`__sawtunaa_saved`), pas un `volume = 1` arbitraire.
  var mutedVideos = [];

  function forceMuteVideo(v) {
    if (!v) return;
    if (v.__sawtunaa_muting) return;
    v.__sawtunaa_muting = true;
    v.__sawtunaa_saved = { muted: nativeGetMuted(v), volume: nativeGetVolume(v) };
    mutedVideos.push(v);

    // Apply mute via native setter first.
    nativeSetMuted(v, true);
    nativeSetVolume(v, 0);

    // Override `muted` and `volume` accessors on this instance so YouTube's
    // attempts to unmute are silently coerced rather than going through. The
    // getter returns the actual native value (so YouTube's read-after-write
    // gives a coherent answer = `true`, no UI confusion); the setter clamps
    // any unmute to `muted=true / volume=0`. Crucially, if the value is
    // already what we want, the native setter is a no-op and no
    // `volumechange` event fires — YouTube doesn't observe a transient
    // false→true flip that would otherwise put it in a degraded UI state.
    try {
      Object.defineProperty(v, 'muted', {
        get: function() { return nativeGetMuted(v); },
        set: function(_value) {
          // Ce que la PAGE veut : rendu tel quel à l'extinction.
          if (v.__sawtunaa_saved) v.__sawtunaa_saved.muted = !!_value;
          if (nativeGetMuted(v) !== true) nativeSetMuted(v, true);
        },
        configurable: true
      });
      Object.defineProperty(v, 'volume', {
        get: function() { return nativeGetVolume(v); },
        set: function(_value) {
          var vol = Number(_value);
          if (v.__sawtunaa_saved && isFinite(vol) && vol >= 0 && vol <= 1) {
            v.__sawtunaa_saved.volume = vol;
          }
          if (nativeGetVolume(v) !== 0) nativeSetVolume(v, 0);
        },
        configurable: true
      });
    } catch(e) {
      LOG('defineProperty failed: ' + e.message);
    }

    // Fullscreen handling. In iOS WKWebView native fullscreen, the video is
    // promoted to an internal AVPlayer that bypasses our defineProperty
    // setters when the system audio level changes (hardware buttons, system
    // events). YouTube's volume slider in fullscreen also triggers a media-
    // level path that ignores our JS overrides. To prevent the original
    // audio from leaking, we attach a `volumechange` listener ONLY during
    // fullscreen — it re-mutes via the native prototype setter every time
    // an iOS-internal change happens. We detach on exit so the listener
    // doesn't disturb YouTube's UI logic in normal mode.
    // Écouteurs plein écran posés UNE fois par élément : la coupure peut être
    // levée puis remise (veille ↔ actif), ils consultent `__sawtunaa_muting`.
    if (v.__sawtunaa_fs_hooked) {
      LOG('Video mute enforcer attached');
      return;
    }
    v.__sawtunaa_fs_hooked = true;
    var fsVolumeListener = null;
    v.addEventListener('webkitbeginfullscreen', function() {
      metric('fullscreen_begin', { video_ms: Math.round(v.currentTime * 1000) });
      if (fsVolumeListener || !v.__sawtunaa_muting) return;
      // Listener in CAPTURE phase + stopImmediatePropagation: hides the
      // volumechange events from YouTube's own listeners. Without this,
      // YouTube sees its volume sets being silently reverted and switches
      // to a degraded UI mode (no controls visible) that persists after
      // fullscreen exit. With stopImmediatePropagation, YouTube never sees
      // the parasitic events — its UI logic stays consistent.
      fsVolumeListener = function(e) {
        if (!v.__sawtunaa_muting) return;
        e.stopImmediatePropagation();
        if (nativeGetMuted(v) !== true) nativeSetMuted(v, true);
        if (nativeGetVolume(v) !== 0) nativeSetVolume(v, 0);
      };
      v.addEventListener('volumechange', fsVolumeListener, true);
    });
    v.addEventListener('webkitendfullscreen', function() {
      metric('fullscreen_end', { video_ms: Math.round(v.currentTime * 1000) });
      if (fsVolumeListener) {
        v.removeEventListener('volumechange', fsVolumeListener, true);
        fsVolumeListener = null;
      }
      // Final re-mute (no listener active anymore — defineProperty resumes).
      if (!v.__sawtunaa_muting) return;
      nativeSetMuted(v, true);
      nativeSetVolume(v, 0);
    });

    LOG('Video mute enforcer attached');
  }

  // Rend à chaque vidéo coupée son son d'avant : retire les accesseurs posés
  // sur l'instance (on retombe sur ceux du prototype) puis remet les valeurs
  // relevées au moment de la coupure.
  function restoreVideoAudio() {
    for (var i = 0; i < mutedVideos.length; i++) {
      var v = mutedVideos[i];
      v.__sawtunaa_muting = false;
      try { delete v.muted; delete v.volume; } catch(e) {}
      var saved = v.__sawtunaa_saved || { muted: false, volume: 1 };
      nativeSetVolume(v, saved.volume);
      nativeSetMuted(v, saved.muted);
      metric('audio_restored', {
        video_ms: Math.round(v.currentTime * 1000),
        saved_muted: saved.muted,
        saved_volume: saved.volume,
        paused: v.paused
      });
      // WebKit peut refuser/mettre en pause un démute sans geste dans la page :
      // on veut le VOIR dans les journaux, pas le supposer.
      (function(video) {
        setTimeout(function() {
          metric('audio_restored_check', {
            muted: nativeGetMuted(video),
            volume: nativeGetVolume(video),
            paused: video.paused
          });
        }, 700);
      })(v);
    }
    mutedVideos = [];
  }

  // ─── Auto-activate: mute video, start scheduler ───
  function autoActivate() {
    if (isActive || !enabled) return;
    isActive = true;
    var v = document.querySelector('video');
    forceMuteVideo(v);
    startPlaybackScheduler();
    metric('auto_activate', {
      video_ms: v ? Math.round(v.currentTime * 1000) : -1,
      decoded_segments: decodedSegments.length
    });
  }

  // ─── Early activation watcher ───
  var earlyActivationInterval = null;
  function startEarlyActivationWatcher() {
    if (earlyActivationInterval || isActive || !enabled) return;
    earlyActivationInterval = setInterval(function() {
      if (isActive || !enabled) {
        clearInterval(earlyActivationInterval);
        earlyActivationInterval = null;
        return;
      }
      var vid = document.querySelector('video');
      if (vid && !vid.paused && vid.currentTime > 0.05 && decodedSegments.length > 0) {
        clearInterval(earlyActivationInterval);
        earlyActivationInterval = null;
        autoActivate();
      }
    }, 50);
  }

  // Detect content change (pre-roll ad → main video, SSAI insertion, etc.)
  // vs seek in the same content. We rely on `video.duration` because:
  //   - pub and main video have different durations → detected
  //   - seek in the same content keeps duration stable → not detected
  //   - codec params are identical for ad and video → unreliable signal
  //   - init segment bytes carry a Track UID that differs even between
  //     seeks of the same video → false positives
  // Also need to keep the cache untouched on plain seeks: YouTube only
  // ever re-delivers chunks via appendBuffer when the seek target is
  // outside its sb.buffered window (~20-30s on mobile). If we drop the
  // cache here, a 5s rewind into the YouTube-buffered zone would have no
  // audio at all (we never get a re-delivery to refill our cache).
  var lastInitSegDuration = -1;

  // ─── Init segment : vu dans tous les modes (veille comprise) ───
  // Détecte un changement de contenu (cf. ci-dessus) et garde l'en-tête pour
  // pouvoir démarrer un décodeur plus tard, à l'allumage.
  // Renvoie `true` si le contenu a changé (l'audio en attente est périmé).
  function noteInitSegment(buf) {
    var v = document.querySelector('video');
    var currentDuration = (v && isFinite(v.duration) && v.duration > 0)
      ? v.duration : -1;
    var prevDuration = lastInitSegDuration;
    var contentChanged = prevDuration > 0 && currentDuration > 0
        && Math.abs(currentDuration - prevDuration) > 2;
    if (contentChanged) {
      metric('content_change_detected', {
        prev_duration_s: Math.round(prevDuration),
        new_duration_s: Math.round(currentDuration)
      });
      // L'audio gardé en veille appartient à l'ancien contenu.
      standbyClear();
      appendLastEndMs = -1;
      if (enabled) send('pageReset', 'duration_change');
    }
    if (currentDuration > 0) lastInitSegDuration = currentDuration;
    standbyInit = buf.slice(0);
    return contentChanged;
  }

  // ─── Init decoder from init segment ───
  // Remet à zéro l'état de décodage et crée un décodeur Opus (actif seulement).
  // `dropPending` : jeter les segments en attente de décodeur. Seulement si le
  // contenu a changé : un nouvel init du MÊME contenu (YouTube en envoie un à
  // chaque changement de format/qualité, fréquent en début de lecture) ne doit
  // pas jeter l'audio gardé en veille qu'on vient de remettre en file à
  // l'allumage — sinon plus rien pour la position courante, seulement l'audio
  // que YouTube charge ~30 s plus loin (silence, recette Karim 2026-10-01).
  // Ce sont des paquets Opus déjà analysés : n'importe quel décodeur les lit.
  function onInitSegment(buf, dropPending) {
    initInfo = parseInitSegment(buf);
    if (dropPending || !decoderInitializing) pendingSegments = [];
    decoderInitializing = true;
    decodedSegments = [];
    lastEstimatedEndMs = 0;
    opusDecoder = null;
    isActive = false;
    audioPaused = false;
    lastVideoTimeMs = -1;
    pendingLen = 0;
    pendingStartMs = 0;
    pendingEndMs = 0;

    metric('init_segment', {
      channels: initInfo.channels,
      preSkip: initInfo.preSkip,
      bytes: buf.byteLength
    });

    // NOTE: do NOT send clearChunks here. YouTube emits a new init_segment
    // after each seek (to re-init the Opus decoder), but the audio cache
    // remains valid for the same video timeline. Clearing it would wipe
    // chunks the user might come back to (e.g. rewind after seek).

    var decoder = new OpusDecoderLib.OpusDecoder({
      channels: initInfo.channels,
      sampleRate: 48000,
      preSkip: initInfo.preSkip,
      streamCount: 1,
      coupledStreamCount: initInfo.channels === 2 ? 1 : 0,
      channelMappingTable: initInfo.channels === 2 ? [0, 1] : [0],
    });

    var generation = decoderGeneration;
    var decoderStartedAt = performance.now();
    decoder.ready.then(function() {
      if (generation !== decoderGeneration) {
        freeDecoder(decoder);
        return;
      }
      opusDecoder = decoder;
      decoderInitializing = false;
      metric('decoder_ready', {
        load_ms: Math.round(performance.now() - decoderStartedAt),
        pending: pendingSegments.length
      });
      var pending = pendingSegments;
      pendingSegments = [];
      for (var i = 0; i < pending.length; i++) {
        decodeParsedSegment(pending[i]);
      }
    }).catch(function(e) {
      decoderInitializing = false;
      metric('decoder_error', { msg: e.message });
    });
  }

  function freeDecoder(d) {
    try { if (d && typeof d.free === 'function') d.free(); } catch(e) {}
  }

  // ─── Decode + send media segment ───
  function decodeParsedSegment(parsed) {
    if (!opusDecoder) {
      if (decoderInitializing) pendingSegments.push(parsed);
      return;
    }
    if (parsed.packets.length === 0) return;

    var decodeStart = performance.now();
    try {
      var result = opusDecoder.decodeFrames(parsed.packets);
      if (!result || result.samplesDecoded === 0) return;
      var decodeMs = Math.round(performance.now() - decodeStart);
      var vidNow = document.querySelector('video');
      metric('decode_done', {
        packets: parsed.packets.length,
        samples: result.samplesDecoded,
        bytes: parsed.bytes || segmentBytes(parsed),
        ts: parsed.startTimeMs,
        decode_ms: decodeMs,
        video_ms: vidNow ? Math.round(vidNow.currentTime * 1000) : -1
      });

      var durationMs = parsed.packets.length * 20;
      var startTimeMs = parsed.startTimeMs;
      // Sanity check: EBML parser may produce false positives if 0xE7 appears
      // inside Opus content (looks like Cluster Timestamp). Reject if out of
      // range OR if it jumps > 60s from the previous estimated position.
      var aberrant = startTimeMs < 0 || startTimeMs > 24 * 3600 * 1000 || !isFinite(startTimeMs);
      if (!aberrant && lastEstimatedEndMs > 0) {
        var jump = Math.abs(startTimeMs - lastEstimatedEndMs);
        if (jump > 60000) {
          aberrant = true;  // > 60s jump suggests false positive
        }
      }
      if (aberrant) {
        if (parsed.startTimeMs !== -1) {
          metric('invalid_timestamp', {
            raw: String(parsed.startTimeMs),
            last_estimated: Math.round(lastEstimatedEndMs)
          });
        }
        startTimeMs = lastEstimatedEndMs;
      }
      lastEstimatedEndMs = startTimeMs + durationMs;

      var totalSamples = result.samplesDecoded;
      // A mono source is duplicated onto both channels: the native side is
      // always fed 2 planar channels, so it never has to branch on layout.
      var srcL = result.channelData[0];
      var srcR = result.channelData.length === 2 ? result.channelData[1] : srcL;

      // Append to pending aggregation buffer (smooths out YouTube's micro-segments
      // — 22% of segments are <100ms which would create choppy playback if sent
      // directly). We flush full 1s chunks to Swift below.
      // If non-contiguous (gap or jump in source time), flush the pending buffer
      // first to avoid mixing chunks with broken timestamps.
      if (pendingLen > 0 && Math.abs(startTimeMs - pendingEndMs) > 50) {
        flushPending();
      }
      if (pendingLen === 0) {
        pendingStartMs = startTimeMs;
      }
      // Append to the per-channel pending buffers (resize if needed)
      if (pendingLen + totalSamples > pendingL.length) {
        var newCap = Math.max(pendingL.length * 2, pendingLen + totalSamples + CHUNK_SAMPLES);
        var grownL = new Float32Array(newCap);
        var grownR = new Float32Array(newCap);
        grownL.set(pendingL.subarray(0, pendingLen));
        grownR.set(pendingR.subarray(0, pendingLen));
        pendingL = grownL;
        pendingR = grownR;
      }
      pendingL.set(srcL.subarray(0, totalSamples), pendingLen);
      pendingR.set(srcR.subarray(0, totalSamples), pendingLen);
      pendingLen += totalSamples;
      pendingEndMs = startTimeMs + durationMs;

      // Flush full 1s chunks while we have enough samples
      while (pendingLen >= CHUNK_SAMPLES) {
        sendChunkToSwift(pendingL, pendingR, CHUNK_SAMPLES, pendingStartMs);
        decodedSegments.push({ startTimeMs: pendingStartMs, durationMs: 1000 });
        // Shift remaining samples left
        pendingL.copyWithin(0, CHUNK_SAMPLES, pendingLen);
        pendingR.copyWithin(0, CHUNK_SAMPLES, pendingLen);
        pendingLen -= CHUNK_SAMPLES;
        pendingStartMs += 1000;
      }

      if (!isActive) {
        startEarlyActivationWatcher();
        var vid = document.querySelector('video');
        if (vid && !vid.paused && vid.currentTime > 0.05 && decodedSegments.length > 0) {
          autoActivate();
        }
      }

      segmentCount++;
    } catch(e) {
      metric('decode_error', { msg: e.message });
    }
  }

  // ─── Playback scheduler ───
  function startPlaybackScheduler() {
    if (schedulerInterval) return;
    schedulerInterval = setInterval(function() {
      var vid = document.querySelector('video');
      if (!vid || !isActive) return;

      // YouTube may swap the <video> element across SPA navigations or
      // fullscreen transitions. Re-attach our mute enforcer if so.
      forceMuteVideo(vid);

      // L'audio natif ne doit courir QUE quand l'image avance. `paused` ne
      // suffit pas : une vidéo qui cale (rebuffering, seek en cours, reprise
      // qui tarde) reste `paused === false` alors que son horloge est figée —
      // l'audio filait devant l'image et le décalage restait jusqu'au seek
      // suivant. On coupe donc aussi quand `currentTime` n'a pas bougé depuis
      // STALL_MS (plus long que le rafraîchissement de `currentTime`), et à la
      // reprise le natif se ré-ancre sur la position réelle.
      var nowWall = Date.now();
      var currentTimeMs = vid.currentTime * 1000;
      if (currentTimeMs !== lastSeenTimeMs) {
        lastSeenTimeMs = currentTimeMs;
        lastAdvanceWallMs = nowWall;
      }
      // ⚠️ Détection du saut AVANT la coupure ci-dessous : pendant un seek la
      // vidéo est `seeking` (donc on sort du tick), et YouTube livre déjà
      // l'audio de la nouvelle position. Si `lastEstimatedEndMs` pointe encore
      // l'ancienne, ces blocs sont jugés aberrants (saut > 60 s) et re-datés à
      // l'ancienne position : silence jusqu'au prochain envoi de YouTube, plus
      // d'une minute (régression du 2026-09-30, curseur posé loin).
      if (lastVideoTimeMs >= 0 && Math.abs(currentTimeMs - lastVideoTimeMs) > 2000) {
        metric('seek_detected', {
          from_ms: Math.round(lastVideoTimeMs),
          to_ms: Math.round(currentTimeMs),
          pending_len: pendingLen,
          last_estimated_end_ms: Math.round(lastEstimatedEndMs)
        });
        // Flush the pending aggregation buffer to avoid mixing samples from
        // the pre-seek timeline with post-seek samples in the next chunk.
        flushPending();
        decodedSegments = [];
        // CRITICAL: reset the estimated continuation timestamp. Without this,
        // post-seek segments arriving with valid ts (e.g. 120s after seeking
        // to 2:00) would be rejected by the >60s jump validation (because
        // lastEstimatedEndMs was still ~49s pre-seek), then replaced by the
        // stale 49s value — corrupting the cache with wrong timestamps.
        lastEstimatedEndMs = 0;
        send('seekTo', '' + Math.round(currentTimeMs));
      }
      lastVideoTimeMs = currentTimeMs;

      var stalled = vid.seeking || (nowWall - lastAdvanceWallMs > STALL_MS);
      if (vid.paused || stalled) {
        if (!audioPaused) {
          audioPaused = true;
          metric(vid.paused ? 'video_paused' : 'video_stalled', {
            video_ms: Math.round(currentTimeMs),
            seeking: vid.seeking,
            ready_state: vid.readyState
          });
          send('pauseAudio');
        }
        return;
      }
      if (audioPaused) {
        audioPaused = false;
        metric('video_resumed', { video_ms: Math.round(currentTimeMs) });
        send('resumeAudio');
      }

      // Position BRUTE + instant du relevé : le natif compense lui-même le
      // transit du message et la latence de sortie réelle (haut-parleur ≠
      // AirPods). L'ancienne avance fixe de +100 ms faisait sortir l'audio
      // avant l'image sur le haut-parleur de l'iPhone.
      send('playAt', Math.round(currentTimeMs) + '|' + nowWall + '|' + (vid.playbackRate || 1));

      while (decodedSegments.length > 0 &&
             decodedSegments[0].startTimeMs + decodedSegments[0].durationMs < currentTimeMs - 1000) {
        decodedSegments.shift();
      }
    }, 30);
  }

  // ─── Detect init segment ───
  function isInitSeg(bytes) {
    if (bytes.byteLength < 4) return false;
    var d = new Uint8Array(bytes);
    return d[0] === 0x1A && d[1] === 0x45 && d[2] === 0xDF && d[3] === 0xA3;
  }

  // ─── Patch SourceBuffer.appendBuffer/remove/abort ───
  // These three methods are how YouTube manipulates its MSE audio buffer.
  // We mirror them on the Swift side so our cache reflects exactly what
  // YouTube has in its internal buffer — enabling instant seek into already-
  // buffered regions.
  function patchSB(sb) {
    if (sbPatched) return;
    try {
      var proto = Object.getPrototypeOf(sb);

      var origAppend = proto.appendBuffer;
      proto.appendBuffer = function(data) {
        if (audioBuffers.indexOf(this) >= 0) {
          var bytes = (data instanceof ArrayBuffer) ? data :
                      (ArrayBuffer.isView(data) ? data.buffer.slice(
                          data.byteOffset, data.byteOffset + data.byteLength) : data);
          try {
            if (isInitSeg(bytes)) {
              var changed = noteInitSegment(bytes);
              if (enabled) onInitSegment(bytes, changed);
            } else {
              // Analysé une seule fois, gardé (copie compressée) dans tous les
              // modes : c'est la source de l'allumage sans rechargement.
              var parsed = parseMediaSegment(bytes);
              dateMediaSegment(parsed, this);
              standbyStore(parsed);
              if (enabled) decodeParsedSegment(parsed);
            }
          } catch(e) {
            metric('append_hook_error', { msg: e.message });
          }
        }
        return origAppend.call(this, data);
      };

      var origRemove = proto.remove;
      if (origRemove) {
        proto.remove = function(start, end) {
          if (audioBuffers.indexOf(this) >= 0) {
            standbyEvict(start * 1000, end * 1000);
            send('evictRange', Math.round(start * 1000) + '|' + Math.round(end * 1000));
            metric('sb_remove', { start_ms: Math.round(start * 1000), end_ms: Math.round(end * 1000) });
          }
          return origRemove.call(this, start, end);
        };
      }

      var origAbort = proto.abort;
      if (origAbort) {
        proto.abort = function() {
          if (audioBuffers.indexOf(this) >= 0) {
            metric('sb_abort', {});
          }
          return origAbort.call(this);
        };
      }

      sbPatched = true;
    } catch(e) {
      LOG('Error patching SB: ' + e.message);
    }
  }

  // ─── Patch MediaSource.addSourceBuffer ───
  function patchMSE(proto) {
    try {
      var orig = proto.addSourceBuffer;
      proto.addSourceBuffer = function(mimeType) {
        var sb = orig.call(this, mimeType);
        patchSB(sb);
        var isAudio = mimeType.indexOf('audio/') === 0;
        // Seul l'Opus en WebM est décodable ici. Depuis que le script tourne
        // aussi Sawtunaa éteint (veille), suivre un flux AAC/MP4 reviendrait à
        // analyser et garder des octets illisibles sur tous les sites
        // (garde-fou repris d'Android, 2026-10-01).
        if (isAudio && /webm|opus/i.test(mimeType)) {
          audioBuffers.push(sb);
        }
        // Structured metric: lets us survey codec usage across sites
        // (YouTube uses Opus, most others use AAC). Helps decide which
        // decoders to bundle.
        metric('source_buffer_added', {
          mime_type: mimeType,
          host: location.host,
          is_audio: isAudio,
          source: proto === (typeof MediaSource !== 'undefined'
            ? MediaSource.prototype : null) ? 'MS' : 'MMS'
        });
        return sb;
      };
    } catch(e) {
      LOG('Error patching MSE: ' + e.message);
      metric('mse_patch_error', { msg: e.message });
    }
  }

  if (hasMS) patchMSE(MediaSource.prototype);
  if (hasMMS) patchMSE(ManagedMediaSource.prototype);

  metric('mse_hooks_installed', { enabled: enabled });

  // ─── Allumage / extinction en direct (appelé par le natif) ───
  // ⛔ Aucun rechargement : la vidéo garde sa position.
  // OFF : le son d'origine revient tout de suite et le lecteur natif s'arrête ;
  //       la veille continue de garder l'audio compressé.
  // ON  : le son de la vidéo est coupé tout de suite, puis l'audio gardé est
  //       décodé à partir de la position courante (~1 s avant le son traité,
  //       le temps du décodeur et du premier bloc NSNet2).
  function setEnabled(on) {
    on = !!on;
    if (on === enabled) return;
    enabled = on;
    decoderGeneration++;
    var v = document.querySelector('video');
    var nowMs = v ? Math.round(v.currentTime * 1000) : -1;
    metric(on ? 'live_enable' : 'live_disable', {
      video_ms: nowMs,
      standby_segments: standbySegments.length,
      standby_kb: Math.round(standbyBytes / 1024),
      has_init: !!standbyInit
    });

    if (!on) {
      isActive = false;
      if (schedulerInterval) { clearInterval(schedulerInterval); schedulerInterval = null; }
      if (earlyActivationInterval) { clearInterval(earlyActivationInterval); earlyActivationInterval = null; }
      restoreVideoAudio();
      freeDecoder(opusDecoder);
      opusDecoder = null;
      decoderInitializing = false;
      pendingSegments = [];
      decodedSegments = [];
      pendingLen = 0;
      audioPaused = false;
      lastVideoTimeMs = -1;
      send('deactivate');
      return;
    }

    send('activate');
    // Couper tout de suite une vidéo qui joue : mieux vaut ~1 s de silence
    // que ~1 s de musique juste après avoir demandé de l'enlever.
    if (v && !v.paused) forceMuteVideo(v);
    if (!standbyInit) return;  // rien encore : le prochain init segment démarrera tout
    onInitSegment(standbyInit, true);
    var fromMs = nowMs >= 0 ? nowMs - 500 : -Infinity;
    standbySegments
      .filter(function(seg) { return seg.endTimeMs > fromMs; })
      .sort(function(a, b) { return a.startTimeMs - b.startTimeMs; })
      .forEach(function(seg) { pendingSegments.push(seg); });
    startEarlyActivationWatcher();
  }
  window.__sawtunaaSetEnabled = setEnabled;

  // Periodic video state polling. 2s is enough to catch state transitions
  // for diagnostics (paused, readyState changes); the engine_state poll on
  // the Swift side runs at 1Hz so we already have fine-grained sync data.
  // Going faster here just spams the log without adding signal.
  setInterval(function() {
    if (!enabled) return;
    var v = document.querySelector('video');
    if (!v) return;
    var bufferedMs = -1;
    try {
      if (v.buffered.length > 0) {
        bufferedMs = Math.round(v.buffered.end(v.buffered.length - 1) * 1000);
      }
    } catch(e) {}
    metric('video_state', {
      currentTime_ms: Math.round(v.currentTime * 1000),
      paused: v.paused,
      muted: v.muted,
      volume: v.volume,
      readyState: v.readyState,
      buffered_end_ms: bufferedMs,
      ready_chunks: decodedSegments.length,
      active: isActive
    });
  }, 2000);

  // NOTE: previously we synced our cache to sb.buffered every 5s, with the
  // intent to evict chunks the browser silently dropped on MSE quota.
  // Disabled because YouTube's sb.buffered shrinks aggressively after seeks
  // (only retains a window around the new position), which would wipe chunks
  // the user might rewind to. The LRU cap (600 chunks ~10min) is a sufficient
  // memory safety net. Explicit SourceBuffer.remove() calls still hit our
  // evictRange handler.
});
