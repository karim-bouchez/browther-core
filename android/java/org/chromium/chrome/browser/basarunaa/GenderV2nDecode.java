// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

package org.chromium.chrome.browser.basarunaa;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

/**
 * Décodage PUR du modèle single-shot gender-v2n {@code [1, C, N]} → persons.
 *
 * <p>AUCUNE dépendance ORT/Android → compilable et testable en standalone
 * ({@code javac}) contre le golden {@code tests/golden/gender-v2n/} sans OVH ni
 * device.
 *
 * <p>Spec de référence (contrat cross-langage) :
 * {@code private/extensions/basarunaa/tests/golden/gender-v2n/DECODE_SPEC.md}.
 * Port ligne-à-ligne de {@code src/detectors/yolo_gender_pose.js} (+ yolo_pose.js,
 * nms.js) — parité vérifiée par le golden. Toute divergence = dette silencieuse.
 *
 * <p>C = 4 (xywh) + numClasses (3 scores) + 3*numKeypoints (17×xyc) = 58.
 * L'accès au tenseur est abstrait par {@link ValueAccessor} : le golden passe un
 * layout dense {@code raw[c*N+i]}, la prod passera un accès ORT (float/strides) —
 * le décodage lui est identique.
 */
public final class GenderV2nDecode {
    public static final double DEFAULT_CONF_THRESHOLD = 0.25;
    public static final double DEFAULT_IOU_THRESHOLD = 0.5;
    public static final double DEFAULT_FACE_PADDING = 0.4;
    /** Seuil de visibilité d'un keypoint pour la dérivation faceBbox (parité JS). */
    public static final double FACE_KP_VISIBLE_THRESHOLD = 0.3;

    /** GenderClass : Male=0, Female=1, Child=2 (aligné core/gender.ts). */
    public static final int MALE = 0;
    public static final int FEMALE = 1;
    public static final int CHILD = 2;

    /** Accès abstrait au tenseur : valeur du canal {@code channel} pour la détection {@code det}. */
    public interface ValueAccessor {
        double get(int channel, int det);
    }

    public static final class Keypoint {
        public final double x;
        public final double y;
        public final double confidence;

        public Keypoint(double x, double y, double confidence) {
            this.x = x;
            this.y = y;
            this.confidence = confidence;
        }
    }

    /**
     * Détection brute — pur extracteur, AUCUNE décision de flou ici (la policy
     * vit dans {@code core/policy.ts}, appliquée côté bundle TS android/).
     */
    public static final class PersonRaw {
        /** {@code [x1, y1, x2, y2]} en pixels image source (peut sortir du cadre). */
        public final double[] bbox;
        /** Score de la classe gagnante (= genderConfidence). */
        public final double confidence;
        /** GenderClass gagnante (MALE/FEMALE/CHILD). */
        public final int genderClass;
        /** 17 keypoints COCO en pixels image source. */
        public final Keypoint[] keypoints;
        /** {@code [x1, y1, x2, y2]} dérivée des kpts visage (0..4), ou null. */
        public final double[] faceBbox;

        public PersonRaw(
                double[] bbox,
                double confidence,
                int genderClass,
                Keypoint[] keypoints,
                double[] faceBbox) {
            this.bbox = bbox;
            this.confidence = confidence;
            this.genderClass = genderClass;
            this.keypoints = keypoints;
            this.faceBbox = faceBbox;
        }
    }

    private GenderV2nDecode() {}

