/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * you can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.basarunaa;

import android.graphics.PointF;

import org.chromium.build.annotations.NullMarked;
import org.chromium.build.annotations.Nullable;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

import org.chromium.chrome.browser.basarunaa.BasarunaaTypes.Bbox;
import org.chromium.chrome.browser.basarunaa.BasarunaaTypes.Keypoint;

/**
 * Build a body-shaped polygon from COCO keypoints — port natif de
 * {@code private/extensions/basarunaa/src/utils/body_polygon.js} (= aussi
 * {@code src/core/body-polygon.ts}).
 *
 * <p>Utilisé pour grayer le background autour du body crop avant que
 * {@link PplcNetClassifier} ne classifie — sinon le classifier voit la
 * scène entière dans la bbox (foule, mobilier) ce qui dégrade gender accuracy.
 *
 * <p>Algorithme :
 * <ol>
 *   <li>Estime la largeur du corps depuis les épaules (kp 5, 6).</li>
 *   <li>Crée 2 points (gauche, droite) par keypoint visible, scalés par
 *       région (tête, épaules, hanche, etc.)</li>
 *   <li>Étend les mains au-delà des poignets (extrapolation coude→poignet).</li>
 *   <li>Étend les pieds sous les chevilles (8% bbox height).</li>
 *   <li>Construit le convex hull (Andrew monotone chain).</li>
 *   <li>Rescale le hull pour remplir la bbox.</li>
 *   <li>Snap aux bords image si la personne est croppée par les bords.</li>
 * </ol>
 */
@NullMarked
public final class BodyPolygon {
    private static final float KP_CONFIDENCE = 0.3f;
    private static final float BODY_WIDTH_FACTOR = 0.55f;
    private static final float HAND_EXTEND = 0.3f;
    private static final float FOOT_EXTEND = 0.08f;
    private static final float EDGE_SNAP_THRESHOLD = 0.05f;
    private static final float NEAR_FRAC = 0.15f;

    private static final float REGION_HEAD = 0.8f; // 0-4
    private static final float REGION_SHOULDER = 1.0f; // 5-6
    private static final float REGION_ELBOW = 0.7f; // 7-8
    private static final float REGION_WRIST = 0.6f; // 9-10
    private static final float REGION_HIP = 1.1f; // 11-12
    private static final float REGION_KNEE = 0.8f; // 13-14
    private static final float REGION_ANKLE = 0.7f; // 15-16

    private BodyPolygon() {}

    public static final class Result {
        public final List<PointF> points;
        public final boolean isBodyShaped;

        Result(List<PointF> points, boolean isBodyShaped) {
            this.points = points;
            this.isBodyShaped = isBodyShaped;
        }
    }

