/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_referral;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.BitmapShader;
import android.graphics.Canvas;
import android.graphics.LinearGradient;
import android.graphics.Matrix;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.RectF;
import android.graphics.Shader;
import android.graphics.Typeface;
import android.graphics.drawable.Drawable;

import androidx.annotation.Nullable;

import org.chromium.chrome.R;

import java.io.IOException;
import java.io.InputStream;

/**
 * ⭐ La carte B9 « Onglets + barre » (2026-09-28) — port de {@code ReferralCardFace} iOS, cote pour
 * cote. {@code devndin/docs/PARRAINAGE-partage-statut.md} § 2 : une carte par produit ; celle de
 * Browther est la carte encre (dégradé {@code #22272a → #16191a → #0f1110}, vagues sauge et or) avec
 * l'interface d'un navigateur DESSINÉE dessus : pastilles du Mac, onglets « Parrainage » (favicon =
 * l'icône) + « YouTube », flèches, barre d'adresse.
 *
 * <p>⚠️ Dessinée dans l'espace de la maquette (<b>330 × 208</b>) : l'appelant met le canevas à
 * l'échelle. Ainsi le lien tient EN ENTIER à toute largeur (⛔ jamais « … » : au pire, un peu plus
 * petit), et l'image du statut ({@link ReferralStatusImage}) la dessine telle quelle, plus grande.
 *
 * <p>Deux faces :
 *
 * <ul>
 *   <li>{@link #app} : le lien dans la barre d'adresse, « Copier » ({@code #7c916f}) à sa droite ;
 *   <li>{@link #status} : ⛔ ni lien ni « Copier » (rien n'y est cliquable) — la barre dit ce que
 *       fait l'app (bouclier), et « 1 mois de bonus » (or) remplace le bouton.
 * </ul>
 *
 * <p>⚠️ Couleurs FIXES dans les deux thèmes : une carte n'a pas de thème. En arabe ({@code rtl}),
 * elle se lit en miroir (pastilles et icône à droite, puce à gauche, flèches retournées) ; le code et
 * le lien restent de gauche à droite.
 *
 * <p>⚠️ Piège déjà payé (§ 8.7) : un {@code Paint} réutilisé garde l'alpha du dernier trait, et un
 * dégradé en HÉRITE — {@code setColor(0xFFFFFFFF)} avant chaque dégradé.
 */
public final class ReferralCardFace {
    public static final float WIDTH = 330f;
    public static final float HEIGHT = 208f;

    private static final int INK = 0xFFF0F1ED;
    private static final int GOLD = 0xFFC4A572;
    private static final float PAD_H = 18f;
    private static final float PAD_V = 16f;
    private static final float RADIUS = 18f;

    /** Les images de la carte, chargées une fois (la carte se redessine à chaque reflet). */
    public static final class Art {
        final @Nullable Bitmap icon;
        final Drawable wordmark;
        final Drawable devndin;
        final Drawable lock;
        final Drawable shield;
        final Drawable copy;
        final Drawable check;

        private Art(Context context) {
            icon = loadIcon(context);
            wordmark = drawable(context, R.drawable.browther_referral_wordmark, 0);
            devndin = drawable(context, R.drawable.browther_intro_devndin_logo, 0);
            lock = drawable(context, R.drawable.browther_intro_glyph_lock, 0xFFA5B299);
            shield = drawable(context, R.drawable.browther_intro_glyph_shield, 0xFFA5B299);
            copy = drawable(context, R.drawable.browther_referral_glyph_copy, 0xFFFAFBF9);
            check = drawable(context, R.drawable.browther_intro_glyph_check, 0xFFFAFBF9);
        }

        private static @Nullable Art sArt;

        public static Art get(Context context) {
            if (sArt == null) sArt = new Art(context.getApplicationContext());
            return sArt;
        }

        private static Drawable drawable(Context context, int id, int tint) {
            Drawable drawable = context.getResources().getDrawable(id, null).mutate();
            if (tint != 0) drawable.setTint(tint);
            return drawable;
        }

