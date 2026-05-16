/* Copyright (c) 2026 dev&din. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

import {html, RegisterStyleOverride} from 'chrome://resources/brave/polymer_overriding.js'

// Browther: cache le toggle "Use Translate" / "Offer translation for languages
// you don't read" dans chrome://settings/languages. La pref kOfferTranslateEnabled
// est déjà à false par défaut côté C++ (cf. brave_profile_prefs.cc), mais le
// toggle restait visible pour réactiver. Browther utilise pas Brave Translate.
RegisterStyleOverride(
  'settings-translate-page',
  html`
    <style>
      #offerTranslateOtherLanguages {
        display: none !important;
      }
    </style>
  ` as HTMLTemplateElement
)
