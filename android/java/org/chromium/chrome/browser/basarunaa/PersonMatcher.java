/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * you can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.basarunaa;

import org.chromium.build.annotations.NullMarked;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;

import org.chromium.chrome.browser.basarunaa.BasarunaaTypes.Bbox;
import org.chromium.chrome.browser.basarunaa.BasarunaaTypes.FaceDetection;
import org.chromium.chrome.browser.basarunaa.BasarunaaTypes.PersonDetection;

/**
 * Matching faces ↔ bodies — port natif de
 * {@code private/extensions/basarunaa/src/pipeline.js#_matchFacesToBodies}.
 *
 * <p>Algorithme global optimal greedy :
 * <ol>
 *   <li>Pour chaque couple (body, face), calcule la distance entre le centre
 *       de la face et la position attendue (centre horizontal du body, 15%
 *       depuis le haut de la bbox body).</li>
 *   <li>Filtre les faces dont la bbox n'est pas entièrement contenue dans
 *       la bbox body (sécurité contre les fausses associations en cas de
 *       crowd).</li>
 *   <li>Trie les couples par distance croissante.</li>
 *   <li>Assigne greedily : pour chaque couple, si ni le body ni la face
 *       n'est déjà utilisé, créer l'association.</li>
 * </ol>
 *
 * <p>Comportement identique au POC JS (l'ordre des couples sortis du sort
 * détermine quelle face est gagnante en cas de tie sur un body — Java
 * Arrays.sort est stable comme V8).
 */
@NullMarked
public final class PersonMatcher {
    private PersonMatcher() {}

    /** Pair body↔face avec l'index original de la face dans la liste source. */
    public static final class Match {
        public final int bodyIndex;
        public final int faceIndex;
        public final FaceDetection face;

        Match(int bodyIndex, int faceIndex, FaceDetection face) {
            this.bodyIndex = bodyIndex;
            this.faceIndex = faceIndex;
            this.face = face;
        }
    }

    /**
     * @return map bodyIndex → Match (subset des bodies effectivement matchés).
     */
    public static Map<Integer, Match> match(
            List<PersonDetection> bodies, List<FaceDetection> faces) {
        if (bodies.isEmpty() || faces.isEmpty()) {
            return Collections.emptyMap();
        }

        // Construit tous les couples valides + leur distance.
        final ArrayList<Candidate> pairs = new ArrayList<>();
        for (int bi = 0; bi < bodies.size(); bi++) {
            final Bbox bb = bodies.get(bi).bbox;
            final float bCx = (bb.x1 + bb.x2) / 2f;
            final float bFaceY = bb.y1 + (bb.y2 - bb.y1) * 0.15f;

            for (int fi = 0; fi < faces.size(); fi++) {
                final Bbox fb = faces.get(fi).bbox;
                // Containment strict : face entièrement dans body.
                if (fb.x1 < bb.x1 || fb.y1 < bb.y1 || fb.x2 > bb.x2 || fb.y2 > bb.y2) {
                    continue;
                }
                final float fcx = (fb.x1 + fb.x2) / 2f;
                final float fcy = (fb.y1 + fb.y2) / 2f;
                final float dx = fcx - bCx;
                final float dy = fcy - bFaceY;
                final float dist = (float) Math.hypot(dx, dy);
                pairs.add(new Candidate(bi, fi, dist));
            }
        }

        // Tri par distance croissante.
        pairs.sort(Comparator.comparingDouble(c -> c.dist));

        final HashMap<Integer, Match> result = new HashMap<>();
        final HashSet<Integer> usedBodies = new HashSet<>();
        final HashSet<Integer> usedFaces = new HashSet<>();
        for (Candidate c : pairs) {
            if (usedBodies.contains(c.bodyIndex) || usedFaces.contains(c.faceIndex)) {
                continue;
            }
            result.put(c.bodyIndex, new Match(c.bodyIndex, c.faceIndex, faces.get(c.faceIndex)));
            usedBodies.add(c.bodyIndex);
            usedFaces.add(c.faceIndex);
        }
        return result;
    }

    private static final class Candidate {
        final int bodyIndex;
        final int faceIndex;
        final float dist;

        Candidate(int bodyIndex, int faceIndex, float dist) {
            this.bodyIndex = bodyIndex;
            this.faceIndex = faceIndex;
            this.dist = dist;
        }
    }
}
