// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// Basarunaa V1 (étape A) : flou CSS naïf sur toutes les <img>.
// Pas de ML — c'est juste le PoC du pipeline d'interception (script handler,
// lifecycle tab, MutationObserver). L'étape B branchera l'analyse ML par image.

window.__firefox__.includeOnce("BasarunaaScript", function($) {
  'use strict';

  // ─── Bridge to Swift ───
  function send(action, data) {
    try {
      $.postNativeMessage('$<message_handler>', {
        securityToken: SECURITY_TOKEN,
        action: action,
        data: data || ''
      });
    } catch (e) {}
  }

  var sessionStart = (typeof performance !== 'undefined' && performance.now)
    ? performance.now()
    : Date.now();
  function metric(event, kvs) {
    var now = (typeof performance !== 'undefined' && performance.now)
      ? performance.now() : Date.now();
    var obj = { t: Math.round(now - sessionStart), event: event, src: 'js' };
    if (kvs) for (var k in kvs) if (Object.prototype.hasOwnProperty.call(kvs, k)) obj[k] = kvs[k];
    try { send('metric', JSON.stringify(obj)); } catch (e) {}
  }

  // ─── Config ───
  // V1: hard-coded blur intensity. V2 will read Preferences.Basarunaa.blurStrength
  // from Swift via an initial postMessage round-trip.
  var BLUR_RADIUS_PX = 20;
  var BLUR_MARKER = 'data-basarunaa-blurred';
  var ID_ATTR = 'data-basarunaa-id';
  var STATE_ATTR = 'data-basarunaa-state';
  var MAX_DIM = 800;
  var MIN_DIM = 64;

  var nextId = 1;

  // ─── Blur application ───
  // We use inline `style.setProperty(..., 'important')` because:
  //   1. `!important` on inline style beats virtually any page-level CSS.
  //   2. Some sites (Google Images, social feeds) mutate the DOM aggressively;
  //      we track STATE_ATTR='remove' so an analyzed-safe image is never
  //      re-blurred even when its parent or src changes.
  function applyBlurTo(img) {
    if (!img || img.nodeType !== 1 || img.tagName !== 'IMG') return false;
    if (img.getAttribute(STATE_ATTR) === 'remove') return false;
    if (img.getAttribute(BLUR_MARKER) === '1') return false;
    try {
      img.style.setProperty('filter', 'blur(' + BLUR_RADIUS_PX + 'px)', 'important');
      img.setAttribute(BLUR_MARKER, '1');
      return true;
    } catch (e) {
      return false;
    }
  }

  function removeBlurFrom(img) {
    try {
      img.style.setProperty('filter', 'none', 'important');
      img.removeAttribute(BLUR_MARKER);
    } catch (e) {}
  }

  function scanAndBlur(root) {
    var imgs = (root || document).querySelectorAll('img');
    var n = 0;
    for (var i = 0; i < imgs.length; i++) {
      if (applyBlurTo(imgs[i])) n++;
    }
    return n;
  }

  // ─── Image → base64 (async) ───
  //
  // Strategy:
  //   1. Try `fetch(img.src, { mode: 'cors' })` first. This is served by the
  //      browser's HTTP cache (no double download), bypasses canvas taint, and
  //      works for any URL whose server returns Access-Control-Allow-Origin
  //      (Wikipedia, most CDNs, Google Images).
  //   2. Fallback to canvas.toDataURL for data: / blob: URLs, or same-origin
  //      images whose servers don't send CORS headers.
  function bytesToBase64(bytes) {
    // chunked to avoid `String.fromCharCode.apply` stack overflows on big arrays
    var binary = '';
    var chunk = 0x8000;
    for (var i = 0; i < bytes.length; i += chunk) {
      binary += String.fromCharCode.apply(null, bytes.subarray(i, i + chunk));
    }
    return btoa(binary);
  }

  function encodeImage(img) {
    return new Promise(function(resolve) {
      var src = img.currentSrc || img.src;
      if (!src) {
        metric('encode_no_src', { id: img.getAttribute(ID_ATTR) });
        resolve(null);
        return;
      }
      // data: / blob: URLs go straight to canvas
      if (/^(data|blob):/.test(src)) {
        resolve(encodeImageViaCanvas(img));
        return;
      }
      // Try CORS fetch (uses HTTP cache, no double network call)
      var aborted = false;
      var timeout = setTimeout(function() {
        aborted = true;
        metric('encode_fetch_timeout', { id: img.getAttribute(ID_ATTR), src: src.slice(0, 80) });
        resolve(encodeImageViaCanvas(img));
      }, 5000);
      fetch(src, { mode: 'cors', credentials: 'omit', cache: 'force-cache' })
        .then(function(r) {
          if (!r.ok) throw new Error('http_' + r.status);
          return r.arrayBuffer();
        })
        .then(function(buf) {
          if (aborted) return;
          clearTimeout(timeout);
          resolve(bytesToBase64(new Uint8Array(buf)));
        })
        .catch(function(e) {
          if (aborted) return;
          clearTimeout(timeout);
          metric('encode_fetch_failed', {
            id: img.getAttribute(ID_ATTR),
            src: src.slice(0, 80),
            err: ('' + e).slice(0, 120)
          });
          resolve(encodeImageViaCanvas(img));
        });
    });
  }

  function encodeImageViaCanvas(img) {
    try {
      var w = img.naturalWidth || img.width;
      var h = img.naturalHeight || img.height;
      if (!w || !h) return null;
      var scale = Math.min(1, MAX_DIM / Math.max(w, h));
      var cw = Math.max(1, Math.round(w * scale));
      var ch = Math.max(1, Math.round(h * scale));
      var canvas = document.createElement('canvas');
      canvas.width = cw;
      canvas.height = ch;
      var ctx = canvas.getContext('2d');
      if (!ctx) return null;
      ctx.drawImage(img, 0, 0, cw, ch);
      var dataUrl = canvas.toDataURL('image/jpeg', 0.85);
      var commaIdx = dataUrl.indexOf(',');
      if (commaIdx < 0) return null;
      return dataUrl.slice(commaIdx + 1);
    } catch (e) {
      metric('encode_canvas_failed', { msg: ('' + e).slice(0, 120) });
      return null;
    }
  }

  // ─── Analysis queue (concurrency 1) ───
  var queue = [];
  var analyzing = false;
  function enqueueAnalyze(img) {
    if (!img || img.tagName !== 'IMG') return;
    if (img.hasAttribute(ID_ATTR)) return;  // already queued/analyzed
    var w = img.naturalWidth || img.width;
    var h = img.naturalHeight || img.height;
    if (w < MIN_DIM || h < MIN_DIM) return;  // skip tiny icons
    if (!img.complete || w === 0 || h === 0) {
      // wait for load, then re-enqueue
      img.addEventListener('load', function() { enqueueAnalyze(img); }, { once: true });
      return;
    }
    var id = nextId++;
    img.setAttribute(ID_ATTR, String(id));
    img.setAttribute(STATE_ATTR, 'pending');
    queue.push({ id: id, img: img });
    drain();
  }

  function drain() {
    if (analyzing) return;
    var job = queue.shift();
    if (!job) return;
    analyzing = true;
    encodeImage(job.img).then(function(b64) {
      if (!b64) {
        // could not encode (broken img, opaque server) — keep default blur
        job.img.setAttribute(STATE_ATTR, 'keep');
        analyzing = false;
        drain();
        return;
      }
      metric('analyze_send', {
        id: job.id,
        w: job.img.naturalWidth,
        h: job.img.naturalHeight,
        bytes: b64.length
      });
      send('analyzeImage', job.id + '|' + b64);
      // Swift will call window.__basarunaaApply(id, decision) when done.
      // drain() resumes inside __basarunaaApply.
    }).catch(function(e) {
      metric('encode_unexpected_error', { msg: ('' + e).slice(0, 120) });
      job.img.setAttribute(STATE_ATTR, 'keep');
      analyzing = false;
      drain();
    });
  }

  function findById(id) {
    return document.querySelector('[' + ID_ATTR + '="' + id + '"]');
  }

  // ─── Receive decision from Swift ───
  window.__basarunaaApply = function(id, decision) {
    try {
      var img = findById(id);
      metric('analyze_decision', { id: id, decision: '' + decision, found: !!img });
      if (img) {
        img.setAttribute(STATE_ATTR, decision);
        if (decision === 'remove') {
          removeBlurFrom(img);
        }
      }
    } catch (e) {
      metric('apply_error', { msg: '' + e });
    } finally {
      analyzing = false;
      drain();
    }
  };

  // ─── IntersectionObserver — only analyze visible images ───
  //
  // Pages can have 50-100+ images, most below the fold. Analyzing all of them
  // upfront wastes ML cycles on imgs the user may never scroll to. We register
  // an IntersectionObserver and only enqueue analysis when an image enters
  // (or is near) the viewport.
  //
  // The CSS blur is still applied to every <img> at scan time, so off-screen
  // imgs are blurred when they arrive — we just defer the *decision* until
  // they're visible.
  var intersectionObserver = null;
  if (typeof IntersectionObserver !== 'undefined') {
    intersectionObserver = new IntersectionObserver(function(entries) {
      for (var i = 0; i < entries.length; i++) {
        var entry = entries[i];
        if (entry.isIntersecting && entry.target.tagName === 'IMG') {
          var img = entry.target;
          intersectionObserver.unobserve(img);
          enqueueAnalyze(img);
        }
      }
    }, {
      // Trigger 200px before the image actually enters the viewport — gives
      // the pipeline time to analyse + apply the decision before the user
      // scrolls to it.
      rootMargin: '200px 0px',
      threshold: 0,
    });
  }

  function observeForAnalysis(img) {
    if (!img || img.tagName !== 'IMG') return;
    if (img.hasAttribute(ID_ATTR)) return;     // already queued/analyzed
    if (img.getAttribute(STATE_ATTR) === 'remove') return;  // sticky safe
    if (intersectionObserver) {
      intersectionObserver.observe(img);
    } else {
      // Fallback for browsers without IntersectionObserver: analyze immediately.
      enqueueAnalyze(img);
    }
  }

  function observeAll(root) {
    var imgs = (root || document).querySelectorAll('img');
    for (var i = 0; i < imgs.length; i++) observeForAnalysis(imgs[i]);
  }

  // ─── Lifecycle ───
  function onPageHide() {
    metric('page_hide', { url: location.href });
    send('pageReset', location.href);
  }
  window.addEventListener('pagehide', onPageHide);
  window.addEventListener('beforeunload', onPageHide);

  function init() {
    var initialCount = scanAndBlur(document);
    metric('script_init', { url: location.href, initial_imgs: initialCount });
    send('scriptReady', location.href);
    send('blurApplied', String(initialCount));
    observeAll(document);

    try {
      var observer = new MutationObserver(function(mutations) {
        var n = 0;
        for (var m = 0; m < mutations.length; m++) {
          var mut = mutations[m];
          if (mut.type === 'childList') {
            for (var a = 0; a < mut.addedNodes.length; a++) {
              var node = mut.addedNodes[a];
              if (!node || node.nodeType !== 1) continue;
              if (node.tagName === 'IMG') {
                if (applyBlurTo(node)) n++;
                observeForAnalysis(node);
              } else if (node.querySelectorAll) {
                n += scanAndBlur(node);
                observeAll(node);
              }
            }
          }
          // NOTE: we deliberately don't observe `src` changes. Lazy-loaded sites
          // (Google Images, social feeds) update `src` from placeholder → full
          // res, which would otherwise re-trigger analysis and cause a visible
          // "blur → unblur → re-blur → unblur" flash. The first decision is
          // sticky for V1. Trade-off: a server-side image swap with different
          // content (rare on lazy-load) will keep the previous decision.
        }
        if (n > 0) metric('mutation_blur', { added: n });
      });
      observer.observe(document.documentElement || document.body, {
        childList: true,
        subtree: true
      });
    } catch (e) {
      metric('observer_error', { msg: '' + e });
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init, { once: true });
  } else {
    init();
  }
});
