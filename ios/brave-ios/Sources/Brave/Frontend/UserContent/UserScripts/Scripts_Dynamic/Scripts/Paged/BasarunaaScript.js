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

  // ─── Decision cache (URL → 'keep' | 'remove') ───
  //
  // Sites with infinite scroll / lazy reload (Google Images, social feeds)
  // create + destroy many <img> elements that share the same URL. Without a
  // cache we'd re-analyse the same bytes every time. With one, the second
  // appearance skips the Swift roundtrip entirely.
  //
  // Map iteration order = insertion order in JS, so we can use it as a
  // simple LRU-ish bound: drop the oldest entry when we hit the cap.
  var DECISION_CACHE_MAX = 500;
  var decisionCache = new Map();

  function imgUrl(img) {
    return img.currentSrc || img.src || '';
  }

  function getCachedDecision(url) {
    return url ? decisionCache.get(url) : undefined;
  }

  function setCachedDecision(url, decision) {
    if (!url) return;
    if (decisionCache.has(url)) {
      decisionCache.delete(url);  // re-insert to refresh LRU position
    } else if (decisionCache.size >= DECISION_CACHE_MAX) {
      var firstKey = decisionCache.keys().next().value;
      decisionCache.delete(firstKey);
    }
    decisionCache.set(url, decision);
  }

  // ─── Blur application ───
  // We use inline `style.setProperty(..., 'important')` because:
  //   1. `!important` on inline style beats virtually any page-level CSS.
  //   2. Some sites (Google Images, social feeds) mutate the DOM aggressively;
  //      we track STATE_ATTR so any analyzed image (keep with per-person
  //      composite, or remove = safe) is never re-blurred when DOM mutates.
  function applyBlurTo(img) {
    if (!img || img.nodeType !== 1 || img.tagName !== 'IMG') return false;
    var state = img.getAttribute(STATE_ATTR);
    if (state === 'remove' || state === 'keep') return false;
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

  // Per-image cached ArrayBuffer (the fetched CORS blob). Reused by the
  // compositing step so it doesn't have to fight cross-origin canvas taint.
  // WeakMap so entries get GC'd when the <img> element is removed from DOM.
  var imageBytesByImg = new WeakMap();

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
          // Stash the CORS-fetched bytes so the compositing step can build a
          // non-tainted ImageBitmap from them when Swift returns persons-to-blur.
          imageBytesByImg.set(img, buf);
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
      img.addEventListener('load', function() { enqueueAnalyze(img); }, { once: true });
      return;
    }
    // URL cache fast-path: same bytes were classified before → skip Swift.
    var url = imgUrl(img);
    var cached = getCachedDecision(url);
    if (cached) {
      var id = nextId++;
      img.setAttribute(ID_ATTR, String(id));
      img.setAttribute(STATE_ATTR, cached);
      if (cached === 'remove') removeBlurFrom(img);
      metric('analyze_cache_hit', { id: id, decision: cached });
      return;
    }
    var id = nextId++;
    img.setAttribute(ID_ATTR, String(id));
    img.setAttribute(STATE_ATTR, 'pending');
    queue.push({ id: id, img: img, url: url });
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

  // ─── Per-person blur compositing (port du POC macOS) ───
  //
  // Stratégie choisie (voir aussi le commit message) : on reproduit le
  // POC `private/extensions/basarunaa/src/content.js#applyBlur` :
  //   1. Dessiner l'image originale dans un canvas
  //   2. Pré-calculer une version floutée edge-clampée (`_createEdgeClampedBlur`)
  //   3. Pour chaque personne à flouter, copier la zone floutée masquée par
  //      le body polygon (depuis les keypoints COCO) avec bords adoucis
  //      (FEATHER_EXPAND + FEATHER_BLUR) → `_drawFeatheredBlur`
  //   4. Remplacer le rendu de l'<img> via `style.content = url(<dataURL>)`
  //      — l'attribut `src` reste intact (pas de re-fetch, pas de mutation
  //      observer en boucle).
  //
  // Trade-off vs DOM overlays : ~50-100 ms compute canvas par image en plus
  // du ML, mais qualité polygon body-shaped + bords adoucis. Si la perf
  // devient un problème (Reels/scroll long), on pourra passer à des overlays
  // CSS rectangulaires en V2.

  var KP_CONFIDENCE = 0.3;
  var BODY_WIDTH_FACTOR = 0.55;
  var HAND_EXTEND = 0.3;
  var FOOT_EXTEND = 0.08;
  var EDGE_SNAP_THRESHOLD = 0.05;
  var FEATHER_EXPAND = 20;
  var FEATHER_BLUR = 10;
  var FEATHER_PAD = FEATHER_EXPAND + FEATHER_BLUR + 5;
  var REGION_SCALE = {
    head: 0.8, shoulder: 1.0, elbow: 0.7, wrist: 0.6,
    hip: 1.1, knee: 0.8, ankle: 0.7,
  };

  function getRegionScale(idx) {
    if (idx <= 4) return REGION_SCALE.head;
    if (idx <= 6) return REGION_SCALE.shoulder;
    if (idx <= 8) return REGION_SCALE.elbow;
    if (idx <= 10) return REGION_SCALE.wrist;
    if (idx <= 12) return REGION_SCALE.hip;
    if (idx <= 14) return REGION_SCALE.knee;
    return REGION_SCALE.ankle;
  }

  // keypoints: [[x, y, conf], ...] (17 COCO) | bbox: [x1, y1, x2, y2]
  function buildBodyPolygon(keypoints, bbox, imgW, imgH) {
    var bx1 = bbox[0], by1 = bbox[1], bx2 = bbox[2], by2 = bbox[3];
    var bw = bx2 - bx1;
    var bh = by2 - by1;

    var fallback = function() {
      return {
        points: [
          { x: bx1, y: by1 }, { x: bx2, y: by1 },
          { x: bx2, y: by2 }, { x: bx1, y: by2 },
        ],
        isBodyShaped: false,
      };
    };

    if (!keypoints || keypoints.length === 0) return fallback();
    var confident = [];
    for (var i = 0; i < keypoints.length; i++) {
      if (keypoints[i][2] >= KP_CONFIDENCE) confident.push(i);
    }
    if (confident.length < 4) return fallback();

    var lSh = keypoints[5], rSh = keypoints[6];
    var halfWidth;
    if (lSh && rSh && lSh[2] >= KP_CONFIDENCE && rSh[2] >= KP_CONFIDENCE) {
      halfWidth = Math.abs(rSh[0] - lSh[0]) * BODY_WIDTH_FACTOR;
    } else {
      halfWidth = bw * 0.25;
    }
    halfWidth = Math.max(halfWidth, bw * 0.2);

    var widened = [];
    for (var c = 0; c < confident.length; c++) {
      var idx = confident[c];
      var k = keypoints[idx];
      var w = halfWidth * getRegionScale(idx);
      widened.push({ x: k[0] - w, y: k[1] });
      widened.push({ x: k[0] + w, y: k[1] });
    }

    // Head padding
    var headIdx = [0, 1, 2, 3, 4].filter(function(i) {
      return keypoints[i] && keypoints[i][2] >= KP_CONFIDENCE;
    });
    if (headIdx.length > 0) {
      var topY = Infinity;
      var headCx = 0;
      for (var hi = 0; hi < headIdx.length; hi++) {
        var hkp = keypoints[headIdx[hi]];
        if (hkp[1] < topY) topY = hkp[1];
        headCx += hkp[0];
      }
      headCx /= headIdx.length;
      var headPadY = Math.max(halfWidth * 0.6, bh * 0.08);
      var headPadX = Math.max(halfWidth * 0.9, bw * 0.25);
      widened.push({ x: headCx - headPadX, y: topY - headPadY });
      widened.push({ x: headCx + headPadX, y: topY - headPadY });
    }

    extendHand(keypoints, 7, 9, halfWidth, widened);
    extendHand(keypoints, 8, 10, halfWidth, widened);

    var footExtend = bh * FOOT_EXTEND;
    [15, 16].forEach(function(aIdx) {
      var a = keypoints[aIdx];
      if (!a || a[2] < KP_CONFIDENCE) return;
      var wA = halfWidth * REGION_SCALE.ankle;
      widened.push({ x: a[0] - wA, y: a[1] + footExtend });
      widened.push({ x: a[0] + wA, y: a[1] + footExtend });
    });

    var hull = convexHull(widened);
    var polyMinX = Infinity, polyMaxX = -Infinity;
    var polyMinY = Infinity, polyMaxY = -Infinity;
    for (var h2 = 0; h2 < hull.length; h2++) {
      var p = hull[h2];
      if (p.x < polyMinX) polyMinX = p.x;
      if (p.x > polyMaxX) polyMaxX = p.x;
      if (p.y < polyMinY) polyMinY = p.y;
      if (p.y > polyMaxY) polyMaxY = p.y;
    }
    var polyCx = (polyMinX + polyMaxX) / 2;
    var polyCy = (polyMinY + polyMaxY) / 2;
    var bboxCx = (bx1 + bx2) / 2;
    var bboxCy = (by1 + by2) / 2;
    var sx = bw / ((polyMaxX - polyMinX) || 1);
    var sy = bh / ((polyMaxY - polyMinY) || 1);
    var scaled = hull.map(function(p) {
      return {
        x: bboxCx + (p.x - polyCx) * sx,
        y: bboxCy + (p.y - polyCy) * sy,
      };
    });

    var snapped = snapToEdges(scaled, bbox, imgW, imgH, keypoints);
    return { points: snapped, isBodyShaped: true };
  }

  function extendHand(kps, elbowIdx, wristIdx, halfWidth, out) {
    var elbow = kps[elbowIdx];
    var wrist = kps[wristIdx];
    if (!elbow || !wrist) return;
    if (elbow[2] < KP_CONFIDENCE || wrist[2] < KP_CONFIDENCE) return;
    var dx = wrist[0] - elbow[0];
    var dy = wrist[1] - elbow[1];
    var hx = wrist[0] + dx * HAND_EXTEND;
    var hy = wrist[1] + dy * HAND_EXTEND;
    var w = halfWidth * 0.6;
    out.push({ x: hx - w, y: hy });
    out.push({ x: hx + w, y: hy });
  }

  function snapToEdges(points, bbox, imgW, imgH, keypoints) {
    var bx1 = bbox[0], by1 = bbox[1], bx2 = bbox[2], by2 = bbox[3];
    var hasAnkles = keypoints &&
      [15, 16].some(function(i) { return keypoints[i] && keypoints[i][2] >= KP_CONFIDENCE; });
    var hasHead = keypoints &&
      [0, 1, 2].some(function(i) { return keypoints[i] && keypoints[i][2] >= KP_CONFIDENCE; });
    var snapBottom = !hasAnkles && by2 / imgH > (1 - EDGE_SNAP_THRESHOLD);
    var snapTop = !hasHead && by1 / imgH < EDGE_SNAP_THRESHOLD;
    var snapLeft = bx1 / imgW < EDGE_SNAP_THRESHOLD;
    var snapRight = bx2 / imgW > (1 - EDGE_SNAP_THRESHOLD);
    if (!snapBottom && !snapTop && !snapLeft && !snapRight) return points;

    var minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
    for (var i = 0; i < points.length; i++) {
      if (points[i].x < minX) minX = points[i].x;
      if (points[i].x > maxX) maxX = points[i].x;
      if (points[i].y < minY) minY = points[i].y;
      if (points[i].y > maxY) maxY = points[i].y;
    }
    var xRange = maxX - minX || 1;
    var yRange = maxY - minY || 1;
    var nearFrac = 0.15;
    return points.map(function(p) {
      var x = p.x, y = p.y;
      if (snapBottom && y > maxY - yRange * nearFrac) y = imgH;
      if (snapTop && y < minY + yRange * nearFrac) y = 0;
      if (snapLeft && x < minX + xRange * nearFrac) x = 0;
      if (snapRight && x > maxX - xRange * nearFrac) x = imgW;
      return { x: x, y: y };
    });
  }

  function convexHull(points) {
    if (points.length < 3) return points;
    var sorted = points.slice().sort(function(a, b) { return a.x - b.x || a.y - b.y; });
    var n = sorted.length;
    var cross = function(o, a, b) {
      return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
    };
    var lower = [];
    for (var i = 0; i < n; i++) {
      while (lower.length >= 2 && cross(lower[lower.length - 2], lower[lower.length - 1], sorted[i]) <= 0) {
        lower.pop();
      }
      lower.push(sorted[i]);
    }
    var upper = [];
    for (var i2 = n - 1; i2 >= 0; i2--) {
      while (upper.length >= 2 && cross(upper[upper.length - 2], upper[upper.length - 1], sorted[i2]) <= 0) {
        upper.pop();
      }
      upper.push(sorted[i2]);
    }
    lower.pop();
    upper.pop();
    return lower.concat(upper);
  }

  // Diagnostic: log canvas filter support once, on first call.
  var canvasFilterChecked = false;
  function checkCanvasFilter() {
    if (canvasFilterChecked) return;
    canvasFilterChecked = true;
    try {
      var c = document.createElement('canvas');
      c.width = 4; c.height = 4;
      var cx = c.getContext('2d');
      cx.filter = 'blur(5px)';
      metric('canvas_filter_check', { set: 'blur(5px)', got: '' + cx.filter });
    } catch (e) {
      metric('canvas_filter_check', { err: '' + e });
    }
  }

  // Downsample-upsample blur — works around iOS WKWebView's silent no-op on
  // `ctx.filter = 'blur(...)'`. We draw the source into a tiny canvas (factor
  // ≈ blur radius) then back into a full-size canvas with bilinear filtering
  // enabled. The interpolation produces a Gaussian-ish blur that visually
  // matches what the POC achieves with `filter: blur(Npx)`.
  function createEdgeClampedBlur(img, w, h, blur) {
    checkCanvasFilter();
    // Two passes give a smoother (more Gaussian-like) result than one.
    var factor = Math.max(8, Math.round(blur / 2));
    var smallW = Math.max(1, Math.floor(w / factor));
    var smallH = Math.max(1, Math.floor(h / factor));
    var passes = 2;

    var src = img;
    var srcW = w, srcH = h;
    for (var p = 0; p < passes; p++) {
      var small = document.createElement('canvas');
      small.width = smallW;
      small.height = smallH;
      var sCtx = small.getContext('2d');
      sCtx.imageSmoothingEnabled = true;
      sCtx.imageSmoothingQuality = 'high';
      sCtx.drawImage(src, 0, 0, srcW, srcH, 0, 0, smallW, smallH);

      var up = document.createElement('canvas');
      up.width = w;
      up.height = h;
      var uCtx = up.getContext('2d');
      uCtx.imageSmoothingEnabled = true;
      uCtx.imageSmoothingQuality = 'high';
      uCtx.drawImage(small, 0, 0, smallW, smallH, 0, 0, w, h);

      src = up;
      srcW = w; srcH = h;
    }
    return src;
  }

  function drawFeatheredBlur(ctx, blurredCanvas, person, w, h, showDebug) {
    var poly = buildBodyPolygon(person.keypoints, person.bbox, w, h);
    var tw = w + 2 * FEATHER_PAD;
    var th = h + 2 * FEATHER_PAD;
    var maskCanvas = document.createElement('canvas');
    maskCanvas.width = tw;
    maskCanvas.height = th;
    var mCtx = maskCanvas.getContext('2d');
    mCtx.fillStyle = '#fff';
    mCtx.beginPath();

    if (poly.isBodyShaped) {
      var cx = 0, cy = 0;
      for (var i = 0; i < poly.points.length; i++) {
        cx += poly.points[i].x; cy += poly.points[i].y;
      }
      cx /= poly.points.length; cy /= poly.points.length;
      for (var i2 = 0; i2 < poly.points.length; i2++) {
        var dx = poly.points[i2].x - cx;
        var dy = poly.points[i2].y - cy;
        var dist = Math.sqrt(dx * dx + dy * dy) || 1;
        var ex = poly.points[i2].x + (dx / dist) * FEATHER_EXPAND + FEATHER_PAD;
        var ey = poly.points[i2].y + (dy / dist) * FEATHER_EXPAND + FEATHER_PAD;
        if (i2 === 0) mCtx.moveTo(ex, ey);
        else mCtx.lineTo(ex, ey);
      }
      mCtx.closePath();
    } else {
      var b = person.bbox;
      var x1 = b[0], y1 = b[1], x2 = b[2], y2 = b[3];
      var snapX = w * 0.10, snapY = h * 0.10;
      if (x1 < snapX) x1 = -FEATHER_PAD; else x1 -= FEATHER_EXPAND;
      if (y1 < snapY) y1 = -FEATHER_PAD; else y1 -= FEATHER_EXPAND;
      if (w - x2 < snapX) x2 = w + FEATHER_PAD; else x2 += FEATHER_EXPAND;
      if (h - y2 < snapY) y2 = h + FEATHER_PAD; else y2 += FEATHER_EXPAND;
      mCtx.rect(x1 + FEATHER_PAD, y1 + FEATHER_PAD, x2 - x1, y2 - y1);
    }
    mCtx.fill();

    // Same downsample-upsample trick on the mask (ctx.filter blur is silent
    // no-op on iOS WKWebView). Gives feathered edges around the polygon.
    var maskFactor = Math.max(4, FEATHER_BLUR);
    var maskSmall = document.createElement('canvas');
    maskSmall.width = Math.max(1, Math.floor(tw / maskFactor));
    maskSmall.height = Math.max(1, Math.floor(th / maskFactor));
    var msCtx = maskSmall.getContext('2d');
    msCtx.imageSmoothingEnabled = true;
    msCtx.imageSmoothingQuality = 'high';
    msCtx.drawImage(maskCanvas, 0, 0, tw, th, 0, 0, maskSmall.width, maskSmall.height);

    var blurredMask = document.createElement('canvas');
    blurredMask.width = tw;
    blurredMask.height = th;
    var bmCtx = blurredMask.getContext('2d');
    bmCtx.imageSmoothingEnabled = true;
    bmCtx.imageSmoothingQuality = 'high';
    bmCtx.drawImage(maskSmall, 0, 0, maskSmall.width, maskSmall.height, 0, 0, tw, th);

    var tempCanvas = document.createElement('canvas');
    tempCanvas.width = w;
    tempCanvas.height = h;
    var tCtx = tempCanvas.getContext('2d');
    tCtx.drawImage(blurredCanvas, 0, 0);
    tCtx.globalCompositeOperation = 'destination-in';
    tCtx.drawImage(blurredMask, FEATHER_PAD, FEATHER_PAD, w, h, 0, 0, w, h);
    ctx.drawImage(tempCanvas, 0, 0);

    // Debug polygons (port direct de _drawFeatheredBlur POC content.js).
    // 4 contours pointillés : polygon YOLO original, début du dégradé,
    // bord du masque blanc, fin du dégradé. Visibles dans les modes
    // debug-mode = "boxes" et "debug".
    if (showDebug) {
      ctx.save();
      ctx.lineWidth = 2;
      var drawExpanded = function(amount) {
        ctx.beginPath();
        if (poly.isBodyShaped) {
          var pcx = 0, pcy = 0;
          for (var i = 0; i < poly.points.length; i++) {
            pcx += poly.points[i].x; pcy += poly.points[i].y;
          }
          pcx /= poly.points.length; pcy /= poly.points.length;
          for (var j = 0; j < poly.points.length; j++) {
            var dxe = poly.points[j].x - pcx;
            var dye = poly.points[j].y - pcy;
            var dist2 = Math.sqrt(dxe * dxe + dye * dye) || 1;
            var ex2 = poly.points[j].x + (dxe / dist2) * amount;
            var ey2 = poly.points[j].y + (dye / dist2) * amount;
            if (j === 0) ctx.moveTo(ex2, ey2);
            else ctx.lineTo(ex2, ey2);
          }
          ctx.closePath();
        } else {
          var bb = person.bbox;
          var rx1 = bb[0], ry1 = bb[1], rx2 = bb[2], ry2 = bb[3];
          ctx.rect(rx1 - amount, ry1 - amount, (rx2 - rx1) + amount * 2, (ry2 - ry1) + amount * 2);
        }
        ctx.stroke();
      };
      // Cyan : polygon original (YOLO body shape)
      ctx.strokeStyle = '#00FFFF';
      ctx.setLineDash([4, 4]);
      drawExpanded(0);
      // Vert : début du dégradé (~expand - blur = 10px)
      ctx.strokeStyle = '#00FF00';
      ctx.setLineDash([3, 3]);
      drawExpanded(FEATHER_EXPAND - FEATHER_BLUR);
      // Orange : bord du masque blanc (expand = 20px)
      ctx.strokeStyle = '#FFA500';
      ctx.setLineDash([6, 3]);
      drawExpanded(FEATHER_EXPAND);
      // Rouge : fin du dégradé (~expand + blur = 30px)
      ctx.strokeStyle = '#FF0000';
      ctx.setLineDash([2, 4]);
      drawExpanded(FEATHER_EXPAND + FEATHER_BLUR);
      ctx.setLineDash([]);
      ctx.restore();
    }
  }

  // Compositing source — prefer the CORS-fetched ArrayBuffer (no canvas taint),
  // fallback to drawing the <img> directly (works only for same-origin or
  // images with crossorigin="anonymous").
  function getCompositingSource(img) {
    return new Promise(function(resolve) {
      var buf = imageBytesByImg.get(img);
      if (buf) {
        try {
          var blob = new Blob([buf]);
          createImageBitmap(blob).then(function(bm) {
            resolve(bm);
          }).catch(function() { resolve(img); });
          return;
        } catch (e) {
          // Fall through to direct img source.
        }
      }
      resolve(img);
    });
  }

  function compositePerPersonBlur(img, persons) {
    if (!persons || persons.length === 0) return Promise.resolve(false);
    var id = img.getAttribute(ID_ATTR);
    // Convert keypoints from [x,y,conf] arrays to {x,y,confidence} objects
    // so `buildBodyPolygon` can read kp.confidence. Without this normalise,
    // the polygon path silently falls back to a bbox rectangle (the blur
    // looks rectangular instead of following the silhouette).
    var normalised = normalisePersons(persons);
    metric('composite_start', {
      id: id,
      naturalW: img.naturalWidth, naturalH: img.naturalHeight,
      persons: normalised.length,
    });
    return getCompositingSource(img).then(function(source) {
      var sourceType = (source && source.constructor) ? source.constructor.name : 'unknown';
      var w = source.naturalWidth != null ? source.naturalWidth : source.width;
      var h = source.naturalHeight != null ? source.naturalHeight : source.height;
      metric('composite_source', { id: id, type: sourceType, w: w, h: h });
      if (!w || !h) {
        metric('composite_nodim', { id: id });
        return false;
      }
      try {
        var canvas = document.createElement('canvas');
        canvas.width = w;
        canvas.height = h;
        var ctx = canvas.getContext('2d');
        ctx.drawImage(source, 0, 0, w, h);
        var blur = Math.max(25, Math.round(Math.max(w, h) * 0.04));
        var blurredCanvas = createEdgeClampedBlur(source, w, h, blur);
        for (var pi = 0; pi < normalised.length; pi++) {
          drawFeatheredBlur(ctx, blurredCanvas, normalised[pi], w, h);
        }
        var srcLower = (img.currentSrc || img.src || '').toLowerCase();
        var needsAlpha = /\.png(\?|$)/.test(srcLower) || /\.webp(\?|$)/.test(srcLower)
          || srcLower.indexOf('data:image/png') === 0;
        var mime = needsAlpha ? 'image/png' : 'image/jpeg';
        var quality = needsAlpha ? undefined : 0.85;
        // Use Blob + createObjectURL (vs toDataURL). Blob URLs are short
        // strings backed by binary in memory — way more reliable than 100+ KB
        // data: URLs on iOS WebKit, where setting img.src to a huge data URL
        // sometimes doesn't trigger a repaint.
        return new Promise(function(resolveBlob) {
          canvas.toBlob(function(blob) { resolveBlob(blob); }, mime, quality);
        }).then(function(blob) {
          if (!blob) {
            metric('composite_no_blob', { id: id });
            return false;
          }
          metric('composite_encoded', { id: id, bytes: blob.size });
          // Strip srcset / <picture><source> so the browser actually uses
          // our new src instead of re-picking a responsive variant.
          if (img.hasAttribute('srcset')) img.removeAttribute('srcset');
          if (img.hasAttribute('sizes')) img.removeAttribute('sizes');
          var pic = img.parentNode;
          if (pic && pic.tagName === 'PICTURE') {
            var sources = pic.querySelectorAll('source');
            for (var si = 0; si < sources.length; si++) {
              sources[si].removeAttribute('srcset');
            }
          }
          if (img.dataset.basarunaaBlobUrl) {
            try { URL.revokeObjectURL(img.dataset.basarunaaBlobUrl); } catch (_) {}
          }
          var blobUrl = URL.createObjectURL(blob);
          img.dataset.basarunaaBlobUrl = blobUrl;
          // Attach diagnostic load/error listeners BEFORE setting src so we
          // know if the browser actually accepts the blob URL.
          img.addEventListener('load', function _onload() {
            img.removeEventListener('load', _onload);
            metric('composite_load_ok', { id: id, w: img.naturalWidth, h: img.naturalHeight });
          });
          img.addEventListener('error', function _onerror(e) {
            img.removeEventListener('error', _onerror);
            metric('composite_load_err', { id: id, msg: '' + (e && e.message || e) });
          });
          // iOS WebKit caches the rendered image after the first load and
          // doesn't always re-render when `img.src` is replaced (especially
          // on ImageDocument pages — direct image URLs like /foo.avif).
          // Workaround: replace the <img> element with a fresh clone that
          // points to our blob URL. This guarantees a new render path.
          var fresh = img.cloneNode(false);
          fresh.removeAttribute('srcset');
          fresh.removeAttribute('sizes');
          fresh.removeAttribute('crossorigin');
          fresh.removeAttribute(BLUR_MARKER);
          fresh.style.removeProperty('filter');
          fresh.dataset.basarunaaBlobUrl = blobUrl;
          fresh.src = blobUrl;
          // Preserve our state so MutationObserver / cache treats it as done.
          fresh.setAttribute(ID_ATTR, img.getAttribute(ID_ATTR) || '');
          fresh.setAttribute(STATE_ATTR, 'keep');
          if (img.parentNode) {
            img.parentNode.replaceChild(fresh, img);
            // Stop observing the old img (it's detached now).
            try { if (intersectionObserver) intersectionObserver.unobserve(img); } catch (_) {}
            metric('composite_applied', { id: id, mode: 'replace', blobUrl: blobUrl.slice(0, 50) });
          } else {
            metric('composite_no_parent', { id: id });
          }
          return true;
        });
      } catch (e) {
        metric('composite_failed', { id: id, msg: ('' + e).slice(0, 120) });
        return false;
      }
    }).catch(function(e) {
      metric('composite_promise_rejected', { id: id, msg: ('' + e).slice(0, 120) });
      return false;
    });
  }

  // ─── Debug overlay — port fidèle du visualizer macOS POC ───
  // (`private/extensions/basarunaa/src/debug/visualizer.js`)
  //
  // Mêmes palettes (5 nuances rose/magenta pour femmes, 5 nuances bleu pour
  // hommes — une nuance distincte par personne via compteur), skeleton COCO,
  // polygon mask (port de `src/utils/body_polygon.js`), keypoints colorés.
  //
  // Coordonnées : on dessine sur un canvas qui *devient* la nouvelle image,
  // donc on travaille en coords pixel originales (le `sx`/`sy` du POC = 1).
  var FEMALE_COLORS = [
    '#FF69B4',  // hot pink
    '#FF1493',  // deep pink
    '#DB7093',  // pale violet red
    '#C71585',  // medium violet red
    '#FF007F',  // rose
  ];
  var MALE_COLORS = [
    '#4169E1',  // royal blue
    '#1E90FF',  // dodger blue
    '#00BFFF',  // deep sky blue
    '#4682B4',  // steel blue
    '#0047AB',  // cobalt
  ];

  var COCO_SKELETON = [
    [0, 1], [0, 2], [1, 3], [2, 4],   // head
    [5, 6],                           // shoulders
    [5, 7], [7, 9],                   // left arm
    [6, 8], [8, 10],                  // right arm
    [5, 11], [6, 12],                 // torso
    [11, 12],                         // hips
    [11, 13], [13, 15],               // left leg
    [12, 14], [14, 16],               // right leg
  ];
  var LIMB_COLORS = [
    '#FF6B6B', '#FF6B6B', '#FF6B6B', '#FF6B6B',   // head: red
    '#FFD93D',                                     // shoulders: yellow
    '#6BCB77', '#6BCB77',                          // left arm: green
    '#4D96FF', '#4D96FF',                          // right arm: blue
    '#FFD93D', '#FFD93D',                          // torso: yellow
    '#FFD93D',                                     // hips: yellow
    '#6BCB77', '#6BCB77',                          // left leg: green
    '#4D96FF', '#4D96FF',                          // right leg: blue
  ];
  var KP_COLORS = [
    '#FF0000', '#00FF00', '#0000FF', '#FFFF00', '#FF00FF',
    '#00FFFF', '#FFA500', '#FF69B4', '#7FFF00', '#DC143C',
    '#00CED1', '#FFD700', '#8A2BE2', '#32CD32', '#FF4500',
    '#1E90FF', '#FF1493',
  ];
  var KP_CONF = 0.3;

  // ─── Body polygon (port de utils/body_polygon.js) ───
  var POLY_KP_CONFIDENCE = 0.3;
  var POLY_BODY_WIDTH_FACTOR = 0.55;
  var POLY_HAND_EXTEND = 0.3;
  var POLY_FOOT_EXTEND = 0.08;
  var POLY_EDGE_SNAP = 0.05;
  var POLY_REGION_SCALE = [
    0.8, 0.8, 0.8, 0.8, 0.8,    // head 0-4
    1.0, 1.0,                   // shoulders 5-6
    0.7, 0.7,                   // elbows 7-8
    0.6, 0.6,                   // wrists 9-10
    1.1, 1.1,                   // hips 11-12
    0.8, 0.8,                   // knees 13-14
    0.7, 0.7,                   // ankles 15-16
  ];

  function _extendHand(kps, elbowIdx, wristIdx, halfWidth, out) {
    var elbow = kps[elbowIdx], wrist = kps[wristIdx];
    if (!elbow || !wrist) return;
    if (elbow.confidence < POLY_KP_CONFIDENCE || wrist.confidence < POLY_KP_CONFIDENCE) return;
    var dx = wrist.x - elbow.x;
    var dy = wrist.y - elbow.y;
    var hx = wrist.x + dx * POLY_HAND_EXTEND;
    var hy = wrist.y + dy * POLY_HAND_EXTEND;
    var w = halfWidth * 0.6;
    out.push({ x: hx - w, y: hy });
    out.push({ x: hx + w, y: hy });
  }

  function _snapToEdges(points, bbox, imgW, imgH, kps) {
    var bx1 = bbox[0], by1 = bbox[1], bx2 = bbox[2], by2 = bbox[3];
    var hasAnkles = kps && [15, 16].some(function(i) {
      return kps[i] && kps[i].confidence >= POLY_KP_CONFIDENCE;
    });
    var hasHead = kps && [0, 1, 2].some(function(i) {
      return kps[i] && kps[i].confidence >= POLY_KP_CONFIDENCE;
    });
    var snapBottom = !hasAnkles && by2 / imgH > (1 - POLY_EDGE_SNAP);
    var snapTop = !hasHead && by1 / imgH < POLY_EDGE_SNAP;
    var snapLeft = bx1 / imgW < POLY_EDGE_SNAP;
    var snapRight = bx2 / imgW > (1 - POLY_EDGE_SNAP);
    if (!snapBottom && !snapTop && !snapLeft && !snapRight) return points;
    var minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
    for (var i = 0; i < points.length; i++) {
      if (points[i].x < minX) minX = points[i].x;
      if (points[i].x > maxX) maxX = points[i].x;
      if (points[i].y < minY) minY = points[i].y;
      if (points[i].y > maxY) maxY = points[i].y;
    }
    var xR = (maxX - minX) || 1;
    var yR = (maxY - minY) || 1;
    var near = 0.15;
    return points.map(function(p) {
      var x = p.x, y = p.y;
      if (snapBottom && y > maxY - yR * near) y = imgH;
      if (snapTop && y < minY + yR * near) y = 0;
      if (snapLeft && x < minX + xR * near) x = 0;
      if (snapRight && x > maxX - xR * near) x = imgW;
      return { x: x, y: y };
    });
  }

  function _bboxFallback(bbox) {
    return {
      points: [
        { x: bbox[0], y: bbox[1] },
        { x: bbox[2], y: bbox[1] },
        { x: bbox[2], y: bbox[3] },
        { x: bbox[0], y: bbox[3] },
      ],
      isBodyShaped: false,
    };
  }

  function _convexHull(points) {
    if (points.length < 3) return points;
    var sorted = points.slice().sort(function(a, b) { return a.x - b.x || a.y - b.y; });
    var n = sorted.length;
    var cross = function(o, a, b) {
      return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
    };
    var lower = [];
    for (var i = 0; i < n; i++) {
      while (lower.length >= 2 && cross(lower[lower.length - 2], lower[lower.length - 1], sorted[i]) <= 0) {
        lower.pop();
      }
      lower.push(sorted[i]);
    }
    var upper = [];
    for (var j = n - 1; j >= 0; j--) {
      while (upper.length >= 2 && cross(upper[upper.length - 2], upper[upper.length - 1], sorted[j]) <= 0) {
        upper.pop();
      }
      upper.push(sorted[j]);
    }
    lower.pop();
    upper.pop();
    return lower.concat(upper);
  }

  function buildBodyPolygon(kps, bbox, imgW, imgH) {
    var bx1 = bbox[0], by1 = bbox[1], bx2 = bbox[2], by2 = bbox[3];
    var bw = bx2 - bx1, bh = by2 - by1;
    if (!kps) return _bboxFallback(bbox);
    var confident = [];
    for (var i = 0; i < kps.length; i++) {
      if (kps[i] && kps[i].confidence >= POLY_KP_CONFIDENCE) {
        confident.push({ idx: i, k: kps[i] });
      }
    }
    if (confident.length < 4) return _bboxFallback(bbox);
    var lSh = kps[5], rSh = kps[6];
    var halfWidth;
    if (lSh && rSh && lSh.confidence >= POLY_KP_CONFIDENCE && rSh.confidence >= POLY_KP_CONFIDENCE) {
      halfWidth = Math.abs(rSh.x - lSh.x) * POLY_BODY_WIDTH_FACTOR;
    } else {
      halfWidth = bw * 0.25;
    }
    halfWidth = Math.max(halfWidth, bw * 0.2);
    var widened = [];
    for (var c = 0; c < confident.length; c++) {
      var entry = confident[c];
      var w = halfWidth * POLY_REGION_SCALE[entry.idx];
      widened.push({ x: entry.k.x - w, y: entry.k.y });
      widened.push({ x: entry.k.x + w, y: entry.k.y });
    }
    var headKps = [];
    for (var hi = 0; hi < 5; hi++) {
      if (kps[hi] && kps[hi].confidence >= POLY_KP_CONFIDENCE) headKps.push(hi);
    }
    if (headKps.length > 0) {
      var topY = Infinity, sumX = 0;
      for (var hh = 0; hh < headKps.length; hh++) {
        var hk = kps[headKps[hh]];
        if (hk.y < topY) topY = hk.y;
        sumX += hk.x;
      }
      var headCx = sumX / headKps.length;
      var headPadY = Math.max(halfWidth * 0.6, bh * 0.08);
      var headPadX = Math.max(halfWidth * 0.9, bw * 0.25);
      widened.push({ x: headCx - headPadX, y: topY - headPadY });
      widened.push({ x: headCx + headPadX, y: topY - headPadY });
    }
    _extendHand(kps, 7, 9, halfWidth, widened);
    _extendHand(kps, 8, 10, halfWidth, widened);
    var footExtend = bh * POLY_FOOT_EXTEND;
    var ankleIndices = [15, 16];
    for (var ai = 0; ai < ankleIndices.length; ai++) {
      var ankle = kps[ankleIndices[ai]];
      if (ankle && ankle.confidence >= POLY_KP_CONFIDENCE) {
        var wA = halfWidth * 0.7;
        widened.push({ x: ankle.x - wA, y: ankle.y + footExtend });
        widened.push({ x: ankle.x + wA, y: ankle.y + footExtend });
      }
    }
    var hull = _convexHull(widened);
    var polyMinX = Infinity, polyMaxX = -Infinity, polyMinY = Infinity, polyMaxY = -Infinity;
    for (var pi = 0; pi < hull.length; pi++) {
      if (hull[pi].x < polyMinX) polyMinX = hull[pi].x;
      if (hull[pi].x > polyMaxX) polyMaxX = hull[pi].x;
      if (hull[pi].y < polyMinY) polyMinY = hull[pi].y;
      if (hull[pi].y > polyMaxY) polyMaxY = hull[pi].y;
    }
    var polyCx = (polyMinX + polyMaxX) / 2;
    var polyCy = (polyMinY + polyMaxY) / 2;
    var bboxCx = (bx1 + bx2) / 2;
    var bboxCy = (by1 + by2) / 2;
    var sX = bw / ((polyMaxX - polyMinX) || 1);
    var sY = bh / ((polyMaxY - polyMinY) || 1);
    var scaled = hull.map(function(p) {
      return { x: bboxCx + (p.x - polyCx) * sX, y: bboxCy + (p.y - polyCy) * sY };
    });
    var snapped = _snapToEdges(scaled, bbox, imgW, imgH, kps);
    return { points: snapped, isBodyShaped: true };
  }

  function polygonToMask(points, imgW, imgH) {
    var data = new Uint8Array(imgW * imgH);
    if (points.length < 3) return { data: data, width: imgW, height: imgH };
    var minY = imgH, maxY = 0;
    for (var i = 0; i < points.length; i++) {
      if (points[i].y < minY) minY = points[i].y;
      if (points[i].y > maxY) maxY = points[i].y;
    }
    minY = Math.max(0, Math.floor(minY));
    maxY = Math.min(imgH - 1, Math.ceil(maxY));
    for (var y = minY; y <= maxY; y++) {
      var inter = [];
      for (var p = 0; p < points.length; p++) {
        var a = points[p];
        var b = points[(p + 1) % points.length];
        if ((a.y <= y && b.y > y) || (b.y <= y && a.y > y)) {
          inter.push(a.x + (y - a.y) / (b.y - a.y) * (b.x - a.x));
        }
      }
      inter.sort(function(u, v) { return u - v; });
      for (var k = 0; k < inter.length - 1; k += 2) {
        var x1 = Math.max(0, Math.floor(inter[k]));
        var x2 = Math.min(imgW - 1, Math.ceil(inter[k + 1]));
        for (var x = x1; x <= x2; x++) {
          data[y * imgW + x] = 1;
        }
      }
    }
    return { data: data, width: imgW, height: imgH };
  }

  // Normalise le payload Swift (keypoints en `[x, y, conf]`) en objets
  // `{x, y, confidence}` que les algos POC consomment.
  function normalisePersons(persons) {
    var out = [];
    for (var i = 0; i < persons.length; i++) {
      var p = persons[i];
      var kps = [];
      if (p.keypoints && p.keypoints.length) {
        for (var k = 0; k < p.keypoints.length; k++) {
          var raw = p.keypoints[k];
          if (raw && raw.length >= 3) {
            kps.push({ x: raw[0], y: raw[1], confidence: raw[2] });
          }
        }
      }
      out.push({
        bbox: p.bbox,
        faceBbox: p.faceBbox || null,
        keypoints: kps,
        bodyConfidence: typeof p.bodyConfidence === 'number' ? p.bodyConfidence : null,
        gender: p.gender || null,
        genderConfidence: typeof p.genderConfidence === 'number' ? p.genderConfidence : null,
        isSyntheticBody: !!p.isSyntheticBody,
        classifierUsed: typeof p.classifierUsed === 'string' ? p.classifierUsed : '',
        facePFemale: typeof p.facePFemale === 'number' ? p.facePFemale : null,
        facePMale: typeof p.facePMale === 'number' ? p.facePMale : null,
        bodyPFemale: typeof p.bodyPFemale === 'number' ? p.bodyPFemale : null,
        bodyPMale: typeof p.bodyPMale === 'number' ? p.bodyPMale : null,
        faceCropDataUrl: typeof p.faceCropDataUrl === 'string' ? p.faceCropDataUrl : null,
        bodyCropDataUrl: typeof p.bodyCropDataUrl === 'string' ? p.bodyCropDataUrl : null,
      });
    }
    return out;
  }

  // Dessine le mask polygone : fill 35% alpha de la couleur de la personne
  // + contour 1px sur les pixels d'arête (port direct de visualizer._drawMask).
  function drawMask(ctx, mask, hexColor) {
    var r = parseInt(hexColor.slice(1, 3), 16);
    var g = parseInt(hexColor.slice(3, 5), 16);
    var b = parseInt(hexColor.slice(5, 7), 16);
    var W = ctx.canvas.width, H = ctx.canvas.height;
    var mw = mask.width, mh = mask.height, d = mask.data;
    var tmp = document.createElement('canvas');
    tmp.width = W; tmp.height = H;
    var tCtx = tmp.getContext('2d');
    var imgData = tCtx.createImageData(W, H);
    for (var y = 0; y < H; y++) {
      var my = y < mh ? y : mh - 1;
      for (var x = 0; x < W; x++) {
        var mx = x < mw ? x : mw - 1;
        if (d[my * mw + mx] > 0) {
          var off = (y * W + x) * 4;
          imgData.data[off] = r;
          imgData.data[off + 1] = g;
          imgData.data[off + 2] = b;
          imgData.data[off + 3] = 255;
        }
      }
    }
    tCtx.putImageData(imgData, 0, 0);
    ctx.save();
    ctx.globalAlpha = 0.35;
    ctx.drawImage(tmp, 0, 0);
    ctx.restore();
    ctx.strokeStyle = hexColor;
    ctx.lineWidth = 2;
    ctx.beginPath();
    for (var ey = 1; ey < mh - 1; ey++) {
      for (var ex = 1; ex < mw - 1; ex++) {
        if (d[ey * mw + ex] === 0) continue;
        var isEdge = d[(ey - 1) * mw + ex] === 0 ||
                     d[(ey + 1) * mw + ex] === 0 ||
                     d[ey * mw + (ex - 1)] === 0 ||
                     d[ey * mw + (ex + 1)] === 0;
        if (isEdge) ctx.rect(ex, ey, 1, 1);
      }
    }
    ctx.stroke();
  }

  // Header timing en haut à gauche : `#<id> XXms` (parité POC visualizer).
  function drawDebugHeader(ctx, id, elapsedMs) {
    var label = '#' + (id || '?');
    if (typeof elapsedMs === 'number' && isFinite(elapsedMs)) {
      label += ' ' + elapsedMs.toFixed(0) + 'ms';
    }
    ctx.font = 'bold 13px monospace';
    var tw = ctx.measureText(label).width + 10;
    ctx.fillStyle = 'rgba(0, 0, 0, 0.75)';
    ctx.fillRect(0, 0, tw, 22);
    ctx.fillStyle = '#00FF00';
    ctx.fillText(label, 5, 16);
  }

  // Dessine le overlay (port direct de visualizer.draw, sx=sy=1).
  function drawDebugDetections(ctx, persons, imgW, imgH, debugMode) {
    var isLite = debugMode === 'boxes';
    var femaleIdx = 0;
    var maleIdx = 0;

    for (var pi = 0; pi < persons.length; pi++) {
      var person = persons[pi];
      var bb = person.bbox;
      if (!bb || bb.length !== 4) continue;
      var x1 = bb[0], y1 = bb[1], x2 = bb[2], y2 = bb[3];
      var dw = x2 - x1, dh = y2 - y1;

      var color;
      if (person.gender === 'female') {
        color = FEMALE_COLORS[femaleIdx % FEMALE_COLORS.length];
        femaleIdx++;
      } else {
        color = MALE_COLORS[maleIdx % MALE_COLORS.length];
        maleIdx++;
      }

      // Polygon mask (debug only) — recalculé à la volée depuis les keypoints.
      if (!isLite && person.keypoints && person.keypoints.length === 17) {
        try {
          var poly = buildBodyPolygon(person.keypoints, bb, imgW, imgH);
          if (poly.isBodyShaped) {
            var mask = polygonToMask(poly.points, imgW, imgH);
            drawMask(ctx, mask, color);
          }
        } catch (_) { /* non-fatal */ }
      }

      // Body bbox
      ctx.strokeStyle = color;
      ctx.lineWidth = isLite ? 2 : 3;
      ctx.strokeRect(x1, y1, dw, dh);

      if (!isLite) {
        // Face bbox (dashed, yellow)
        if (person.faceBbox && person.faceBbox.length === 4) {
          var fx1 = person.faceBbox[0], fy1 = person.faceBbox[1];
          var fx2 = person.faceBbox[2], fy2 = person.faceBbox[3];
          ctx.strokeStyle = '#FFD700';
          ctx.lineWidth = 2;
          ctx.setLineDash([4, 4]);
          ctx.strokeRect(fx1, fy1, fx2 - fx1, fy2 - fy1);
          ctx.setLineDash([]);
        }
        // Skeleton + keypoints
        if (person.keypoints && person.keypoints.length) {
          var kps = person.keypoints;
          var kpRadius = Math.max(1.5, Math.min(4, dw * 0.025));
          ctx.lineWidth = Math.max(1, Math.round(dw * 0.012));
          for (var si = 0; si < COCO_SKELETON.length; si++) {
            var a = COCO_SKELETON[si][0], b = COCO_SKELETON[si][1];
            if (kps[a] && kps[b] && kps[a].confidence > KP_CONF && kps[b].confidence > KP_CONF) {
              ctx.strokeStyle = LIMB_COLORS[si];
              ctx.beginPath();
              ctx.moveTo(kps[a].x, kps[a].y);
              ctx.lineTo(kps[b].x, kps[b].y);
              ctx.stroke();
            }
          }
          for (var ki = 0; ki < kps.length; ki++) {
            var kp = kps[ki];
            if (kp && kp.confidence > KP_CONF) {
              ctx.beginPath();
              ctx.arc(kp.x, kp.y, kpRadius, 0, Math.PI * 2);
              ctx.fillStyle = KP_COLORS[ki % KP_COLORS.length];
              ctx.fill();
              ctx.strokeStyle = '#000';
              ctx.lineWidth = 1;
              ctx.stroke();
            }
          }
        }
      }

      // Label (POC parity)
      var gShort = person.gender === 'female' ? 'F'
                 : person.gender === 'male'   ? 'M'
                 : '?';
      var classLabel = person.classifierUsed ? ' [' + person.classifierUsed + ']' : '';
      if (isLite) {
        // Boxes mode : "F XX%" + classifier label in brackets (macOS POC).
        var confTxt = person.genderConfidence != null
          ? (gShort + ' ' + Math.round(person.genderConfidence * 100) + '%' + classLabel)
          : gShort + classLabel;
        ctx.font = 'bold 13px monospace';
        var tw = ctx.measureText(confTxt).width + 6;
        var lh = 18;
        var ly = y1 >= lh ? y1 - lh : y1;
        ctx.fillStyle = color;
        ctx.fillRect(x1, ly, tw, lh);
        ctx.fillStyle = '#fff';
        ctx.fillText(confTxt, x1 + 3, ly + lh - 4);
      } else {
        // Debug complet : main + body conf + classifier label.
        var confStr = person.genderConfidence != null
          ? (Math.round(person.genderConfidence * 100) + '%')
          : '';
        var bodyStr = person.bodyConfidence != null
          ? ('body ' + Math.round(person.bodyConfidence * 100) + '%')
          : null;
        var mainLabel = gShort + ' ' + confStr + classLabel;
        var extra = bodyStr ? [bodyStr] : [];
        var lineH = 15;
        var totalH = (1 + extra.length) * lineH + 4;
        ctx.font = 'bold 13px monospace';
        var labelW = ctx.measureText(mainLabel).width;
        for (var ei = 0; ei < extra.length; ei++) {
          labelW = Math.max(labelW, ctx.measureText(extra[ei]).width);
        }
        labelW += 8;
        var lyD = y1 >= totalH ? y1 - totalH : y1;
        ctx.fillStyle = color;
        ctx.fillRect(x1, lyD, labelW, totalH);
        ctx.fillStyle = '#FFFFFF';
        ctx.fillText(mainLabel, x1 + 4, lyD + lineH - 2);
        ctx.fillStyle = 'rgba(255,255,255,0.7)';
        for (var el = 0; el < extra.length; el++) {
          ctx.fillText(extra[el], x1 + 4, lyD + (el + 2) * lineH - 2);
        }
      }
    }
  }

  // Decode a `data:image/png;base64,...` URL into an HTMLImageElement.
  // Wrapped in a Promise so we can await the decode before drawing.
  function decodeDataUrl(dataUrl) {
    return new Promise(function(resolve) {
      if (!dataUrl) { resolve(null); return; }
      var im = new Image();
      im.onload = function() { resolve(im); };
      im.onerror = function() { resolve(null); };
      im.src = dataUrl;
    });
  }

  // Draw the bottom black strip — face + body side by side per person, with
  // labels in gender colours like the macOS POC `_drawCropStrip` :
  //
  //   [face 96×96][body 100×133]    ← 4px gap between, yellow border face
  //   [male 95%]  [male 91%]        ← yellow under face, gender colour under body
  //   M 95% [insightface (partial body)]   ← gender colour, classifier suffix
  function drawCropStripAndEncode(canvas, ctx, persons, imgW, imgH, stripH, sourceImg) {
    ctx.fillStyle = '#000';
    ctx.fillRect(0, imgH, imgW, stripH);

    // Decode all crops in parallel.
    var jobs = [];
    for (var i = 0; i < persons.length; i++) {
      jobs.push(decodeDataUrl(persons[i].faceCropDataUrl));
      jobs.push(decodeDataUrl(persons[i].bodyCropDataUrl));
    }
    return Promise.all(jobs).then(function(images) {
      var FACE_DISPLAY = 96;
      var BODY_DISPLAY_W = 100;
      var BODY_DISPLAY_H = 133;
      var INNER_GAP = 4;  // face-body gap inside a column
      var COL_W = FACE_DISPLAY + INNER_GAP + BODY_DISPLAY_W;   // 200
      var COL_GAP = 12;
      var TOP_PAD = 6;
      var x = 6;
      var stripTop = imgH;
      // Female / male palette indices reset per strip — match drawDebugDetections.
      var femaleIdx = 0;
      var maleIdx = 0;

      for (var pi = 0; pi < persons.length; pi++) {
        var person = persons[pi];
        var face = images[pi * 2];
        var body = images[pi * 2 + 1];

        // Person colour from the same palettes as the bbox overlay.
        var personColor;
        if (person.gender === 'female') {
          personColor = FEMALE_COLORS[femaleIdx % FEMALE_COLORS.length];
          femaleIdx++;
        } else {
          personColor = MALE_COLORS[maleIdx % MALE_COLORS.length];
          maleIdx++;
        }

        // Derive per-classifier gender + conf for the labels (POC reports
        // both face and body classifier outputs even when one didn't run).
        var faceGenderLabel = '';
        if (person.facePFemale != null && person.facePMale != null) {
          var faceIsFemale = person.facePFemale >= person.facePMale;
          var faceConf = faceIsFemale ? person.facePFemale : person.facePMale;
          faceGenderLabel = (faceIsFemale ? 'female ' : 'male ')
            + Math.round(faceConf * 100) + '%';
        } else {
          faceGenderLabel = 'face';
        }
        var bodyGenderLabel = '';
        if (person.bodyPFemale != null && person.bodyPMale != null) {
          var bodyIsFemale = person.bodyPFemale >= person.bodyPMale;
          var bodyConf = bodyIsFemale ? person.bodyPFemale : person.bodyPMale;
          bodyGenderLabel = (bodyIsFemale ? 'female ' : 'male ')
            + Math.round(bodyConf * 100) + '%';
        } else {
          bodyGenderLabel = 'body';
        }
        // Final winner label (matches the bbox label format).
        var gShort = person.gender === 'female' ? 'F'
                   : person.gender === 'male'   ? 'M'
                   : '?';
        var winnerConf = person.genderConfidence != null
          ? Math.round(person.genderConfidence * 100) + '%'
          : '';
        // Shorten classifier names so the label fits in the column width
        // (POC uses long labels but desktop has more horizontal space).
        var classSuffix = '';
        if (person.classifierUsed) {
          classSuffix = ' ['
            + person.classifierUsed
              .replace('insightface (partial body)', 'IF (part)')
              .replace('insightface (synth body)', 'IF (synth)')
              .replace('insightface (conflict)', 'IF (cnflct)')
              .replace('insightface (align fail)', 'IF (align)')
              .replace('pplcnet (synth body)', 'PP (synth)')
              .replace('pplcnet (no face)', 'PP (no face)')
              .replace('pplcnet (best)', 'PP (best)')
              .replace('pplcnet (align fail)', 'PP (align)')
              .replace('insightface', 'IF')
              .replace('pplcnet', 'PP')
            + ']';
        }
        var classLabel = gShort + ' ' + winnerConf + classSuffix;

        var y = stripTop + TOP_PAD;
        // 1) Face + body side by side
        if (face) {
          ctx.drawImage(face, x, y, FACE_DISPLAY, FACE_DISPLAY);
          // Yellow border on face (POC parity).
          ctx.strokeStyle = '#FFD700';
          ctx.lineWidth = 2;
          ctx.strokeRect(x, y, FACE_DISPLAY, FACE_DISPLAY);
        } else {
          ctx.fillStyle = '#222';
          ctx.fillRect(x, y, FACE_DISPLAY, FACE_DISPLAY);
        }
        var bx = x + FACE_DISPLAY + INNER_GAP;
        // Center body vertically with face (both bottoms aligned).
        var bodyY = y + (FACE_DISPLAY - BODY_DISPLAY_H);  // negative for taller body
        // If body is taller than face, draw it from y and let it extend below.
        // Otherwise align tops. POC stacks bottoms; we do the same.
        var bodyDrawY = y + Math.max(0, FACE_DISPLAY - BODY_DISPLAY_H);
        if (BODY_DISPLAY_H >= FACE_DISPLAY) bodyDrawY = y;
        if (body) {
          ctx.drawImage(body, bx, bodyDrawY, BODY_DISPLAY_W, BODY_DISPLAY_H);
          // Person-colour border on body.
          ctx.strokeStyle = personColor;
          ctx.lineWidth = 2;
          ctx.strokeRect(bx, bodyDrawY, BODY_DISPLAY_W, BODY_DISPLAY_H);
        } else {
          ctx.fillStyle = '#222';
          ctx.fillRect(bx, bodyDrawY, BODY_DISPLAY_W, BODY_DISPLAY_H);
        }

        // 2) Labels under each vignette
        var labelY = y + Math.max(FACE_DISPLAY, BODY_DISPLAY_H) + 12;
        ctx.font = 'bold 11px monospace';
        ctx.textAlign = 'center';
        ctx.fillStyle = '#FFD700';
        ctx.fillText(faceGenderLabel, x + FACE_DISPLAY / 2, labelY);
        ctx.fillStyle = personColor;
        ctx.fillText(bodyGenderLabel, bx + BODY_DISPLAY_W / 2, labelY);

        // 3) Final winner label (gender colour) centered under the column,
        // clipped to column width so it never overlaps the next person.
        ctx.font = 'bold 11px monospace';
        ctx.textAlign = 'center';
        ctx.fillStyle = personColor;
        var classLabelClipped = classLabel;
        var maxLabelW = COL_W - 4;
        while (classLabelClipped.length > 6
               && ctx.measureText(classLabelClipped).width > maxLabelW) {
          classLabelClipped = classLabelClipped.slice(0, -1);
        }
        ctx.fillText(classLabelClipped, x + COL_W / 2, labelY + 16);

        x += COL_W + COL_GAP;
        if (x + COL_W > imgW) break;
      }
      ctx.textAlign = 'left';  // restore

      var srcLower = (sourceImg.currentSrc || sourceImg.src || '').toLowerCase();
      var needsAlpha = /\.png(\?|$)/.test(srcLower) || /\.webp(\?|$)/.test(srcLower)
        || srcLower.indexOf('data:image/png') === 0;
      var mime = needsAlpha ? 'image/png' : 'image/jpeg';
      var quality = needsAlpha ? undefined : 0.85;
      return new Promise(function(resolveBlob) {
        canvas.toBlob(function(blob) { resolveBlob(blob); }, mime, quality);
      }).then(function(blob) {
        if (!blob) return false;
        return replaceImgWithBlob(sourceImg, blob);
      });
    });
  }

  // Replace the original <img> with a fresh clone pointing to a blob URL —
  // factored out of compositePerPersonBlur for the debug strip path.
  function replaceImgWithBlob(img, blob) {
    if (img.hasAttribute('srcset')) img.removeAttribute('srcset');
    if (img.hasAttribute('sizes')) img.removeAttribute('sizes');
    var pic = img.parentNode;
    if (pic && pic.tagName === 'PICTURE') {
      var sources = pic.querySelectorAll('source');
      for (var si = 0; si < sources.length; si++) {
        sources[si].removeAttribute('srcset');
      }
    }
    if (img.dataset.basarunaaBlobUrl) {
      try { URL.revokeObjectURL(img.dataset.basarunaaBlobUrl); } catch (_) {}
    }
    var blobUrl = URL.createObjectURL(blob);
    img.dataset.basarunaaBlobUrl = blobUrl;
    var fresh = img.cloneNode(false);
    fresh.removeAttribute('srcset');
    fresh.removeAttribute('sizes');
    fresh.removeAttribute('crossorigin');
    fresh.removeAttribute(BLUR_MARKER);
    fresh.style.removeProperty('filter');
    fresh.dataset.basarunaaBlobUrl = blobUrl;
    fresh.src = blobUrl;
    fresh.setAttribute(ID_ATTR, img.getAttribute(ID_ATTR) || '');
    fresh.setAttribute(STATE_ATTR, 'keep');
    if (img.parentNode) {
      img.parentNode.replaceChild(fresh, img);
      try { if (intersectionObserver) intersectionObserver.unobserve(img); } catch (_) {}
    }
    return true;
  }

  function compositeDebugOverlay(img, persons, debugMode, elapsedMs) {
    if (!persons || persons.length === 0) return Promise.resolve(false);
    var id = img.getAttribute(ID_ATTR);
    var normalised = normalisePersons(persons);
    // POC parity: in debug mode, the per-person blur from the active mode
    // is still applied — the overlay just draws on top so the user sees
    // *both* the production behaviour and what the pipeline detected.
    var toBlur = [];
    for (var bi = 0; bi < persons.length; bi++) {
      if (persons[bi].shouldBlur) toBlur.push(persons[bi]);
    }
    metric('debug_overlay_start', {
      id: id, persons: normalised.length, toBlur: toBlur.length, mode: '' + debugMode,
    });
    return getCompositingSource(img).then(function(source) {
      var w = source.naturalWidth != null ? source.naturalWidth : source.width;
      var h = source.naturalHeight != null ? source.naturalHeight : source.height;
      if (!w || !h) {
        metric('debug_overlay_nodim', { id: id });
        return false;
      }
      try {
        // In "debug" mode (full debug), add a black strip below the image
        // showing the face crop 96×96 + body crop 192×256 that each
        // classifier actually saw. Lets us diagnose visually instead of
        // guessing what the model received.
        var isFullDebug = debugMode === 'debug';
        var stripH = 0;
        if (isFullDebug) {
          // POC parity layout : face 96×96 + body 100×133 side-by-side.
          // top pad + max(face,body) + per-vignette label + winner label + pad
          stripH = 6 + 133 + 12 + 11 + 16 + 12 + 10;  // ≈200
        }
        var canvas = document.createElement('canvas');
        canvas.width = w;
        canvas.height = h + stripH;
        var ctx = canvas.getContext('2d');
        ctx.drawImage(source, 0, 0, w, h);
        // 1) blur the persons the active mode would normally blur, with
        //    the POC's debug contours (cyan/green/orange/red dashed) drawn
        //    around each silhouette so the user sees what the polygon mask
        //    looks like — only in debug mode (`showDebug=true`).
        if (toBlur.length > 0) {
          var blur = Math.max(25, Math.round(Math.max(w, h) * 0.04));
          var blurredCanvas = createEdgeClampedBlur(source, w, h, blur);
          for (var pi = 0; pi < toBlur.length; pi++) {
            drawFeatheredBlur(ctx, blurredCanvas, toBlur[pi], w, h, true);
          }
        }
        // 2) draw the debug overlay on top of the (partially) blurred image.
        drawDebugDetections(ctx, normalised, w, h, debugMode);
        // 3) header in top-left : `#<id> <elapsed>ms` (POC parity).
        drawDebugHeader(ctx, id, elapsedMs);
        // 4) crop strip in the bottom black band (debug mode only).
        if (isFullDebug && stripH > 0) {
          return drawCropStripAndEncode(canvas, ctx, normalised, w, h, stripH, img);
        }
        var srcLower = (img.currentSrc || img.src || '').toLowerCase();
        var needsAlpha = /\.png(\?|$)/.test(srcLower) || /\.webp(\?|$)/.test(srcLower)
          || srcLower.indexOf('data:image/png') === 0;
        var mime = needsAlpha ? 'image/png' : 'image/jpeg';
        var quality = needsAlpha ? undefined : 0.85;
        return new Promise(function(resolveBlob) {
          canvas.toBlob(function(blob) { resolveBlob(blob); }, mime, quality);
        }).then(function(blob) {
          if (!blob) {
            metric('debug_overlay_no_blob', { id: id });
            return false;
          }
          if (img.hasAttribute('srcset')) img.removeAttribute('srcset');
          if (img.hasAttribute('sizes')) img.removeAttribute('sizes');
          var pic = img.parentNode;
          if (pic && pic.tagName === 'PICTURE') {
            var sources = pic.querySelectorAll('source');
            for (var si = 0; si < sources.length; si++) {
              sources[si].removeAttribute('srcset');
            }
          }
          if (img.dataset.basarunaaBlobUrl) {
            try { URL.revokeObjectURL(img.dataset.basarunaaBlobUrl); } catch (_) {}
          }
          var blobUrl = URL.createObjectURL(blob);
          img.dataset.basarunaaBlobUrl = blobUrl;
          var fresh = img.cloneNode(false);
          fresh.removeAttribute('srcset');
          fresh.removeAttribute('sizes');
          fresh.removeAttribute('crossorigin');
          fresh.removeAttribute(BLUR_MARKER);
          fresh.style.removeProperty('filter');
          fresh.dataset.basarunaaBlobUrl = blobUrl;
          fresh.src = blobUrl;
          fresh.setAttribute(ID_ATTR, img.getAttribute(ID_ATTR) || '');
          fresh.setAttribute(STATE_ATTR, 'keep');
          if (img.parentNode) {
            img.parentNode.replaceChild(fresh, img);
            try { if (intersectionObserver) intersectionObserver.unobserve(img); } catch (_) {}
            metric('debug_overlay_applied', { id: id, persons: persons.length });
          }
          return true;
        });
      } catch (e) {
        metric('debug_overlay_failed', { id: id, msg: ('' + e).slice(0, 120) });
        return false;
      }
    }).catch(function(e) {
      metric('debug_overlay_rejected', { id: id, msg: ('' + e).slice(0, 120) });
      return false;
    });
  }

  // ─── Receive decision from Swift ───
  // Swift sends `(id, decision, persons, debugMode, elapsedMs)`.
  // `persons` includes a per-entry `shouldBlur` flag (true for the persons
  // the active mode would normally blur). `debugMode` is one of
  // "none" / "boxes" / "debug" — when not "none", we draw a debug overlay
  // on top of the per-person blur (POC parity), and a `#<id> XXms`
  // header in the top-left corner.
  window.__basarunaaApply = function(id, decision, persons, debugMode, elapsedMs) {
    try {
      var img = findById(id);
      var personCount = (persons && persons.length) || 0;
      var isDebug = debugMode === 'boxes' || debugMode === 'debug';
      metric('analyze_decision', {
        id: id, decision: '' + decision, persons: personCount,
        found: !!img, debug: '' + (debugMode || 'none'),
      });
      if (img) {
        img.setAttribute(STATE_ATTR, decision);
        if (isDebug) {
          // Debug overlay: composite blur (on shouldBlur=true persons) then
          // draw bboxes/labels/skeleton on top. We don't cache the
          // decision in debug mode so the user can toggle modes and reload.
          removeBlurFrom(img);
          if (personCount > 0) {
            compositeDebugOverlay(img, persons, debugMode, elapsedMs);
          }
        } else if (decision === 'remove') {
          removeBlurFrom(img);
          setCachedDecision(imgUrl(img), decision);
        } else if (decision === 'keep' && personCount > 0) {
          // Per-person composite blur (POC method). Async because we need to
          // decode the CORS-fetched blob into an ImageBitmap before drawing.
          // Falls back silently to full-image blur on failure.
          compositePerPersonBlur(img, persons);
          setCachedDecision(imgUrl(img), decision);
        } else {
          // 'keep' without persons (NSFW) → full-image blur already applied.
          setCachedDecision(imgUrl(img), decision);
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
