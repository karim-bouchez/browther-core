/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_referral;

import android.app.Activity;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.Build;

import androidx.annotation.Nullable;

import org.chromium.chrome.browser.browther_referral.core.ReferralShare;
import org.chromium.chrome.browser.browther_referral.core.ReferralStatus;

import java.util.Locale;
import java.util.function.Consumer;

/**
 * Le partage du code (§ 12.1, § 12.10) — pendant de {@code ReferralSharing} et de {@code
 * referralShareMyCode} (iOS).
 *
 * <p>🔴 Le message part SEUL, en texte : le lien est DANS le texte, sur la dernière ligne — ⛔ ni
 * sujet (il se colle en tête du message dans certaines cibles), ni URL à part.
 *
 * <p>⚠️ Android ne dit rien d'un sélecteur refermé : seule une cible CHOISIE revient (par l'{@code
 * IntentSender} du sélecteur). C'est donc « partagé » ou rien — ⛔ jamais un {@code cancelled}
 * inventé. « Copier » (carte du code) est un partage abouti lui aussi (§ 12.20).
 */
public final class ReferralSharing {
    private ReferralSharing() {}

    public enum Result {
        SHARED("shared"),
        COPIED("copied");

        public final String wire;

        Result(String wire) {
            this.wire = wire;
        }
    }

    private static final String ACTION_CHOSEN = "org.chromium.chrome.browser.browther_referral.SHARE_CHOSEN";

    /** Le partage en attente de sa cible — un seul à la fois, comme le sélecteur. */
    private static @Nullable BroadcastReceiver sPending;

    /** Le message complet : le texte, puis le lien seul sur la dernière ligne. */
    public static String message(Context context, ReferralStatus status) {
        String code = status.referral.code.toUpperCase(Locale.ROOT);
        String text = ReferralStrings.fill(ReferralStrings.get(context, "share.message"), "code", code);
        return ReferralShare.message(text, code, status.referral.url);
    }

    /**
     * Le sélecteur du système avec le message seul. {@code done} n'est appelé que si une cible a
     * été choisie ; l'analytique ({@code referral_shared}) et les 3 jours ({@code shareDone}) sont
     * posés ici — ⛔ muets en aperçu (§ 13.8).
     */
    public static void share(
            Activity activity,
            ReferralStatus status,
            String screen,
            boolean preview,
            @Nullable Consumer<Result> done) {
        Context app = activity.getApplicationContext();
        unregisterPending(app);
        BroadcastReceiver receiver =
                new BroadcastReceiver() {
                    @Override
                    public void onReceive(Context context, Intent intent) {
                        unregisterPending(app);
                        achieved(screen, preview, Result.SHARED, done);
                    }
                };
        IntentFilter filter = new IntentFilter(ACTION_CHOSEN);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            app.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED);
        } else {
            app.registerReceiver(receiver, filter);
        }
        sPending = receiver;

        Intent send = new Intent(Intent.ACTION_SEND);
        send.setType("text/plain");
        send.putExtra(Intent.EXTRA_TEXT, message(activity, status));
        // ⚠️ Explicite (le paquet) ET mutable : le système y ajoute la cible choisie.
        Intent chosen = new Intent(ACTION_CHOSEN).setPackage(app.getPackageName());
        PendingIntent callback =
                PendingIntent.getBroadcast(
                        app,
                        0,
                        chosen,
                        PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_MUTABLE);
        Intent chooser =
                Intent.createChooser(
                        send, ReferralStrings.get(activity, "invite.share"), callback.getIntentSender());
        try {
            activity.startActivity(chooser);
        } catch (RuntimeException e) {
            unregisterPending(app);
        }
    }

    /**
     * Le message COMPLET dans le presse-papier, SANS rien compter : la carte du code l'appelle, et
     * c'est son {@code onCopied} (l'écran qui la porte) qui dit « partage abouti » — ⛔ pas deux
     * fois.
     */
    public static void copy(Context context, ReferralStatus status) {
        ClipboardManager clipboard = context.getSystemService(ClipboardManager.class);
        if (clipboard == null) return;
        clipboard.setPrimaryClip(ClipData.newPlainText("Browther", message(context, status)));
    }

    /** « Copier » : le message COMPLET, lien compris — et c'est un partage abouti (§ 12.20). */
    public static void copy(
            Context context,
            ReferralStatus status,
            String screen,
            boolean preview,
            @Nullable Consumer<Result> done) {
        copy(context, status);
        achieved(screen, preview, Result.COPIED, done);
    }

    private static void achieved(
            String screen, boolean preview, Result result, @Nullable Consumer<Result> done) {
        BrowtherReferralController controller = BrowtherReferralController.get();
        controller.note("referral_shared", preview, "screen", screen, "result", result.wire);
        if (done != null) done.accept(result);
        controller.shareDone(screen, preview);
    }

    private static void unregisterPending(Context app) {
        BroadcastReceiver pending = sPending;
        sPending = null;
        if (pending == null) return;
        try {
            app.unregisterReceiver(pending);
        } catch (IllegalArgumentException e) {
            // Déjà retiré.
        }
    }
}
