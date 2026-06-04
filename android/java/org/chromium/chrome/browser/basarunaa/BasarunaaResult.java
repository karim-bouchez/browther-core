/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.basarunaa;

import org.chromium.build.annotations.NullMarked;

/**
 * Résultat d'une analyse ML (Jalon 2.D = stub vide, sera enrichi au Jalon 2.E).
 *
 * <p>{@link #personsJson} = JSON array conforme au type {@code Person} du core
 * POC TS (cf. {@code private/extensions/basarunaa/src/core/types.ts}). Vide
 * tant que le pipeline n'est pas câblé.
 *
 * <p>{@link #decision} = "keep" (aucune personne à flouter, image inerte),
 * "blur" (au moins 1 personne à flouter), "nsfw" (full-image blur).
 */
@NullMarked
public final class BasarunaaResult {
    public final int imageId;
    public final String decision;
    public final String personsJson;
    public final double elapsedMs;

    public BasarunaaResult(int imageId, String decision, String personsJson, double elapsedMs) {
        this.imageId = imageId;
        this.decision = decision;
        this.personsJson = personsJson;
        this.elapsedMs = elapsedMs;
    }

    /** Stub Jalon 2.D : retourne un verdict "keep" instantané, JSON vide. */
    public static BasarunaaResult empty(int imageId) {
        return new BasarunaaResult(imageId, "keep", "[]", 0.0);
    }
}
