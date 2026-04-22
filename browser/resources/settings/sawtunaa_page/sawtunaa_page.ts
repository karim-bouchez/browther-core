/* Copyright (c) 2026 dev&din. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

import {PrefsMixin} from '/shared/settings/prefs/prefs_mixin.js'
import {PolymerElement} from 'chrome://resources/polymer/v3_0/polymer/polymer_bundled.min.js'
import {getTemplate} from './sawtunaa_page.html.js'

const SettingsSawtunaaPageElementBase = PrefsMixin(PolymerElement)

/**
 * 'settings-sawtunaa-page' is the settings page for Sawtunaa
 * (real-time music/noise removal).
 */
class SettingsSawtunaaPageElement extends SettingsSawtunaaPageElementBase {
  static get is() {
    return 'settings-sawtunaa-page'
  }

  static get template() {
    return getTemplate()
  }
}

customElements.define(
  SettingsSawtunaaPageElement.is,
  SettingsSawtunaaPageElement
)
