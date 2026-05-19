/* Copyright (c) 2020 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.language.settings;

import android.os.Bundle;

import androidx.preference.PreferenceCategory;

public class BraveLanguageSettings extends LanguageSettings {
    static final String TRANSLATION_SETTINGS_SECTION = "translation_settings_section";

    @Override
    public void onCreatePreferences(Bundle savedInstanceState, String rootKey) {
        super.onCreatePreferences(savedInstanceState, rootKey);

        // Browther: Translate retiré entièrement (aligné sur macOS). On supprime
        // la section translation_settings_section ET on n'ajoute pas le toggle
        // "Use Brave Translate" (qui était précédemment ajouté à appLanguageSection).
        // Translate désactivé via pref `kOfferTranslateEnabled=false` côté C++
        // (browser/brave_profile_prefs.cc). UseGoogleTranslateEndpoint() reste true
        // mais sans entrypoint UI le service est inutilisé.
        PreferenceCategory translateSwitch =
                (PreferenceCategory) findPreference(TRANSLATION_SETTINGS_SECTION);
        if (translateSwitch != null) {
            getPreferenceScreen().removePreference(translateSwitch);
        }
    }
}