    /** Décode {@code [1, numChannels, numDetections]} → persons (post-NMS). */
    public static List<PersonRaw> decode(
            int numChannels,
            int numDetections,
            int numClasses,
            int numKeypoints,
            double scale,
            double padX,
            double padY,
            double srcWidth,
            double srcHeight,
            double confThreshold,
            double iouThreshold,
            double facePadding,
            ValueAccessor value) {
        final int kptOffset = 4 + numClasses; // 7
        List<PersonRaw> boxes = new ArrayList<>();

        for (int i = 0; i < numDetections; i++) {
            // Score = argmax des scores de classe. `>` strict → 1er max gagne (parité JS).
            double score = 0.0;
            int cls = 0;
            for (int k = 0; k < numClasses; k++) {
                double s = value.get(4 + k, i);
                if (s > score) {
                    score = s;
                    cls = k;
                }
            }
            if (score < confThreshold) {
                continue;
            }

            double cx = value.get(0, i);
            double cy = value.get(1, i);
            double w = value.get(2, i);
            double h = value.get(3, i);

            double x1 = Math.max(0, (cx - w / 2 - padX) / scale);
            double y1 = Math.max(0, (cy - h / 2 - padY) / scale);
            double x2 = Math.min(srcWidth, (cx + w / 2 - padX) / scale);
            double y2 = Math.min(srcHeight, (cy + h / 2 - padY) / scale);

            Keypoint[] keypoints = new Keypoint[numKeypoints];
            for (int k = 0; k < numKeypoints; k++) {
                int base = kptOffset + k * 3;
                double kx = (value.get(base, i) - padX) / scale;
                double ky = (value.get(base + 1, i) - padY) / scale;
                double kc = value.get(base + 2, i);
                keypoints[k] = new Keypoint(kx, ky, kc);
            }

            double[] faceBbox = deriveFaceBbox(keypoints, srcWidth, srcHeight, facePadding);

            boxes.add(new PersonRaw(new double[] {x1, y1, x2, y2}, score, cls, keypoints, faceBbox));
        }

        return nms(boxes, iouThreshold);
    }

    /**
     * faceBbox carrée dérivée des kpts 0..4 (nez, yeux, oreilles), parité
     * {@code yolo_pose.js:_deriveFaceBbox}. Visible = conf > 0.3 ; < 2 visibles → null.
     */
    static double[] deriveFaceBbox(
            Keypoint[] keypoints, double srcWidth, double srcHeight, double facePadding) {
        if (keypoints.length < 5) {
            return null;
        }
        List<Keypoint> visible = new ArrayList<>();
        for (int i = 0; i < 5; i++) {
            if (keypoints[i].confidence > FACE_KP_VISIBLE_THRESHOLD) {
                visible.add(keypoints[i]);
            }
        }
        if (visible.size() < 2) {
            return null;
        }

        double minX = Double.POSITIVE_INFINITY;
        double minY = Double.POSITIVE_INFINITY;
        double maxX = Double.NEGATIVE_INFINITY;
        double maxY = Double.NEGATIVE_INFINITY;
        for (Keypoint kp : visible) {
            minX = Math.min(minX, kp.x);
            minY = Math.min(minY, kp.y);
            maxX = Math.max(maxX, kp.x);
            maxY = Math.max(maxY, kp.y);
        }

        double w = maxX - minX;
        double h = maxY - minY;
        double size = Math.max(w, h); // carré
        double centerX = (minX + maxX) / 2;
        double centerY = (minY + maxY) / 2;
        double halfSize = (size * (1 + facePadding)) / 2;

        return new double[] {
            Math.max(0, centerX - halfSize),
            Math.max(0, centerY - halfSize),
            Math.min(srcWidth, centerX + halfSize),
            Math.min(srcHeight, centerY + halfSize),
        };
    }

    /**
     * NMS class-agnostic gloutonne (parité {@code nms.js}) : tri par confidence
     * décroissante, on garde la meilleure et retire les restantes avec IoU > seuil.
     */
    static List<PersonRaw> nms(List<PersonRaw> boxes, double iouThreshold) {
        if (boxes.isEmpty()) {
            return new ArrayList<>();
        }
        List<PersonRaw> sorted = new ArrayList<>(boxes);
        // Tri stable par confidence décroissante (Collections.sort est stable).
        sorted.sort(Comparator.comparingDouble((PersonRaw p) -> p.confidence).reversed());
        List<PersonRaw> kept = new ArrayList<>();
        for (PersonRaw det : sorted) {
            boolean suppressed = false;
            for (PersonRaw keptDet : kept) {
                if (iou(det.bbox, keptDet.bbox) > iouThreshold) {
                    suppressed = true;
                    break;
                }
            }
            if (!suppressed) {
                kept.add(det);
            }
        }
        return kept;
    }

    /** IoU sur {@code [x1,y1,x2,y2]} (parité {@code nms.js:iou}). */
    static double iou(double[] a, double[] b) {
        double x1 = Math.max(a[0], b[0]);
        double y1 = Math.max(a[1], b[1]);
        double x2 = Math.min(a[2], b[2]);
        double y2 = Math.min(a[3], b[3]);
        double inter = Math.max(0, x2 - x1) * Math.max(0, y2 - y1);
        if (inter == 0) {
            return 0;
        }
        double areaA = (a[2] - a[0]) * (a[3] - a[1]);
        double areaB = (b[2] - b[0]) * (b[3] - b[1]);
        return inter / (areaA + areaB - inter);
    }
}
