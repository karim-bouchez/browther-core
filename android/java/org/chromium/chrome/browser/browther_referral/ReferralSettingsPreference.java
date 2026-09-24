/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_referral;

import android.content.Context;
import android.graphics.Typeface;
import android.graphics.drawable.Drawable;
import android.text.SpannableStringBuilder;
import android.text.Spanned;
import android.text.style.ForegroundColorSpan;
import android.text.style.RelativeSizeSpan;
import android.text.style.StyleSpan;

import androidx.core.content.ContextCompat;
import androidx.preference.Preference;

import org.chromium.chrome.R;

/**
 * La ligne « Parrainage » EN HAUT des Paramètres (private/docs/PARRAINAGE.md § 2.10) : l'icône
 * cadeau et le titre en OR, « Gagne des hassanats et l'accès à vie » dessous, et la mention
 * « Nouveau » quand une BONNE nouvelle attend (8, 8 bis) — ⛔ jamais pour un J−3 ou un J0.
 *
 * <p>⛔ Ni aplat ni ligne entière colorée (les deux passes de recette desktop du 2026-09-23) : le
 * fond appartient à la liste, la ligne se distingue par l'icône et la couleur du titre.
 */
public final class ReferralSettingsPreference extends Preference {
    public static final String KEY = "browther_referral";

    /** Le clic est branché par les Paramètres, qui tiennent l'activité (⛔ pas le contexte). */
    public ReferralSettingsPreference(Context context) {
        super(context);
        setKey(KEY);
        setPersistent(false);
        refresh();
    }

    /** Relu à chaque retour sur les Paramètres : la pastille suit les bonnes nouvelles. */
    public void refresh() {
        Context context = getContext();
        int gold = ContextCompat.getColor(context, R.color.browther_referral_gold);
        SpannableStringBuilder title = new SpannableStringBuilder(ReferralStrings.get(context, "home.title"));
        title.setSpan(new ForegroundColorSpan(gold), 0, title.length(), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
        title.setSpan(new StyleSpan(Typeface.BOLD), 0, title.length(), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
        if (BrowtherReferralController.get().hasFreshNews()) {
            int start = title.length();
            title.append("  ● ").append(ReferralStrings.get(context, "settings.news"));
            title.setSpan(new ForegroundColorSpan(gold), start, title.length(),
                    Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
            title.setSpan(new RelativeSizeSpan(0.8f), start, title.length(),
                    Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
        }
        setTitle(title);
        setSummary(ReferralStrings.get(context, "settings.subtitle"));
        Drawable icon = ContextCompat.getDrawable(context, R.drawable.browther_referral_glyph_gift);
        if (icon != null) {
            icon = icon.mutate();
            icon.setTint(gold);
            setIcon(icon);
        }
    }
}
