/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_intro;

import static org.chromium.chrome.browser.browther_intro.BrowtherIntroUi.MATCH;
import static org.chromium.chrome.browser.browther_intro.BrowtherIntroUi.WRAP;
import static org.chromium.chrome.browser.browther_intro.BrowtherIntroUi.dp;
import static org.chromium.chrome.browser.browther_intro.BrowtherIntroUi.dpf;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.LinearGradient;
import android.graphics.Outline;
import android.graphics.Paint;
import android.graphics.Shader;
import android.graphics.Typeface;
import android.os.Handler;
import android.os.Looper;
import android.view.Gravity;
import android.view.View;
import android.view.ViewOutlineProvider;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import org.chromium.chrome.R;

/**
 * 1 · Accueil. L'app s'ouvre sur un fond du Nouvel Onglet — celui qu'on retrouve en arrivant — et
 * sur le verset qui résume les deux moteurs : l'ouïe (Sawtunaa) et la vue (Basarunaa).
 */
final class BrowtherIntroWelcomeStep extends BrowtherIntroStepView {
    /**
     * Coran 17:36, seconde moitié, texte uthmani — ⛔ jamais ressaisi à la main : copie exacte de
     * {@code private/design/intro-iphone/verse.txt}, la même que l'iOS et le desktop. En séquences
     * {@code \}{@code u} : un éditeur qui normalise l'Unicode réordonne les signes (šadda et voyelle
     * échangées), c'est arrivé au portage desktop. Vérifié octet par octet contre la source.
     *
     * <p>⚠️ Édition {@code quran-uthmani-quran-academy} (api.alquran.cloud), PAS {@code
     * quran-uthmani} (Tanzil) : cette dernière accole un U+06ED SMALL LOW MEEM à chaque tanwīn fatḥ
     * suivi d'alif, qu'une police de muṣḥaf dessine comme un vrai mīm sous la ligne.
     */
    static final String VERSE =
            "\u0625\u0650\u0646\u0651\u064e \u0671\u0644\u0633\u0651\u064e\u0645\u06e1\u0639\u064e \u0648\u064e\u0671\u0644\u06e1\u0628\u064e\u0635\u064e\u0631\u064e " +
            "\u0648\u064e\u0671\u0644\u06e1\u0641\u064f\u0624\u064e\u0627\u062f\u064e \u0643\u064f\u0644\u0651\u064f \u0623\u064f\u0648\u06df\u0644\u064e\u0640\u0670\u06e4\u0649\u0655\u0650\u0643\u064e " +
            "\u0643\u064e\u0627\u0646\u064e \u0639\u064e\u0646\u06e1\u0647\u064f \u0645\u064e\u0633\u06e1\u0640\u0654\u064f\u0648\u0644\u08f0\u0627";

    private final ImageView mBackground;
    private final LinearLayout mContent;

    BrowtherIntroWelcomeStep(Context context, BrowtherIntroModel model) {
        super(context, model);
        setBackgroundColor(BrowtherIntroUi.NIGHT);

        // ⚠️ Le fond est CONTRAINT et ROGNÉ par l'écran, jamais posé en frère d'une pile : une image
        // « remplir » sans taille imposée ferait déborder tout l'écran (défaut vu sur iOS). Il
        // couvre aussi la barre de navigation, sinon une bande noire reste dessous.
        mBackground = new ImageView(context);
        mBackground.setScaleType(ImageView.ScaleType.CENTER_CROP);
        mBackground.setImportantForAccessibility(IMPORTANT_FOR_ACCESSIBILITY_NO);
        addView(mBackground, new LayoutParams(MATCH, MATCH));
        addView(new Shade(context), new LayoutParams(MATCH, MATCH));

        ScrollView scroll = new ScrollView(context);
        scroll.setFillViewport(true);
        scroll.setVerticalScrollBarEnabled(false);
        scroll.setOverScrollMode(OVER_SCROLL_NEVER);
        addView(scroll, new LayoutParams(MATCH, MATCH));

        mContent = BrowtherIntroUi.column(context);
        mContent.setGravity(Gravity.CENTER_HORIZONTAL);
        mContent.setClipChildren(false);
        scroll.addView(mContent, new ScrollView.LayoutParams(MATCH, MATCH));

        // L'icône de l'app, pas le bouclier — le bouclier est l'icône des pubs.
        ImageView icon = new ImageView(context);
        Bitmap appIcon =
                BrowtherIntroUi.decodeAsset(
                        context, BrowtherIntroUi.ASSETS + "browther-app-icon.png", dp(context, 66));
        icon.setImageBitmap(appIcon);
        icon.setScaleType(ImageView.ScaleType.FIT_CENTER);
        final float iconRadius = dpf(context, 15);
        icon.setOutlineProvider(
                new ViewOutlineProvider() {
                    @Override
                    public void getOutline(View view, Outline outline) {
                        outline.setRoundRect(0, 0, view.getWidth(), view.getHeight(), iconRadius);
                    }
                });
        icon.setClipToOutline(true);
        icon.setElevation(dpf(context, 10));
        icon.setImportantForAccessibility(IMPORTANT_FOR_ACCESSIBILITY_NO);
        mContent.addView(icon, BrowtherIntroUi.linear(dp(context, 66), dp(context, 66)));

        mContent.addView(verse(context), marginTop(MATCH, dp(context, 22)));

        View spacer = new View(context);
        LinearLayout.LayoutParams spacerParams = new LinearLayout.LayoutParams(MATCH, 0, 1f);
        spacer.setMinimumHeight(dp(context, 16));
        mContent.addView(spacer, spacerParams);

        TextView title =
                BrowtherIntroUi.text(
                        context,
                        R.string.browther_intro_welcome_title,
                        29,
                        BrowtherIntroUi.SEMIBOLD,
                        Color.WHITE);
        title.setGravity(Gravity.CENTER);
        title.setAccessibilityHeading(true);
        mContent.addView(title, BrowtherIntroUi.linear(MATCH, WRAP));

        mContent.addView(protections(context), marginTop(MATCH, dp(context, 18)));

        BrowtherIntroWidgets.Button start =
                new BrowtherIntroWidgets.Button(
                        context,
                        R.string.browther_intro_start_button,
                        BrowtherIntroWidgets.Button.Style.LIGHT);
        start.setOnClickListener(v -> mModel.advance());
        mContent.addView(start, marginTop(MATCH, dp(context, 18)));

        LinearLayout.LayoutParams signatureParams = BrowtherIntroUi.linear(WRAP, WRAP);
        signatureParams.topMargin = dp(context, 14);
        mContent.addView(BrowtherIntroWidgets.signature(context), signatureParams);

        loadBackground(context);
    }