        /** L'icône de l'app : celle de l'introduction (mêmes assets, déjà dans l'APK). */
        private static @Nullable Bitmap loadIcon(Context context) {
            try (InputStream input =
                    context.getAssets().open("browther_intro/browther-app-icon.png")) {
                return BitmapFactory.decodeStream(input);
            } catch (IOException e) {
                return null;
            }
        }
    }

    private final String mCode;
    private final boolean mStatusFace;
    private final @Nullable String mLink;
    private String mCopyLabel;
    private boolean mCopied;
    private final @Nullable String mOmni;
    private final @Nullable String mGift;
    private final String mTab;
    private final String mLabel;
    private final String mTag;
    private final boolean mRtl;
    private final Art mArt;

    private final Paint mFill = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint mStroke = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint mText =
            new Paint(Paint.ANTI_ALIAS_FLAG | Paint.SUBPIXEL_TEXT_FLAG | Paint.LINEAR_TEXT_FLAG);
    private final Path mClip = new Path();
    private final Path mWaves = new Path();
    private final Path mWavesGold = new Path();
    private final Path mChip = new Path();
    private final Path mChevrons = new Path();
    private final RectF mRect = new RectF();
    private final RectF mCard = new RectF(0, 0, WIDTH, HEIGHT);
    private final LinearGradient mBackground;
    private final LinearGradient mGloss;
    private final LinearGradient mChipGradient;
    private final LinearGradient mShineGradient;
    private @Nullable BitmapShader mIconShader;
    private final Matrix mIconMatrix = new Matrix();

    // La mise en page (espace de la maquette, gauche → droite ; le miroir se fait au dessin).
    private float mTabWidth;
    private float mTabTextWidth;
    private float mBarLeft;
    private float mBarRight;
    private float mBarTextSize;
    private float mTrailWidth;
    private float mTrailTextWidth;
    private float mMiddleTop;
    private float mLabelWidth;
    private float mLabelHeight;
    private float mCodeWidth;
    private float mTagSize;
    private float mTagWidth;
    private float mPillWidth;
    private final RectF mCopyRect = new RectF();

    private ReferralCardFace(
            Context context,
            String code,
            boolean statusFace,
            @Nullable String link,
            @Nullable String copyLabel,
            @Nullable String omni,
            @Nullable String gift,
            String tab,
            String label,
            String tag,
            boolean rtl) {
        mCode = code;
        mStatusFace = statusFace;
        mLink = link;
        mCopyLabel = copyLabel == null ? "" : copyLabel;
        mOmni = omni;
        mGift = gift;
        mTab = tab;
        mLabel = label;
        mTag = tag;
        mRtl = rtl;
        mArt = Art.get(context);

        mBackground =
                new LinearGradient(
                        WIDTH * 0.18f, 0, WIDTH * 0.82f, HEIGHT,
                        new int[] {0xFF22272A, 0xFF16191A, 0xFF0F1110},
                        new float[] {0f, 0.5f, 1f},
                        Shader.TileMode.CLAMP);
        mGloss =
                new LinearGradient(
                        0, 0, WIDTH * 0.4f, HEIGHT * 0.5f,
                        0x29FFFFFF, 0x00FFFFFF,
                        Shader.TileMode.CLAMP);
        mChipGradient =
                new LinearGradient(
                        0, 0, 46, 36,
                        new int[] {0xFFEFDCB2, 0xFFC4A572, 0xFF8E6B30},
                        new float[] {0f, 0.55f, 1f},
                        Shader.TileMode.CLAMP);
        mShineGradient =
                new LinearGradient(
                        0, 0, 110, 0,
                        new int[] {0x00FFFFFF, 0x38FFFFFF, 0x00FFFFFF},
                        null,
                        Shader.TileMode.CLAMP);
        if (mArt.icon != null) {
            mIconShader = new BitmapShader(mArt.icon, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP);
        }
        mClip.addRoundRect(mCard, RADIUS, RADIUS, Path.Direction.CW);
        buildWaves();
        buildChip();
        layout();
    }

    /** La face de l'app : le lien EN ENTIER dans la barre, « Copier » à sa droite. */
    public static ReferralCardFace app(
            Context context,
            String code,
            String link,
            String copyLabel,
            String tab,
            String label,
            String tag,
            boolean rtl) {
        return new ReferralCardFace(
                context, code, false, link, copyLabel, null, null, tab, label, tag, rtl);
    }

