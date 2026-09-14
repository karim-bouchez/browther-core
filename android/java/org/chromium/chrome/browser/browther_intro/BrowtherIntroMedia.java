/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_intro;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BlurMaskFilter;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Path;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import org.chromium.base.Log;

import java.io.IOException;
import java.util.ArrayList;
import java.util.List;

/**
 * Les médias de l'introduction et leur <b>floutage pré-calculé</b>.
 *
 * <p>Pourquoi pré-calculé : faire tourner le modèle pendant l'écran coûterait un chargement, un
 * délai variable et un rendu qui dépend du téléphone, pour une scène connue d'avance. Le vrai
 * pipeline a tourné une fois sur Mac ({@code render_intro_media.mjs}), et l'app embarque son
 * résultat : par personne, le contour du voile, son genre et la confiance. L'app ne fait plus que
 * poser le voile — le choix « les femmes / les hommes / les deux » reste vivant à l'écran.
 *
 * <p>🔴 Mêmes fichiers que l'iOS et le desktop (ONBOARDING-SPEC.md § 6).
 */
final class BrowtherIntroMedia {
    private static final String TAG = "BrowtherIntro";

    static final String PHOTO = BrowtherIntroUi.ASSETS + "browther-intro-photo.jpg";
    static final String VIDEO = BrowtherIntroUi.ASSETS + "browther-intro-video.mp4";
    static final String AUDIO_BEFORE = BrowtherIntroUi.ASSETS + "browther-intro-audio-before.m4a";
    static final String AUDIO_AFTER = BrowtherIntroUi.ASSETS + "browther-intro-audio-after.m4a";

    /** Largeurs d'encodage des médias : le flou et l'adoucissement sont en pixels DU MÉDIA. */
    static final int PHOTO_WIDTH = 1200;
    static final int VIDEO_WIDTH = 900;

    /**
     * Ce que le voile couvre.
     *
     * <p>⚠️ {@code EVERYTHING} n'est pas un réglage du moteur : c'est l'état <b>avant</b> que la
     * personne allume le floutage. ⛔ On ne montre pas en clair ce que l'app existe pour cacher, à
     * quelqu'un qui n'a rien demandé.
     */
    enum VeilKind {
        /** Rideau : l'état initial. */
        EVERYTHING,
        /** Rien de couvert : l'« avant » assumé, une fois le floutage allumé puis éteint. */
        NOTHING,
        /** Le voile ciblé. */
        TARGET
    }

    /** Le mode du voile, comparable. */
    static final class Veil {
        final VeilKind mKind;
        final BrowtherIntroModel.BlurTarget mTarget;

        Veil(VeilKind kind, BrowtherIntroModel.BlurTarget target) {
            mKind = kind;
            mTarget = target;
        }

        static Veil of(BrowtherIntroModel model) {
            if (model.isBlurDemoOn()) return new Veil(VeilKind.TARGET, model.getBlurTarget());
            return new Veil(model.isBlurDemoEverOn() ? VeilKind.NOTHING : VeilKind.EVERYTHING, null);
        }

        @Override
        public boolean equals(Object other) {
            if (!(other instanceof Veil)) return false;
            Veil veil = (Veil) other;
            return mKind == veil.mKind && (mKind != VeilKind.TARGET || mTarget == veil.mTarget);
        }

        @Override
        public int hashCode() {
            return mKind.hashCode() * 31 + (mTarget == null ? 0 : mTarget.hashCode());
        }
    }

    /** Une personne détectée, en coordonnées relatives (0…1). */
    static final class Person {
        /** Contour du voile, déjà dilaté par le moteur : x0, y0, x1, y1… */
        final float[] mPoly;

        final String mGender;
        final double mConfidence;

        Person(float[] poly, String gender, double confidence) {
            mPoly = poly;
            mGender = gender;
            mConfidence = confidence;
        }

