// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// Sawtunaa: MSE SourceBuffer interception + Opus decode + native NSNet2 playback.
// This script intercepts audio data from YouTube's MediaSource Extensions,
// decodes Opus packets via WASM, and sends mono PCM to Swift for noise suppression.

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

  metric('script_init', { hasMS: hasMS, hasMMS: hasMMS });

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
        continue;
      } else if (data[pos] === 0xE7 && pos + 1 < data.length) {
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

  // Aggregation buffer: accumulates mono PCM until we can send a full 1s chunk.
  // Smooths out YouTube's micro-segments (22% are <100ms) which would otherwise
  // create many tiny scheduleBuffer calls and audible micro-glitches.
  var pendingMono = new Float32Array(CHUNK_SAMPLES * 2);
  var pendingMonoLen = 0;
  var pendingMonoStartMs = 0;
  var pendingMonoEndMs = 0;

  function flushPendingMono() {
    if (pendingMonoLen <= 0) return;
    var chunkSlice = new Float32Array(pendingMono.buffer, pendingMono.byteOffset, pendingMonoLen);
    sendChunkToSwift(chunkSlice, pendingMonoStartMs);
    decodedSegments.push({ startTimeMs: pendingMonoStartMs, durationMs: pendingMonoLen / 48 });
    pendingMonoLen = 0;
  }

  // ─── Send mono PCM chunk to Swift for NSNet2 processing ───
  var chunkSendCount = 0;
  function sendChunkToSwift(monoChunk, timestampMs) {
    try {
      var binary = '';
      var bytes = new Uint8Array(monoChunk.buffer, monoChunk.byteOffset, monoChunk.byteLength);
      for (var j = 0; j < bytes.length; j++) {
        binary += String.fromCharCode(bytes[j]);
      }
      var b64 = btoa(binary);
      send('preprocess', Math.round(timestampMs) + '|' + b64);
      chunkSendCount++;
      metric('chunk_send', {
        chunk_ts: Math.round(timestampMs),
        samples: monoChunk.length,
        idx: chunkSendCount
      });
    } catch(e) {
      metric('chunk_send_error', { msg: e.message });
    }
  }

  // ─── Force-mute video element persistently ───
  function forceMuteVideo(v) {
    if (!v) return;
    v.muted = true;
    v.volume = 0;

    // Override volume/muted setters to prevent YouTube from unmuting
    try {
      var proto = Object.getPrototypeOf(v);
      if (!proto.__sawtunaa_patched) {
        var volDesc = Object.getOwnPropertyDescriptor(proto, 'volume')
          || Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'volume');
        var mutedDesc = Object.getOwnPropertyDescriptor(proto, 'muted')
          || Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'muted');

        if (volDesc && volDesc.set) {
          Object.defineProperty(v, 'volume', {
            get: function() { return 0; },
            set: function() { /* blocked */ },
            configurable: true
          });
        }
        if (mutedDesc && mutedDesc.set) {
          Object.defineProperty(v, 'muted', {
            get: function() { return true; },
            set: function() { /* blocked */ },
            configurable: true
          });
        }
        proto.__sawtunaa_patched = true;
        LOG('Video volume/muted locked');
      }
    } catch(e) {
      // Fallback: re-mute on interval
      LOG('Could not lock volume: ' + e.message);
    }
  }

  // ─── Auto-activate: mute video, start scheduler ───
  function autoActivate() {
    if (isActive) return;
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
    if (earlyActivationInterval || isActive) return;
    earlyActivationInterval = setInterval(function() {
      if (isActive) {
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

  // ─── Init decoder from init segment ───
  function onInitSegment(buf) {
    initInfo = parseInitSegment(buf);
    decoderInitializing = true;
    pendingSegments = [];
    decodedSegments = [];
    lastEstimatedEndMs = 0;
    opusDecoder = null;
    isActive = false;
    audioPaused = false;
    lastVideoTimeMs = -1;
    pendingMonoLen = 0;
    pendingMonoStartMs = 0;
    pendingMonoEndMs = 0;

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

    var decoderStartedAt = performance.now();
    decoder.ready.then(function() {
      opusDecoder = decoder;
      decoderInitializing = false;
      metric('decoder_ready', {
        load_ms: Math.round(performance.now() - decoderStartedAt),
        pending: pendingSegments.length
      });
      for (var i = 0; i < pendingSegments.length; i++) {
        onMediaSegment(pendingSegments[i]);
      }
      pendingSegments = [];
    }).catch(function(e) {
      decoderInitializing = false;
      metric('decoder_error', { msg: e.message });
    });
  }

  // ─── Decode + send media segment ───
  function onMediaSegment(buf) {
    if (!opusDecoder) {
      if (decoderInitializing) {
        pendingSegments.push(buf.slice ? buf.slice(0) : new Uint8Array(buf).buffer);
      }
      return;
    }

    var parsed = parseMediaSegment(buf);
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
        bytes: buf.byteLength,
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
      var mono = new Float32Array(totalSamples);
      if (result.channelData.length === 2) {
        for (var mi = 0; mi < totalSamples; mi++) {
          mono[mi] = (result.channelData[0][mi] + result.channelData[1][mi]) * 0.5;
        }
      } else {
        mono.set(result.channelData[0]);
      }

      // Append to pending aggregation buffer (smooths out YouTube's micro-segments
      // — 22% of segments are <100ms which would create choppy playback if sent
      // directly). We flush full 1s chunks to Swift below.
      // If non-contiguous (gap or jump in source time), flush the pending buffer
      // first to avoid mixing chunks with broken timestamps.
      if (pendingMonoLen > 0 && Math.abs(startTimeMs - pendingMonoEndMs) > 50) {
        flushPendingMono();
      }
      if (pendingMonoLen === 0) {
        pendingMonoStartMs = startTimeMs;
      }
      // Append mono samples to pendingMono (resize if needed)
      if (pendingMonoLen + totalSamples > pendingMono.length) {
        var newCap = Math.max(pendingMono.length * 2, pendingMonoLen + totalSamples + CHUNK_SAMPLES);
        var grown = new Float32Array(newCap);
        grown.set(pendingMono.subarray(0, pendingMonoLen));
        pendingMono = grown;
      }
      pendingMono.set(mono, pendingMonoLen);
      pendingMonoLen += totalSamples;
      pendingMonoEndMs = startTimeMs + durationMs;

      // Flush full 1s chunks while we have enough samples
      while (pendingMonoLen >= CHUNK_SAMPLES) {
        var chunkSlice = new Float32Array(pendingMono.buffer, pendingMono.byteOffset, CHUNK_SAMPLES);
        sendChunkToSwift(chunkSlice, pendingMonoStartMs);
        decodedSegments.push({ startTimeMs: pendingMonoStartMs, durationMs: 1000 });
        // Shift remaining samples left
        pendingMono.copyWithin(0, CHUNK_SAMPLES, pendingMonoLen);
        pendingMonoLen -= CHUNK_SAMPLES;
        pendingMonoStartMs += 1000;
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

      if (vid.paused) {
        if (!audioPaused) {
          audioPaused = true;
          send('pauseAudio');
        }
        return;
      }
      if (audioPaused) {
        audioPaused = false;
        send('resumeAudio');
      }

      var currentTimeMs = vid.currentTime * 1000;

      if (lastVideoTimeMs >= 0 && Math.abs(currentTimeMs - lastVideoTimeMs) > 2000) {
        metric('seek_detected', {
          from_ms: Math.round(lastVideoTimeMs),
          to_ms: Math.round(currentTimeMs),
          pending_mono_len: pendingMonoLen
        });
        // Flush the pending aggregation buffer to avoid mixing samples from
        // the pre-seek timeline with post-seek samples in the next chunk.
        flushPendingMono();
        decodedSegments = [];
        send('seekTo', '' + Math.round(currentTimeMs));
      }
      lastVideoTimeMs = currentTimeMs;

      send('playAt', '' + (currentTimeMs + 100));

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
          if (isInitSeg(bytes)) {
            onInitSegment(bytes);
          } else {
            onMediaSegment(bytes);
          }
        }
        return origAppend.call(this, data);
      };

      var origRemove = proto.remove;
      if (origRemove) {
        proto.remove = function(start, end) {
          if (audioBuffers.indexOf(this) >= 0) {
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
        if (mimeType.indexOf('audio/') === 0) {
          audioBuffers.push(sb);
          LOG('Audio SB: ' + mimeType);
        }
        return sb;
      };
    } catch(e) {
      LOG('Error patching MSE: ' + e.message);
    }
  }

  if (hasMS) patchMSE(MediaSource.prototype);
  if (hasMMS) patchMSE(ManagedMediaSource.prototype);

  metric('mse_hooks_installed', {});

  // Periodic video state polling (every 500ms)
  setInterval(function() {
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
  }, 500);

  // NOTE: previously we synced our cache to sb.buffered every 5s, with the
  // intent to evict chunks the browser silently dropped on MSE quota.
  // Disabled because YouTube's sb.buffered shrinks aggressively after seeks
  // (only retains a window around the new position), which would wipe chunks
  // the user might rewind to. The LRU cap (600 chunks ~10min) is a sufficient
  // memory safety net. Explicit SourceBuffer.remove() calls still hit our
  // evictRange handler.
});