    private static LinearLayout.LayoutParams marginTop(int width, int margin) {
        return BrowtherIntroUi.marginTop(BrowtherIntroUi.linear(width, WRAP), margin);
    }

    @Override
    protected void applyInsets(int top, int bottom) {
        int gutter = dp(getContext(), 20);
        // Le logo commence SOUS la barre de progression.
        mContent.setPadding(
                gutter, top + dp(getContext(), 60), gutter, bottom + dp(getContext(), 26));
    }

    @Override
    void bind(boolean animated) {}

    @Override
    CharSequence accessibilityTitle() {
        return getContext().getString(R.string.browther_intro_welcome_title);
    }

    private void loadBackground(Context context) {
        final int width = context.getResources().getDisplayMetrics().widthPixels;
        Handler main = new Handler(Looper.getMainLooper());
        new Thread(
                        () -> {
                            Bitmap bitmap =
                                    BrowtherIntroUi.decodeAsset(
                                            context, BrowtherIntroUi.WELCOME_BACKGROUND, width);
                            main.post(() -> mBackground.setImageBitmap(bitmap));
                        },
                        "BrowtherIntroWelcome")
                .start();
    }

    private View verse(Context context) {
        LinearLayout column = BrowtherIntroUi.column(context);
        column.setGravity(Gravity.CENTER_HORIZONTAL);
        column.setPadding(dp(context, 6), 0, dp(context, 6), 0);

        // La police du muṣḥaf : les polices système dessinent un arabe moderne, sans ses signes.
        TextView arabic = new TextView(context);
        arabic.setText(VERSE);
        arabic.setTypeface(BrowtherIntroUi.quranTypeface(context));
        arabic.setTextSize(22);
        arabic.setTextColor(Color.WHITE);
        arabic.setGravity(Gravity.CENTER);
        arabic.setTextDirection(TEXT_DIRECTION_RTL);
        arabic.setTextLocale(java.util.Locale.forLanguageTag("ar"));
        arabic.setLineSpacing(dpf(context, 14), 1f);
        arabic.setShadowLayer(dpf(context, 10), 0, 0, 0x80000000);
        column.addView(arabic, BrowtherIntroUi.linear(MATCH, WRAP));

        TextView translation = new TextView(context);
        translation.setText(R.string.browther_intro_verse_translation);
        translation.setTypeface(Typeface.create(Typeface.SERIF, Typeface.ITALIC));
        translation.setTextSize(15.5f);
        translation.setTextColor(BrowtherIntroUi.withAlpha(Color.WHITE, 0.84f));
        translation.setGravity(Gravity.CENTER);
        column.addView(
                translation,
                BrowtherIntroUi.marginTop(BrowtherIntroUi.linear(MATCH, WRAP), dp(context, 10)));

        TextView reference =
                BrowtherIntroUi.text(
                        context,
                        R.string.browther_intro_verse_reference,
                        10.5f,
                        BrowtherIntroUi.SEMIBOLD,
                        BrowtherIntroUi.SAGE);
        reference.setAllCaps(true);
        reference.setLetterSpacing(1.6f / 10.5f);
        reference.setGravity(Gravity.CENTER);
        column.addView(
                reference,
                BrowtherIntroUi.marginTop(BrowtherIntroUi.linear(MATCH, WRAP), dp(context, 10)));
        return column;
    }