        /**
         * Faut-il flouter cette personne pour ce choix ?
         *
         * <p>⚠️ Même règle que le moteur ({@code src/core/policy.ts}) : la cible choisie, <b>plus
         * tout ce dont le genre n'est pas sûr</b>. Dans le doute, on floute — une prévisualisation
         * plus permissive que l'app mentirait sur ce qu'elle fait.
         */
        boolean isBlurred(BrowtherIntroModel.BlurTarget target) {
            switch (target) {
                case BOTH:
                    return true;
                case WOMEN:
                    if ("female".equals(mGender)) return true;
                    break;
                case MEN:
                    if ("male".equals(mGender)) return true;
                    break;
            }
            return mConfidence < 0.70;
        }
    }

    /** Les personnes d'une vidéo, échantillonnées à {@code fps} images par seconde. */
    static final class Track {
        final double mFps;
        final List<List<Person>> mFrames;

        Track(double fps, List<List<Person>> frames) {
            mFps = fps;
            mFrames = frames;
        }

        /**
         * Les personnes à l'instant {@code seconds}. On prend l'échantillon le plus proche : les
         * contours sont calculés à 8 images/s alors que la lecture tourne à 24 — interpoler
         * n'apporterait rien à cette échelle, le voile est large et adouci.
         */
        int indexAt(double seconds) {
            if (mFrames.isEmpty()) return -1;
            int index = (int) Math.round(seconds * mFps);
            return Math.max(0, Math.min(mFrames.size() - 1, index));
        }
    }

    private BrowtherIntroMedia() {}

    // -------------------- Lecture des JSON --------------------

    static List<Person> loadPhotoPersons(Context context) {
        try {
            JSONObject file =
                    new JSONObject(
                            BrowtherIntroUi.readAsset(
                                    context, BrowtherIntroUi.ASSETS + "browther-intro-photo.json"));
            return parsePersons(file.getJSONArray("persons"));
        } catch (IOException | JSONException e) {
            Log.e(TAG, "Voile de la photo illisible", e);
            return new ArrayList<>();
        }
    }

    static Track loadVideoTrack(Context context) {
        try {
            JSONObject file =
                    new JSONObject(
                            BrowtherIntroUi.readAsset(
                                    context, BrowtherIntroUi.ASSETS + "browther-intro-video.json"));
            JSONArray frames = file.getJSONArray("frames");
            List<List<Person>> list = new ArrayList<>(frames.length());
            for (int i = 0; i < frames.length(); i++) {
                list.add(parsePersons(frames.getJSONObject(i).getJSONArray("persons")));
            }
            return new Track(file.getDouble("fps"), list);
        } catch (IOException | JSONException e) {
            Log.e(TAG, "Voile de la vidéo illisible", e);
            return new Track(8, new ArrayList<>());
        }
    }

    private static List<Person> parsePersons(JSONArray array) throws JSONException {
        List<Person> persons = new ArrayList<>(array.length());
        for (int i = 0; i < array.length(); i++) {
            JSONObject person = array.getJSONObject(i);
            JSONArray poly = person.getJSONArray("poly");
            float[] points = new float[poly.length() * 2];
            for (int p = 0; p < poly.length(); p++) {
                JSONArray point = poly.getJSONArray(p);
                points[p * 2] = (float) point.getDouble(0);
                points[p * 2 + 1] = (float) point.getDouble(1);
            }
            persons.add(
                    new Person(points, person.getString("gender"), person.getDouble("confidence")));
        }
        return persons;
    }

    // -------------------- Le compositeur --------------------

    /** {@code blurRadiusForImage} du compositeur : {@code max(25, 4 % du plus grand côté)}. */
    static float blurRadius(int width, int height) {
        return Math.max(25f, Math.round(Math.max(width, height) * 0.04f));
    }

