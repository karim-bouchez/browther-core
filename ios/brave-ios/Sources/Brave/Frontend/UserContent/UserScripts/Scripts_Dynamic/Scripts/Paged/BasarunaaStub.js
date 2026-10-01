// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// Basarunaa — amorce TOUJOURS injectée, dans tous les frames (2026-10-01).
//
// Pour allumer/éteindre Basarunaa sans recharger la page. Contrairement à
// Sawtunaa, le script complet (212 Ko) n'a pas besoin d'être là dès le
// chargement : éteint, seule cette amorce est injectée (quelques lignes, aucun
// observateur), et le natif charge le script complet dans le frame à
// l'allumage. Elle ne décide de rien : `syncState` demande au natif l'état réel,
// et c'est le natif qui allume, éteint, ou injecte — une page qui appellerait
// `__browtherBasarunaaSync` ne fait que reposer la question.
//
// Le natif ne sait viser que le frame principal par `evaluateJavaScript` : le
// frame principal relaie donc la question à ses iframes (postMessage), qui la
// relaient aux leurs. Chaque frame interroge le natif depuis LUI-MÊME, et la
// réponse lui revient (`message.frameInfo`).
window.__firefox__.includeOnce("BasarunaaStub", function($) {
  'use strict';

  function send(action, data) {
    try {
      $.postNativeMessage('$<message_handler>', {
        securityToken: SECURITY_TOKEN,
        action: action,
        data: data || ''
      });
    } catch (e) {}
  }

  function relay() {
    var frames = window.frames;
    for (var i = 0; i < frames.length; i++) {
      try { frames[i].postMessage({ __browtherBasarunaaSync: 1 }, '*'); } catch (e) {}
    }
  }

  function sync() {
    send('syncState', location.href);
    relay();
  }

  window.addEventListener('message', function(e) {
    if (e && e.data && e.data.__browtherBasarunaaSync === 1
        && window.parent !== window && e.source === window.parent) {
      sync();
    }
  });

  try {
    Object.defineProperty(window, '__browtherBasarunaaSync', {
      value: sync, configurable: false, writable: false
    });
  } catch (e) {}
});
