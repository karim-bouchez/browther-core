/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * you can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.basarunaa;

import org.chromium.build.annotations.NullMarked;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;

import org.chromium.chrome.browser.basarunaa.BasarunaaTypes.Bbox;
import org.chromium.chrome.browser.basarunaa.BasarunaaTypes.Detection;

/**
 * Non-Maximum Suppression — port natif de
 * {@code private/extensions/basarunaa/src/utils/nms.js}.
 *
 * <p>Algorithme identique : tri descendant par confidence, on garde le meilleur,
 * on supprime ceux dont l'IoU > seuil avec lui, on recommence.
 */
@NullMarked
public final class Nms {
    private Nms() {}

    /** Supprime les détections en overlap, retourne la liste filtrée. */
    public static <T extends Detection> List<T> suppress(List<T> detections, float iouThreshold) {
        if (detections.isEmpty()) {
            return Collections.emptyList();
        }
        final ArrayList<T> sorted = new ArrayList<>(detections);
        sorted.sort(Comparator.comparingDouble((T d) -> -d.confidence));

        final ArrayList<T> kept = new ArrayList<>();
        while (!sorted.isEmpty()) {
            final T best = sorted.remove(0);
            kept.add(best);
            for (int i = sorted.size() - 1; i >= 0; i--) {
                if (iou(best.bbox, sorted.get(i).bbox) > iouThreshold) {
                    sorted.remove(i);
                }
            }
        }
        return kept;
    }

    /** IoU classique sur 2 bboxes. */
    static float iou(Bbox a, Bbox b) {
        final float x1 = Math.max(a.x1, b.x1);
        final float y1 = Math.max(a.y1, b.y1);
        final float x2 = Math.min(a.x2, b.x2);
        final float y2 = Math.min(a.y2, b.y2);
        final float intersection = Math.max(0f, x2 - x1) * Math.max(0f, y2 - y1);
        if (intersection == 0f) return 0f;
        final float areaA = a.area();
        final float areaB = b.area();
        return intersection / (areaA + areaB - intersection);
    }
}