    /** La face du statut : ⛔ ni lien ni « Copier » ; ce que fait l'app, et le mois de bonus. */
    public static ReferralCardFace status(
            Context context,
            String code,
            String omni,
            String gift,
            String tab,
            String label,
            String tag,
            boolean rtl) {
        return new ReferralCardFace(
                context, code, true, null, null, omni, gift, tab, label, tag, rtl);
    }

    /** « Copier » ↔ « Copié ✓ » (deux secondes après une copie). */
    public void setCopied(boolean copied, String label) {
        mCopied = copied;
        mCopyLabel = label;
        layout();
    }

    /** Le rectangle de « Copier », dans l'espace de la maquette (déjà en miroir en arabe). */
    public RectF copyRect() {
        return mCopyRect;
    }

    // -------------------- Mise en page --------------------

    private void layout() {
        // 1ʳᵉ rangée : l'onglet actif.
        setText(9f, ReferralUi.SEMIBOLD, false, 0f);
        mTabTextWidth = mText.measureText(mTab);
        mTabWidth = 8 + 11 + 5 + mTabTextWidth + 8;

        // 2ᵉ rangée : ‹ › (14) · 8 · la barre · 8 · « Copier » ou ce que donne le code.
        mBarLeft = PAD_H + 14 + 8;
        if (mStatusFace) {
            setText(9f, ReferralUi.SEMIBOLD, false, 0f);
            mTrailTextWidth = mText.measureText(mGift == null ? "" : mGift);
            mTrailWidth = mTrailTextWidth;
        } else {
            setText(10f, ReferralUi.SEMIBOLD, false, 0f);
            mTrailTextWidth = mText.measureText(mCopyLabel);
            mTrailWidth = 9 + 9 + 4 + mTrailTextWidth + 9;
        }
        mBarRight = WIDTH - PAD_H - mTrailWidth - 8;
        // ⛔ Jamais tronqué : le texte de la barre rétrécit s'il le faut, jusqu'à tenir en entier.
        float room = (mBarRight - mBarLeft) - 9 - 7.5f - 6 - 9;
        mBarTextSize = mStatusFace ? 8.6f : 9f;
        setBarText(mBarTextSize);
        float width = mText.measureText(barText());
        if (width > room && width > 0) mBarTextSize *= room / width;
        float copyTop = 40 + (21 - 19) / 2f;
        mCopyRect.set(
                mirrorLeft(WIDTH - PAD_H - mTrailWidth, mTrailWidth),
                copyTop,
                mirrorLeft(WIDTH - PAD_H - mTrailWidth, mTrailWidth) + mTrailWidth,
                copyTop + 19);

        // Au centre : le libellé et le code, centrés entre la barre et le bas.
        setLabelText();
        Paint.FontMetrics label = mText.getFontMetrics();
        mLabelWidth = mText.measureText(labelText());
        mLabelHeight = label.descent - label.ascent;
        setCodeText();
        Paint.FontMetrics code = mText.getFontMetrics();
        mCodeWidth = mText.measureText(mCode);
        float block = mLabelHeight + 5 + (code.descent - code.ascent);
        float top = 61;
        float bottom = HEIGHT - PAD_V - 30;
        mMiddleTop = top + (bottom - top - block) / 2;

        // En bas : la pastille « Un projet dev&din », sans jamais toucher le logotype.
        float wordmarkRight = PAD_H + 30 + 8 + wordmarkWidth();
        mTagSize = 11f;
        setText(mTagSize, ReferralUi.MEDIUM, false, 0f);
        mTagWidth = mText.measureText(mTag);
        float logo = 16 * 33.5f / 15;
        float maxTag = (WIDTH - PAD_H) - (wordmarkRight + 4) - 11 - 6 - logo - 10;
        if (mTagWidth > maxTag && maxTag > 0) {
            mTagSize *= maxTag / mTagWidth;
            mTagWidth = maxTag;
        }
        mPillWidth = 11 + mTagWidth + 6 + logo + 10;
    }

    private String barText() {
        String text = mStatusFace ? mOmni : mLink;
        return text == null ? "" : text;
    }

