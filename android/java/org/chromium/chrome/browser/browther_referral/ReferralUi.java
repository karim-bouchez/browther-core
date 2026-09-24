/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_referral;

import android.animation.ValueAnimator;
import android.content.Context;
import android.content.res.ColorStateList;
import android.content.res.Configuration;
import android.graphics.Typeface;
import android.graphics.drawable.Drawable;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.RippleDrawable;
import android.provider.Settings;
import android.text.SpannableStringBuilder;
import android.text.Spanned;
import android.text.TextUtils;
import android.text.style.StyleSpan;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.HapticFeedbackConstants;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.view.animation.PathInterpolator;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;

import org.chromium.chrome.R;
import org.chromium.chrome.browser.browther_referral.core.ExtrasState;

/**
 * La grammaire visuelle du parrainage Android — pendant de {@code ReferralComponents.swift} (iOS,
 * la référence : private/docs/PARRAINAGE.md § 8.1).
 *
 * <p>Tout est construit en code, comme l'introduction : une vue par composant, ⛔ aucun layout
 * XML — c'est ce qui permet l'aperçu à l'émulateur par un mini-APK hors Chromium (§ 8.5).
 *
 * <p>🔴 <b>Deux ors, deux rôles</b> (§ 12.24 du doc commun) : {@link Palette#gold} est un TEXTE
 * (or foncé sur fond clair, or vif sur fond sombre) ; {@link Palette#goldFill} est un APLAT qui
 * ne porte que de l'encre sombre ({@link Palette#INK}) — ⛔ jamais de l'or sur de l'or.
 *
 * <p>🔴 <b>Android 9 ne peint pas les enfants d'une vue qui ne dessine rien</b> (§ 12.38 du doc
 * commun, Huawei) : la barre du haut et le conteneur du défilement de chaque fenêtre portent un
 * fond égal à celui de l'écran. Il est invisible — ⛔ ne pas le retirer.
 */
public final class ReferralUi {
    private ReferralUi() {}

    // -------------------- Couleurs --------------------

    /** Les couleurs résolues pour UN thème (clair ou sombre), au moment de construire l'écran. */
    public static final class Palette {
        /** L'encre des aplats dorés : sombre dans les deux thèmes. */
        public static final int INK = 0xFF2A1B05;

        public static final int GOLD_FILL = 0xFFE2B95C;

        public final boolean dark;
        /** Le fond de page. */
        public final int screen;
        /** Les cartes posées sur la page (liste des fonctionnalités, jauge). */
        public final int panel;
        public final int text;
        public final int text2;
        public final int text3;
        public final int line;
        public final int track;
        public final int green;
        public final int greenFill;
        public final int greenSurface;
        public final int gold;
        public final int goldFill;
        public final int goldSurface;
        public final int ink;
        /** Le bouton principal : l'encre du thème en aplat (blanc sur noir, noir sur blanc). */
        public final int primary;
        public final int onPrimary;

        Palette(boolean dark) {
            this.dark = dark;
            screen = dark ? 0xFF16171B : 0xFFF2F3F6;
            panel = dark ? 0xFF24262C : 0xFFFFFFFF;
            text = dark ? 0xFFF4F4F6 : 0xFF16171B;
            text2 = dark ? 0xB3EBEBF5 : 0x993C3C43;
            text3 = dark ? 0x66EBEBF5 : 0x663C3C43;
            line = dark ? 0x1FFFFFFF : 0x1A000000;
            track = dark ? 0x5C787880 : 0x33787880;
            green = dark ? 0xFF6FD79B : 0xFF1C5A3A;
            greenFill = 0xFF2A8F5A;
            greenSurface = withAlpha(dark ? 0xFF6FD79B : 0xFF2A8F5A, 0.13f);
            gold = dark ? 0xFFE2B95C : 0xFF9A5A0C;
            goldFill = GOLD_FILL;
            goldSurface = withAlpha(GOLD_FILL, 0.16f);
            ink = INK;
            primary = dark ? 0xFFF4F4F6 : 0xFF16171B;
            onPrimary = dark ? 0xFF16171B : 0xFFFFFFFF;
        }
    }

    public static Palette palette(Context context) {
        int night = context.getResources().getConfiguration().uiMode & Configuration.UI_MODE_NIGHT_MASK;
        return new Palette(night == Configuration.UI_MODE_NIGHT_YES);
    }

