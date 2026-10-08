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

import org.chromium.chrome.browser.browther_referral.core.ReferralShare;
import org.chromium.chrome.browser.browther_referral.core.ReferralStatus;
import org.chromium.chrome.browser.browther_referral.core.ReferralStatusVideo;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.function.Consumer;

/**
 * Le partage du code (§ 12.1, § 12.10) — pendant de {@code ReferralSharing} (iOS, {@code
 * BrowtherReferralPresenter.swift}).
 *
 * <p>⭐ Depuis le 2026-10-08 (private/docs/PARRAINAGE.md § 11), c'est la feuille « Partager mon
 * code » ({@link ReferralShareSheet}) qui partage, par <b>UN envoi = UN fichier et un texte</b> :
 * la vidéo de présentation ou l'image du statut, avec le lien SEUL (statut WhatsApp : il devient la
 * légende) ou le message à un proche. ⛔ Jamais deux fichiers dans le même envoi : WhatsApp ne donne
 * le texte qu'au premier. Le message en texte seul ({@link #share}) reste : c'est le partage du
 * cadeau, et le repli quand aucun fichier ne peut partir.
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
        COPIED("copied"),
        /** Rien n'a pu partir : le fichier manque, ou aucune app ne s'est ouverte. */
        UNAVAILABLE("unavailable");

        public final String wire;

        Result(String wire) {
            this.wire = wire;
        }
    }

    /**
     * Ce qui est partagé (§ 9, {@code PARRAINAGE-partage-statut.md} § 4) : le message à un proche,
     * ou un statut WhatsApp. ⭐ Porté par {@code referral_shared.format} — ⛔ pas un nouvel
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

    /** Ce qu'un envoi a ouvert. */
    public enum Launch {
        /**
         * L'app visée, directement (WhatsApp, pour un statut). Android n'en dira rien de plus :
         * ouvrir vaut « partagé ».
         */
        DIRECT,
        /** Le sélecteur du système : seule une cible CHOISIE revient (le rappel {@code chosen}). */
        CHOOSER,
        /** Rien ne s'est ouvert. */
        NONE
    }

    /** Le fichier de l'image du statut, une fois écrit — {@code null} si l'écriture a échoué. */
    public interface FileCallback {
        void onFile(@Nullable File file);
    }

    private static final String ACTION_CHOSEN = "org.chromium.chrome.browser.browther_referral.SHARE_CHOSEN";

    /** Le dossier de l'image du statut : sous {@code files/images/}, servi par le FileProvider. */
    private static final String STATUS_DIR = "images/browther_referral";

    /**
     * Où un STATUT s'ouvre d'office : WhatsApp, puis WhatsApp Business — le bouton dit « Publier en
     * statut WhatsApp ». ⚠️ {@code startActivity} avec un paquet n'a pas besoin de {@code
     * <queries>} : il lève simplement si l'app n'est pas là.
     */
    private static final String[] WHATSAPP = {"com.whatsapp", "com.whatsapp.w4b"};

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

    // -------------------- Le message en texte seul --------------------

    /**
     * Le sélecteur du système avec le message seul — le partage du cadeau (§ 12.27). {@code done}
     * n'est appelé que si une cible a été choisie ; l'analytique ({@code referral_shared}) et les 3
     * jours ({@code shareDone}) sont posés ici — ⛔ muets en aperçu (§ 13.8).
     */
    public static void share(
            Activity activity,
            ReferralStatus status,
            String screen,
            boolean preview,
            @Nullable Consumer<Result> done) {
        shareText(activity, status, () -> achieved(screen, preview, Result.SHARED, done));
    }

    /**
     * Le même sélecteur, SANS rien compter : la feuille de partage y retombe quand aucun fichier ne
     * peut partir, et c'est elle qui écrit l'évènement et dit les 3 jours.
     */
    static Launch shareText(Activity activity, ReferralStatus status, Runnable chosen) {
        Intent send = new Intent(Intent.ACTION_SEND);
        send.setType("text/plain");
        send.putExtra(Intent.EXTRA_TEXT, message(activity, status));
        return choose(activity, send, "invite.share", chosen);
    }

    // -------------------- UN fichier et un texte (§ 11) --------------------

    /**
     * ⭐ <b>Un statut WhatsApp</b> : la vidéo de présentation ou l'image qui porte le code, <b>+ le
     * lien SEUL en texte</b> — WhatsApp en fait la légende, juste sous l'étiquette « Clique sur le
     * lien en dessous 👇 ». ⛔ Pas le message : il doublerait le texte déjà DANS l'image.
     *
     * <p>Ouvert directement dans WhatsApp s'il est installé ({@link Launch#DIRECT} : ouvrir vaut
     * « partagé ») ; sinon le sélecteur du système, avec la règle de toujours — seule une cible
     * CHOISIE compte ({@code chosen}). ⛔ Rien n'est compté ici : la feuille écrit un évènement par
     * ENVOI et dit les 3 jours une fois, en se refermant.
     */
    public static Launch shareStatusFile(Activity activity, File file, String link, Runnable chosen) {
        Intent send = fileIntent(file, link);
        if (send == null) return Launch.NONE;
        for (String target : WHATSAPP) {
            try {
                activity.startActivity(new Intent(send).setPackage(target));
                return Launch.DIRECT;
            } catch (RuntimeException e) {
                // `ActivityNotFoundException` : pas installée (ou elle ne prend pas ce type) — on
                // essaie la suivante, puis le sélecteur.
            }
        }
        return choose(activity, send, "invite.shareStatus", chosen);
    }

    /**
     * ⭐ <b>Le message à un proche</b>, avec son fichier (la vidéo, ou l'image du statut) : le texte
     * devient sa légende. ⛔ Toujours le sélecteur du système, jamais WhatsApp d'office — on écrit à
     * qui l'on veut, par où l'on veut. Seule une cible CHOISIE compte.
     */
    public static Launch shareMessageFile(
            Activity activity, File file, String message, Runnable chosen) {
        Intent send = fileIntent(file, message);
        if (send == null) return Launch.NONE;
        return choose(activity, send, "share.send", chosen);
    }

    /** {@code video/mp4} pour la vidéo, {@code image/jpeg} pour l'image du statut. */
    static String mimeType(File file) {
        return file.getName().toLowerCase(Locale.ROOT).endsWith(".mp4") ? "video/mp4" : "image/jpeg";
    }

    /**
     * L'envoi d'UN fichier et de son texte — typé selon le fichier (⚠️ un partage écrit pour un
     * JPEG ne convient pas à une vidéo). {@code null} si le fichier manque ou si le FileProvider
     * n'en veut pas.
     */
    private static @Nullable Intent fileIntent(File file, String text) {
        if (!file.isFile()) return null;
        Uri uri = BrowtherReferralController.get().shareableUri(file);
        if (uri == null) return null;
        Intent send = new Intent(Intent.ACTION_SEND);
        send.setType(mimeType(file));
        send.putExtra(Intent.EXTRA_STREAM, uri);
        send.putExtra(Intent.EXTRA_TEXT, text);
        // ⚠️ Le ClipData porte la permission de lecture jusqu'à l'app qui reçoit l'envoi, À TRAVERS
        // le sélecteur compris (sinon WhatsApp reçoit un fichier qu'il n'a pas le droit d'ouvrir).
        send.setClipData(ClipData.newRawUri("", uri));
        send.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        return send;
    }

    /**
     * L'image du statut ({@link ReferralStatusImage}) écrite en JPEG (qualité 0,92, comme iOS),
     * sous un nom qui porte le code — hors du fil de l'interface, le rappel y revient. ⚠️ L'image
     * n'est PAS libérée : la feuille montre la même (ce qu'on voit est ce qui part).
     */
    public static void statusImageFile(
            Context context, String code, Bitmap image, FileCallback done) {
        File dir = new File(context.getApplicationContext().getFilesDir(), STATUS_DIR);
        Handler main = new Handler(Looper.getMainLooper());
        sIo.execute(
                () -> {
                    File file = writeJpeg(dir, code, image);
                    main.post(() -> done.onFile(file));
                });
    }

    /**
     * ⚠️ Les anciennes images du dossier sont effacées (une seule à la fois) : TOUT le dossier —
     * c'est pourquoi la vidéo vit dans le sien ({@code ReferralStatusVideoStore}).
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
            return image.compress(Bitmap.CompressFormat.JPEG, 92, out) ? file : null;
        } catch (IOException | RuntimeException e) {
            return null;
        }
    }

    /**
     * Le sélecteur du système ; seule une cible CHOISIE revient (voir l'en-tête), par {@code
     * chosen}. {@link Launch#NONE} si rien ne s'est ouvert.
     */
    private static Launch choose(Activity activity, Intent send, String titleKey, Runnable chosen) {
        Context app = activity.getApplicationContext();
        unregisterPending(app);
        BroadcastReceiver receiver =
                new BroadcastReceiver() {
                    @Override
                    public void onReceive(Context context, Intent intent) {
                        unregisterPending(app);
                        chosen.run();
                    }
                };
        IntentFilter filter = new IntentFilter(ACTION_CHOSEN);
        // NON exporté sur toutes les versions, comme `ContextUtils.registerNonExportedBroadcastReceiver`
        // de Chromium : sans ça, une autre app pourrait simuler un partage abouti (et ses 3 jours).
        app.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED);
        sPending = receiver;

        // ⚠️ Explicite (le paquet) ET mutable : le système y ajoute la cible choisie.
        Intent target = new Intent(ACTION_CHOSEN).setPackage(app.getPackageName());
        PendingIntent callback =
                PendingIntent.getBroadcast(
                        app,
                        0,
                        target,
                        PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_MUTABLE);
        // ⚠️ `createChooser` reprend de lui-même le ClipData et la permission de lecture de l'envoi.
        Intent chooser =
                Intent.createChooser(
                        send, ReferralStrings.get(activity, titleKey), callback.getIntentSender());
        try {
            activity.startActivity(chooser);
            return Launch.CHOOSER;
        } catch (RuntimeException e) {
            unregisterPending(app);
            return Launch.NONE;
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

    // -------------------- L'analytique d'un partage (§ 13, § 11) --------------------

    /**
     * Un statut est parti (ou n'a pas pu partir) : il dit TOUJOURS lequel — {@code media} = la
     * vidéo ou l'image. ⚠️ Un évènement par ENVOI : qui publie les deux statuts en émet deux —
     * compter des personnes, pas des lignes. ⛔ Muet en aperçu (§ 13.8).
     */
    static void noteStatus(
            String screen, boolean preview, Result result, ReferralStatusVideo.Segment media) {
        BrowtherReferralController.get()
                .note(
                        "referral_shared",
                        preview,
                        "screen",
                        screen,
                        "result",
                        result.wire,
                        "format",
                        Format.STATUS.wire,
                        "media",
                        media.rawValue);
    }

    /**
     * Un message est parti : {@code media} dit le fichier joint ({@code video} | {@code image}), ⛔
     * ABSENT si le texte est parti seul. ⛔ Muet en aperçu (§ 13.8).
     */
    static void noteMessage(
            String screen,
            boolean preview,
            Result result,
            @Nullable ReferralStatusVideo.Segment media) {
        BrowtherReferralController controller = BrowtherReferralController.get();
        if (media == null) {
            controller.note(
                    "referral_shared",
                    preview,
                    "screen",
                    screen,
                    "result",
                    result.wire,
                    "format",
                    Format.MESSAGE.wire);
            return;
        }
        controller.note(
                "referral_shared",
                preview,
                "screen",
                screen,
                "result",
                result.wire,
                "format",
                Format.MESSAGE.wire,
                "media",
                media.rawValue);
    }

    /** Un message en texte seul a abouti, hors de la feuille : l'évènement, puis les 3 jours. */
    private static void achieved(
            String screen, boolean preview, Result result, @Nullable Consumer<Result> done) {
        noteMessage(screen, preview, result, null);
        if (done != null) done.accept(result);
        BrowtherReferralController.get().shareDone(screen, preview);
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