    private String labelText() {
        return mRtl ? mLabel : mLabel.toUpperCase(java.util.Locale.ROOT);
    }

    private void setBarText(float size) {
        if (mStatusFace) {
            setText(size, ReferralUi.SEMIBOLD, false, 0f);
        } else {
            setText(size, ReferralUi.REGULAR, true, 0f);
        }
    }

    private void setLabelText() {
        if (mRtl) {
            setText(10.5f, ReferralUi.SEMIBOLD, false, 0f);
        } else {
            setText(9.5f, ReferralUi.SEMIBOLD, false, 1.7f / 9.5f);
        }
    }

    private void setCodeText() {
        setText(27f, ReferralUi.BOLD, false, 0.17f);
    }

    private void setText(float size, int weight, boolean mono, float letterSpacing) {
        mText.setTextSize(size);
        mText.setTypeface(
                Typeface.create(mono ? Typeface.MONOSPACE : Typeface.DEFAULT, weight, false));
        mText.setLetterSpacing(letterSpacing);
        mText.setTextAlign(Paint.Align.LEFT);
        mText.setShader(null);
    }

    private float wordmarkWidth() {
        int w = mArt.wordmark.getIntrinsicWidth();
        int h = mArt.wordmark.getIntrinsicHeight();
        return h <= 0 ? 112.4f : 20f * w / h;
    }

    /** Le bord gauche d'un élément de largeur {@code width} posé à {@code left} (LTR), en miroir. */
    private float mirrorLeft(float left, float width) {
        return mRtl ? WIDTH - left - width : left;
    }

    private void buildWaves() {
        int count = (int) Math.ceil((HEIGHT + 30) / 10.0);
        for (int i = 0; i < count; i++) {
            double base = -5 + i * 10.0;
            double phase = i * 0.18;
            Path path = i % 6 == 0 ? mWavesGold : mWaves;
            boolean first = true;
            for (double x = -10; x <= 340; x += 6) {
                double u = x * 0.024;
                double y =
                        base
                                + (Math.sin(u + phase) * 5
                                        + Math.sin(u * 2.1 + phase * 1.7) * 2.5
                                        + Math.sin(u * 0.4) * 2);
                if (first) {
                    path.moveTo((float) x, (float) y);
                    first = false;
                } else {
                    path.lineTo((float) x, (float) y);
                }
            }
        }
    }

    /** Les pistes de la puce, dans son propre espace (46 × 36). */
    private void buildChip() {
        float sx = 46f / 36;
        float sy = 36f / 28;
        for (float y : new float[] {9.5f, 18.5f}) {
            mChip.moveTo(0, y * sy);
            mChip.lineTo(12 * sx, y * sy);
            mChip.moveTo(24 * sx, y * sy);
            mChip.lineTo(36 * sx, y * sy);
        }
        for (float x : new float[] {12f, 24f}) {
            mChip.moveTo(x * sx, 0);
            mChip.lineTo(x * sx, 28 * sy);
        }
        mChip.moveTo(12 * sx, 14 * sy);
        mChip.lineTo(24 * sx, 14 * sy);
    }

    // -------------------- Dessin --------------------