    /** Les trois protections : icône réelle, nom, point d'état avec halo, seconde ligne. */
    private View protections(Context context) {
        LinearLayout panel = BrowtherIntroUi.row(context, 0);
        panel.setClipChildren(false);
        panel.setPadding(0, dp(context, 13), 0, dp(context, 13));
        panel.setBackground(
                BrowtherIntroUi.rounded(
                        BrowtherIntroUi.withAlpha(Color.WHITE, 0.08f),
                        dpf(context, 20),
                        Math.max(1, dp(context, 1)),
                        BrowtherIntroUi.withAlpha(Color.WHITE, 0.12f)));
        boolean soon = mModel.isEarlyAccess();
        panel.addView(
                protection(context, R.drawable.shield_icon_toolbar,
                        R.string.browther_intro_protection_ads, false),
                new LinearLayout.LayoutParams(0, WRAP, 1f));
        panel.addView(divider(context));
        panel.addView(
                protection(context, R.drawable.sawtunaa_icon_toolbar,
                        R.string.browther_intro_protection_music, soon),
                new LinearLayout.LayoutParams(0, WRAP, 1f));
        panel.addView(divider(context));
        panel.addView(
                protection(context, R.drawable.basarunaa_icon_toolbar,
                        R.string.browther_intro_protection_images, soon),
                new LinearLayout.LayoutParams(0, WRAP, 1f));
        return panel;
    }

    private static View divider(Context context) {
        View divider = new View(context);
        divider.setBackgroundColor(BrowtherIntroUi.withAlpha(Color.WHITE, 0.12f));
        divider.setLayoutParams(
                new LinearLayout.LayoutParams(Math.max(1, dp(context, 0.5f)), dp(context, 58)));
        return divider;
    }

    /** Les icônes sont celles de la barre d'outils : la personne les reverra telles quelles. */
    private static View protection(Context context, int iconId, int nameId, boolean soon) {
        LinearLayout column = BrowtherIntroUi.column(context);
        column.setGravity(Gravity.CENTER_HORIZONTAL);
        column.setClipChildren(false);
        column.setPadding(dp(context, 4), 0, dp(context, 4), 0);
        column.addView(BrowtherIntroUi.glyph(context, iconId, 26, Color.WHITE));

        TextView name =
                BrowtherIntroUi.text(context, nameId, 14, BrowtherIntroUi.SEMIBOLD, Color.WHITE);
        name.setGravity(Gravity.CENTER);
        BrowtherIntroUi.singleLine(name, 11, 14);
        column.addView(name, marginTop(MATCH, dp(context, 7)));

        LinearLayout status = BrowtherIntroUi.row(context, 0);
        status.setGravity(Gravity.CENTER);
        status.setClipChildren(false);
        BrowtherIntroWidgets.StatusDot dot = new BrowtherIntroWidgets.StatusDot(context, soon);
        LinearLayout.LayoutParams dotParams = BrowtherIntroUi.linear(WRAP, WRAP);
        int overflow = dot.overflow();
        dotParams.setMargins(-overflow, -overflow, -overflow + dp(context, 5), -overflow);
        status.addView(dot, dotParams);
        TextView state =
                BrowtherIntroUi.text(
                        context,
                        soon ? R.string.browther_intro_status_soon
                                : R.string.browther_intro_status_active,
                        11,
                        BrowtherIntroUi.SEMIBOLD,
                        BrowtherIntroUi.withAlpha(Color.WHITE, 0.72f));
        status.addView(state);
        column.addView(status, marginTop(WRAP, dp(context, 7)));

        // Seconde ligne : l'invocation pour ce qui arrive, « dès maintenant » pour ce qui marche
        // déjà — même poids pour les deux, sinon la colonne active paraît vide.
        TextView detail =
                BrowtherIntroUi.text(context, 11, BrowtherIntroUi.REGULAR, BrowtherIntroUi.SAGE);
        if (soon) {
            detail.setText("إن شاء الله");
            detail.setTextLocale(java.util.Locale.forLanguageTag("ar"));
        } else {
            detail.setText(R.string.browther_intro_status_active_detail);
        }
        detail.setGravity(Gravity.CENTER);
        BrowtherIntroUi.singleLine(detail, 9, 11);
        column.addView(detail, marginTop(MATCH, dp(context, 7)));
        return column;
    }

    /** Dégradé vers le noir en bas : le texte et les protections restent lisibles. */
    private static final class Shade extends View {
        private final Paint mPaint = new Paint();

        Shade(Context context) {
            super(context);
            setImportantForAccessibility(IMPORTANT_FOR_ACCESSIBILITY_NO);
        }

        @Override
        protected void onSizeChanged(int w, int h, int oldw, int oldh) {
            mPaint.setShader(
                    new LinearGradient(
                            0, 0, 0, h,
                            new int[] {0x33000000, 0x59000000, 0xE0000000, BrowtherIntroUi.NIGHT},
                            new float[] {0f, 0.34f, 0.64f, 1f},
                            Shader.TileMode.CLAMP));
        }

        @Override
        protected void onDraw(Canvas canvas) {
            canvas.drawRect(0, 0, getWidth(), getHeight(), mPaint);
        }
    }
}
