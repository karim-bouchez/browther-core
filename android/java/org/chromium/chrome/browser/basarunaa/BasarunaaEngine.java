/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.basarunaa;

import org.chromium.base.Log;
import org.chromium.build.annotations.NullMarked;
import org.chromium.build.annotations.Nullable;

import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Singleton ML engine pour Basarunaa Android.
 *
 * <p><b>Jalon 2.D — STUB.</b> {@link #analyze} retourne {@link BasarunaaResult#empty}
 * immédiatement. Permet de valider la chaîne complète Mojo + JNI + reply
 * sans investir dans le pipeline ML (Jalon 2.E).
 *
 * <p><b>Jalon 2.E</b> : portera 4 sessions ORT (yolo-pose, yolo-face, genderage,
 * nanodet) chargées paresseusement au premier {@link #analyze} (lazy load
 * synchronized double-check), dispatcheur {@link PersonMatcher} + face align
 * + gender fusion, sérialisation {@link BasarunaaPersonJson}. Pipeline
 * séquentiel single-thread car ORT YOLO-pose 298 ms (cf. Jalon 1 bench Huawei)
 * + on évite 2 sessions concurrentes qui monopolisent les CPU cores plus
 * longtemps qu'en séquentiel.
 *
 * <p>Le pool {@link #PIPELINE_EXEC} est statique partagé inter-tabs : on
 * sérialise vraiment 1 image à la fois sur tout le navigateur (justifié car
 * user voit une image à la fois en pratique, les bursts MutationObserver
 * peuvent attendre — la queue côté {@link BasarunaaTabAnalyzer} amortit).
 */
@NullMarked
public final class BasarunaaEngine {
    private static final String TAG = "Basarunaa";

    /** Pool single-thread global : 1 inférence ML à la fois sur tout le browser. */
    public static final ExecutorService PIPELINE_EXEC =
            Executors.newSingleThreadExecutor(r -> new Thread(r, "Basarunaa-Pipeline"));

    @Nullable private static volatile BasarunaaEngine sInstance;

    public static BasarunaaEngine getInstance() {
        BasarunaaEngine local = sInstance;
        if (local == null) {
            synchronized (BasarunaaEngine.class) {
                local = sInstance;
                if (local == null) {
                    local = new BasarunaaEngine();
                    sInstance = local;
                }
            }
        }
        return local;
    }

    private BasarunaaEngine() {
        Log.i(TAG, "[Engine] singleton created (stub Jalon 2.D — ML pipeline Jalon 2.E)");
    }

    /**
     * Analyse une image encodée (JPEG/PNG/WEBP) et retourne le verdict ML.
     *
     * <p>Jalon 2.D : ignore {@code bytes} et retourne {@link BasarunaaResult#empty}.
     * Pas de modification DOM côté JS attendue (decision="keep" → toutes les
     * images restent en hide-first jusqu'à 2.E qui posera les vrais verdicts).
     *
     * @param imageId data-basarunaa-id côté DOM
     * @param bytes JPEG/PNG/WEBP encodés
     * @param mode "blur-female" | "blur-male" | "blur-all"
     * @param confBody 0.0-1.0
     * @param confFace 0.0-1.0
     * @param genderCertainty 0.0-1.0
     * @return verdict ML
     */
    public BasarunaaResult analyze(int imageId, byte[] bytes, String mode,
                                   double confBody, double confFace,
                                   double genderCertainty) {
        // Jalon 2.D stub : log + return empty.
        Log.i(TAG, "[Engine] analyze stub imageId=%d bytes=%d mode=%s",
                imageId, bytes.length, mode);
        return BasarunaaResult.empty(imageId);
    }
}