    /**
     * Dessine la carte dans l'espace de la maquette (330 × 208, origine en haut à gauche).
     *
     * @param shine le reflet qui balaie la carte (de −0,4 à 1) ; hors de cet intervalle, pas de
     *     reflet.
     */
    public void draw(Canvas canvas, float shine) {
        canvas.save();
        canvas.clipPath(mClip);

        mFill.setStyle(Paint.Style.FILL);
        mFill.setColor(0xFFFFFFFF);
        mFill.setShader(mBackground);
        canvas.drawRect(mCard, mFill);
        mFill.setShader(null);

        // Les vagues des créas de la régie (base sauge à .20, une ligne sur six en or à .38).
        mStroke.setStyle(Paint.Style.STROKE);
        mStroke.setShader(null);
        mStroke.setStrokeCap(Paint.Cap.BUTT);
        mStroke.setStrokeWidth(0.6f);
        mStroke.setColor(0x337C916F);
        canvas.drawPath(mWaves, mStroke);
        mStroke.setStrokeWidth(0.8f);
        mStroke.setColor(0x61B88C3E);
        canvas.drawPath(mWavesGold, mStroke);

        mFill.setColor(0xFFFFFFFF);
        mFill.setShader(mGloss);
        canvas.drawRect(mCard, mFill);
        mFill.setShader(null);

        if (shine > -0.4f && shine < 1f) {
            canvas.save();
            float x = shine * 594 - 66;
            canvas.rotate(18, x + 55, -56 + 160);
            canvas.translate(x, -56);
            mFill.setColor(0xFFFFFFFF);
            mFill.setShader(mShineGradient);
            canvas.drawRect(0, 0, 110, 320, mFill);
            mFill.setShader(null);
            canvas.restore();
        }

        drawTabs(canvas);
        drawBar(canvas);
        drawMiddle(canvas);
        drawBottom(canvas);
        drawChip(canvas);
        canvas.restore();

        mStroke.setStrokeWidth(1f);
        mStroke.setColor(0x1FFFFFFF);
        mRect.set(0.5f, 0.5f, WIDTH - 0.5f, HEIGHT - 0.5f);
        canvas.drawRoundRect(mRect, RADIUS - 0.5f, RADIUS - 0.5f, mStroke);
    }

    // 1ʳᵉ rangée : les pastilles du Mac, l'onglet actif, l'onglet YouTube.
    private void drawTabs(Canvas canvas) {
        float cy = PAD_V + 9.5f;
        int[] dots = {0xFFFF5F57, 0xFFFEBC2E, 0xFF28C840};
        mFill.setStyle(Paint.Style.FILL);
        for (int i = 0; i < 3; i++) {
            mFill.setColor(dots[i]);
            canvas.drawCircle(mirrorLeft(PAD_H + i * 14, 9) + 4.5f, cy, 4.5f, mFill);
        }
        float tabLeft = PAD_H + 37 + 7;
        float left = mirrorLeft(tabLeft, mTabWidth);
        mRect.set(left, PAD_V, left + mTabWidth, PAD_V + 19);
        mFill.setColor(0x1AFFFFFF);
        canvas.drawRoundRect(mRect, 7, 7, mFill);
        drawIcon(canvas, mirrorLeft(tabLeft + 8, 11), cy - 5.5f, 11, 3);
        setText(9f, ReferralUi.SEMIBOLD, false, 0f);
        mText.setColor(INK);
        drawTextLine(canvas, mTab, mirrorLeft(tabLeft + 8 + 11 + 5, mTabTextWidth), cy);

        float ytLeft = tabLeft + mTabWidth + 7 + 8;
        mFill.setColor(0xFFFF3B30);
        float red = mirrorLeft(ytLeft, 10);
        mRect.set(red, cy - 3.5f, red + 10, cy + 3.5f);
        canvas.drawRoundRect(mRect, 2, 2, mFill);
        setText(9f, ReferralUi.MEDIUM, false, 0f);
        mText.setColor(ReferralUi.withAlpha(INK, 0.5f));
        float ytWidth = mText.measureText("YouTube");
        drawTextLine(canvas, "YouTube", mirrorLeft(ytLeft + 10 + 5, ytWidth), cy);
    }

