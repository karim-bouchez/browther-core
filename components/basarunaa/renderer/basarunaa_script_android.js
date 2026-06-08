// Copyright (c) 2026 The Browther Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.
//
// AUTO-GENERATED from private/extensions/basarunaa/src/android/userscript.ts
// by private/scripts/deploy-basarunaa-script-android.sh. DO NOT EDIT.
// Modifier le .ts source à la place, puis re-run le deploy script.

(function () {
  'use strict';

  class DecisionCache {
    constructor(maxEntries = 500) {
      this.maxEntries = maxEntries;
      this.cache = /* @__PURE__ */ new Map();
    }
    get(url) {
      return url ? this.cache.get(url) : void 0;
    }
    set(url, decision) {
      if (!url) return;
      if (this.cache.has(url)) {
        this.cache.delete(url);
      } else if (this.cache.size >= this.maxEntries) {
        const oldestKey = this.cache.keys().next().value;
        if (oldestKey !== void 0) this.cache.delete(oldestKey);
      }
      this.cache.set(url, decision);
    }
    clear() {
      this.cache.clear();
    }
    get size() {
      return this.cache.size;
    }
  }

  const BLUR_MARKER = "data-basarunaa-blurred";
  const STATE_ATTR = "data-basarunaa-state";
  const ID_ATTR = "data-basarunaa-id";
  const DEFAULT_HIDE_FIRST_BLUR_PX = 20;
  function applyHideFirst(el, opts = {}) {
    const state = el.getAttribute(STATE_ATTR);
    if (state === "keep" || state === "remove") return false;
    if (el.getAttribute(BLUR_MARKER) === "1") return false;
    const radius = opts.blurRadiusPx ?? DEFAULT_HIDE_FIRST_BLUR_PX;
    const filter = opts.grayscale ? `blur(${radius}px) grayscale(1)` : `blur(${radius}px)`;
    try {
      el.style.setProperty("filter", filter, "important");
      el.setAttribute(BLUR_MARKER, "1");
      return true;
    } catch {
      return false;
    }
  }
  function releaseHideFirst(el) {
    try {
      el.style.removeProperty("filter");
      el.removeAttribute(BLUR_MARKER);
    } catch {
    }
  }
  function getImageState(el) {
    const v = el.getAttribute(STATE_ATTR);
    if (v === "pending" || v === "analyzing" || v === "keep" || v === "remove") {
      return v;
    }
    return null;
  }

  const DEFAULT_MIN_SIZE = 46;
  function isSvgUrl(url) {
    const lower = url.toLowerCase();
    return lower.endsWith(".svg") || lower.includes(".svg?") || lower.includes(".svg#") || lower.startsWith("data:image/svg");
  }
  const SVG_TYPE = "image/svg+xml";
  function isProcessableImage(img, minSize = DEFAULT_MIN_SIZE) {
    if (!img || img.tagName !== "IMG") return false;
    if (img.naturalWidth < minSize || img.naturalHeight < minSize) return false;
    if (!img.complete) return false;
    if (img.type === SVG_TYPE) return false;
    const src = (img.currentSrc || img.src || "").toLowerCase();
    if (!src) return false;
    if (isSvgUrl(src)) return false;
    return true;
  }
  class DomScanner {
    constructor(hooks, opts = {}) {
      this.hooks = hooks;
      this.observer = null;
      this.seen = /* @__PURE__ */ new WeakSet();
      this.nextId = 1;
      this.minSize = opts.minSize ?? DEFAULT_MIN_SIZE;
      this.observeMutations = opts.observeMutations ?? true;
    }
    start() {
      this.scanAll(document);
      if (this.observeMutations) {
        this.observer = new MutationObserver((muts) => this.onMutations(muts));
        const root = document.documentElement || document.body;
        this.observer.observe(root, { childList: true, subtree: true });
      }
    }
    stop() {
      if (this.observer) {
        this.observer.disconnect();
        this.observer = null;
      }
    }
    scanAll(root = document) {
      const imgs = root.querySelectorAll("img");
      let n = 0;
      for (let i = 0; i < imgs.length; i++) {
        if (this.notifyIfProcessable(imgs[i])) n++;
      }
      return n;
    }
    notifyIfProcessable(img) {
      if (this.seen.has(img)) return false;
      if (img.hasAttribute(ID_ATTR)) {
        this.seen.add(img);
        return false;
      }
      const state = getImageState(img);
      if (state === "keep" || state === "remove") {
        this.seen.add(img);
        return false;
      }
      if (!isProcessableImage(img, this.minSize)) return false;
      const id = this.nextId++;
      img.setAttribute(ID_ATTR, String(id));
      this.seen.add(img);
      this.hooks.onImageDiscovered(img, id);
      return true;
    }
    onMutations(mutations) {
      for (const m of mutations) {
        if (m.type !== "childList") continue;
        for (let i = 0; i < m.addedNodes.length; i++) {
          const node = m.addedNodes[i];
          if (!node || node.nodeType !== 1) continue;
          if (node.tagName === "IMG") {
            this.notifyIfProcessable(node);
          } else if (node.querySelectorAll) {
            this.scanAll(node);
          }
        }
        if (this.hooks.onImageRemoved) {
          for (let i = 0; i < m.removedNodes.length; i++) {
            const node = m.removedNodes[i];
            if (!node || node.nodeType !== 1) continue;
            if (node.tagName === "IMG") {
              const img = node;
              const idAttr = img.getAttribute(ID_ATTR);
              if (idAttr) this.hooks.onImageRemoved(img, Number(idAttr));
            }
          }
        }
      }
    }
  }

  const KP_CONFIDENCE = 0.3;
  const BODY_WIDTH_FACTOR = 0.55;
  const HAND_EXTEND = 0.3;
  const FOOT_EXTEND = 0.08;
  const EDGE_SNAP_THRESHOLD = 0.05;
  const REGION_SCALE = {
    head: 0.8,
    // 0-4
    shoulder: 1,
    // 5-6
    elbow: 0.7,
    // 7-8
    wrist: 0.6,
    // 9-10
    hip: 1.1,
    // 11-12
    knee: 0.8,
    // 13-14
    ankle: 0.7
    // 15-16
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
  function buildBodyPolygon(keypoints, bbox, imgW, imgH) {
    const [bx1, by1, bx2, by2] = bbox;
    const bw = bx2 - bx1;
    const bh = by2 - by1;
    if (!keypoints) return bboxFallback(bbox);
    const confident = keypoints.filter((k) => k && k.confidence >= KP_CONFIDENCE);
    if (confident.length < 4) return bboxFallback(bbox);
    const lSh = keypoints[5];
    const rSh = keypoints[6];
    let halfWidth;
    if (lSh && rSh && lSh.confidence >= KP_CONFIDENCE && rSh.confidence >= KP_CONFIDENCE) {
      halfWidth = Math.abs(rSh.x - lSh.x) * BODY_WIDTH_FACTOR;
    } else {
      halfWidth = bw * 0.25;
    }
    halfWidth = Math.max(halfWidth, bw * 0.2);
    const widened = [];
    for (const k of confident) {
      const idx = keypoints.indexOf(k);
      const scale = getRegionScale(idx);
      const w = halfWidth * scale;
      widened.push({ x: k.x - w, y: k.y }, { x: k.x + w, y: k.y });
    }
    const headKpIdxs = [0, 1, 2, 3, 4].filter(
      (i) => keypoints[i] && keypoints[i].confidence >= KP_CONFIDENCE
    );
    if (headKpIdxs.length > 0) {
      const topY = Math.min(...headKpIdxs.map((i) => keypoints[i].y));
      const headCx = headKpIdxs.reduce((s, i) => s + keypoints[i].x, 0) / headKpIdxs.length;
      const headPadY = Math.max(halfWidth * 0.6, bh * 0.08);
      const headPadX = Math.max(halfWidth * 0.9, bw * 0.25);
      widened.push(
        { x: headCx - headPadX, y: topY - headPadY },
        { x: headCx + headPadX, y: topY - headPadY }
      );
    }
    extendHand(keypoints, 7, 9, halfWidth, widened);
    extendHand(keypoints, 8, 10, halfWidth, widened);
    const footExtend = bh * FOOT_EXTEND;
    for (const ankleIdx of [15, 16]) {
      const ankle = keypoints[ankleIdx];
      if (ankle && ankle.confidence >= KP_CONFIDENCE) {
        const w = halfWidth * REGION_SCALE.ankle;
        widened.push(
          { x: ankle.x - w, y: ankle.y + footExtend },
          { x: ankle.x + w, y: ankle.y + footExtend }
        );
      }
    }
    const hull = convexHull(widened);
    const xs = hull.map((p) => p.x);
    const ys = hull.map((p) => p.y);
    const polyMinX = Math.min(...xs);
    const polyMaxX = Math.max(...xs);
    const polyMinY = Math.min(...ys);
    const polyMaxY = Math.max(...ys);
    const polyCx = (polyMinX + polyMaxX) / 2;
    const polyCy = (polyMinY + polyMaxY) / 2;
    const bboxCx = (bx1 + bx2) / 2;
    const bboxCy = (by1 + by2) / 2;
    const sx = bw / (polyMaxX - polyMinX || 1);
    const sy = bh / (polyMaxY - polyMinY || 1);
    const scaled = hull.map((p) => ({
      x: bboxCx + (p.x - polyCx) * sx,
      y: bboxCy + (p.y - polyCy) * sy
    }));
    const snapped = snapToEdges(scaled, bbox, imgW, imgH, keypoints);
    return { points: snapped, isBodyShaped: true };
  }
  function extendHand(kps, elbowIdx, wristIdx, halfWidth, out) {
    const elbow = kps[elbowIdx];
    const wrist = kps[wristIdx];
    if (!elbow || !wrist) return;
    if (elbow.confidence < KP_CONFIDENCE || wrist.confidence < KP_CONFIDENCE)
      return;
    const dx = wrist.x - elbow.x;
    const dy = wrist.y - elbow.y;
    const hx = wrist.x + dx * HAND_EXTEND;
    const hy = wrist.y + dy * HAND_EXTEND;
    const w = halfWidth * 0.6;
    out.push({ x: hx - w, y: hy }, { x: hx + w, y: hy });
  }
  function snapToEdges(points, bbox, imgW, imgH, keypoints) {
    const [bx1, by1, bx2, by2] = bbox;
    const hasAnkles = [15, 16].some(
      (i) => keypoints[i] && keypoints[i].confidence >= KP_CONFIDENCE
    );
    const hasHead = [0, 1, 2].some(
      (i) => keypoints[i] && keypoints[i].confidence >= KP_CONFIDENCE
    );
    const snapBottom = !hasAnkles && by2 / imgH > 1 - EDGE_SNAP_THRESHOLD;
    const snapTop = !hasHead && by1 / imgH < EDGE_SNAP_THRESHOLD;
    const snapLeft = bx1 / imgW < EDGE_SNAP_THRESHOLD;
    const snapRight = bx2 / imgW > 1 - EDGE_SNAP_THRESHOLD;
    if (!snapBottom && !snapTop && !snapLeft && !snapRight) return points;
    const xs = points.map((p) => p.x);
    const ys = points.map((p) => p.y);
    const minX = Math.min(...xs);
    const maxX = Math.max(...xs);
    const minY = Math.min(...ys);
    const maxY = Math.max(...ys);
    const xRange = maxX - minX || 1;
    const yRange = maxY - minY || 1;
    const nearFrac = 0.15;
    return points.map((p) => {
      let { x, y } = p;
      if (snapBottom && y > maxY - yRange * nearFrac) y = imgH;
      if (snapTop && y < minY + yRange * nearFrac) y = 0;
      if (snapLeft && x < minX + xRange * nearFrac) x = 0;
      if (snapRight && x > maxX - xRange * nearFrac) x = imgW;
      return { x, y };
    });
  }
  function bboxFallback(bbox) {
    const [x1, y1, x2, y2] = bbox;
    return {
      points: [
        { x: x1, y: y1 },
        { x: x2, y: y1 },
        { x: x2, y: y2 },
        { x: x1, y: y2 }
      ],
      isBodyShaped: false
    };
  }
  function convexHull(points) {
    if (points.length < 3) return points.slice();
    const sorted = points.slice().sort((a, b) => a.x - b.x || a.y - b.y);
    const n = sorted.length;
    const cross = (o, a, b) => (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
    const lower = [];
    for (let i = 0; i < n; i++) {
      const p = sorted[i];
      while (lower.length >= 2 && cross(lower[lower.length - 2], lower[lower.length - 1], p) <= 0) {
        lower.pop();
      }
      lower.push(p);
    }
    const upper = [];
    for (let i = n - 1; i >= 0; i--) {
      const p = sorted[i];
      while (upper.length >= 2 && cross(upper[upper.length - 2], upper[upper.length - 1], p) <= 0) {
        upper.pop();
      }
      upper.push(p);
    }
    lower.pop();
    upper.pop();
    return lower.concat(upper);
  }
  function polygonToMask(points, imgW, imgH) {
    const data = new Uint8Array(imgW * imgH);
    if (points.length < 3) return { data, width: imgW, height: imgH };
    const ys = points.map((p) => p.y);
    const minY = Math.max(0, Math.floor(Math.min(...ys)));
    const maxY = Math.min(imgH - 1, Math.ceil(Math.max(...ys)));
    for (let y = minY; y <= maxY; y++) {
      const intersections = [];
      for (let i = 0; i < points.length; i++) {
        const a = points[i];
        const b = points[(i + 1) % points.length];
        if (a.y <= y && b.y > y || b.y <= y && a.y > y) {
          const x = a.x + (y - a.y) / (b.y - a.y) * (b.x - a.x);
          intersections.push(x);
        }
      }
      intersections.sort((a, b) => a - b);
      for (let i = 0; i < intersections.length - 1; i += 2) {
        const xa = intersections[i];
        const xb = intersections[i + 1];
        const x1 = Math.max(0, Math.floor(xa));
        const x2 = Math.min(imgW - 1, Math.ceil(xb));
        for (let x = x1; x <= x2; x++) {
          data[y * imgW + x] = 1;
        }
      }
    }
    return { data, width: imgW, height: imgH };
  }

  const MIN_BLUR_PX = 25;
  const FEATHER_EXPAND = 20;
  const FEATHER_BLUR = 10;
  const FEATHER_PAD = FEATHER_EXPAND + FEATHER_BLUR + 5;
  function blurRadiusForImage(w, h) {
    return Math.max(MIN_BLUR_PX, Math.round(Math.max(w, h) * 0.04));
  }
  let canvasBlurSupported = null;
  function isCanvasFilterBlurSupported() {
    if (canvasBlurSupported !== null) return canvasBlurSupported;
    try {
      const c = document.createElement("canvas");
      c.width = 64;
      c.height = 64;
      const ctx = c.getContext("2d");
      if (!ctx) {
        canvasBlurSupported = false;
        return false;
      }
      ctx.fillStyle = "#000";
      ctx.fillRect(0, 0, 64, 32);
      ctx.fillStyle = "#fff";
      ctx.fillRect(0, 32, 64, 32);
      ctx.filter = "blur(8px)";
      ctx.drawImage(c, 0, 0);
      ctx.filter = "none";
      const px = ctx.getImageData(32, 32, 1, 1).data;
      canvasBlurSupported = px[0] > 30 && px[0] < 225;
    } catch {
      canvasBlurSupported = false;
    }
    return canvasBlurSupported;
  }
  function newCanvas(w, h) {
    const c = document.createElement("canvas");
    c.width = w;
    c.height = h;
    return c;
  }
  function ctxOf(c) {
    return c.getContext("2d");
  }
  function blurCanvasGaussian(src, srcW, srcH, dstW, dstH, blurPx) {
    const out = newCanvas(dstW, dstH);
    const c = ctxOf(out);
    c.filter = `blur(${blurPx}px)`;
    c.drawImage(src, 0, 0, srcW, srcH, 0, 0, dstW, dstH);
    c.filter = "none";
    return out;
  }
  function blurCanvasDownsample(src, srcW, srcH, dstW, dstH, blurPx) {
    const factor = Math.max(8, Math.round(blurPx / 2));
    const smallW = Math.max(1, Math.floor(dstW / factor));
    const smallH = Math.max(1, Math.floor(dstH / factor));
    const passes = 2;
    let cur = src;
    let curW = srcW;
    let curH = srcH;
    let last = null;
    for (let p = 0; p < passes; p++) {
      const small = newCanvas(smallW, smallH);
      const sCtx = ctxOf(small);
      sCtx.imageSmoothingEnabled = true;
      sCtx.imageSmoothingQuality = "high";
      sCtx.drawImage(cur, 0, 0, curW, curH, 0, 0, smallW, smallH);
      const up = newCanvas(dstW, dstH);
      const uCtx = ctxOf(up);
      uCtx.imageSmoothingEnabled = true;
      uCtx.imageSmoothingQuality = "high";
      uCtx.drawImage(small, 0, 0, smallW, smallH, 0, 0, dstW, dstH);
      cur = up;
      curW = dstW;
      curH = dstH;
      last = up;
    }
    return last;
  }
  function blurCanvas(src, srcW, srcH, dstW, dstH, blurPx) {
    return isCanvasFilterBlurSupported() ? blurCanvasGaussian(src, srcW, srcH, dstW, dstH, blurPx) : blurCanvasDownsample(src, srcW, srcH, dstW, dstH, blurPx);
  }
  function createEdgeClampedBlur(img, w, h, blurPx) {
    const pad = blurPx * 3;
    const pw = w + 2 * pad;
    const ph = h + 2 * pad;
    const padCanvas = newCanvas(pw, ph);
    const pCtx = ctxOf(padCanvas);
    pCtx.fillStyle = "#808080";
    pCtx.fillRect(0, 0, pw, ph);
    if (pad > 0) {
      pCtx.drawImage(img, 0, 0, w, 1, pad, 0, w, pad);
      pCtx.drawImage(img, 0, h - 1, w, 1, pad, pad + h, w, pad);
      pCtx.drawImage(img, 0, 0, 1, h, 0, pad, pad, h);
      pCtx.drawImage(img, w - 1, 0, 1, h, pad + w, pad, pad, h);
      pCtx.drawImage(img, 0, 0, 1, 1, 0, 0, pad, pad);
      pCtx.drawImage(img, w - 1, 0, 1, 1, pad + w, 0, pad, pad);
      pCtx.drawImage(img, 0, h - 1, 1, 1, 0, pad + h, pad, pad);
      pCtx.drawImage(img, w - 1, h - 1, 1, 1, pad + w, pad + h, pad, pad);
    }
    pCtx.drawImage(img, pad, pad);
    const blurred = blurCanvas(padCanvas, pw, ph, pw, ph, blurPx);
    const result = newCanvas(w, h);
    ctxOf(result).drawImage(blurred, pad, pad, w, h, 0, 0, w, h);
    return result;
  }
  function drawFeatheredBlur(ctx, blurredCanvas, person, w, h, opts = {}) {
    const poly = buildBodyPolygon(person.keypoints ?? null, person.bbox, w, h);
    drawFeatheredFromShape(ctx, blurredCanvas, person.bbox, poly, w, h, opts);
  }
  function drawFeatheredFromShape(ctx, blurredCanvas, bbox, poly, w, h, opts) {
    const tw = w + 2 * FEATHER_PAD;
    const th = h + 2 * FEATHER_PAD;
    const maskCanvas = newCanvas(tw, th);
    const mCtx = ctxOf(maskCanvas);
    mCtx.fillStyle = "#fff";
    mCtx.beginPath();
    if (poly.isBodyShaped) {
      let cx = 0;
      let cy = 0;
      for (const p of poly.points) {
        cx += p.x;
        cy += p.y;
      }
      cx /= poly.points.length;
      cy /= poly.points.length;
      for (let i = 0; i < poly.points.length; i++) {
        const p = poly.points[i];
        const dx = p.x - cx;
        const dy = p.y - cy;
        const dist = Math.sqrt(dx * dx + dy * dy) || 1;
        const ex = p.x + dx / dist * FEATHER_EXPAND + FEATHER_PAD;
        const ey = p.y + dy / dist * FEATHER_EXPAND + FEATHER_PAD;
        if (i === 0) mCtx.moveTo(ex, ey);
        else mCtx.lineTo(ex, ey);
      }
      mCtx.closePath();
    } else {
      let [x1, y1, x2, y2] = bbox;
      const snapX = w * 0.1;
      const snapY = h * 0.1;
      if (x1 < snapX) x1 = -FEATHER_PAD;
      else x1 -= FEATHER_EXPAND;
      if (y1 < snapY) y1 = -FEATHER_PAD;
      else y1 -= FEATHER_EXPAND;
      if (w - x2 < snapX) x2 = w + FEATHER_PAD;
      else x2 += FEATHER_EXPAND;
      if (h - y2 < snapY) y2 = h + FEATHER_PAD;
      else y2 += FEATHER_EXPAND;
      mCtx.rect(x1 + FEATHER_PAD, y1 + FEATHER_PAD, x2 - x1, y2 - y1);
    }
    mCtx.fill();
    const blurredMask = blurCanvas(maskCanvas, tw, th, tw, th, FEATHER_BLUR);
    const temp = newCanvas(w, h);
    const tCtx = ctxOf(temp);
    tCtx.drawImage(blurredCanvas, 0, 0);
    tCtx.globalCompositeOperation = "destination-in";
    tCtx.drawImage(blurredMask, FEATHER_PAD, FEATHER_PAD, w, h, 0, 0, w, h);
    ctx.drawImage(temp, 0, 0);
    if (opts.showDebug) {
      drawFeatherDebugOverlays(ctx, bbox, poly, w, h);
    }
  }
  function drawFeatherDebugOverlays(ctx, bbox, poly, w, h) {
    ctx.save();
    ctx.lineWidth = 2;
    const drawExpanded = (amount) => {
      ctx.beginPath();
      if (poly.isBodyShaped) {
        let pcx = 0;
        let pcy = 0;
        for (const p of poly.points) {
          pcx += p.x;
          pcy += p.y;
        }
        pcx /= poly.points.length;
        pcy /= poly.points.length;
        for (let i = 0; i < poly.points.length; i++) {
          const p = poly.points[i];
          const dx = p.x - pcx;
          const dy = p.y - pcy;
          const dist = Math.sqrt(dx * dx + dy * dy) || 1;
          const ex = p.x + dx / dist * amount;
          const ey = p.y + dy / dist * amount;
          if (i === 0) ctx.moveTo(ex, ey);
          else ctx.lineTo(ex, ey);
        }
        ctx.closePath();
      } else {
        let [bx1, by1, bx2, by2] = bbox;
        const snapX = w * 0.1;
        const snapY = h * 0.1;
        if (bx1 < snapX) bx1 = 0;
        else bx1 -= amount;
        if (by1 < snapY) by1 = 0;
        else by1 -= amount;
        if (w - bx2 < snapX) bx2 = w;
        else bx2 += amount;
        if (h - by2 < snapY) by2 = h;
        else by2 += amount;
        ctx.rect(bx1, by1, bx2 - bx1, by2 - by1);
      }
      ctx.stroke();
    };
    ctx.strokeStyle = "#00ffff";
    ctx.setLineDash([6, 4]);
    drawExpanded(FEATHER_EXPAND);
    ctx.strokeStyle = "#ffcc00";
    ctx.setLineDash([4, 4]);
    drawExpanded(FEATHER_EXPAND + FEATHER_BLUR);
    ctx.restore();
  }

  const FEMALE_COLORS = [
    "#FF69B4",
    "#FF1493",
    "#DB7093",
    "#C71585",
    "#FF007F"
  ];
  const MALE_COLORS = [
    "#4169E1",
    "#1E90FF",
    "#00BFFF",
    "#4682B4",
    "#0047AB"
  ];
  const COCO_SKELETON = [
    [0, 1],
    [0, 2],
    [1, 3],
    [2, 4],
    // head
    [5, 6],
    // shoulders
    [5, 7],
    [7, 9],
    // left arm
    [6, 8],
    [8, 10],
    // right arm
    [5, 11],
    [6, 12],
    // torso
    [11, 12],
    // hips
    [11, 13],
    [13, 15],
    // left leg
    [12, 14],
    [14, 16]
    // right leg
  ];
  const LIMB_COLORS = [
    "#FF6B6B",
    "#FF6B6B",
    "#FF6B6B",
    "#FF6B6B",
    // head: red
    "#FFD93D",
    // shoulders: yellow
    "#6BCB77",
    "#6BCB77",
    // left arm: green
    "#4D96FF",
    "#4D96FF",
    // right arm: blue
    "#FFD93D",
    "#FFD93D",
    // torso: yellow
    "#FFD93D",
    // hips: yellow
    "#6BCB77",
    "#6BCB77",
    // left leg: green
    "#4D96FF",
    "#4D96FF"
    // right leg: blue
  ];

  function getBinding() {
    if (typeof window === "undefined") return null;
    return window.__basarunaa ?? null;
  }
  function send(action, data = "") {
    const b = getBinding();
    if (!b) return;
    try {
      b.send(action, data);
    } catch {
    }
  }
  function getConfig() {
    const b = getBinding();
    if (!b) return null;
    try {
      return b.getConfig();
    } catch {
      return null;
    }
  }
  function isEnabled() {
    const b = getBinding();
    if (!b) return false;
    try {
      return b.isEnabled();
    } catch {
      return false;
    }
  }
  const sessionStart = typeof performance !== "undefined" && performance.now ? performance.now() : Date.now();
  function now() {
    return typeof performance !== "undefined" && performance.now ? performance.now() : Date.now();
  }
  function metric(event, kvs) {
    const payload = {
      t: Math.round(now() - sessionStart),
      event,
      src: "js"
    };
    if (kvs) {
      for (const k in kvs) payload[k] = kvs[k];
    }
    try {
      send("metric", JSON.stringify(payload));
    } catch {
    }
  }

  const ROOT_MARGIN = "200px 0px";
  function createImageIntersectionObserver(deps) {
    if (typeof IntersectionObserver === "undefined") return null;
    return new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting && entry.target.tagName === "IMG") {
            deps.onVisible(entry.target);
          }
        }
      },
      { rootMargin: ROOT_MARGIN, threshold: 0 }
    );
  }

  let intersectionObserver = null;
  function setIntersectionObserver(io) {
    intersectionObserver = io;
  }
  function unobserveImage(img) {
    if (!intersectionObserver) return;
    try {
      intersectionObserver.unobserve(img);
    } catch {
    }
  }

  const imageBytesByImg = /* @__PURE__ */ new WeakMap();

  function sourceSize(s) {
    const sw = s.naturalWidth;
    const sh = s.naturalHeight;
    if (sw && sh) return { w: sw, h: sh };
    const w = s.width ?? 0;
    const h = s.height ?? 0;
    return { w, h };
  }
  function getCompositingSource(img) {
    return new Promise((resolve) => {
      const buf = imageBytesByImg.get(img);
      if (buf) {
        try {
          const blob = new Blob([buf]);
          createImageBitmap(blob).then((bm) => {
            const { w: w2, h: h2 } = sourceSize(bm);
            resolve({ source: bm, w: w2, h: h2, type: "ImageBitmap" });
          }).catch(() => {
            const { w: w2, h: h2 } = sourceSize(img);
            resolve({ source: img, w: w2, h: h2, type: "HTMLImageElement" });
          });
          return;
        } catch {
        }
      }
      const { w, h } = sourceSize(img);
      resolve({ source: img, w, h, type: "HTMLImageElement" });
    });
  }
  function pickMime(img) {
    const srcLower = (img.currentSrc || img.src || "").toLowerCase();
    const needsAlpha = /\.png(\?|$)/.test(srcLower) || /\.webp(\?|$)/.test(srcLower) || srcLower.indexOf("data:image/png") === 0;
    return needsAlpha ? { mime: "image/png" } : { mime: "image/jpeg", quality: 0.85 };
  }
  function replaceImgWithBlob(img, blob) {
    if (img.hasAttribute("srcset")) img.removeAttribute("srcset");
    if (img.hasAttribute("sizes")) img.removeAttribute("sizes");
    const pic = img.parentNode;
    if (pic && pic.tagName === "PICTURE") {
      pic.querySelectorAll("source").forEach((s) => s.removeAttribute("srcset"));
    }
    const prev = img.dataset.basarunaaBlobUrl;
    if (prev) {
      try {
        URL.revokeObjectURL(prev);
      } catch {
      }
    }
    const blobUrl = URL.createObjectURL(blob);
    img.dataset.basarunaaBlobUrl = blobUrl;
    const fresh = img.cloneNode(false);
    fresh.removeAttribute("srcset");
    fresh.removeAttribute("sizes");
    fresh.removeAttribute("crossorigin");
    fresh.removeAttribute(BLUR_MARKER);
    fresh.style.removeProperty("filter");
    fresh.dataset.basarunaaBlobUrl = blobUrl;
    fresh.src = blobUrl;
    fresh.setAttribute(ID_ATTR, img.getAttribute(ID_ATTR) || "");
    fresh.setAttribute(STATE_ATTR, "keep");
    if (!img.parentNode) {
      metric("composite_no_parent", { id: img.getAttribute(ID_ATTR) });
      return null;
    }
    img.parentNode.replaceChild(fresh, img);
    unobserveImage(img);
    return fresh;
  }
  function compositePerPersonBlur(img, persons) {
    if (!persons || persons.length === 0) return Promise.resolve(false);
    const id = img.getAttribute(ID_ATTR);
    metric("composite_start", {
      id,
      naturalW: img.naturalWidth,
      naturalH: img.naturalHeight,
      persons: persons.length
    });
    return getCompositingSource(img).then(({ source, w, h, type }) => {
      metric("composite_source", { id, type, w, h });
      if (!w || !h) {
        metric("composite_nodim", { id });
        return false;
      }
      try {
        const canvas = document.createElement("canvas");
        canvas.width = w;
        canvas.height = h;
        const ctx = canvas.getContext("2d");
        if (!ctx) {
          metric("composite_no_ctx", { id });
          return false;
        }
        ctx.drawImage(source, 0, 0, w, h);
        const blur = blurRadiusForImage(w, h);
        const blurredCanvas = createEdgeClampedBlur(source, w, h, blur);
        for (const p of persons) drawFeatheredBlur(ctx, blurredCanvas, p, w, h);
        const { mime, quality } = pickMime(img);
        return new Promise((resolve) => {
          canvas.toBlob((b) => resolve(b), mime, quality);
        }).then((blob) => {
          if (!blob) {
            metric("composite_no_blob", { id });
            return false;
          }
          metric("composite_encoded", { id, bytes: blob.size });
          const replaced = replaceImgWithBlob(img, blob);
          if (replaced) {
            metric("composite_applied", { id, mode: "replace" });
          }
          return !!replaced;
        });
      } catch (e) {
        metric("composite_failed", { id, msg: String(e).slice(0, 120) });
        return false;
      }
    }).catch((e) => {
      metric("composite_promise_rejected", {
        id,
        msg: String(e).slice(0, 120)
      });
      return false;
    });
  }

  const KP_DOT_COLORS = [
    "#FF0000",
    "#00FF00",
    "#0000FF",
    "#FFFF00",
    "#FF00FF",
    "#00FFFF",
    "#FFA500",
    "#FF69B4",
    "#7FFF00",
    "#DC143C",
    "#00CED1",
    "#FFD700",
    "#8A2BE2",
    "#32CD32",
    "#FF4500",
    "#1E90FF",
    "#FF1493"
  ];
  const KP_CONF = 0.3;
  function drawMask(ctx, mask, hexColor) {
    const r = parseInt(hexColor.slice(1, 3), 16);
    const g = parseInt(hexColor.slice(3, 5), 16);
    const b = parseInt(hexColor.slice(5, 7), 16);
    const W = ctx.canvas.width;
    const H = ctx.canvas.height;
    const mw = mask.width;
    const mh = mask.height;
    const d = mask.data;
    const tmp = document.createElement("canvas");
    tmp.width = W;
    tmp.height = H;
    const tCtx = tmp.getContext("2d");
    if (!tCtx) return;
    const imgData = tCtx.createImageData(W, H);
    for (let y = 0; y < H; y++) {
      const my = y < mh ? y : mh - 1;
      for (let x = 0; x < W; x++) {
        const mx = x < mw ? x : mw - 1;
        if (d[my * mw + mx] > 0) {
          const off = (y * W + x) * 4;
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
    for (let ey = 1; ey < mh - 1; ey++) {
      for (let ex = 1; ex < mw - 1; ex++) {
        if (d[ey * mw + ex] === 0) continue;
        const isEdge = d[(ey - 1) * mw + ex] === 0 || d[(ey + 1) * mw + ex] === 0 || d[ey * mw + (ex - 1)] === 0 || d[ey * mw + (ex + 1)] === 0;
        if (isEdge) ctx.rect(ex, ey, 1, 1);
      }
    }
    ctx.stroke();
  }
  function drawDebugHeader(ctx, id, elapsedMs) {
    let label = `#${id ?? "?"}`;
    if (typeof elapsedMs === "number" && isFinite(elapsedMs)) {
      label += ` ${elapsedMs.toFixed(0)}ms`;
    }
    ctx.save();
    ctx.font = "bold 13px monospace";
    const tw = ctx.measureText(label).width + 10;
    ctx.fillStyle = "rgba(0, 0, 0, 0.75)";
    ctx.fillRect(0, 0, tw, 22);
    ctx.fillStyle = "#00FF00";
    ctx.fillText(label, 5, 16);
    ctx.restore();
  }
  function drawDebugDetections(ctx, persons, imgW, imgH, debugMode) {
    const isLite = debugMode === "boxes";
    let femaleIdx = 0;
    let maleIdx = 0;
    for (const person of persons) {
      const bb = person.bbox;
      if (!bb || bb.length !== 4) continue;
      const [x1, y1, x2, y2] = bb;
      const dw = x2 - x1;
      const dh = y2 - y1;
      let color;
      if (person.gender === "F") {
        color = FEMALE_COLORS[femaleIdx % FEMALE_COLORS.length];
        femaleIdx++;
      } else {
        color = MALE_COLORS[maleIdx % MALE_COLORS.length];
        maleIdx++;
      }
      if (!isLite && person.keypoints && person.keypoints.length === 17) {
        try {
          const poly = buildBodyPolygon(person.keypoints, bb, imgW, imgH);
          if (poly.isBodyShaped) {
            const mask = polygonToMask(poly.points, imgW, imgH);
            drawMask(ctx, mask, color);
          }
        } catch {
        }
      }
      ctx.strokeStyle = color;
      ctx.lineWidth = isLite ? 2 : 3;
      ctx.strokeRect(x1, y1, dw, dh);
      if (!isLite) {
        if (person.faceBbox && person.faceBbox.length === 4) {
          const [fx1, fy1, fx2, fy2] = person.faceBbox;
          ctx.strokeStyle = "#FFD700";
          ctx.lineWidth = 2;
          ctx.setLineDash([4, 4]);
          ctx.strokeRect(fx1, fy1, fx2 - fx1, fy2 - fy1);
          ctx.setLineDash([]);
        }
        if (person.keypoints && person.keypoints.length) {
          const kps = person.keypoints;
          const kpRadius = Math.max(1.5, Math.min(4, dw * 0.025));
          ctx.lineWidth = Math.max(1, Math.round(dw * 0.012));
          for (let si = 0; si < COCO_SKELETON.length; si++) {
            const limb = COCO_SKELETON[si];
            const a = kps[limb[0]];
            const b = kps[limb[1]];
            if (a && b && a.confidence > KP_CONF && b.confidence > KP_CONF) {
              ctx.strokeStyle = LIMB_COLORS[si];
              ctx.beginPath();
              ctx.moveTo(a.x, a.y);
              ctx.lineTo(b.x, b.y);
              ctx.stroke();
            }
          }
          for (let ki = 0; ki < kps.length; ki++) {
            const kp = kps[ki];
            if (kp && kp.confidence > KP_CONF) {
              ctx.beginPath();
              ctx.arc(kp.x, kp.y, kpRadius, 0, Math.PI * 2);
              ctx.fillStyle = KP_DOT_COLORS[ki % KP_DOT_COLORS.length];
              ctx.fill();
              ctx.strokeStyle = "#000";
              ctx.lineWidth = 1;
              ctx.stroke();
            }
          }
        }
      }
      const gShort = person.gender ?? "?";
      const classRaw = person.classifierUsedRaw || "";
      const classLabel = classRaw ? ` [${classRaw}]` : "";
      if (isLite) {
        const confTxt = person.genderConfidence != null ? `${gShort} ${Math.round(person.genderConfidence * 100)}%${classLabel}` : `${gShort}${classLabel}`;
        ctx.font = "bold 13px monospace";
        const tw = ctx.measureText(confTxt).width + 6;
        const lh = 18;
        const ly = y1 >= lh ? y1 - lh : y1;
        ctx.fillStyle = color;
        ctx.fillRect(x1, ly, tw, lh);
        ctx.fillStyle = "#fff";
        ctx.fillText(confTxt, x1 + 3, ly + lh - 4);
      } else {
        const confStr = person.genderConfidence != null ? `${Math.round(person.genderConfidence * 100)}%` : "";
        const bodyStr = person.bodyConfidence != null ? `body ${Math.round(person.bodyConfidence * 100)}%` : null;
        const mainLabel = `${gShort} ${confStr}${classLabel}`;
        const extra = bodyStr ? [bodyStr] : [];
        const lineH = 15;
        const totalH = (1 + extra.length) * lineH + 4;
        ctx.font = "bold 13px monospace";
        let labelW = ctx.measureText(mainLabel).width;
        for (const e of extra) {
          const w = ctx.measureText(e).width;
          if (w > labelW) labelW = w;
        }
        labelW += 8;
        const lyD = y1 >= totalH ? y1 - totalH : y1;
        ctx.fillStyle = color;
        ctx.fillRect(x1, lyD, labelW, totalH);
        ctx.fillStyle = "#FFFFFF";
        ctx.fillText(mainLabel, x1 + 4, lyD + lineH - 2);
        ctx.fillStyle = "rgba(255,255,255,0.7)";
        for (let el = 0; el < extra.length; el++) {
          ctx.fillText(extra[el], x1 + 4, lyD + (el + 2) * lineH - 2);
        }
      }
    }
  }
  function decodeDataUrl(dataUrl) {
    return new Promise((resolve) => {
      if (!dataUrl) {
        resolve(null);
        return;
      }
      const im = new Image();
      im.onload = () => resolve(im);
      im.onerror = () => resolve(null);
      im.src = dataUrl;
    });
  }
  function shortenClassifier(raw) {
    return raw.replace("insightface (partial body)", "IF (part)").replace("insightface (synth body)", "IF (synth)").replace("insightface (conflict)", "IF (cnflct)").replace("insightface (align fail)", "IF (align)").replace("pplcnet (synth body)", "PP (synth)").replace("pplcnet (no face)", "PP (no face)").replace("pplcnet (best)", "PP (best)").replace("pplcnet (align fail)", "PP (align)").replace("insightface", "IF").replace("pplcnet", "PP");
  }
  function drawCropStripAndEncode(canvas, ctx, persons, imgW, imgH, sourceImg) {
    ctx.fillStyle = "#000";
    ctx.fillRect(0, imgH, imgW, canvas.height - imgH);
    const jobs = [];
    for (const p of persons) {
      jobs.push(decodeDataUrl(p.faceCropDataUrl));
      jobs.push(decodeDataUrl(p.bodyCropDataUrl));
    }
    return Promise.all(jobs).then((images) => {
      const FACE_DISPLAY = 96;
      const BODY_DISPLAY_W = 100;
      const BODY_DISPLAY_H = 133;
      const INNER_GAP = 4;
      const COL_W = FACE_DISPLAY + INNER_GAP + BODY_DISPLAY_W;
      const COL_GAP = 12;
      const TOP_PAD = 6;
      let x = 6;
      const stripTop = imgH;
      let femaleIdx = 0;
      let maleIdx = 0;
      for (let pi = 0; pi < persons.length; pi++) {
        const person = persons[pi];
        const face = images[pi * 2];
        const body = images[pi * 2 + 1];
        let personColor;
        if (person.gender === "F") {
          personColor = FEMALE_COLORS[femaleIdx % FEMALE_COLORS.length];
          femaleIdx++;
        } else {
          personColor = MALE_COLORS[maleIdx % MALE_COLORS.length];
          maleIdx++;
        }
        let faceGenderLabel = "face";
        if (person.facePFemale != null && person.facePMale != null) {
          const faceIsFemale = person.facePFemale >= person.facePMale;
          const faceConf = faceIsFemale ? person.facePFemale : person.facePMale;
          faceGenderLabel = `${faceIsFemale ? "female " : "male "}${Math.round(faceConf * 100)}%`;
        }
        let bodyGenderLabel = "body";
        if (person.bodyPFemale != null && person.bodyPMale != null) {
          const bodyIsFemale = person.bodyPFemale >= person.bodyPMale;
          const bodyConf = bodyIsFemale ? person.bodyPFemale : person.bodyPMale;
          bodyGenderLabel = `${bodyIsFemale ? "female " : "male "}${Math.round(bodyConf * 100)}%`;
        }
        const gShort = person.gender ?? "?";
        const winnerConf = person.genderConfidence != null ? `${Math.round(person.genderConfidence * 100)}%` : "";
        const classRaw = person.classifierUsedRaw || "";
        const classSuffix = classRaw ? ` [${shortenClassifier(classRaw)}]` : "";
        const classLabel = `${gShort} ${winnerConf}${classSuffix}`;
        const y = stripTop + TOP_PAD;
        if (face) {
          ctx.drawImage(face, x, y, FACE_DISPLAY, FACE_DISPLAY);
          ctx.strokeStyle = "#FFD700";
          ctx.lineWidth = 2;
          ctx.strokeRect(x, y, FACE_DISPLAY, FACE_DISPLAY);
        } else {
          ctx.fillStyle = "#222";
          ctx.fillRect(x, y, FACE_DISPLAY, FACE_DISPLAY);
        }
        const bx = x + FACE_DISPLAY + INNER_GAP;
        const bodyDrawY = y ;
        if (body) {
          ctx.drawImage(body, bx, bodyDrawY, BODY_DISPLAY_W, BODY_DISPLAY_H);
          ctx.strokeStyle = personColor;
          ctx.lineWidth = 2;
          ctx.strokeRect(bx, bodyDrawY, BODY_DISPLAY_W, BODY_DISPLAY_H);
        } else {
          ctx.fillStyle = "#222";
          ctx.fillRect(bx, bodyDrawY, BODY_DISPLAY_W, BODY_DISPLAY_H);
        }
        const labelY = y + Math.max(FACE_DISPLAY, BODY_DISPLAY_H) + 12;
        ctx.font = "bold 11px monospace";
        ctx.textAlign = "center";
        ctx.fillStyle = "#FFD700";
        ctx.fillText(faceGenderLabel, x + FACE_DISPLAY / 2, labelY);
        ctx.fillStyle = personColor;
        ctx.fillText(bodyGenderLabel, bx + BODY_DISPLAY_W / 2, labelY);
        ctx.font = "bold 11px monospace";
        ctx.textAlign = "center";
        ctx.fillStyle = personColor;
        let classLabelClipped = classLabel;
        const maxLabelW = COL_W - 4;
        while (classLabelClipped.length > 6 && ctx.measureText(classLabelClipped).width > maxLabelW) {
          classLabelClipped = classLabelClipped.slice(0, -1);
        }
        ctx.fillText(classLabelClipped, x + COL_W / 2, labelY + 16);
        x += COL_W + COL_GAP;
        if (x + COL_W > imgW) break;
      }
      ctx.textAlign = "left";
      const srcLower = (sourceImg.currentSrc || sourceImg.src || "").toLowerCase();
      const needsAlpha = /\.png(\?|$)/.test(srcLower) || /\.webp(\?|$)/.test(srcLower) || srcLower.indexOf("data:image/png") === 0;
      const mime = needsAlpha ? "image/png" : "image/jpeg";
      const quality = needsAlpha ? void 0 : 0.85;
      return new Promise((resolve) => {
        canvas.toBlob((b) => resolve(b), mime, quality);
      }).then((blob) => {
        if (!blob) return false;
        return !!replaceImgWithBlob(sourceImg, blob);
      });
    });
  }
  function compositeDebugOverlay(img, persons, debugMode, elapsedMs) {
    if (!persons || persons.length === 0) return Promise.resolve(false);
    const id = img.getAttribute(ID_ATTR);
    const toBlur = persons.filter((p) => p.shouldBlur);
    metric("debug_overlay_start", {
      id,
      persons: persons.length,
      toBlur: toBlur.length,
      mode: String(debugMode)
    });
    return getCompositingSource(img).then(({ source, w, h }) => {
      if (!w || !h) {
        metric("debug_overlay_nodim", { id });
        return false;
      }
      try {
        const isFullDebug = debugMode === "debug";
        const stripH = isFullDebug ? 6 + 133 + 12 + 11 + 16 + 12 + 10 : 0;
        const canvas = document.createElement("canvas");
        canvas.width = w;
        canvas.height = h + stripH;
        const ctx = canvas.getContext("2d");
        if (!ctx) return false;
        ctx.drawImage(source, 0, 0, w, h);
        if (toBlur.length > 0) {
          const blur = blurRadiusForImage(w, h);
          const blurredCanvas = createEdgeClampedBlur(source, w, h, blur);
          for (const p of toBlur) {
            drawFeatheredBlur(ctx, blurredCanvas, p, w, h, { showDebug: true });
          }
        }
        drawDebugDetections(ctx, persons, w, h, debugMode);
        drawDebugHeader(ctx, id, elapsedMs);
        if (isFullDebug && stripH > 0) {
          return drawCropStripAndEncode(canvas, ctx, persons, w, h, img);
        }
        const srcLower = (img.currentSrc || img.src || "").toLowerCase();
        const needsAlpha = /\.png(\?|$)/.test(srcLower) || /\.webp(\?|$)/.test(srcLower) || srcLower.indexOf("data:image/png") === 0;
        const mime = needsAlpha ? "image/png" : "image/jpeg";
        const quality = needsAlpha ? void 0 : 0.85;
        return new Promise((resolve) => {
          canvas.toBlob((b) => resolve(b), mime, quality);
        }).then((blob) => {
          if (!blob) {
            metric("debug_overlay_no_blob", { id });
            return false;
          }
          const replaced = replaceImgWithBlob(img, blob);
          if (replaced) {
            metric("debug_overlay_applied", { id, persons: persons.length });
          }
          return !!replaced;
        });
      } catch (e) {
        metric("debug_overlay_failed", { id, msg: String(e).slice(0, 120) });
        return false;
      }
    }).catch((e) => {
      metric("debug_overlay_rejected", { id, msg: String(e).slice(0, 120) });
      return false;
    });
  }

  function toKeypoints(raw) {
    if (!raw || raw.length === 0) return void 0;
    const kps = [];
    for (const r of raw) {
      if (r && r.length >= 3) {
        kps.push({ x: r[0], y: r[1], confidence: r[2] });
      }
    }
    return kps.length > 0 ? kps : void 0;
  }
  function mapGender(g) {
    if (g === "female") return "F";
    if (g === "male") return "M";
    return void 0;
  }
  function normalisePersons(persons) {
    const out = [];
    for (const p of persons) {
      const kps = toKeypoints(p.keypoints);
      const person = {
        bbox: p.bbox,
        ...p.faceBbox ? { faceBbox: p.faceBbox } : {},
        ...kps ? { keypoints: kps } : {},
        ...typeof p.bodyConfidence === "number" ? { bodyConfidence: p.bodyConfidence } : {},
        ...p.gender ? { gender: mapGender(p.gender) } : {},
        ...typeof p.genderConfidence === "number" ? { genderConfidence: p.genderConfidence } : {},
        ...p.isSyntheticBody ? { isSyntheticBody: true } : {},
        // classifierUsed: the core type is restricted to face/body/unmatched
        // but Swift sends free-form strings ("insightface (partial body)",
        // "pplcnet (synth body)", etc.). We keep the raw string on the
        // normalised payload for debug labels.
        facePFemale: typeof p.facePFemale === "number" ? p.facePFemale : null,
        facePMale: typeof p.facePMale === "number" ? p.facePMale : null,
        bodyPFemale: typeof p.bodyPFemale === "number" ? p.bodyPFemale : null,
        bodyPMale: typeof p.bodyPMale === "number" ? p.bodyPMale : null,
        faceCropDataUrl: typeof p.faceCropDataUrl === "string" ? p.faceCropDataUrl : null,
        bodyCropDataUrl: typeof p.bodyCropDataUrl === "string" ? p.bodyCropDataUrl : null,
        shouldBlur: !!p.shouldBlur
      };
      person.classifierUsedRaw = typeof p.classifierUsed === "string" ? p.classifierUsed : "";
      out.push(person);
    }
    return out;
  }

  const MAX_DIM = 800;
  const ENCODE_TIMEOUT_MS = 5e3;
  function bytesToBase64(bytes) {
    let binary = "";
    const chunk = 32768;
    for (let i = 0; i < bytes.length; i += chunk) {
      binary += String.fromCharCode.apply(
        null,
        Array.from(bytes.subarray(i, i + chunk))
      );
    }
    return btoa(binary);
  }
  function encodeImageViaCanvas(img) {
    try {
      const w = img.naturalWidth || img.width;
      const h = img.naturalHeight || img.height;
      if (!w || !h) return null;
      const scale = Math.min(1, MAX_DIM / Math.max(w, h));
      const cw = Math.max(1, Math.round(w * scale));
      const ch = Math.max(1, Math.round(h * scale));
      const canvas = document.createElement("canvas");
      canvas.width = cw;
      canvas.height = ch;
      const ctx = canvas.getContext("2d");
      if (!ctx) return null;
      ctx.drawImage(img, 0, 0, cw, ch);
      const dataUrl = canvas.toDataURL("image/jpeg", 0.85);
      const commaIdx = dataUrl.indexOf(",");
      if (commaIdx < 0) return null;
      return dataUrl.slice(commaIdx + 1);
    } catch (e) {
      metric("encode_canvas_failed", { msg: String(e).slice(0, 120) });
      return null;
    }
  }
  function encodeImage(img) {
    return new Promise((resolve) => {
      const src = img.currentSrc || img.src;
      if (!src) {
        metric("encode_no_src", { id: img.getAttribute(ID_ATTR) });
        resolve(null);
        return;
      }
      if (/^(data|blob):/.test(src)) {
        resolve(encodeImageViaCanvas(img));
        return;
      }
      let aborted = false;
      const timeout = setTimeout(() => {
        aborted = true;
        metric("encode_fetch_timeout", {
          id: img.getAttribute(ID_ATTR),
          src: src.slice(0, 80)
        });
        resolve(encodeImageViaCanvas(img));
      }, ENCODE_TIMEOUT_MS);
      fetch(src, { mode: "cors", credentials: "omit", cache: "force-cache" }).then((r) => {
        if (!r.ok) throw new Error("http_" + r.status);
        return r.arrayBuffer();
      }).then((buf) => {
        if (aborted) return;
        clearTimeout(timeout);
        imageBytesByImg.set(img, buf);
        resolve(bytesToBase64(new Uint8Array(buf)));
      }).catch((e) => {
        if (aborted) return;
        clearTimeout(timeout);
        metric("encode_fetch_failed", {
          id: img.getAttribute(ID_ATTR),
          src: src.slice(0, 80),
          err: String(e).slice(0, 120)
        });
        resolve(encodeImageViaCanvas(img));
      });
    });
  }

  const MIN_DIM = 64;
  function imgUrl$1(img) {
    return img.currentSrc || img.src || "";
  }
  class AnalyzeQueue {
    constructor(deps) {
      this.deps = deps;
      this.jobs = [];
      this.analyzing = false;
    }
    /**
     * Try to enqueue the image. Returns false if skipped (no ID, too small, cache
     * hit, already analyzed). Cache hits short-circuit and set STATE_ATTR
     * synchronously — no Swift roundtrip.
     */
    enqueue(img, id) {
      if (!img || img.tagName !== "IMG") return false;
      const state = img.getAttribute(STATE_ATTR);
      if (state === "keep" || state === "remove" || state === "analyzing") {
        return false;
      }
      const w = img.naturalWidth || img.width;
      const h = img.naturalHeight || img.height;
      if (w < MIN_DIM || h < MIN_DIM) return false;
      if (!img.complete || w === 0 || h === 0) {
        img.addEventListener(
          "load",
          () => {
            this.enqueue(img, id);
          },
          { once: true }
        );
        return false;
      }
      const url = imgUrl$1(img);
      const cached = this.deps.decisionCache.get(url);
      if (cached) {
        img.setAttribute(STATE_ATTR, cached);
        if (cached === "remove") releaseHideFirst(img);
        metric("analyze_cache_hit", { id, decision: cached });
        return false;
      }
      img.setAttribute(STATE_ATTR, "pending");
      this.jobs.push({ id, img, url });
      this.drain();
      return true;
    }
    /**
     * Called by the reply handler once Swift has answered (success or error).
     * Releases the in-flight slot and tries to pick the next job.
     */
    releaseSlot() {
      this.analyzing = false;
      this.drain();
    }
    drain() {
      if (this.analyzing) return;
      const job = this.jobs.shift();
      if (!job) return;
      this.analyzing = true;
      job.img.setAttribute(STATE_ATTR, "analyzing");
      encodeImage(job.img).then((b64) => {
        if (!b64) {
          job.img.setAttribute(STATE_ATTR, "keep");
          this.releaseSlot();
          return;
        }
        metric("analyze_send", {
          id: job.id,
          w: job.img.naturalWidth,
          h: job.img.naturalHeight,
          bytes: b64.length
        });
        send("analyzeImage", `${job.id}|${b64}`);
      }).catch((e) => {
        metric("encode_unexpected_error", { msg: String(e).slice(0, 120) });
        job.img.setAttribute(STATE_ATTR, "keep");
        this.releaseSlot();
      });
    }
  }
  function findImageById(id) {
    return document.querySelector(
      `[${ID_ATTR}="${id}"]`
    );
  }

  function imgUrl(img) {
    return img.currentSrc || img.src || "";
  }
  function parsePersons(raw) {
    if (!raw) return [];
    if (Array.isArray(raw)) return raw;
    if (typeof raw === "string") {
      if (raw === "" || raw === "null") return [];
      try {
        const parsed = JSON.parse(raw);
        if (Array.isArray(parsed)) return parsed;
        return [];
      } catch (e) {
        metric("apply_parse_error", { msg: String(e).slice(0, 120) });
        return [];
      }
    }
    return [];
  }
  function installReplyHandlers(deps) {
    window.__basarunaaApply = function basarunaaApply(id, decision, persons, debugMode, elapsedMs) {
      try {
        const img = findImageById(id);
        const rawPersons = parsePersons(persons);
        const personCount = rawPersons.length;
        const dec = decision;
        const dbgMode = debugMode ?? "none";
        const isDebug = dbgMode === "boxes" || dbgMode === "debug";
        metric("analyze_decision", {
          id,
          decision: String(dec),
          persons: personCount,
          found: !!img,
          debug: String(dbgMode),
          elapsed_ms: typeof elapsedMs === "number" ? Math.round(elapsedMs) : void 0
        });
        if (img) {
          img.setAttribute(STATE_ATTR, dec === "blur" ? "remove" : "keep");
          if (isDebug) {
            releaseHideFirst(img);
            if (personCount > 0) {
              const normalised = normalisePersons(rawPersons);
              void compositeDebugOverlay(img, normalised, dbgMode, elapsedMs);
            }
          } else if (dec === "keep") {
            releaseHideFirst(img);
            deps.decisionCache.set(imgUrl(img), "remove");
          } else if (dec === "blur" && personCount > 0) {
            const normalised = normalisePersons(rawPersons);
            void compositePerPersonBlur(img, normalised);
            deps.decisionCache.set(imgUrl(img), "keep");
          } else if (dec === "nsfw") {
            img.style.setProperty(
              "filter",
              `blur(${DEFAULT_HIDE_FIRST_BLUR_PX}px)`,
              "important"
            );
            img.setAttribute(BLUR_MARKER, "1");
            deps.decisionCache.set(imgUrl(img), "keep");
          } else {
            deps.decisionCache.set(imgUrl(img), "keep");
          }
        }
      } catch (e) {
        metric("apply_error", { msg: String(e).slice(0, 120) });
      } finally {
        deps.queue.releaseSlot();
      }
    };
    window.__basarunaaApplyNsfw = function basarunaaApplyNsfw(id, score) {
      try {
        const img = findImageById(id);
        metric("apply_nsfw", { id, score, found: !!img });
        if (img) {
          img.style.setProperty(
            "filter",
            `blur(${DEFAULT_HIDE_FIRST_BLUR_PX}px)`,
            "important"
          );
          img.setAttribute(BLUR_MARKER, "1");
          img.setAttribute(STATE_ATTR, "keep");
          deps.decisionCache.set(imgUrl(img), "keep");
        }
      } catch (e) {
        metric("apply_nsfw_error", { msg: String(e).slice(0, 120) });
      }
    };
  }

  const DECISION_CACHE_MAX = 500;
  function createImagePipeline() {
    const decisionCache = new DecisionCache(DECISION_CACHE_MAX);
    const queue = new AnalyzeQueue({ decisionCache });
    let discoveredCount = 0;
    const observer = createImageIntersectionObserver({
      onVisible(img) {
        observer?.unobserve(img);
        const idAttr = img.getAttribute("data-basarunaa-id");
        if (idAttr) queue.enqueue(img, Number(idAttr));
      }
    });
    setIntersectionObserver(observer);
    installReplyHandlers({ decisionCache, queue });
    const scanner = new DomScanner(
      {
        onImageDiscovered(img) {
          discoveredCount++;
          applyHideFirst(img);
          if (observer) {
            observer.observe(img);
          } else {
            const idAttr = img.getAttribute("data-basarunaa-id");
            if (idAttr) queue.enqueue(img, Number(idAttr));
          }
        },
        onImageRemoved(img) {
          unobserveImage(img);
        }
      },
      { minSize: 64 }
    );
    function onPageHide() {
      metric("page_hide", { url: location.href });
      send("pageReset", location.href);
    }
    window.addEventListener("pagehide", onPageHide);
    window.addEventListener("beforeunload", onPageHide);
    return {
      scanner,
      queue,
      observer,
      decisionCache,
      imagesDiscovered: () => discoveredCount,
      stop() {
        scanner.stop();
        observer?.disconnect();
        setIntersectionObserver(null);
      }
    };
  }

  const SENTINEL_MIN_INTERVAL_MS = 100;
  const YOLO_INTERVAL_TRACKING_MS = 1e3;
  const YOLO_INTERVAL_SAFE_MS = 5e3;
  const YOLO_IOU_MATCH_THRESHOLD = 0.3;
  const MIN_VIDEO_SIZE = 120;
  const CANVAS_CLASS = "basarunaa-video-overlay";
  const VIDEO_ID_OFFSET = 1e6;
  let nextFrameId = 1;
  let nextYoloFrameId = VIDEO_ID_OFFSET;
  const pendingByFrameId = /* @__PURE__ */ new Map();
  const pendingYoloByFrameId = /* @__PURE__ */ new Map();
  let mutationObserver = null;
  const trackers = /* @__PURE__ */ new WeakMap();
  const allTrackers = /* @__PURE__ */ new Set();
  let started$1 = false;
  function logInfo$1(msg) {
    send("log", `[basarunaa-android/video] ${msg}`);
  }
  function isVideoCandidate(el) {
    if (el.tagName !== "VIDEO") return false;
    const v = el;
    const w = v.videoWidth || v.clientWidth;
    const h = v.videoHeight || v.clientHeight;
    if (w && h && (w < MIN_VIDEO_SIZE || h < MIN_VIDEO_SIZE)) return false;
    return true;
  }
  function attachCanvas(video) {
    const canvas = document.createElement("canvas");
    canvas.className = CANVAS_CLASS;
    canvas.style.position = "absolute";
    canvas.style.pointerEvents = "none";
    canvas.style.zIndex = "2147483646";
    canvas.style.display = "none";
    document.body.appendChild(canvas);
    return canvas;
  }
  function syncCanvasToVideo(t) {
    const r = t.video.getBoundingClientRect();
    const scrollX = window.scrollX || window.pageXOffset || 0;
    const scrollY = window.scrollY || window.pageYOffset || 0;
    t.canvas.style.left = `${r.left + scrollX}px`;
    t.canvas.style.top = `${r.top + scrollY}px`;
    t.canvas.style.width = `${r.width}px`;
    t.canvas.style.height = `${r.height}px`;
    const vw = t.video.videoWidth || Math.round(r.width);
    const vh = t.video.videoHeight || Math.round(r.height);
    if (t.canvas.width !== vw) t.canvas.width = vw;
    if (t.canvas.height !== vh) t.canvas.height = vh;
  }
  function applyState(t) {
    const cfg = getConfig();
    const isDebug = cfg?.debugMode === "debug" || cfg?.debugMode === "boxes";
    if (t.state === "safe") {
      t.canvas.style.display = isDebug ? "" : "none";
      t.video.style.removeProperty("filter");
      return;
    }
    if (t.state === "full_blur") {
      const vw = t.video.videoWidth || t.video.clientWidth || 720;
      const r = Math.max(20, Math.min(60, Math.round(vw / 36)));
      t.video.style.setProperty(
        "filter",
        `blur(${r}px) grayscale(1)`,
        "important"
      );
      t.canvas.style.display = isDebug ? "" : "none";
      return;
    }
    t.video.style.removeProperty("filter");
    t.canvas.style.display = "";
    renderTracking(t, isDebug);
  }
  function iou(a, b) {
    const x1 = Math.max(a[0], b[0]);
    const y1 = Math.max(a[1], b[1]);
    const x2 = Math.min(a[2], b[2]);
    const y2 = Math.min(a[3], b[3]);
    if (x2 <= x1 || y2 <= y1) return 0;
    const inter = (x2 - x1) * (y2 - y1);
    const aArea = (a[2] - a[0]) * (a[3] - a[1]);
    const bArea = (b[2] - b[0]) * (b[3] - b[1]);
    return inter / (aArea + bArea - inter);
  }
  function inferGender(bbox, yoloPersons) {
    let bestIoU = YOLO_IOU_MATCH_THRESHOLD;
    let best = null;
    for (const p of yoloPersons) {
      const o = iou(bbox, p.bbox);
      if (o > bestIoU) {
        bestIoU = o;
        best = p;
      }
    }
    return best?.gender ?? null;
  }
  function shouldBlur(gender, mode) {
    if (mode === "blur-all") return true;
    if (gender == null) return true;
    if (mode === "blur-female") return gender === "female";
    if (mode === "blur-male") return gender === "male";
    return false;
  }
  function renderTracking(t, isDebug) {
    const ctx = t.ctx;
    if (!ctx) return;
    ctx.clearRect(0, 0, t.canvas.width, t.canvas.height);
    const cfg = getConfig();
    const mode = cfg?.mode || "blur-female";
    for (const b of t.lastBboxes) {
      const [x1, y1, x2, y2] = b;
      const w = x2 - x1;
      const h = y2 - y1;
      if (w <= 0 || h <= 0) continue;
      const gender = inferGender(b, t.lastYoloPersons);
      const blur = shouldBlur(gender, mode);
      const r = Math.max(12, Math.min(40, Math.round(Math.min(w, h) / 4)));
      if (blur) {
        ctx.save();
        ctx.filter = `blur(${r}px)`;
        try {
          ctx.drawImage(t.video, x1, y1, w, h, x1, y1, w, h);
        } catch {
        }
        ctx.restore();
      }
      if (isDebug) {
        const color = blur ? "rgba(255, 0, 0, 0.7)" : "rgba(0, 255, 0, 0.7)";
        ctx.strokeStyle = color;
        ctx.lineWidth = 2;
        ctx.strokeRect(x1, y1, w, h);
        if (gender) {
          ctx.fillStyle = color;
          ctx.font = "14px sans-serif";
          ctx.fillText(gender, x1 + 4, y1 + 16);
        }
      }
    }
  }
  function captureFrameJpeg(t) {
    const w = t.video.videoWidth;
    const h = t.video.videoHeight;
    if (!w || !h) return null;
    const cap = document.createElement("canvas");
    cap.width = w;
    cap.height = h;
    const c = cap.getContext("2d");
    if (!c) return null;
    try {
      c.drawImage(t.video, 0, 0, w, h);
    } catch {
      return null;
    }
    try {
      return cap.toDataURL("image/jpeg", 0.7);
    } catch {
      return null;
    }
  }
  function tickFrame(t) {
    if (t.destroyed) return;
    syncCanvasToVideo(t);
    applyState(t);
    const now = performance.now();
    const videoReady = t.video.readyState >= 2 && !t.video.paused;
    if (!videoReady) {
      scheduleNextTick(t);
      return;
    }
    const yoloInterval = t.state === "safe" ? YOLO_INTERVAL_SAFE_MS : YOLO_INTERVAL_TRACKING_MS;
    const wantsYolo = !t.yoloPending && now - t.lastYoloSentAt >= yoloInterval;
    const wantsSentinel = !t.sentinelPending && now - t.lastSentinelSentAt >= SENTINEL_MIN_INTERVAL_MS;
    if (wantsYolo || wantsSentinel) {
      const dataUrl = captureFrameJpeg(t);
      if (dataUrl) {
        const base64 = dataUrl.substring(dataUrl.indexOf(",") + 1);
        if (wantsYolo) {
          const yoloFrameId = nextYoloFrameId++;
          pendingYoloByFrameId.set(yoloFrameId, t);
          t.yoloPending = true;
          t.lastYoloSentAt = now;
          send("analyzeImage", `${yoloFrameId}|${base64}`);
        } else if (wantsSentinel) {
          const frameId = nextFrameId++;
          pendingByFrameId.set(frameId, t);
          t.sentinelPending = true;
          t.lastSentinelSentAt = now;
          send("sentinelFrame", `${frameId}|${base64}`);
        }
      }
    }
    scheduleNextTick(t);
  }
  function scheduleNextTick(t) {
    const vEl = t.video;
    if (typeof vEl.requestVideoFrameCallback === "function") {
      t.rvfcHandle = vEl.requestVideoFrameCallback(() => tickFrame(t));
    } else {
      t.rvfcHandle = requestAnimationFrame(() => tickFrame(t));
    }
  }
  function startTracker(video) {
    if (trackers.has(video)) return;
    if (!isVideoCandidate(video)) return;
    const canvas = attachCanvas();
    const ctx = canvas.getContext("2d");
    const t = {
      video,
      canvas,
      ctx,
      state: "full_blur",
      lastBboxes: [],
      lastYoloPersons: [],
      lastSentinelSentAt: 0,
      lastYoloSentAt: 0,
      sentinelPending: false,
      yoloPending: false,
      rvfcHandle: null,
      destroyed: false
    };
    trackers.set(video, t);
    allTrackers.add(t);
    logInfo$1(`startTracker ${video.videoWidth || "?"}x${video.videoHeight || "?"}`);
    applyState(t);
    scheduleNextTick(t);
  }
  function destroyTracker(t) {
    if (t.destroyed) return;
    t.destroyed = true;
    try {
      t.video.style.removeProperty("filter");
    } catch {
    }
    try {
      t.canvas.remove();
    } catch {
    }
    allTrackers.delete(t);
    trackers.delete(t.video);
  }
  function scanInitial(root) {
    root.querySelectorAll("video").forEach((v) => startTracker(v));
  }
  function onMutations(muts) {
    for (const m of muts) {
      m.addedNodes.forEach((n) => {
        if (n.nodeType !== 1) return;
        const el = n;
        if (el.tagName === "VIDEO") {
          startTracker(el);
        } else {
          el.querySelectorAll?.("video").forEach(
            (v) => startTracker(v)
          );
        }
      });
      m.removedNodes.forEach((n) => {
        if (n.nodeType !== 1) return;
        const el = n;
        if (el.tagName === "VIDEO") {
          const t = trackers.get(el);
          if (t) destroyTracker(t);
        } else {
          el.querySelectorAll?.("video").forEach((v) => {
            const t = trackers.get(v);
            if (t) destroyTracker(t);
          });
        }
      });
    }
  }
  function parseYoloPersons(persons) {
    let arr;
    if (typeof persons === "string") {
      try {
        arr = JSON.parse(persons);
      } catch {
        return [];
      }
    } else {
      arr = persons;
    }
    if (!Array.isArray(arr)) return [];
    const out = [];
    for (const p of arr) {
      if (!p || typeof p !== "object") continue;
      const obj = p;
      const bbox = obj.bbox;
      if (!Array.isArray(bbox) || bbox.length !== 4) continue;
      if (bbox.some((v) => typeof v !== "number")) continue;
      const g = obj.gender;
      const gender = g === "male" || g === "female" ? g : null;
      const gc = obj.genderConfidence;
      const genderConfidence = typeof gc === "number" ? gc : null;
      out.push({
        bbox,
        gender,
        genderConfidence
      });
    }
    return out;
  }
  function installApplyHandler() {
    const w = window;
    w.__basarunaaApplyVideoSentinel = (frameId, bboxes) => {
      const t = pendingByFrameId.get(frameId);
      pendingByFrameId.delete(frameId);
      if (!t || t.destroyed) return;
      t.sentinelPending = false;
      t.lastBboxes = Array.isArray(bboxes) ? bboxes : [];
      if (t.lastBboxes.length === 0 && t.lastYoloPersons.length === 0) {
        t.state = "safe";
      } else if (t.lastBboxes.length > 0) {
        t.state = "tracking";
      }
      applyState(t);
    };
    const prevApply = window.__basarunaaApply;
    window.__basarunaaApply = function basarunaaApplyRouter(id, decision, persons, debugMode, elapsedMs) {
      if (id >= VIDEO_ID_OFFSET) {
        const t = pendingYoloByFrameId.get(id);
        pendingYoloByFrameId.delete(id);
        if (!t || t.destroyed) return;
        t.yoloPending = false;
        if (decision === "nsfw") {
          const w0 = t.video.videoWidth || 1;
          const h0 = t.video.videoHeight || 1;
          t.lastBboxes = [[0, 0, w0, h0]];
          t.lastYoloPersons = [
            { bbox: [0, 0, w0, h0], gender: null, genderConfidence: null }
          ];
          t.state = "tracking";
        } else {
          t.lastYoloPersons = parseYoloPersons(persons);
          if (t.lastBboxes.length === 0 && t.lastYoloPersons.length > 0) {
            t.lastBboxes = t.lastYoloPersons.map((p) => p.bbox);
          }
          if (t.lastBboxes.length === 0 && t.lastYoloPersons.length === 0) {
            t.state = "safe";
          } else {
            t.state = "tracking";
          }
        }
        applyState(t);
        return;
      }
      if (prevApply) {
        prevApply(id, decision, persons, debugMode, elapsedMs);
      }
    };
  }
  function createVideoPipeline() {
    if (started$1) {
      return { stop: stopVideoPipeline };
    }
    started$1 = true;
    installApplyHandler();
    scanInitial(document);
    mutationObserver = new MutationObserver(onMutations);
    mutationObserver.observe(document.documentElement, {
      childList: true,
      subtree: true
    });
    logInfo$1("video pipeline started");
    return { stop: stopVideoPipeline };
  }
  function stopVideoPipeline() {
    if (!started$1) return;
    started$1 = false;
    mutationObserver?.disconnect();
    mutationObserver = null;
    for (const t of Array.from(allTrackers)) destroyTracker(t);
    pendingByFrameId.clear();
    pendingYoloByFrameId.clear();
    try {
      delete window.__basarunaaApplyVideoSentinel;
    } catch {
    }
  }

  let pipeline = null;
  let videoPipeline = null;
  let started = false;
  function logInfo(msg) {
    send("log", `[basarunaa-android] ${msg}`);
  }
  function teardown() {
    if (pipeline) {
      pipeline.stop();
      pipeline = null;
    }
    if (videoPipeline) {
      videoPipeline.stop();
      videoPipeline = null;
    }
  }
  function start() {
    if (started) return;
    started = true;
    const config = getConfig();
    if (!config) return;
    if (!config.enabled || !isEnabled()) {
      logInfo("pref OFF at bootstrap, skipping");
      return;
    }
    pipeline = createImagePipeline();
    pipeline.scanner.start();
    videoPipeline = createVideoPipeline();
    window.__browtherBasarunaaAndroid = {
      phase: 2,
      config,
      pipeline,
      get imagesDiscovered() {
        return pipeline?.imagesDiscovered() ?? 0;
      },
      get cacheSize() {
        return pipeline?.decisionCache.size ?? 0;
      },
      initializedAt: typeof performance !== "undefined" && performance.now ? performance.now() : Date.now()
    };
    const initialCount = pipeline.imagesDiscovered();
    logInfo(
      `init mode=${config.mode} debug=${config.debugMode} initial_imgs=${initialCount}`
    );
    send("pageReset", location.href);
    metric("script_init", {
      url: location.href,
      initial_imgs: initialCount,
      jalon: "2G.step3"
    });
  }
  function attachLifecycleListeners() {
    window.addEventListener(
      "basarunaa-disable",
      () => {
        logInfo("received basarunaa-disable, teardown");
        teardown();
      },
      false
    );
    window.addEventListener(
      "basarunaa-config-changed",
      () => {
        const cfg = getConfig();
        if (!cfg) return;
        logInfo(`config-changed mode=${cfg.mode} debug=${cfg.debugMode}`);
      },
      false
    );
  }
  (function bootstrap() {
    if (typeof window === "undefined") return;
    const w = window;
    if (w.__basarunaa_initialized) return;
    w.__basarunaa_initialized = true;
    attachLifecycleListeners();
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", start, { once: true });
    } else {
      start();
    }
  })();

})();