    /**
     * Construit le polygone autour du body. Si moins de 4 keypoints visibles,
     * fallback sur les 4 coins de la bbox.
     *
     * @param keypoints 17 COCO ou null
     * @param bbox bbox body en coords image source
     * @param imgW largeur image source
     * @param imgH hauteur image source
     */
    public static Result build(
            Keypoint @Nullable [] keypoints, Bbox bbox, int imgW, int imgH) {
        final float bw = bbox.width();
        final float bh = bbox.height();

        if (keypoints == null) return bboxFallback(bbox);

        int confidentCount = 0;
        for (Keypoint k : keypoints) {
            if (k != null && k.confidence >= KP_CONFIDENCE) confidentCount++;
        }
        if (confidentCount < 4) return bboxFallback(bbox);

        // Half-width depuis les épaules.
        final Keypoint lSh = keypoints[5];
        final Keypoint rSh = keypoints[6];
        float halfWidth;
        if (lSh.confidence >= KP_CONFIDENCE && rSh.confidence >= KP_CONFIDENCE) {
            halfWidth = Math.abs(rSh.x - lSh.x) * BODY_WIDTH_FACTOR;
        } else {
            halfWidth = bw * 0.25f;
        }
        halfWidth = Math.max(halfWidth, bw * 0.2f);

        final ArrayList<PointF> widened = new ArrayList<>();
        for (int i = 0; i < keypoints.length; i++) {
            final Keypoint k = keypoints[i];
            if (k.confidence < KP_CONFIDENCE) continue;
            final float scale = getRegionScale(i);
            final float w = halfWidth * scale;
            widened.add(new PointF(k.x - w, k.y));
            widened.add(new PointF(k.x + w, k.y));
        }

        // Head padding au-dessus des keypoints head visibles.
        float topY = Float.POSITIVE_INFINITY;
        float headCxSum = 0f;
        int headCount = 0;
        for (int i = 0; i <= 4; i++) {
            final Keypoint k = keypoints[i];
            if (k.confidence < KP_CONFIDENCE) continue;
            if (k.y < topY) topY = k.y;
            headCxSum += k.x;
            headCount++;
        }
        if (headCount > 0) {
            final float headCx = headCxSum / headCount;
            final float headPadY = Math.max(halfWidth * 0.6f, bh * 0.08f);
            final float headPadX = Math.max(halfWidth * 0.9f, bw * 0.25f);
            widened.add(new PointF(headCx - headPadX, topY - headPadY));
            widened.add(new PointF(headCx + headPadX, topY - headPadY));
        }

        // Hand extrapolation : coude→poignet → main extra.
        extendHand(keypoints, 7, 9, halfWidth, widened);
        extendHand(keypoints, 8, 10, halfWidth, widened);

        // Foot extension : ankle + footExtend en y.
        final float footExtend = bh * FOOT_EXTEND;
        for (int ankleIdx : new int[] {15, 16}) {
            final Keypoint ankle = keypoints[ankleIdx];
            if (ankle.confidence < KP_CONFIDENCE) continue;
            final float w = halfWidth * REGION_ANKLE;
            widened.add(new PointF(ankle.x - w, ankle.y + footExtend));
            widened.add(new PointF(ankle.x + w, ankle.y + footExtend));
        }

        // Convex hull.
        final List<PointF> hull = convexHull(widened);
        if (hull.size() < 3) return bboxFallback(bbox);

        // Rescale pour remplir la bbox.
        float polyMinX = Float.POSITIVE_INFINITY, polyMaxX = Float.NEGATIVE_INFINITY;
        float polyMinY = Float.POSITIVE_INFINITY, polyMaxY = Float.NEGATIVE_INFINITY;
        for (PointF p : hull) {
            if (p.x < polyMinX) polyMinX = p.x;
            if (p.x > polyMaxX) polyMaxX = p.x;
            if (p.y < polyMinY) polyMinY = p.y;
            if (p.y > polyMaxY) polyMaxY = p.y;
        }
        final float polyCx = (polyMinX + polyMaxX) / 2f;
        final float polyCy = (polyMinY + polyMaxY) / 2f;
        final float bboxCx = (bbox.x1 + bbox.x2) / 2f;
        final float bboxCy = (bbox.y1 + bbox.y2) / 2f;
        final float dx = polyMaxX - polyMinX;
        final float dy = polyMaxY - polyMinY;
        final float sx = bw / (dx == 0f ? 1f : dx);
        final float sy = bh / (dy == 0f ? 1f : dy);

        final ArrayList<PointF> scaled = new ArrayList<>(hull.size());
        for (PointF p : hull) {
            scaled.add(new PointF(
                    bboxCx + (p.x - polyCx) * sx,
                    bboxCy + (p.y - polyCy) * sy));
        }

        // Edge snapping si la personne touche les bords.
        final List<PointF> snapped = snapToEdges(scaled, bbox, imgW, imgH, keypoints);

        return new Result(snapped, true);
    }

    /**
     * Teste si un point (x, y) est à l'intérieur du polygone via raycast.
     * Utilisé par {@link PplcNetClassifier} pour grayer hors polygon.
     */
    public static boolean contains(List<PointF> polygon, float x, float y) {
        boolean inside = false;
        final int n = polygon.size();
        for (int i = 0, j = n - 1; i < n; j = i++) {
            final PointF a = polygon.get(i);
            final PointF b = polygon.get(j);
            if (((a.y > y) != (b.y > y))
                    && (x < (b.x - a.x) * (y - a.y) / (b.y - a.y) + a.x)) {
                inside = !inside;
            }
        }
        return inside;
    }

    private static float getRegionScale(int idx) {
        if (idx <= 4) return REGION_HEAD;
        if (idx <= 6) return REGION_SHOULDER;
        if (idx <= 8) return REGION_ELBOW;
        if (idx <= 10) return REGION_WRIST;
        if (idx <= 12) return REGION_HIP;
        if (idx <= 14) return REGION_KNEE;
        return REGION_ANKLE;
    }

