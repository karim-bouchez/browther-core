/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_referral;

import android.content.Context;
import android.text.TextUtils;
import android.view.Gravity;
import android.view.View;
import android.widget.FrameLayout;
import android.widget.TextView;

/**
 * ⭐ « Recommandé » est un TAMPON posé sur le coin du bouton Google, hors mise en page, légèrement
 * penché (le patron de Sawtunaa, {@code SsoButtons.tsx}) — ⛔ pas dans la rangée, où il décale le
 * libellé et fait un bouton différent des deux autres (Karim, 2026-10-07). Fond de la page et or du
 * parrainage : il se lit sur le bouton plein comme sur la page. En arabe il passe sur l'autre coin
 * et penche de l'autre côté. Port de {@code ReferralStamp} ({@code ReferralAccountView.swift}).
 *
 * <p>🔴 <b>Il ne dessine JAMAIS hors de sa boîte</b> (private/docs/PARRAINAGE.md § 8.7 : lever la
 * découpe des conteneurs avait suffi à l'émulateur, pas au Huawei P20). Le bouton est donc posé dans
 * une enveloppe qui RÉSERVE la place du tampon — au-dessus du bouton et au-delà de son bord — et
 * c'est dans cette marge-là qu'il déborde. L'enveloppe se pose avec des marges de côté réduites de
 * {@link #sideRoom} : le bouton garde exactement la largeur des deux autres.
 */
public final class ReferralStamp {
    private ReferralStamp() {}

    /** De combien il penche (dans le sens des aiguilles en gauche-à-droite). */
    private static final float TILT = 8f;

    /** De combien il sort du coin : vers l'extérieur, et vers le haut. */
    private static final float OUT_DP = 6f;

    private static final float UP_DP = 9f;

    /** La place réservée de chaque côté du bouton — à retirer des marges de l'enveloppe. */
    public static int sideRoom(Context context) {
        return ReferralUi.dp(context, 8);
    }

    /** La place réservée au-dessus du bouton (le tampon sorti de 9, plus ce que la pente ajoute). */
    public static int topRoom(Context context) {
        return ReferralUi.dp(context, 16);
    }

    /** Le bouton dans son enveloppe, le tampon sur son coin de fin. */
    public static FrameLayout wrap(Context context, ReferralUi.Palette p, View button, String text) {
        boolean rtl =
                context.getResources().getConfiguration().getLayoutDirection()
                        == View.LAYOUT_DIRECTION_RTL;
        FrameLayout envelope = new FrameLayout(context);
        int side = sideRoom(context);
        envelope.setPadding(side, topRoom(context), side, 0);
        // ⚠️ Le tampon vit dans la MARGE INTÉRIEURE de l'enveloppe : sans ceci il y serait rogné.
        envelope.setClipToPadding(false);
        envelope.addView(
                button, new FrameLayout.LayoutParams(ReferralUi.MATCH, ReferralUi.WRAP));

        TextView stamp =
                ReferralUi.text(
                        context,
                        text.toUpperCase(ReferralFormat.locale(context)),
                        10,
                        ReferralUi.BOLD,
                        p.gold);
        stamp.setLetterSpacing(0.06f);
        stamp.setSingleLine(true);
        stamp.setEllipsize(TextUtils.TruncateAt.END);
        stamp.setIncludeFontPadding(false);
        int padH = ReferralUi.dp(context, 7);
        int padV = ReferralUi.dp(context, 3);
        stamp.setPadding(padH, padV, padH, padV);
        stamp.setBackground(
                ReferralUi.rounded(p.screen, ReferralUi.dp(context, 4), ReferralUi.dp(context, 1), p.gold));
        stamp.setRotation(rtl ? -TILT : TILT);
        // ⚠️ Vers l'EXTÉRIEUR du coin : un décalage ne se retourne pas tout seul en arabe.
        stamp.setTranslationX(ReferralUi.dp(context, OUT_DP) * (rtl ? -1 : 1));
        stamp.setTranslationY(-ReferralUi.dp(context, UP_DP));
        // Il ne prend aucun toucher (le bouton est dessous) et ne se lit pas deux fois : le libellé
        // d'accessibilité du bouton le dit déjà.
        stamp.setClickable(false);
        stamp.setFocusable(false);
        stamp.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
        envelope.addView(
                stamp,
                new FrameLayout.LayoutParams(
                        ReferralUi.WRAP, ReferralUi.WRAP, Gravity.TOP | Gravity.END));
        return envelope;
    }
}
