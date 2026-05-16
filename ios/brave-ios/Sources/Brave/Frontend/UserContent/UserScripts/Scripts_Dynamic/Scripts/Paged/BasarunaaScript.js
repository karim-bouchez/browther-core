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

  function drawFeatheredBlur(ctx, blurredCanvas, person, w, h) {
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
    metric('composite_start', {
      id: id,
      naturalW: img.naturalWidth, naturalH: img.naturalHeight,
      persons: persons.length,
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
        for (var pi = 0; pi < persons.length; pi++) {
          drawFeatheredBlur(ctx, blurredCanvas, persons[pi], w, h);
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

  // Draw a debug overlay (bboxes + optional face + keypoints) on top of the
  // original image. Reuses the same "encode image to canvas, blob URL, clone
  // and replace the <img>" plumbing as compositePerPersonBlur — the only
  // difference is *what* gets painted on the canvas.
  function genderColor(gender) {
    if (gender === 'female') return '#22c55e';   // green
    if (gender === 'male')   return '#3b82f6';   // blue
    return '#f59e0b';                            // amber for nil / unknown
  }

  function drawDebugDetections(ctx, persons, w, h, debugMode) {
    var lineW = Math.max(2, Math.round(Math.min(w, h) / 200));
    ctx.lineWidth = lineW;
    ctx.font = Math.max(14, Math.round(Math.min(w, h) / 30)) + 'px -apple-system, sans-serif';
    ctx.textBaseline = 'top';
    for (var i = 0; i < persons.length; i++) {
      var p = persons[i];
      var bb = p.bbox || [];
      if (bb.length !== 4) continue;
      var x1 = bb[0], y1 = bb[1], x2 = bb[2], y2 = bb[3];
      var color = genderColor(p.gender);
      ctx.strokeStyle = color;
      ctx.fillStyle = color;
      // Body bbox
      ctx.strokeRect(x1, y1, x2 - x1, y2 - y1);
      // Label (gender + confidence)
      var genderLabel = p.gender || '?';
      var conf = (typeof p.genderConfidence === 'number')
        ? (' ' + Math.round(p.genderConfidence * 100) + '%')
        : '';
      var bodyConf = (typeof p.bodyConfidence === 'number')
        ? (' body=' + Math.round(p.bodyConfidence * 100) + '%')
        : '';
      var label = genderLabel + conf + bodyConf;
      var pad = 4;
      var tw = ctx.measureText(label).width + pad * 2;
      var th = parseInt(ctx.font, 10) + pad * 2;
      var ly = Math.max(0, y1 - th);
      ctx.fillRect(x1, ly, tw, th);
      ctx.fillStyle = '#000';
      ctx.fillText(label, x1 + pad, ly + pad);
      ctx.fillStyle = color;

      if (debugMode === 'debug') {
        // Face bbox in red dashed
        if (p.faceBbox && p.faceBbox.length === 4) {
          ctx.save();
          ctx.strokeStyle = '#ef4444';
          ctx.setLineDash([lineW * 2, lineW * 2]);
          var fx1 = p.faceBbox[0], fy1 = p.faceBbox[1];
          var fx2 = p.faceBbox[2], fy2 = p.faceBbox[3];
          ctx.strokeRect(fx1, fy1, fx2 - fx1, fy2 - fy1);
          ctx.restore();
        }
        // Keypoints as small dots, alpha by confidence
        var kps = p.keypoints || [];
        var dotR = Math.max(3, Math.round(lineW * 1.5));
        for (var k = 0; k < kps.length; k++) {
          var kp = kps[k];
          if (!kp || kp.length < 3) continue;
          var kx = kp[0], ky = kp[1], kc = kp[2];
          if (kc < 0.2) continue;
          ctx.save();
          ctx.globalAlpha = Math.max(0.2, Math.min(1, kc));
          ctx.fillStyle = '#fde047';
          ctx.beginPath();
          ctx.arc(kx, ky, dotR, 0, Math.PI * 2);
          ctx.fill();
          ctx.restore();
        }
      }
    }
  }

  function compositeDebugOverlay(img, persons, debugMode) {
    if (!persons || persons.length === 0) return Promise.resolve(false);
    var id = img.getAttribute(ID_ATTR);
    metric('debug_overlay_start', {
      id: id, persons: persons.length, mode: '' + debugMode,
    });
    return getCompositingSource(img).then(function(source) {
      var w = source.naturalWidth != null ? source.naturalWidth : source.width;
      var h = source.naturalHeight != null ? source.naturalHeight : source.height;
      if (!w || !h) {
        metric('debug_overlay_nodim', { id: id });
        return false;
      }
      try {
        var canvas = document.createElement('canvas');
        canvas.width = w;
        canvas.height = h;
        var ctx = canvas.getContext('2d');
        ctx.drawImage(source, 0, 0, w, h);
        drawDebugDetections(ctx, persons, w, h, debugMode);
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
  // Swift sends `(id, decision, persons, debugMode)`. `persons` is the array
  // of detected people. `debugMode` is one of "none" / "boxes" / "debug" —
  // when not "none", we draw a visible overlay (no blur) instead of
  // compositing the per-person mask.
  window.__basarunaaApply = function(id, decision, persons, debugMode) {
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
          // Debug overlay (boxes / full debug): always remove the default
          // blur first, then draw the detections on top of the original
          // image. We don't cache the decision in debug mode so the user
          // can toggle modes and refresh.
          removeBlurFrom(img);
          if (personCount > 0) {
            compositeDebugOverlay(img, persons, debugMode);
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