    public static int withAlpha(int color, float alpha) {
        int a = Math.round(((color >>> 24) & 0xFF) * alpha);
        return (a << 24) | (color & 0x00FFFFFF);
    }

    // -------------------- Mesures --------------------

    public static int dp(Context context, float value) {
        return Math.round(
                TypedValue.applyDimension(
                        TypedValue.COMPLEX_UNIT_DIP, value, context.getResources().getDisplayMetrics()));
    }

    public static final int MATCH = ViewGroup.LayoutParams.MATCH_PARENT;
    public static final int WRAP = ViewGroup.LayoutParams.WRAP_CONTENT;

    public static LinearLayout.LayoutParams linear(int width, int height) {
        return new LinearLayout.LayoutParams(width, height);
    }

    public static LinearLayout.LayoutParams linear(int width, int height, int topMarginPx) {
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(width, height);
        params.topMargin = topMarginPx;
        return params;
    }

    public static FrameLayout.LayoutParams frame(int width, int height, int gravity) {
        return new FrameLayout.LayoutParams(width, height, gravity);
    }

    public static LinearLayout column(Context context) {
        LinearLayout column = new LinearLayout(context);
        column.setOrientation(LinearLayout.VERTICAL);
        return column;
    }

    public static LinearLayout row(Context context) {
        LinearLayout row = new LinearLayout(context);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);
        return row;
    }

    /** Un espace vertical fixe dans une colonne. */
    public static void gap(LinearLayout column, float dp) {
        View space = new View(column.getContext());
        column.addView(space, linear(1, dp(column.getContext(), dp)));
    }

    // -------------------- Formes --------------------

    public static GradientDrawable rounded(int color, float radiusPx) {
        GradientDrawable drawable = new GradientDrawable();
        drawable.setColor(color);
        drawable.setCornerRadius(radiusPx);
        return drawable;
    }

    public static GradientDrawable rounded(int color, float radiusPx, int strokePx, int strokeColor) {
        GradientDrawable drawable = rounded(color, radiusPx);
        drawable.setStroke(strokePx, strokeColor);
        return drawable;
    }

    public static GradientDrawable oval(int color) {
        GradientDrawable drawable = new GradientDrawable();
        drawable.setShape(GradientDrawable.OVAL);
        drawable.setColor(color);
        return drawable;
    }

    /** Un fond qui répond au toucher (ondulation) par-dessus une forme. */
    public static Drawable pressable(Drawable content, int rippleColor, float radiusPx) {
        return new RippleDrawable(
                ColorStateList.valueOf(rippleColor), content, rounded(0xFFFFFFFF, radiusPx));
    }

    // -------------------- Texte --------------------

    public static final int REGULAR = 400;
    public static final int MEDIUM = 500;
    public static final int SEMIBOLD = 600;
    public static final int BOLD = 700;

    public static Typeface typeface(int weight) {
        return Typeface.create(Typeface.DEFAULT, weight, false);
    }

    public static TextView text(Context context, float sizeSp, int weight, int color) {
        TextView view = new TextView(context);
        view.setTextSize(TypedValue.COMPLEX_UNIT_SP, sizeSp);
        view.setTypeface(typeface(weight));
        view.setTextColor(color);
        view.setIncludeFontPadding(true);
        return view;
    }

    public static TextView text(Context context, CharSequence value, float sizeSp, int weight, int color) {
        TextView view = text(context, sizeSp, weight, color);
        view.setText(value);
        return view;
    }

    /**
     * Les balises {@code **…**} du pool (le seul formatage des textes du parrainage) → du gras.
     * Une balise orpheline reste telle quelle : on n'avale jamais de texte.
     */
    public static CharSequence rich(String text) {
        if (text == null || !text.contains("**")) return text == null ? "" : text;
        SpannableStringBuilder out = new SpannableStringBuilder();
        int index = 0;
        while (true) {
            int open = text.indexOf("**", index);
            int close = open < 0 ? -1 : text.indexOf("**", open + 2);
            if (open < 0 || close < 0) {
                out.append(text.substring(index));
                return out;
            }
            out.append(text, index, open);
            int start = out.length();
            out.append(text, open + 2, close);
            out.setSpan(
                    new StyleSpan(Typeface.BOLD), start, out.length(), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
            index = close + 2;
        }
    }

    /** Le titre d'une fenêtre du flow (centré). */
    public static TextView title(Context context, Palette p, String value) {
        TextView view = text(context, value, 22, SEMIBOLD, p.text);
        view.setGravity(Gravity.CENTER_HORIZONTAL);
        return view;
    }

    /**
     * ⭐ L'accroche (§ 12.30) : le GAIN, sur sa propre ligne et dans l'or du TEXTE — fondue dans le
     * titre, elle se lisait comme la fin d'une mauvaise nouvelle.
     */
    public static TextView hook(Context context, Palette p, String value) {
        TextView view = text(context, value, 17, SEMIBOLD, p.gold);
        view.setGravity(Gravity.CENTER_HORIZONTAL);
        return view;
    }

    /** Le sujet au-dessus du titre — ⛔ seulement sur ce que personne n'a demandé (8, 8 bis). */
    public static TextView eyebrow(Context context, Palette p, String value) {
        TextView view = text(context, value, 14, SEMIBOLD, p.text2);
        view.setGravity(Gravity.CENTER_HORIZONTAL);
        return view;
    }

    /**
     * Le corps d'une fenêtre. ⚠️ Centré seulement s'il est court (§ 12.26) : un paragraphe de
     * plusieurs lignes s'aligne sur le début de la ligne.
     */
    public static TextView body(Context context, Palette p, String value) {
        TextView view = text(context, rich(value), 16, REGULAR, p.text2);
        view.setLineSpacing(0, 1.12f);
        view.setGravity(value.length() > 140 ? Gravity.START : Gravity.CENTER_HORIZONTAL);
        view.setTextAlignment(
                value.length() > 140 ? View.TEXT_ALIGNMENT_VIEW_START : View.TEXT_ALIGNMENT_CENTER);
        return view;
    }

    public static TextView footnote(Context context, Palette p, String value) {
        TextView view = text(context, rich(value), 13, REGULAR, p.text2);
        view.setGravity(Gravity.CENTER_HORIZONTAL);
        view.setTextAlignment(View.TEXT_ALIGNMENT_CENTER);
        return view;
    }

    // -------------------- Pictogrammes --------------------

    public static ImageView glyph(Context context, int drawableId, float sizeDp, int color) {
        ImageView view = new ImageView(context);
        view.setImageResource(drawableId);
        view.setImageTintList(ColorStateList.valueOf(color));
        view.setScaleType(ImageView.ScaleType.FIT_CENTER);
        int size = dp(context, sizeDp);
        view.setLayoutParams(new LinearLayout.LayoutParams(size, size));
        view.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
        return view;
    }

    public enum Tone {
        GOLD,
        GREEN
    }

    /** Une icône dans un rond : les fenêtres du flow ont une icône en tête (§ 12.26). */
    public static View roundIcon(Context context, Palette p, int drawableId, Tone tone, float sizeDp) {
        FrameLayout circle = new FrameLayout(context);
        circle.setBackground(oval(tone == Tone.GOLD ? p.goldSurface : p.greenSurface));
        ImageView icon = glyph(context, drawableId, sizeDp * 0.42f, tone == Tone.GOLD ? p.gold : p.green);
        int iconSize = dp(context, sizeDp * 0.42f);
        circle.addView(icon, frame(iconSize, iconSize, Gravity.CENTER));
        int size = dp(context, sizeDp);
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(size, size);
        params.gravity = Gravity.CENTER_HORIZONTAL;
        circle.setLayoutParams(params);
        return circle;
    }

    // -------------------- Boutons --------------------

    /** Enfoncement doux (échelle + opacité) : le pendant du {@code ButtonStyle} iOS. */
    public static void pressFeedback(View view) {
        view.setOnTouchListener(
                (v, event) -> {
                    switch (event.getActionMasked()) {
                        case MotionEvent.ACTION_DOWN:
                            v.animate().scaleX(0.97f).scaleY(0.97f).alpha(0.85f).setDuration(120).start();
                            break;
                        case MotionEvent.ACTION_UP:
                        case MotionEvent.ACTION_CANCEL:
                            v.animate().scaleX(1f).scaleY(1f).alpha(1f).setDuration(120).start();
                            break;
                        default:
                            break;
                    }
                    return false;
                });
    }

    /**
     * Le bouton principal : un aplat plein, la sous-ligne éventuelle DANS le bouton (« Inviter un
     * proche — Et tenter d'avoir l'accès gratuit à vie »). ⚠️ Un libellé long passe à la ligne
     * CENTRÉ (« Régler Browther comme navigateur par défaut », recette iOS du 2026-09-24).
     */
    public static View primaryButton(
            Context context, Palette p, String label, String sub, int iconRes, Runnable action) {
        return filledButton(context, p, label, sub, iconRes, p.primary, p.onPrimary, action);
    }

    /**
     * ⭐ Le bouton principal allumé au palier « à vie » (§ 12.30) : aplat doré sous encre sombre,
     * ∞, un halo qui pulse DEUX fois (⛔ pas en boucle). ⚠️ Mêmes cotes que {@link
     * #primaryButton} : s'allumer ne fait pas sauter le pied de l'écran.
     */
    public static View lifetimeButton(
            Context context, Palette p, String label, String sub, Runnable action) {
        View button =
                filledButton(
                        context,
                        p,
                        label,
                        sub,
                        R.drawable.browther_referral_glyph_infinity,
                        p.goldFill,
                        Palette.INK,
                        action);
        if (!reduceMotion(context)) {
            ValueAnimator halo = ValueAnimator.ofFloat(0f, 1f);
            halo.setDuration(900);
            halo.setRepeatCount(1);
            halo.addUpdateListener(
                    animator -> {
                        float t = (float) animator.getAnimatedValue();
                        button.setElevation(dp(context, 10) * (1 - t));
                        button.setScaleX(1f + 0.02f * (1 - t));
                        button.setScaleY(1f + 0.02f * (1 - t));
                    });
            button.post(halo::start);
        }
        return button;
    }

    private static View filledButton(
            Context context,
            Palette p,
            String label,
            String sub,
            int iconRes,
            int fill,
            int ink,
            Runnable action) {
        LinearLayout button = column(context);
        button.setGravity(Gravity.CENTER);
        float radius = dp(context, 18);
        button.setBackground(pressable(rounded(fill, radius), withAlpha(ink, 0.2f), radius));
        button.setMinimumHeight(dp(context, 52));
        int padH = dp(context, 16);
        int padV = dp(context, sub == null ? 12 : 9);
        button.setPadding(padH, padV, padH, padV);

        LinearLayout line = row(context);
        line.setGravity(Gravity.CENTER);
        if (iconRes != 0) {
            line.addView(glyph(context, iconRes, 18, ink));
            View space = new View(context);
            line.addView(space, new LinearLayout.LayoutParams(dp(context, 8), 1));
        }
        TextView labelView = text(context, label, 16, SEMIBOLD, ink);
        labelView.setGravity(Gravity.CENTER);
        labelView.setTextAlignment(View.TEXT_ALIGNMENT_CENTER);
        line.addView(labelView, new LinearLayout.LayoutParams(WRAP, WRAP));
        button.addView(line, linear(WRAP, WRAP));
        if (sub != null) {
            TextView subView = text(context, sub, 13, REGULAR, withAlpha(ink, 0.75f));
            subView.setGravity(Gravity.CENTER);
            subView.setTextAlignment(View.TEXT_ALIGNMENT_CENTER);
            button.addView(subView, linear(WRAP, WRAP));
        }
        button.setClickable(true);
        button.setFocusable(true);
        button.setContentDescription(sub == null ? label : label + ". " + sub);
        button.setOnClickListener(v -> action.run());
        pressFeedback(button);
        button.setLayoutParams(linear(MATCH, WRAP));
        return button;
    }

    /** L'alternative : un contour. */
    public static View secondaryButton(Context context, Palette p, String label, Runnable action) {
        TextView button = text(context, label, 15, SEMIBOLD, p.text2);
        button.setGravity(Gravity.CENTER);
        button.setTextAlignment(View.TEXT_ALIGNMENT_CENTER);
        float radius = dp(context, 14);
        button.setBackground(
                pressable(
                        rounded(0, radius, dp(context, 1.5f), withAlpha(p.text2, 0.55f)),
                        withAlpha(p.text, 0.12f),
                        radius));
        button.setMinimumHeight(dp(context, 48));
        int pad = dp(context, 12);
        button.setPadding(pad, pad / 2, pad, pad / 2);
        button.setOnClickListener(v -> action.run());
        pressFeedback(button);
        button.setLayoutParams(linear(MATCH, WRAP));
        return button;
    }

    /**
     * Une sortie en toutes lettres (« Plus tard », la du'a, « Retour »). 🔴 Cliquable sur le texte
     * et juste autour, ⛔ jamais sur toute la largeur (§ 12.9) : une fenêtre qui attend une action
     * ne se ferme que par elle.
     */
    public static View textExit(
            Context context, Palette p, String label, boolean italic, boolean back, Runnable action) {
        LinearLayout exit = row(context);
        exit.setGravity(Gravity.CENTER);
        int padH = dp(context, 10);
        int padV = dp(context, 8);
        exit.setPadding(padH, padV, padH, padV);
        exit.setMinimumHeight(dp(context, 44));
        if (back) {
            ImageView chevron =
                    glyph(context, R.drawable.browther_intro_glyph_chevron_left, 14, p.text2);
            chevron.getDrawable().setAutoMirrored(true);
            exit.addView(chevron);
            View space = new View(context);
            exit.addView(space, new LinearLayout.LayoutParams(dp(context, 4), 1));
        }
        TextView labelView = text(context, label, 15, MEDIUM, p.text2);
        labelView.setGravity(Gravity.CENTER);
        labelView.setTextAlignment(View.TEXT_ALIGNMENT_CENTER);
        if (italic) labelView.setTypeface(Typeface.create(typeface(MEDIUM), Typeface.ITALIC));
        exit.addView(labelView, new LinearLayout.LayoutParams(WRAP, WRAP));
        exit.setBackground(pressable(null, withAlpha(p.text, 0.1f), dp(context, 10)));
        exit.setClickable(true);
        exit.setFocusable(true);
        exit.setContentDescription(label);
        exit.setOnClickListener(v -> action.run());
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(WRAP, WRAP);
        params.gravity = Gravity.CENTER_HORIZONTAL;
        exit.setLayoutParams(params);
        return exit;
    }

    /** « ——— ou ——— » entre deux façons de soutenir. */
    public static View orSeparator(Context context, Palette p, String or) {
        LinearLayout row = row(context);
        int pad = dp(context, 2);
        row.setPadding(0, pad, 0, pad);
        View left = new View(context);
        left.setBackgroundColor(p.line);
        row.addView(left, new LinearLayout.LayoutParams(0, dp(context, 1), 1));
        TextView label = text(context, or, 13, REGULAR, p.text2);
        int margin = dp(context, 10);
        label.setPadding(margin, 0, margin, 0);
        row.addView(label, new LinearLayout.LayoutParams(WRAP, WRAP));
        View right = new View(context);
        right.setBackgroundColor(p.line);
        row.addView(right, new LinearLayout.LayoutParams(0, dp(context, 1), 1));
        row.setLayoutParams(linear(MATCH, WRAP));
        return row;
    }

    // -------------------- Le composant « fonctionnalités » (§ 2.2) --------------------

    /**
     * Neutre, réutilisé sur l'annonce, J−3, J0, « Merci » et le cadeau, avec l'état qui va. ⛔ Rien
     * de ce qui est « disponible, pour toujours » n'y porte jamais « en pause ».
     *
     * @param extrasOnly sur l'abonnement : ce qu'on DÉBLOQUE, pas ce qu'on a déjà (§ 2.2).
     */
    public static View featureList(
            Context context, Palette p, ExtrasState extras, boolean extrasOnly) {
        LinearLayout list = column(context);
        int pad = dp(context, 14);
        list.setPadding(pad, pad, pad, pad);
        list.setBackground(rounded(p.panel, dp(context, 16)));
        if (!extrasOnly) {
            list.addView(
                    text(context, ReferralStrings.get(context, "features.freeHead"), 13, SEMIBOLD, p.text));
            addFeatureRow(context, p, list, R.drawable.browther_referral_glyph_eye_slash,
                    ReferralStrings.get(context, "features.essential.blur"), check(context, p));
            addFeatureRow(context, p, list, R.drawable.browther_intro_glyph_shield,
                    ReferralStrings.get(context, "features.essential.shields"), check(context, p));
            addFeatureRow(context, p, list, R.drawable.browther_referral_glyph_globe,
                    ReferralStrings.get(context, "features.essential.browsing"), check(context, p));
            gap(list, 14);
        }
        list.addView(
                text(
                        context,
                        ReferralStrings.get(
                                context, extrasOnly ? "features.gainHead" : "features.extrasHead"),
                        13,
                        SEMIBOLD,
                        p.text));
        addFeatureRow(context, p, list, R.drawable.browther_intro_glyph_music_note,
                ReferralStrings.get(context, "features.extras.musicRemoval"),
                statePill(context, p, extras));
        list.setLayoutParams(linear(MATCH, WRAP));
        return list;
    }

    private static void addFeatureRow(
            Context context, Palette p, LinearLayout list, int icon, String name, View trailing) {
        LinearLayout row = row(context);
        row.setPadding(0, dp(context, 8), 0, 0);
        ImageView glyph = glyph(context, icon, 16, p.text2);
        LinearLayout.LayoutParams glyphParams = new LinearLayout.LayoutParams(dp(context, 16), dp(context, 16));
        glyphParams.setMarginEnd(dp(context, 12));
        row.addView(glyph, glyphParams);
        TextView label = text(context, name, 15, REGULAR, p.text);
        row.addView(label, new LinearLayout.LayoutParams(0, WRAP, 1));
        LinearLayout.LayoutParams trailingParams = new LinearLayout.LayoutParams(WRAP, WRAP);
        trailingParams.setMarginStart(dp(context, 8));
        row.addView(trailing, trailingParams);
        list.addView(row, linear(MATCH, WRAP));
    }

    private static View check(Context context, Palette p) {
        return glyph(context, R.drawable.browther_intro_glyph_check, 14, p.green);
    }

    /** L'état de la fonctionnalité supplémentaire : Offert 1 mois · Jusqu'au … · En pause … · Inclus. */
    public static View statePill(Context context, Palette p, ExtrasState extras) {
        String label;
        int tone;
        switch (extras.kind) {
            case UNTIL:
                label = ReferralStrings.fill(
                        ReferralStrings.get(context, "features.until"),
                        "date", ReferralFormat.date(context, extras.until, false));
                tone = p.green;
                break;
            case SOON:
                label = ReferralStrings.plural(context, "features.soon", extras.days);
                tone = p.gold;
                break;
            case PAUSED:
                label = ReferralStrings.get(context, "features.paused");
                tone = p.gold;
                break;
            case INCLUDED:
                label = ReferralStrings.get(context, "features.included");
                tone = p.green;
                break;
            case OFFERED:
            default:
                label = ReferralStrings.get(context, "features.offered");
                tone = p.green;
                break;
        }
        TextView pill = text(context, label, 12, SEMIBOLD, tone);
        pill.setSingleLine(true);
        pill.setEllipsize(TextUtils.TruncateAt.END);
        int padH = dp(context, 8);
        int padV = dp(context, 3);
        pill.setPadding(padH, padV, padH, padV);
        pill.setBackground(rounded(withAlpha(tone, 0.12f), dp(context, 100)));
        return pill;
    }

    // -------------------- Mouvement et haptique --------------------

    /** « Réduire les animations » du système (durées d'animation à zéro). */
    public static boolean reduceMotion(Context context) {
        try {
            return Settings.Global.getFloat(
                            context.getContentResolver(), Settings.Global.ANIMATOR_DURATION_SCALE, 1f)
                    == 0f;
        } catch (RuntimeException e) {
            return false;
        }
    }

    /** L'haptique de succès (validation, « à vie », cadeau). */
    public static void success(View view) {
        view.performHapticFeedback(HapticFeedbackConstants.CONFIRM);
    }

    /** Un cran (la jauge, un choix). */
    public static void tick(View view) {
        view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK);
    }

    /** Un refus (code invalide). */
    public static void reject(View view) {
        view.performHapticFeedback(HapticFeedbackConstants.REJECT);
    }

    public static final PathInterpolator EASE_OUT = new PathInterpolator(0.23f, 1f, 0.32f, 1f);
}
