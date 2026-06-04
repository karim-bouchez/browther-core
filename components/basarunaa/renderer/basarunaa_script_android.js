// Copyright (c) 2026 The Browther Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Browther Basarunaa Android — script main world STUB (Jalon 2.F).
//
// Ce fichier est un STUB destiné à valider la chaîne complète V8 binding +
// Mojo + Apply round-trip côté JS. Le port complet du userscript Basarunaa
// (intercepteur DOM <img>/<video>, hide-first, decision cache, compositing
// polygon mask, debug overlay) sera fait au Jalon 2.G en réutilisant le
// bundle TS partagé `private/extensions/basarunaa/src/core/` (cf. CLAUDE.md).
//
// Objectifs du STUB :
//   1. Définir `window.__basarunaaApply(...)` et `window.__basarunaaApplyNsfw(...)`
//      pour que les Apply Mojo arrivent bien au JS (loggué dans console).
//   2. Écouter `basarunaa-disable` et logger l'état.
//   3. Écouter `basarunaa-config-changed` et re-fetcher `getConfig()`.
//   4. Émettre 1 PageReset au load pour valider le rétro-chemin renderer→browser.
//   5. Logger la config courante à l'init pour validation du push browser→renderer.
(function () {
  'use strict';

  if (typeof window.__basarunaa === 'undefined') {
    // V8 binding pas installé : RFO a skip (frame iframe / about:blank /
    // window object intermédiaire). Abort silencieux.
    return;
  }

  if (window.__basarunaa_initialized) {
    return;
  }
  window.__basarunaa_initialized = true;

  var binding = window.__basarunaa;

  function logInfo(msg) {
    try {
      binding.send('log', '[basarunaa-stub] ' + msg);
    } catch (e) {}
  }

  // 1. Snapshot config initial.
  var config = null;
  try {
    config = binding.getConfig();
  } catch (e) {
    logInfo('getConfig threw: ' + e);
  }
  logInfo('script loaded, config=' + JSON.stringify(config));

  // 2. Apply callbacks (Mojo browser → renderer → ce JS).
  window.__basarunaaApply = function (imageId, decision, persons, debugMode, elapsedMs) {
    logInfo('Apply imageId=' + imageId + ' decision=' + decision +
            ' persons=' + (persons ? persons.length : 'null') +
            ' debugMode=' + debugMode + ' elapsedMs=' + elapsedMs);
  };
  window.__basarunaaApplyNsfw = function (imageId, score) {
    logInfo('ApplyNsfw imageId=' + imageId + ' score=' + score);
  };

  // 3. Disable event (browser → renderer pref ON → OFF live).
  window.addEventListener('basarunaa-disable', function () {
    logInfo('received basarunaa-disable, releasing hide-first (stub)');
  }, false);

  // 4. Config changed (sliders / mode toggle live sans flip enabled).
  window.addEventListener('basarunaa-config-changed', function () {
    try {
      config = binding.getConfig();
      logInfo('config-changed, new config=' + JSON.stringify(config));
    } catch (e) {}
  }, false);

  // 5. PageReset ping pour valider le sens renderer → browser.
  try {
    binding.send('pageReset', location.href);
  } catch (e) {}

  logInfo('init complete');
})();
