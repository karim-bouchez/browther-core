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
  var MARKER_ATTR = 'data-basarunaa-blurred';

  // ─── Blur application ───
  function applyBlurTo(img) {
    if (!img || img.nodeType !== 1 || img.tagName !== 'IMG') return false;
    if (img.hasAttribute(MARKER_ATTR)) return false;
    try {
      // Merge with any existing filter the page may have set.
      var existing = img.style.filter || '';
      var blur = 'blur(' + BLUR_RADIUS_PX + 'px)';
      img.style.filter = existing.indexOf('blur(') === -1
        ? (existing ? existing + ' ' + blur : blur)
        : existing;
      img.setAttribute(MARKER_ATTR, '1');
      return true;
    } catch (e) {
      return false;
    }
  }

  function scanAndBlur(root) {
    var imgs = (root || document).querySelectorAll('img');
    var n = 0;
    for (var i = 0; i < imgs.length; i++) {
      if (applyBlurTo(imgs[i])) n++;
    }
    return n;
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

    // Observe new <img> nodes + src changes.
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
              } else if (node.querySelectorAll) {
                n += scanAndBlur(node);
              }
            }
          } else if (mut.type === 'attributes' && mut.attributeName === 'src' && mut.target) {
            // src changed: page may swap an image's content — re-blur to be safe.
            mut.target.removeAttribute(MARKER_ATTR);
            if (applyBlurTo(mut.target)) n++;
          }
        }
        if (n > 0) metric('mutation_blur', { added: n });
      });
      observer.observe(document.documentElement || document.body, {
        childList: true,
        subtree: true,
        attributes: true,
        attributeFilter: ['src']
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