    private static void extendHand(
            Keypoint[] kps, int elbowIdx, int wristIdx, float halfWidth,
            ArrayList<PointF> out) {
        final Keypoint elbow = kps[elbowIdx];
        final Keypoint wrist = kps[wristIdx];
        if (elbow.confidence < KP_CONFIDENCE || wrist.confidence < KP_CONFIDENCE) return;
        final float dxL = wrist.x - elbow.x;
        final float dyL = wrist.y - elbow.y;
        final float hx = wrist.x + dxL * HAND_EXTEND;
        final float hy = wrist.y + dyL * HAND_EXTEND;
        final float w = halfWidth * 0.6f;
        out.add(new PointF(hx - w, hy));
        out.add(new PointF(hx + w, hy));
    }

    private static List<PointF> snapToEdges(
            List<PointF> points, Bbox bbox, int imgW, int imgH, Keypoint[] keypoints) {
        boolean hasAnkles = false;
        boolean hasHead = false;
        for (int i : new int[] {15, 16}) {
            if (keypoints[i].confidence >= KP_CONFIDENCE) {
                hasAnkles = true;
                break;
            }
        }
        for (int i : new int[] {0, 1, 2}) {
            if (keypoints[i].confidence >= KP_CONFIDENCE) {
                hasHead = true;
                break;
            }
        }
        final boolean snapBottom = !hasAnkles && bbox.y2 / imgH > (1f - EDGE_SNAP_THRESHOLD);
        final boolean snapTop = !hasHead && bbox.y1 / imgH < EDGE_SNAP_THRESHOLD;
        final boolean snapLeft = bbox.x1 / imgW < EDGE_SNAP_THRESHOLD;
        final boolean snapRight = bbox.x2 / imgW > (1f - EDGE_SNAP_THRESHOLD);
        if (!snapBottom && !snapTop && !snapLeft && !snapRight) return points;

        float minX = Float.POSITIVE_INFINITY, maxX = Float.NEGATIVE_INFINITY;
        float minY = Float.POSITIVE_INFINITY, maxY = Float.NEGATIVE_INFINITY;
        for (PointF p : points) {
            if (p.x < minX) minX = p.x;
            if (p.x > maxX) maxX = p.x;
            if (p.y < minY) minY = p.y;
            if (p.y > maxY) maxY = p.y;
        }
        final float xRange = Math.max(1f, maxX - minX);
        final float yRange = Math.max(1f, maxY - minY);

        final ArrayList<PointF> out = new ArrayList<>(points.size());
        for (PointF p : points) {
            float x = p.x;
            float y = p.y;
            if (snapBottom && y > maxY - yRange * NEAR_FRAC) y = imgH;
            if (snapTop && y < minY + yRange * NEAR_FRAC) y = 0f;
            if (snapLeft && x < minX + xRange * NEAR_FRAC) x = 0f;
            if (snapRight && x > maxX - xRange * NEAR_FRAC) x = imgW;
            out.add(new PointF(x, y));
        }
        return out;
    }

    private static Result bboxFallback(Bbox bbox) {
        final ArrayList<PointF> pts = new ArrayList<>(4);
        pts.add(new PointF(bbox.x1, bbox.y1));
        pts.add(new PointF(bbox.x2, bbox.y1));
        pts.add(new PointF(bbox.x2, bbox.y2));
        pts.add(new PointF(bbox.x1, bbox.y2));
        return new Result(pts, false);
    }

    /** Andrew's monotone chain convex hull. */
    private static List<PointF> convexHull(List<PointF> points) {
        if (points.size() < 3) return new ArrayList<>(points);
        final ArrayList<PointF> sorted = new ArrayList<>(points);
        sorted.sort(Comparator.comparing((PointF p) -> p.x).thenComparing(p -> p.y));
        final int n = sorted.size();

        final ArrayList<PointF> lower = new ArrayList<>();
        for (int i = 0; i < n; i++) {
            while (lower.size() >= 2
                    && cross(lower.get(lower.size() - 2),
                            lower.get(lower.size() - 1), sorted.get(i)) <= 0f) {
                lower.remove(lower.size() - 1);
            }
            lower.add(sorted.get(i));
        }
        final ArrayList<PointF> upper = new ArrayList<>();
        for (int i = n - 1; i >= 0; i--) {
            while (upper.size() >= 2
                    && cross(upper.get(upper.size() - 2),
                            upper.get(upper.size() - 1), sorted.get(i)) <= 0f) {
                upper.remove(upper.size() - 1);
            }
            upper.add(sorted.get(i));
        }
        lower.remove(lower.size() - 1);
        upper.remove(upper.size() - 1);
        lower.addAll(upper);
        return lower;
    }

    private static float cross(PointF o, PointF a, PointF b) {
        return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
    }
}
