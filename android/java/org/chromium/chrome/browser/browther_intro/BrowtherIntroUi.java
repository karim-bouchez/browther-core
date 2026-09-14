/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_intro;

import android.content.Context;
import android.content.res.AssetFileDescriptor;
import android.content.res.AssetManager;
import android.content.res.ColorStateList;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.text.TextUtils;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.animation.PathInterpolator;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;

import org.chromium.base.Log;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;

/**
 * Couleurs, typographie, gabarits et accès aux médias de l'introduction.
 *
 * <p>⚠️ L'introduction est <b>toujours sombre</b> (ONBOARDING-SPEC.md § 3.1) : la séquence est
 * composée pour le sombre — photo étoilée, voile, tampons, lecteur vert profond, confettis clairs.
 * Le thème est imposé au contexte de l'écran ({@link BrowtherIntroView#darkContext}), et les
 * couleurs ci-dessous sont les variantes sombres de la palette iOS ({@code BrowtherIntroPalette}) et
 * des couleurs système sombres qu'elle emploie.
 */
final class BrowtherIntroUi {
    private static final String TAG = "BrowtherIntro";

    /** Dossier des médias dans l'APK (//brave/browser/browther_intro/android). */
    static final String ASSETS = "browther_intro/";

    /** Fond du Nouvel Onglet déjà embarqué : aucun asset de plus, continuité gratuite. */
    static final String WELCOME_BACKGROUND =
            "browther_backgrounds_mobile/david-billings-KCEwOduK8ck-unsplash.jpg";

    // -------------------- Palette (variantes sombres de l'iOS) --------------------

    static final int BACKGROUND = 0xFF000000;
    /** secondarySystemGroupedBackground, sombre. */
    static final int SURFACE = 0xFF1C1C1E;
    /** regularMaterial sur fond noir. */
    static final int MATERIAL = 0xFF252528;
    static final int INK = 0xFFFFFFFF;
    /** secondaryLabel, sombre. */
    static final int INK_SOFT = 0x99EBEBF5;
    /** tertiaryLabel, sombre. */
    static final int INK_TERTIARY = 0x4DEBEBF5;
    static final int SAGE = 0xFFA5B299;
    static final int GOLD = 0xFFD4A857;
    static final int HALAL = 0xFF2A8F5A;
    static final int HARAM = 0xFFC44545;
    /**
     * Le vert <b>du texte</b>, distinct de celui des aplats : sur fond noir, {@link #HALAL} tombe à
     * 3:1, trop sombre pour un libellé.
     */
    static final int HALAL_TEXT = 0xFF6FD79B;
    static final int FEMININE = 0xFFF48FB1;
    static final int MASCULINE = 0xFF90CAF9;
    /** Fond des maquettes (conversation). */
    static final int CANVAS = 0xFF1C1F1C;
    /** L'ambre de l'accès anticipé en thème sombre (BrowtherEarlyAccess). */
    static final int AMBER = 0xFFFBBF24;
    static final int CREAM = 0xFFF8F3EA;
    static final int NIGHT = 0xFF0F100E;
    static final int PLAYER_INK = 0xFF151916;
    static final int PLAYER_CREAM = 0xFFE7E2D5;

    /** « Snappy » des transitions iOS. */
    static final PathInterpolator EASE_OUT = new PathInterpolator(0.2f, 0f, 0f, 1f);

    /** Ressort léger (dépassement ~6 %), pour ce qui monte ou claque. */
    static final PathInterpolator SPRING = new PathInterpolator(0.34f, 1.36f, 0.64f, 1f);

    private static Typeface sQuranTypeface;

    private BrowtherIntroUi() {}

    // -------------------- Mesures --------------------

    static int dp(Context context, float value) {
        return Math.round(
                TypedValue.applyDimension(
                        TypedValue.COMPLEX_UNIT_DIP,
                        value,
                        context.getResources().getDisplayMetrics()));
    }

