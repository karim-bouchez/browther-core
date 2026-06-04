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
  function setImageState(el, state) {
    el.setAttribute(STATE_ATTR, state);
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

  const pending = /* @__PURE__ */ new Map();
  let scanner = null;
  let started = false;
  let imagesDiscovered = 0;
  let imagesAnalyzed = 0;
  let imagesKept = 0;
  let imagesBlurred = 0;
  function logInfo(msg) {
    send("log", `[basarunaa-android] ${msg}`);
  }
  function setState(img, state) {
    setImageState(img, state);
  }
  function onImageDiscovered(img, id) {
    imagesDiscovered++;
    applyHideFirst(img);
    setImageState(img, "analyzing");
    pending.set(id, img);
    send("analyzeImage", `${id}|`);
    imagesAnalyzed++;
  }
  function onImageRemoved(_img, id) {
    if (pending.delete(id)) {
      send("cancelAnalyze", String(id));
    }
  }
  const applyHandler = (imageId, decision, persons, debugMode, elapsedMs) => {
    const img = pending.get(imageId);
    if (!img) {
      logInfo(`Apply id=${imageId} dropped (img gone, decision=${decision})`);
      return;
    }
    pending.delete(imageId);
    const personCount = Array.isArray(persons) ? persons.length : 0;
    logInfo(
      `Apply id=${imageId} decision=${decision} persons=${personCount} debug=${debugMode} elapsed=${elapsedMs}ms`
    );
    if (decision === "keep") {
      releaseHideFirst(img);
      setState(img, "keep");
      imagesKept++;
    } else if (decision === "blur") {
      setState(img, "remove");
      imagesBlurred++;
    } else {
      setState(img, "remove");
    }
  };
  const applyNsfwHandler = (imageId, score) => {
    const img = pending.get(imageId);
    pending.delete(imageId);
    logInfo(`ApplyNsfw id=${imageId} score=${score.toFixed(3)}`);
    if (img) {
      setState(img, "remove");
      imagesBlurred++;
    }
  };
  function teardown() {
    if (scanner) {
      scanner.stop();
      scanner = null;
    }
    for (const img of pending.values()) {
      releaseHideFirst(img);
      img.removeAttribute(ID_ATTR);
    }
    pending.clear();
    imagesDiscovered = 0;
    imagesAnalyzed = 0;
    imagesKept = 0;
    imagesBlurred = 0;
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
    window.__basarunaaApply = applyHandler;
    window.__basarunaaApplyNsfw = applyNsfwHandler;
    scanner = new DomScanner({ onImageDiscovered, onImageRemoved });
    scanner.start();
    window.__browtherBasarunaaAndroid = {
      phase: 2,
      config,
      scanner,
      get imagesDiscovered() {
        return imagesDiscovered;
      },
      get imagesAnalyzed() {
        return imagesAnalyzed;
      },
      get imagesKept() {
        return imagesKept;
      },
      get imagesBlurred() {
        return imagesBlurred;
      },
      initializedAt: typeof performance !== "undefined" && performance.now ? performance.now() : Date.now()
    };
    logInfo(
      `init mode=${config.mode} debug=${config.debugMode} initial_imgs=${imagesDiscovered}`
    );
    send("pageReset", location.href);
    metric("script_init", {
      url: location.href,
      initial_imgs: imagesDiscovered,
      jalon: "2G.step2"
    });
  }
  function attachLifecycleListeners() {
    window.addEventListener(
      "basarunaa-disable",
      () => {
        logInfo(`received basarunaa-disable, teardown (${pending.size} pending)`);
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
