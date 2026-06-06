/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * you can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.basarunaa;

import android.graphics.Bitmap;
import android.util.Base64;

import org.chromium.build.annotations.NullMarked;
import org.chromium.build.annotations.Nullable;

import java.io.ByteArrayOutputStream;

/**
 * Helper pour transformer un Bitmap en data URL JPEG/PNG utilisable côté JS
 * (debug overlay {@code faceCropDataUrl} / {@code bodyCropDataUrl}).
 *
 * <p>Format produit : {@code "data:image/jpeg;base64,<base64>"}.
 */
@NullMarked
public final class BitmapDataUrl {
    private BitmapDataUrl() {}

    /** Encode JPEG (quality 70 par défaut, bon compromis taille / lisibilité). */
    @Nullable
    public static String encodeJpeg(@Nullable Bitmap bitmap) {
        if (bitmap == null) return null;
        try (ByteArrayOutputStream baos = new ByteArrayOutputStream(8192)) {
            if (!bitmap.compress(Bitmap.CompressFormat.JPEG, 70, baos)) {
                return null;
            }
            final String base64 = Base64.encodeToString(baos.toByteArray(), Base64.NO_WRAP);
            return "data:image/jpeg;base64," + base64;
        } catch (Throwable t) {
            return null;
        }
    }
}