    static float dpf(Context context, float value) {
        return TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_DIP, value, context.getResources().getDisplayMetrics());
    }

    static boolean isRtl(View view) {
        return view.getLayoutDirection() == View.LAYOUT_DIRECTION_RTL;
    }

    static int withAlpha(int color, float alpha) {
        return Color.argb(
                Math.round(alpha * Color.alpha(color)),
                Color.red(color),
                Color.green(color),
                Color.blue(color));
    }

    // -------------------- Texte --------------------

    static final int REGULAR = 400;
    static final int MEDIUM = 500;
    static final int SEMIBOLD = 600;
    static final int BOLD = 700;
    static final int HEAVY = 800;

    static Typeface typeface(int weight) {
        return Typeface.create(Typeface.DEFAULT, weight, false);
    }

    static TextView text(Context context, float sizeSp, int weight, int color) {
        TextView view = new TextView(context);
        view.setTextSize(TypedValue.COMPLEX_UNIT_SP, sizeSp);
        view.setTypeface(typeface(weight));
        view.setTextColor(color);
        view.setIncludeFontPadding(false);
        return view;
    }

    static TextView text(Context context, int stringId, float sizeSp, int weight, int color) {
        TextView view = text(context, sizeSp, weight, color);
        view.setText(stringId);
        return view;
    }

    /**
     * Une ligne, quoi qu'il arrive : le texte rétrécit jusqu'à {@code minSp} plutôt que de se
     * casser en deux et de faire sauter la mise en page (équivalent de {@code
     * minimumScaleFactor}).
     */
    static void singleLine(TextView view, float minSp, float maxSp) {
        view.setMaxLines(1);
        view.setEllipsize(TextUtils.TruncateAt.END);
        view.setAutoSizeTextTypeUniformWithConfiguration(
                Math.round(minSp), Math.round(maxSp), 1, TypedValue.COMPLEX_UNIT_SP);
    }

    /** Amiri Quran (SIL OFL 1.1), la police du muṣḥaf, embarquée. */
    static Typeface quranTypeface(Context context) {
        if (sQuranTypeface == null) {
            try {
                sQuranTypeface =
                        Typeface.createFromAsset(
                                context.getAssets(), ASSETS + "AmiriQuran-Regular.ttf");
            } catch (RuntimeException e) {
                Log.e(TAG, "Police Amiri Quran introuvable", e);
                sQuranTypeface = Typeface.SERIF;
            }
        }
        return sQuranTypeface;
    }

    // -------------------- Formes --------------------

    static GradientDrawable rounded(int color, float radiusPx) {
        GradientDrawable drawable = new GradientDrawable();
        drawable.setColor(color);
        drawable.setCornerRadius(radiusPx);
        return drawable;
    }

    static GradientDrawable rounded(int color, float radiusPx, int strokePx, int strokeColor) {
        GradientDrawable drawable = rounded(color, radiusPx);
        drawable.setStroke(strokePx, strokeColor);
        return drawable;
    }

    /** Coins inégaux : haut-début, haut-fin, bas-fin, bas-début (sens de lecture ignoré). */
    static GradientDrawable corners(int color, float tl, float tr, float br, float bl) {
        GradientDrawable drawable = new GradientDrawable();
        drawable.setColor(color);
        drawable.setCornerRadii(new float[] {tl, tl, tr, tr, br, br, bl, bl});
        return drawable;
    }

    static GradientDrawable capsule(int color) {
        GradientDrawable drawable = new GradientDrawable();
        drawable.setColor(color);
        drawable.setCornerRadius(10000f);
        return drawable;
    }

    // -------------------- Pictogrammes --------------------

    static ImageView glyph(Context context, int drawableId, float sizeDp, int color) {
        ImageView view = new ImageView(context);
        view.setImageResource(drawableId);
        view.setImageTintList(ColorStateList.valueOf(color));
        view.setScaleType(ImageView.ScaleType.FIT_CENTER);
        int size = dp(context, sizeDp);
        view.setLayoutParams(new LinearLayout.LayoutParams(size, size));
        view.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
        return view;
    }

    // -------------------- Mise en page --------------------

    static LinearLayout column(Context context) {
        LinearLayout layout = new LinearLayout(context);
        layout.setOrientation(LinearLayout.VERTICAL);
        return layout;
    }

    static LinearLayout row(Context context, float spacingDp) {
        LinearLayout layout = new LinearLayout(context);
        layout.setOrientation(LinearLayout.HORIZONTAL);
        layout.setGravity(Gravity.CENTER_VERTICAL);
        if (spacingDp > 0) {
            GradientDrawable divider = new GradientDrawable();
            divider.setSize(dp(context, spacingDp), 1);
            layout.setDividerDrawable(divider);
            layout.setShowDividers(LinearLayout.SHOW_DIVIDER_MIDDLE);
        }
        return layout;
    }

    static void spacing(LinearLayout column, float spacingDp) {
        GradientDrawable divider = new GradientDrawable();
        divider.setSize(1, dp(column.getContext(), spacingDp));
        column.setDividerDrawable(divider);
        column.setShowDividers(LinearLayout.SHOW_DIVIDER_MIDDLE);
    }

    static LinearLayout.LayoutParams linear(int width, int height) {
        return new LinearLayout.LayoutParams(width, height);
    }

    static FrameLayout.LayoutParams frame(int width, int height, int gravity) {
        return new FrameLayout.LayoutParams(width, height, gravity);
    }

    static final int MATCH = ViewGroup.LayoutParams.MATCH_PARENT;
    static final int WRAP = ViewGroup.LayoutParams.WRAP_CONTENT;

    static LinearLayout.LayoutParams marginTop(LinearLayout.LayoutParams params, int px) {
        params.topMargin = px;
        return params;
    }

    // -------------------- Médias embarqués --------------------

    /** Lit un texte des assets (JSON des voiles). */
    static String readAsset(Context context, String path) throws IOException {
        try (InputStream input = context.getAssets().open(path)) {
            ByteArrayOutputStream output = new ByteArrayOutputStream();
            byte[] buffer = new byte[16 * 1024];
            int read;
            while ((read = input.read(buffer)) > 0) {
                output.write(buffer, 0, read);
            }
            return new String(output.toByteArray(), StandardCharsets.UTF_8);
        }
    }

    static AssetFileDescriptor openFd(Context context, String path) throws IOException {
        return context.getAssets().openFd(path);
    }

    /**
     * Décode une image des assets <b>à la taille d'affichage</b> : le fond du Nouvel Onglet fait
     * plusieurs mégapixels, le décoder entier sur un téléphone de 4 Go coûterait des dizaines de
     * mégaoctets pour rien.
     */
    static Bitmap decodeAsset(Context context, String path, int targetWidthPx) {
        AssetManager assets = context.getAssets();
        try {
            BitmapFactory.Options bounds = new BitmapFactory.Options();
            bounds.inJustDecodeBounds = true;
            try (InputStream input = assets.open(path)) {
                BitmapFactory.decodeStream(input, null, bounds);
            }
            BitmapFactory.Options options = new BitmapFactory.Options();
            int sample = 1;
            while (targetWidthPx > 0 && bounds.outWidth / (sample * 2) >= targetWidthPx) {
                sample *= 2;
            }
            options.inSampleSize = sample;
            try (InputStream input = assets.open(path)) {
                return BitmapFactory.decodeStream(input, null, options);
            }
        } catch (IOException e) {
            Log.e(TAG, "Asset illisible : %s", path, e);
            return null;
        }
    }
}
