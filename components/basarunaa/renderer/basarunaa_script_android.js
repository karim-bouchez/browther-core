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

  let started = false;
  function logInfo(msg) {
    send("log", `[basarunaa-android] ${msg}`);
  }
  const applyHandler = (imageId, decision, persons, debugMode, elapsedMs) => {
    const personCount = Array.isArray(persons) ? persons.length : 0;
    logInfo(
      `Apply id=${imageId} decision=${decision} persons=${personCount} debug=${debugMode} elapsed=${elapsedMs}ms`
    );
  };
  const applyNsfwHandler = (imageId, score) => {
    logInfo(`ApplyNsfw id=${imageId} score=${score.toFixed(3)}`);
  };
  function start() {
    if (started) return;
    started = true;
    const config = getConfig();
    if (!config) {
      return;
    }
    if (!config.enabled || !isEnabled()) {
      logInfo("pref OFF at bootstrap, skipping");
      return;
    }
    window.__basarunaaApply = applyHandler;
    window.__basarunaaApplyNsfw = applyNsfwHandler;
    window.__browtherBasarunaa = {
      phase: 2,
      config,
      initializedAt: typeof performance !== "undefined" && performance.now ? performance.now() : Date.now()
    };
    logInfo(
      `init mode=${config.mode} confBody=${config.confBody} confFace=${config.confFace} genderCertainty=${config.genderCertainty} debug=${config.debugMode}`
    );
    send("pageReset", location.href);
    metric("script_init", { url: location.href, jalon: "2G.step1" });
  }
  function attachDisableListener() {
    window.addEventListener(
      "basarunaa-disable",
      () => {
        logInfo("received basarunaa-disable, releasing (stub)");
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
    attachDisableListener();
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", start, { once: true });
    } else {
      start();
    }
  })();

})();