    /**
     * Le masque du compositeur, dans {@code mask} : les contours remplis puis adoucis de 10 px du
     * média ({@code featherPx}, déjà mis à l'échelle du masque). Blanc = voilé.
     */
    static void drawMask(
            Bitmap mask,
            List<Person> persons,
            Veil veil,
            float featherPx,
            Paint paint,
            Path path) {
        mask.eraseColor(Color.TRANSPARENT);
        if (veil.mKind == VeilKind.NOTHING) return;
        if (veil.mKind == VeilKind.EVERYTHING) {
            mask.eraseColor(Color.WHITE);
            return;
        }
        Canvas canvas = new Canvas(mask);
        int width = mask.getWidth();
        int height = mask.getHeight();
        paint.reset();
        paint.setAntiAlias(true);
        paint.setColor(Color.WHITE);
        // BlurMaskFilter prend un rayon ; Skia en déduit sigma ≈ 0,57735·r + 0,5. Le compositeur
        // adoucit d'un écart type de 10 px du média.
        float radius = Math.max(0.5f, (featherPx - 0.5f) / 0.57735f);
        paint.setMaskFilter(new BlurMaskFilter(radius, BlurMaskFilter.Blur.NORMAL));
        for (Person person : persons) {
            if (!person.isBlurred(veil.mTarget) || person.mPoly.length < 6) continue;
            path.reset();
            path.moveTo(person.mPoly[0] * width, person.mPoly[1] * height);
            for (int i = 2; i < person.mPoly.length; i += 2) {
                path.lineTo(person.mPoly[i] * width, person.mPoly[i + 1] * height);
            }
            path.close();
            canvas.drawPath(path, paint);
        }
    }

    /**
     * Flou gaussien d'une image, <b>bords étirés</b> (le flou reste plein au bord, sans halo
     * sombre), comme {@code createEdgeClampedBlur} du compositeur. Calculé sur une image réduite
     * : pour un rayon de plusieurs dizaines de pixels, flouter en réduit puis agrandir rend la même
     * chose pour une fraction du calcul.
     *
     * @param sigma écart type en pixels de {@code source}.
     */
    static Bitmap gaussianBlur(Bitmap source, float sigma) {
        int width = source.getWidth();
        int height = source.getHeight();
        int[] pixels = new int[width * height];
        source.getPixels(pixels, 0, width, 0, 0, width, height);
        int radius = Math.max(1, (int) Math.ceil(sigma * 3));
        float[] kernel = new float[radius * 2 + 1];
        float sum = 0;
        for (int i = -radius; i <= radius; i++) {
            float weight = (float) Math.exp(-(i * i) / (2 * sigma * sigma));
            kernel[i + radius] = weight;
            sum += weight;
        }
        for (int i = 0; i < kernel.length; i++) kernel[i] /= sum;

        int[] temp = new int[width * height];
        blurPass(pixels, temp, width, height, kernel, radius, true);
        blurPass(temp, pixels, width, height, kernel, radius, false);
        Bitmap output = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888);
        output.setPixels(pixels, 0, width, 0, 0, width, height);
        return output;
    }

    private static void blurPass(
            int[] in, int[] out, int width, int height, float[] kernel, int radius,
            boolean horizontal) {
        int length = horizontal ? width : height;
        int lines = horizontal ? height : width;
        for (int line = 0; line < lines; line++) {
            for (int i = 0; i < length; i++) {
                float r = 0;
                float g = 0;
                float b = 0;
                for (int k = -radius; k <= radius; k++) {
                    int j = Math.min(length - 1, Math.max(0, i + k));
                    int pixel = horizontal ? in[line * width + j] : in[j * width + line];
                    float weight = kernel[k + radius];
                    r += ((pixel >> 16) & 0xFF) * weight;
                    g += ((pixel >> 8) & 0xFF) * weight;
                    b += (pixel & 0xFF) * weight;
                }
                int value =
                        0xFF000000
                                | (Math.min(255, Math.round(r)) << 16)
                                | (Math.min(255, Math.round(g)) << 8)
                                | Math.min(255, Math.round(b));
                if (horizontal) {
                    out[line * width + i] = value;
                } else {
                    out[i * width + line] = value;
                }
            }
        }
    }
}