    // 2ᵉ rangée : ‹ › · la barre d'adresse · « Copier » (ou ce que donne le code).
    private void drawBar(Canvas canvas) {
        float cy = 40 + 10.5f;
        // Les flèches : dessinées, et retournées en arabe avec le reste.
        canvas.save();
        if (mRtl) canvas.scale(-1, 1, WIDTH / 2, 0);
        mChevrons.reset();
        mChevrons.moveTo(PAD_H + 4.5f, cy - 4f);
        mChevrons.lineTo(PAD_H + 1f, cy);
        mChevrons.lineTo(PAD_H + 4.5f, cy + 4f);
        mStroke.setStrokeWidth(1.6f);
        mStroke.setStrokeCap(Paint.Cap.ROUND);
        mStroke.setStrokeJoin(Paint.Join.ROUND);
        mStroke.setColor(ReferralUi.withAlpha(INK, 0.65f));
        canvas.drawPath(mChevrons, mStroke);
        mChevrons.reset();
        mChevrons.moveTo(PAD_H + 9.5f, cy - 4f);
        mChevrons.lineTo(PAD_H + 13f, cy);
        mChevrons.lineTo(PAD_H + 9.5f, cy + 4f);
        mStroke.setColor(ReferralUi.withAlpha(INK, 0.23f));
        canvas.drawPath(mChevrons, mStroke);
        canvas.restore();
        mStroke.setStrokeCap(Paint.Cap.BUTT);

        // La barre d'adresse.
        float barWidth = mBarRight - mBarLeft;
        float left = mirrorLeft(mBarLeft, barWidth);
        mRect.set(left, 40, left + barWidth, 61);
        mFill.setStyle(Paint.Style.FILL);
        mFill.setColor(0x12FFFFFF);
        canvas.drawRoundRect(mRect, 8, 8, mFill);
        mRect.inset(0.5f, 0.5f);
        mStroke.setStrokeWidth(1f);
        mStroke.setColor(0x17FFFFFF);
        canvas.drawRoundRect(mRect, 7.5f, 7.5f, mStroke);
        Drawable icon = mStatusFace ? mArt.shield : mArt.lock;
        float iconLeft = mirrorLeft(mBarLeft + 9 - 1.5f, 10.5f);
        drawDrawable(canvas, icon, iconLeft, cy - 5.25f, 10.5f, 10.5f);
        setBarText(mBarTextSize);
        mText.setColor(0xFFD9DBD5);
        String text = barText();
        float textWidth = mText.measureText(text);
        // Le lien se lit de gauche à droite, même en arabe (il part de l'icône).
        float textLeft =
                mRtl ? left + barWidth - 9 - 7.5f - 6 - textWidth : mBarLeft + 9 + 7.5f + 6;
        drawTextLine(canvas, text, textLeft, cy);

        float trailLeft = mirrorLeft(WIDTH - PAD_H - mTrailWidth, mTrailWidth);
        if (mStatusFace) {
            setText(9f, ReferralUi.SEMIBOLD, false, 0f);
            mText.setColor(GOLD);
            drawTextLine(canvas, mGift == null ? "" : mGift, trailLeft, cy);
            return;
        }
        mFill.setColor(0xFF7C916F);
        canvas.drawRoundRect(mCopyRect, 9.5f, 9.5f, mFill);
        float contentLeft = mRtl ? trailLeft + mTrailWidth - 9 - 9 : trailLeft + 9;
        drawDrawable(canvas, mCopied ? mArt.check : mArt.copy, contentLeft - 1, cy - 5.5f, 11, 11);
        setText(10f, ReferralUi.SEMIBOLD, false, 0f);
        mText.setColor(0xFFFAFBF9);
        float labelLeft =
                mRtl ? contentLeft - 4 - mTrailTextWidth : contentLeft + 9 + 4;
        drawTextLine(canvas, mCopyLabel, labelLeft, cy);
    }

    // Au centre : le libellé et le code (de gauche à droite, même en arabe).
    private void drawMiddle(Canvas canvas) {
        setLabelText();
        mText.setColor(GOLD);
        Paint.FontMetrics label = mText.getFontMetrics();
        canvas.drawText(
                labelText(), mirrorLeft(PAD_H, mLabelWidth), mMiddleTop - label.ascent, mText);
        setCodeText();
        mText.setColor(INK);
        Paint.FontMetrics code = mText.getFontMetrics();
        canvas.drawText(
                mCode,
                mirrorLeft(PAD_H, mCodeWidth),
                mMiddleTop + mLabelHeight + 5 - code.ascent,
                mText);
    }

