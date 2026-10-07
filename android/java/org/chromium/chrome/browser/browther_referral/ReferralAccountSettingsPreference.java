/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_referral;

import android.content.Context;
import android.graphics.drawable.Drawable;

import androidx.core.content.ContextCompat;
import androidx.preference.Preference;

import org.chromium.chrome.R;
import org.chromium.chrome.browser.browther_referral.core.ReferralAccount;
import org.chromium.chrome.browser.browther_referral.core.ReferralAccountLabel;

/**
 * La ligne « Compte dev&din » des Paramètres, juste sous « Parrainage » — port de {@code
 * ReferralAccountSettingsRow} ({@code ReferralAccountView.swift}), le contrat commun (docs/
 * PARRAINAGE.md § 7.1, « L'accès permanent au compte »).
 *
 * <p>Son état est EN CLAIR : « Non connecté », ou l'adresse (« Connecté » pour un relais d'Apple ou
 * une adresse qu'on ne connaît pas). C'est là qu'on cherche un compte, et c'est elle qui porte le
 * libellé que le bouclier de l'écran Parrainage n'a pas.
 *
 * <p>⚠️ La page du compte s'ouvre PAR-DESSUS les Paramètres, qui ne « reprennent » donc pas quand
 * elle se ferme : la ligne écoute le contrôleur tant qu'elle est à l'écran ({@link #onAttached}),
 * sinon elle dirait encore « Non connecté » à quelqu'un qui vient de se connecter.
 */
public final class ReferralAccountSettingsPreference extends Preference
        implements BrowtherReferralController.Listener {
    public static final String KEY = "browther_referral_account";

    /** Le clic est branché par les Paramètres, qui tiennent l'activité (⛔ pas le contexte). */
    public ReferralAccountSettingsPreference(Context context) {
        super(context);
        setKey(KEY);
        setPersistent(false);
        refresh();
    }

    @Override
    public void onAttached() {
        super.onAttached();
        BrowtherReferralController.get().addListener(this);
        refresh();
    }

    @Override
    public void onDetached() {
        BrowtherReferralController.get().removeListener(this);
        super.onDetached();
    }

    @Override
    public void onReferralChanged() {
        refresh();
    }

    /** Relu à chaque retour sur les Paramètres, et à chaque changement du compte. */
    public void refresh() {
        Context context = getContext();
        BrowtherReferralController controller = BrowtherReferralController.get();
        controller.boot();
        ReferralAccount account = controller.account();
        ReferralUi.Palette p = ReferralUi.palette(context);
        setTitle(ReferralStrings.get(context, "account.title"));
        setSummary(state(context, account));
        Drawable icon =
                ContextCompat.getDrawable(
                        context,
                        account == null
                                ? R.drawable.browther_referral_glyph_shield
                                : R.drawable.browther_referral_glyph_shield_check);
        if (icon != null) {
            icon = icon.mutate();
            icon.setTint(account == null ? p.text2 : p.green);
            setIcon(icon);
        }
    }

    private static String state(Context context, ReferralAccount account) {
        if (account == null) return ReferralStrings.get(context, "account.off");
        ReferralAccountLabel label = ReferralAccountLabel.of(account);
        if (label.kind == ReferralAccountLabel.Kind.EMAIL && label.email != null) return label.email;
        return ReferralStrings.get(context, "account.on");
    }
}
