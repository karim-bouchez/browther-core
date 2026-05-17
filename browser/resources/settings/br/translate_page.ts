/* Copyright (c) 2026 dev&din. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

import {
  RegisterPolymerTemplateModifications
} from 'chrome://resources/brave/polymer_overriding.js'

// Browther: cache la section "Brave Translate" dans chrome://settings/languages.
// La pref kOfferTranslateEnabled est déjà à false par défaut côté C++
// (cf. brave_profile_prefs.cc), mais la section avec le toggle "Use Brave
// Translate" restait visible. Browther n'utilise pas Brave Translate.
//
// On set un style="display:none" inline sur le `<settings-translate-page>` sans
// le retirer du DOM (sinon le parent appelle switchViews(['languages',
// 'spellCheck', 'translate']) qui plante car la view doit exister).
//
// Note : on n'utilise pas RegisterStyleOverride qui ne semble pas s'appliquer
// correctement à ce composant (peut-être lazy-load mismatch — testé avec
// `:host` et avec `#translate` sur le parent, sans succès).
RegisterPolymerTemplateModifications({
  'settings-languages-page-index': (templateContent) => {
    const translatePage = templateContent.querySelector('settings-translate-page')
    if (translatePage) {
      const existingStyle = translatePage.getAttribute('style') ?? ''
      translatePage.setAttribute('style',
        `${existingStyle}; display: none !important;`)
    }
  }
})
