/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * you can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.basarunaa;

import org.chromium.build.annotations.NullMarked;
import org.chromium.build.annotations.Nullable;

/**
 * POJO partagés pour le pipeline ML Basarunaa Android (Jalon 2.E.3+).
 *
 * <p>Mirroir des types JS du POC `private/extensions/basarunaa/src/detectors/`
 * et `src/core/types.ts`. Tout port natif <b>doit</b> conserver le même
 * format que le POC (règle d'or cross-platform, cf. CLAUDE.md
 * `private/extensions/basarunaa/`).
 */
@NullMarked
public final class BasarunaaTypes {
    private BasarunaaTypes() {}

    /** Bounding box en coordonnées image source (pixels). */
    public static final class Bbox {
        public final float x1;
        public final float y1;
        public final float x2;
        public final float y2;

        public Bbox(float x1, float y1, float x2, float y2) {
            this.x1 = x1;
            this.y1 = y1;
            this.x2 = x2;
            this.y2 = y2;
        }

        public float width() {
            return x2 - x1;
        }

        public float height() {
            return y2 - y1;
        }

        public float area() {
            return Math.max(0f, x2 - x1) * Math.max(0f, y2 - y1);
        }
    }

    /** Keypoint 2D + confidence (COCO 17 ou landmarks face 5). */
    public static final class Keypoint {
        public final float x;
        public final float y;
        public final float confidence;

        public Keypoint(float x, float y, float confidence) {
            this.x = x;
            this.y = y;
            this.confidence = confidence;
        }
    }

    /**
     * Base pour les détections produites par les détecteurs YOLO. Permet
     * à {@link Nms} d'être générique sur tout type de détection.
     */
    public abstract static class Detection {
        public final Bbox bbox;
        public final float confidence;

        protected Detection(Bbox bbox, float confidence) {
            this.bbox = bbox;
            this.confidence = confidence;
        }
    }

    /**
     * Sortie YOLO-pose : bbox personne + 17 keypoints COCO + faceBbox dérivée
     * des 5 premiers keypoints (nez, yeux, oreilles).
     *
     * <p>COCO keypoints : 0=nose, 1=left_eye, 2=right_eye, 3=left_ear,
     * 4=right_ear, 5=left_shoulder, 6=right_shoulder, 7-16=elbows/wrists/
     * hips/knees/ankles.
     */
    public static final class PersonDetection extends Detection {
        public final Keypoint[] keypoints; // length 17
        @Nullable public final Bbox faceBbox;

        public PersonDetection(
                Bbox bbox, float confidence, Keypoint[] keypoints, @Nullable Bbox faceBbox) {
            super(bbox, confidence);
            this.keypoints = keypoints;
            this.faceBbox = faceBbox;
        }
    }

    /**
     * Sortie YOLO-face : bbox face + 5 landmarks (left_eye, right_eye, nose,
     * left_mouth, right_mouth) — exactement ce dont InsightFace norm_crop a
     * besoin.
     */
    public static final class FaceDetection extends Detection {
        /** 5 landmarks ordre YOLO-Face : 0=left_eye, 1=right_eye, 2=nose, 3=left_mouth, 4=right_mouth. */
        public final Keypoint[] landmarks;

        public FaceDetection(Bbox bbox, float confidence, Keypoint[] landmarks) {
            super(bbox, confidence);
            this.landmarks = landmarks;
        }
    }
}