    // En bas : l'icône et le logotype, la pastille « Un projet dev&din ».
    private void drawBottom(Canvas canvas) {
        float top = HEIGHT - PAD_V - 30;
        float cy = top + 15;
        float iconLeft = mirrorLeft(PAD_H, 30);
        mFill.setStyle(Paint.Style.FILL);
        mFill.setColor(0xFF000000);
        mFill.setShadowLayer(3, 0, 2, 0x4D000000);
        mRect.set(iconLeft, top, iconLeft + 30, top + 30);
        canvas.drawRoundRect(mRect, 8, 8, mFill);
        mFill.clearShadowLayer();
        drawIcon(canvas, iconLeft, top, 30, 8);
        float wordmark = wordmarkWidth();
        drawDrawable(canvas, mArt.wordmark, mirrorLeft(PAD_H + 38, wordmark), cy - 10, wordmark, 20);

        float pillLeft = mirrorLeft(WIDTH - PAD_H - mPillWidth, mPillWidth);
        mRect.set(pillLeft, cy - 13, pillLeft + mPillWidth, cy + 13);
        mFill.setColor(0x14FFFFFF);
        canvas.drawRoundRect(mRect, 13, 13, mFill);
        mRect.inset(0.5f, 0.5f);
        mStroke.setStrokeWidth(1f);
        mStroke.setColor(0x38FFFFFF);
        canvas.drawRoundRect(mRect, 12.5f, 12.5f, mStroke);
        float logo = 16 * 33.5f / 15;
        setText(mTagSize, ReferralUi.MEDIUM, false, 0f);
        mText.setColor(0xD1FFFFFF);
        // Dans la pastille : « Un projet » puis le logo (le logo à gauche en arabe).
        float tagLeft = mRtl ? pillLeft + 10 + logo + 6 : pillLeft + 11;
        float logoLeft = mRtl ? pillLeft + 10 : pillLeft + 11 + mTagWidth + 6;
        drawTextLine(canvas, mTag, tagLeft, cy);
        drawDrawable(canvas, mArt.devndin, logoLeft, cy - 8, logo, 16);
    }

    /** La puce : ce qui fait lire « carte » au premier coup d'œil (centre à 40 % de la hauteur). */
    private void drawChip(Canvas canvas) {
        float left = mirrorLeft(WIDTH - 32 - 46, 46);
        float top = HEIGHT * 0.4f - 18;
        canvas.save();
        canvas.translate(left, top);
        mRect.set(0, 0, 46, 36);
        mFill.setStyle(Paint.Style.FILL);
        mFill.setColor(0xFFFFFFFF);
        mFill.setShader(mChipGradient);
        canvas.drawRoundRect(mRect, 8, 8, mFill);
        mFill.setShader(null);
        mStroke.setStrokeWidth(1f);
        mStroke.setColor(0x59000000);
        canvas.save();
        canvas.clipRect(mRect);
        canvas.drawPath(mChip, mStroke);
        canvas.restore();
        mRect.inset(0.5f, 0.5f);
        mStroke.setColor(0x33000000);
        canvas.drawRoundRect(mRect, 7.5f, 7.5f, mStroke);
        canvas.restore();
    }

    /** Une ligne de texte centrée verticalement sur {@code cy}. */
    private void drawTextLine(Canvas canvas, String text, float left, float cy) {
        Paint.FontMetrics fm = mText.getFontMetrics();
        canvas.drawText(text, left, cy - (fm.ascent + fm.descent) / 2, mText);
    }

    /** L'icône de l'app, arrondie. */
    private void drawIcon(Canvas canvas, float left, float top, float size, float radius) {
        if (mIconShader == null || mArt.icon == null) return;
        float scale = size / mArt.icon.getWidth();
        mIconMatrix.setScale(scale, scale);
        mIconMatrix.postTranslate(left, top);
        mIconShader.setLocalMatrix(mIconMatrix);
        mFill.setStyle(Paint.Style.FILL);
        mFill.setColor(0xFFFFFFFF);
        mFill.setShader(mIconShader);
        mRect.set(left, top, left + size, top + size);
        canvas.drawRoundRect(mRect, radius, radius, mFill);
        mFill.setShader(null);
    }

    private static void drawDrawable(
            Canvas canvas, Drawable drawable, float left, float top, float width, float height) {
        // Les bornes d'un Drawable sont entières : on les pose à ×100 et on réduit le canevas.
        canvas.save();
        canvas.translate(left, top);
        canvas.scale(0.01f, 0.01f);
        drawable.setBounds(0, 0, Math.round(width * 100), Math.round(height * 100));
        drawable.draw(canvas);
        canvas.restore();
    }
}
