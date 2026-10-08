/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_referral;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;

import androidx.annotation.Nullable;

import org.chromium.chrome.browser.browther_referral.core.ReferralStatusVideo;
import org.chromium.chrome.browser.browther_referral.core.ReferralStatusVideoLoader;

import java.io.File;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Télécharge et garde en cache la <b>vidéo du statut WhatsApp</b> — port de {@code
 * ReferralStatusVideoStore} (iOS) ; règle et pourquoi : {@code core/ReferralStatusVideo},
 * private/docs/PARRAINAGE.md § 11. Le transfert lui-même : {@code core/ReferralStatusVideoLoader}.
 *
 * <p>⭐ Demandée dès que « Partager mon code » est à l'écran ({@link ReferralShareSheet#button}), pas
 * au tap : la vidéo est là quand la feuille s'ouvre. Une fois en cache, plus aucun transfert — seul
 * le manifeste (quelques centaines d'octets) est relu, pour suivre un changement ou une coupure.
 *
 * <p>🔴 <b>Ne lève jamais</b> : {@code null} = pas de vidéo, et le statut part avec l'image seule.
 * ⚠️ Un échec n'est PAS mémorisé (le réseau revient). ⚠️ Un succès n'est mémorisé que {@link
 * ReferralStatusVideo#FRESH_MS} : le manifeste est aussi l'interrupteur qui COUPE la vidéo.
 *
 * <p>⚠️ Tout se demande et se rend sur le fil de l'interface ; seul le transfert en sort.
 */
public final class ReferralStatusVideoStore {
    private ReferralStatusVideoStore() {}

    /** Le fichier local de la vidéo, ou {@code null} s'il n'y en a pas. */
    public interface Callback {
        void onVideo(@Nullable File file);
    }

    /**
     * 🔴 SON dossier, sous {@code files/images/} (servi par le FileProvider de Chrome, comme
     * l'image) : {@code ReferralSharing.writeJpeg} EFFACE tout {@code images/browther_referral} à
     * chaque image — la vidéo y serait retéléchargée à chaque ouverture de la feuille.
     */
    static final String VIDEO_DIR = "images/browther_referral_video";

    /** Un seul fil : une seule requête à la fois, quelle que soit la langue. */
    private static final ExecutorService sIo = Executors.newSingleThreadExecutor();

    private static final Handler sMain = new Handler(Looper.getMainLooper());

    private static final class Ready {
        final File file;
        final long at;

        Ready(File file, long at) {
            this.file = file;
            this.at = at;
        }
    }

    private static final Map<String, Ready> sReady = new HashMap<>();

    /** Ceux qui attendent la réponse en cours, par langue : ⛔ pas deux transferts de la même. */
    private static final Map<String, List<Callback>> sInflight = new HashMap<>();

    /** 🧪 L'aperçu à l'émulateur : une vidéo posée à la main, sans réseau. ⛔ Jamais ailleurs. */
    private static @Nullable File sPreviewFile;

    /**
     * ⭐ La langue de la vidéo = celle de l'IMAGE du statut (fr, en, ar, sinon l'anglais) : une
     * langue sans image reçoit l'image ET la vidéo en anglais (Karim, 2026-10-08).
     */
    public static String language(Context context) {
        return ReferralStatusVideo.statusLanguage(
                ReferralStatusImage.Texts.current(context, 1).language);
    }

    /** Demande la vidéo sans l'attendre : elle sera là quand la feuille s'ouvrira. */
    public static void warmUp(Context context) {
        prepare(context, language(context), file -> {});
    }

    /**
     * Le fichier local de la vidéo de {@code language} (celle de l'IMAGE du statut — ⛔ jamais un
     * repli ici). ⚠️ Une réponse encore fraîche est rendue TOUT DE SUITE, dans l'appel.
     */
    public static void prepare(Context context, String language, Callback done) {
        File known = fresh(language);
        if (known != null) {
            done.onVideo(known);
            return;
        }
        List<Callback> waiting = sInflight.get(language);
        if (waiting != null) {
            waiting.add(done);
            return;
        }
        waiting = new ArrayList<>();
        waiting.add(done);
        sInflight.put(language, waiting);
        File folder = new File(context.getApplicationContext().getFilesDir(), VIDEO_DIR);
        sIo.execute(
                () -> {
                    File file = ReferralStatusVideoLoader.load(folder, language);
                    sMain.post(() -> settle(language, file));
                });
    }

    private static void settle(String language, @Nullable File file) {
        List<Callback> waiting = sInflight.remove(language);
        if (file != null) {
            sReady.put(language, new Ready(file, SystemClock.elapsedRealtime()));
        } else {
            sReady.remove(language);
        }
        if (waiting == null) return;
        for (Callback callback : waiting) callback.onVideo(file);
    }

    /**
     * La réponse encore fraîche, si son fichier est toujours là (Chromium fait le ménage dans
     * {@code files/images/} quand il veut).
     */
    private static @Nullable File fresh(String language) {
        if (sPreviewFile != null) return sPreviewFile.isFile() ? sPreviewFile : null;
        Ready known = sReady.get(language);
        if (known == null) return null;
        if (SystemClock.elapsedRealtime() - known.at > ReferralStatusVideo.FRESH_MS) return null;
        return known.file.isFile() ? known.file : null;
    }

    /** 🧪 L'aperçu à l'émulateur : cette vidéo-là, pour toutes les langues. ⛔ Jamais ailleurs. */
    public static void setFileForPreview(@Nullable File file) {
        sPreviewFile = file;
    }

    /**
     * Où en est la vidéo, telle que la feuille « Partager mon code » s'en sert — port de {@code
     * ReferralStatusVideoWatch} (iOS). Déjà là si le bouton a eu le temps de la faire venir, sinon
     * on l'attend {@link ReferralStatusVideo#WAIT_MS}, puis on s'en passe pour cette fois. 🔴
     * {@link Phase#NONE} ne retire rien : chaque onglet garde son geste d'avant (l'image seule).
     */
    public static final class Watch {
        public enum Phase {
            LOADING,
            READY,
            NONE
        }

        private final Handler mHandler = new Handler(Looper.getMainLooper());
        private Phase mPhase = Phase.LOADING;
        private @Nullable File mFile;
        private boolean mStarted;
        private @Nullable Runnable mOnChange;

        public Phase phase() {
            return mPhase;
        }

        public @Nullable File file() {
            return mFile;
        }

        /**
         * La feuille propose-t-elle la vidéo (deux vignettes, la case « Joindre la vidéo ») ? Oui
         * tant qu'on l'attend encore.
         */
        public boolean offered() {
            return mPhase != Phase.NONE;
        }

        /**
         * @param onChange appelé quand la vidéo arrive, ou qu'on renonce à l'attendre — ⚠️ jamais
         *     pendant cet appel : une vidéo déjà en cache est là au retour, sans rappel.
         */
        public void start(Context context, String language, Runnable onChange) {
            if (mStarted) return;
            mStarted = true;
            prepare(context, language, file -> settle(file == null ? Phase.NONE : Phase.READY, file));
            mOnChange = onChange;
            if (mPhase != Phase.LOADING) return;
            mHandler.postDelayed(() -> settle(Phase.NONE, null), ReferralStatusVideo.WAIT_MS);
        }

        /** La feuille se referme : plus personne à prévenir. */
        public void stop() {
            mHandler.removeCallbacksAndMessages(null);
            mOnChange = null;
        }

        /**
         * Le premier qui répond l'emporte : une vidéo arrivée après le délai ne réorganise pas une
         * feuille déjà lue.
         */
        private void settle(Phase next, @Nullable File file) {
            if (mPhase != Phase.LOADING) return;
            mPhase = next;
            mFile = file;
            mHandler.removeCallbacksAndMessages(null);
            if (mOnChange != null) mOnChange.run();
        }
    }
}
