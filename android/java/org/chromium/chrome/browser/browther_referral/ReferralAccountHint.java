/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_referral;

import android.app.Activity;
import android.view.Gravity;
import android.view.View;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;

import androidx.annotation.Nullable;

import org.chromium.chrome.R;
import org.chromium.chrome.browser.browther_referral.core.ReferralAccountStake;

/**
 * La proposition du compte dev&din, onglet par onglet — port de {@code ReferralAccountHint} ({@code
 * ReferralAccountView.swift}).
 *
 * <p>Ce que l'onglet contient est en jeu : la rangée le dit avec SES mots, et mène à la page du
 * compte. Une seule rangée, quatre enjeux ({@link ReferralAccountStake}) : « Mets ton code à
 * l'abri » (Inviter, dès qu'un partage aboutit), « tes invitations » (Invitations), « ton mois
 * offert » (Code reçu, dès qu'un code est saisi), « ton abonnement » (Soutenir).
 *
 * <p>⭐ Elle apparaît sur l'écran où l'on EST, au moment où l'enjeu naît : l'écran Parrainage se
 * redessine au changement ({@code Listener}), et redemande la rangée. ⛔ Rien pour qui est déjà
 * connecté, ⛔ rien quand le compte n'existe pas dans ce binaire.
 */
public final class ReferralAccountHint {
    private ReferralAccountHint() {}

    /** La rangée de cet enjeu — {@code null} quand il n'y a rien à proposer. */
    public static @Nullable View of(
            Activity activity, ReferralUi.Palette p, ReferralAccountStake stake, boolean preview) {
        BrowtherReferralController controller = BrowtherReferralController.get();
        if (!controller.isAccountEnabled() || controller.account() != null) return null;
        if (!controller.accountStakes().has(stake)) return null;

        String title = ReferralStrings.get(activity, "account.hint." + stake.rawValue + ".title");
        String sub = ReferralStrings.get(activity, "account.hint." + stake.rawValue + ".sub");

        LinearLayout row = ReferralUi.row(activity);
        int padH = ReferralUi.dp(activity, 14);
        int padV = ReferralUi.dp(activity, 12);
        row.setPadding(padH, padV, padH, padV);
        float radius = ReferralUi.dp(activity, 16);
        row.setBackground(
                ReferralUi.pressable(
                        ReferralUi.rounded(
                                p.goldSurface,
                                radius,
                                ReferralUi.dp(activity, 1),
                                ReferralUi.withAlpha(p.gold, 0.3f)),
                        ReferralUi.withAlpha(p.gold, 0.18f),
                        radius));

        ImageView shield =
                ReferralUi.glyph(activity, R.drawable.browther_referral_glyph_shield_check, 20, p.gold);
        row.addView(shield);

        LinearLayout texts = ReferralUi.column(activity);
        TextView titleView = ReferralUi.text(activity, title, 15, ReferralUi.SEMIBOLD, p.text);
        titleView.setTextAlignment(View.TEXT_ALIGNMENT_VIEW_START);
        texts.addView(titleView, ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP));
        TextView subView = ReferralUi.text(activity, sub, 13, ReferralUi.REGULAR, p.text2);
        subView.setTextAlignment(View.TEXT_ALIGNMENT_VIEW_START);
        texts.addView(
                subView,
                ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP, ReferralUi.dp(activity, 2)));
        LinearLayout.LayoutParams textsParams = new LinearLayout.LayoutParams(0, ReferralUi.WRAP, 1);
        textsParams.setMarginStart(ReferralUi.dp(activity, 12));
        textsParams.setMarginEnd(ReferralUi.dp(activity, 8));
        row.addView(texts, textsParams);

        ImageView chevron =
                ReferralUi.glyph(activity, R.drawable.browther_intro_glyph_chevron_right, 13, p.text2);
        // « Vers l'avant » : il se retourne en arabe. ⚠️ `mutate` : sans lui, le réglage vaudrait
        // pour TOUTES les flèches chargées depuis cette ressource.
        chevron.getDrawable().mutate().setAutoMirrored(true);
        row.addView(chevron);

        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setClickable(true);
        row.setFocusable(true);
        row.setContentDescription(title + ". " + sub);
        row.setOnClickListener(
                v -> {
                    ReferralUi.tick(v);
                    // « Soutenir » est aussi l'écran de paiement : sa provenance le dit.
                    BrowtherReferralPresenter.openAccount(
                            activity,
                            stake == ReferralAccountStake.PAID
                                    ? BrowtherReferralPresenter.AccountOrigin.BILLING
                                    : BrowtherReferralPresenter.AccountOrigin.HOME,
                            preview);
                });
        ReferralUi.pressFeedback(row);
        row.setLayoutParams(ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP));
        return row;
    }
}
