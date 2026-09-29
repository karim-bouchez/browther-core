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
import android.graphics.Bitmap;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;

import androidx.annotation.Nullable;

import org.chromium.chrome.browser.browther_referral.core.MilestoneScale;
import org.chromium.chrome.browser.browther_referral.core.ReferralShare;
import org.chromium.chrome.browser.browther_referral.core.ReferralStatus;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.function.Consumer;

/**
 * Le partage du code (§ 12.1, § 12.10) — pendant de {@code ReferralSharing} et de {@code
 * referralShareMyCode} / {@code referralShareStatus} (iOS). Deux formats : le message ({@link
 * #share}) et le statut WhatsApp ({@link #shareStatus}, § 9).
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

    /**
     * Ce qui est partagé (§ 9, {@code PARRAINAGE-partage-statut.md} § 4) : le message en texte, ou
     * l'image du statut WhatsApp. ⭐ Porté par {@code referral_shared.format} — ⛔ pas un nouvel
     * évènement. Verrouillé par {@code android-referral-tests/analytics_check.py}.
     */
    public enum Format {
        MESSAGE("message"),
        STATUS("status");

        public final String wire;

        Format(String wire) {
            this.wire = wire;
        }
    }

    private static final String ACTION_CHOSEN = "org.chromium.chrome.browser.browther_referral.SHARE_CHOSEN";

    /** Le dossier de l'image du statut : sous {@code files/images/}, servi par le FileProvider. */
    private static final String STATUS_DIR = "images/browther_referral";

    /** L'écriture de l'image (JPEG, ~300 Ko) : hors du fil de l'interface. */
    private static final ExecutorService sIo = Executors.newSingleThreadExecutor();

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
        Intent send = new Intent(Intent.ACTION_SEND);
        send.setType("text/plain");
        send.putExtra(Intent.EXTRA_TEXT, message(activity, status));
        choose(activity, send, "invite.share", screen, preview, Format.MESSAGE, done);
    }

    /**
     * ⭐ <b>Le statut WhatsApp</b> (2026-09-29, {@code PARRAINAGE-partage-statut.md}) — pendant de
     * {@code ReferralSharing.shareStatus} iOS : l'image du statut ({@link ReferralStatusImage},
     * dans la langue de l'app : fr, en ou ar, sinon l'anglais) <b>+ le lien SEUL en texte</b> —
     * WhatsApp en fait la légende, juste sous l'étiquette « Clique sur le lien en dessous 👇 ». ⛔
     * Pas le message : il doublerait le texte déjà DANS l'image. Le seuil de l'accès à vie vient du
     * barème du service ({@code lifetimeAt}, ⛔ jamais en dur).
     *
     * <p>Mêmes règles que le message : un partage abouti n'ouvre droit qu'aux 3 jours (§ 4), et ⛔
     * rien ne s'écrit depuis un aperçu (§ 13.8).
     */
    public static void shareStatus(
            Activity activity,
            ReferralStatus status,
            String screen,
            boolean preview,
            @Nullable Consumer<Result> done) {
        String code = status.referral.code.toUpperCase(Locale.ROOT);
        ReferralStatusImage.Texts texts =
                ReferralStatusImage.Texts.current(activity, new MilestoneScale(status).lifetimeAt);
        Bitmap image = ReferralStatusImage.render(activity, code, texts);
        String link = ReferralShare.link(code, status.referral.url);
        File dir = new File(activity.getApplicationContext().getFilesDir(), STATUS_DIR);
        Handler main = new Handler(Looper.getMainLooper());
        sIo.execute(
                () -> {
                    File file = writeJpeg(dir, code, image);
                    main.post(
                            () -> {
                                if (file == null || activity.isFinishing()) return;
                                Uri uri = BrowtherReferralController.get().shareableUri(file);
                                if (uri == null) return;
                                Intent send = new Intent(Intent.ACTION_SEND);
                                send.setType("image/jpeg");
                                send.putExtra(Intent.EXTRA_STREAM, uri);
                                send.putExtra(Intent.EXTRA_TEXT, link);
                                // ⚠️ Le ClipData porte la permission de lecture jusqu'à la cible
                                // choisie À TRAVERS le sélecteur (sinon WhatsApp reçoit une image
                                // qu'il n'a pas le droit d'ouvrir).
                                send.setClipData(ClipData.newRawUri("", uri));
                                send.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
                                choose(
                                        activity,
                                        send,
                                        "invite.shareStatus",
                                        screen,
                                        preview,
                                        Format.STATUS,
                                        done);
                            });
                });
    }

    /**
     * L'image en JPEG (qualité 0,92, comme iOS), sous un nom qui porte le code ; les anciennes
     * images du dossier sont effacées (une seule à la fois).
     */
    private static @Nullable File writeJpeg(File dir, String code, Bitmap image) {
        if (!dir.isDirectory() && !dir.mkdirs()) return null;
        File[] old = dir.listFiles();
        if (old != null) {
            // Best effort : une image restée là sera effacée au prochain partage.
            for (File file : old) file.delete();
        }
        File file = new File(dir, "browther-" + code.toLowerCase(Locale.ROOT) + ".jpg");
        try (FileOutputStream out = new FileOutputStream(file)) {
            image.compress(Bitmap.CompressFormat.JPEG, 92, out);
            return file;
        } catch (IOException e) {
            return null;
        } finally {
            image.recycle();
        }
    }

    /** Le sélecteur du système ; seule une cible CHOISIE revient (voir l'en-tête). */
    private static void choose(
            Activity activity,
            Intent send,
            String titleKey,
            String screen,
            boolean preview,
            Format format,
            @Nullable Consumer<Result> done) {
        Context app = activity.getApplicationContext();
        unregisterPending(app);
        BroadcastReceiver receiver =
                new BroadcastReceiver() {
                    @Override
                    public void onReceive(Context context, Intent intent) {
                        unregisterPending(app);
                        achieved(screen, preview, Result.SHARED, format, done);
                    }
                };
        IntentFilter filter = new IntentFilter(ACTION_CHOSEN);
        // NON exporté sur toutes les versions, comme `ContextUtils.registerNonExportedBroadcastReceiver`
        // de Chromium : sans ça, une autre app pourrait simuler un partage abouti (et ses 3 jours).
        app.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED);
        sPending = receiver;

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
                        send, ReferralStrings.get(activity, titleKey), callback.getIntentSender());
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
        achieved(screen, preview, Result.COPIED, Format.MESSAGE, done);
    }

    private static void achieved(
            String screen,
            boolean preview,
            Result result,
            Format format,
            @Nullable Consumer<Result> done) {
        BrowtherReferralController controller = BrowtherReferralController.get();
        controller.note(
                "referral_shared",
                preview,
                "screen",
                screen,
                "result",
                result.wire,
                "format",
                format.wire);
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
