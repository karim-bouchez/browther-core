/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_intro;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.os.SystemClock;
import android.view.View;

import java.util.Random;

/**
 * La récompense du geste : quand l'interrupteur passe sur ON, une gerbe de confettis tombe du haut
 * de l'écran et <b>s'éteint en chemin</b>. Rendue par-dessus tout l'écran, jamais dans la vignette
 * qui la déclenche.
 *
 * <p>Patron « falling confetti » (ONBOARDING-SPEC.md § 3.6), cinq points, tous nécessaires : durée
 * de vie et retard au départ propres à chaque confetti ; vitesse initiale et pesanteur propres ;
 * dérive latérale oscillante ; bascule sur l'axe vertical (le rectangle s'aplatit puis se rouvre) ;
 * fondu à partir de mi-vie. ⛔ Une chute uniforme de haut en bas avec disparition au bord donne un
 * champ qui glisse d'un bloc : c'est ce qui a été refusé.
 *
 * <p>Une seule passe de dessin pour toute la gerbe, pas une vue par confetti.
 */
final class BrowtherIntroConfetti extends View {
    private static final int COUNT = 160;
    private static final float MAX_LIFETIME = 2.3f;
    private static final float MAX_DELAY = 0.7f;

    /** Les teintes de la marque, plus un blanc cassé pour la lumière. */
    private static final int[] PALETTE = {
        BrowtherIntroUi.SAGE,
        BrowtherIntroUi.GOLD,
        BrowtherIntroUi.HALAL,
        BrowtherIntroUi.CREAM,
        0xFF34C759,
    };

    private static final class Piece {
        float mX;
        float mWidth;
        float mHeight;
        int mColor;
        float mSpin;
        float mDelay;
        float mLifetime;
        float mSpeed;
        float mGravity;
        float mSwayWidth;
        float mSwayRate;
        float mSwayPhase;
        float mFlipRate;
        float mFlipPhase;
    }

    private final Paint mPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Piece[] mPieces = new Piece[COUNT];
    private final float mDensity;
    private long mStart = -1;

    BrowtherIntroConfetti(Context context) {
        super(context);
        mDensity = context.getResources().getDisplayMetrics().density;
        setImportantForAccessibility(IMPORTANT_FOR_ACCESSIBILITY_NO);
        setClickable(false);
        setFocusable(false);
        for (int i = 0; i < COUNT; i++) mPieces[i] = new Piece();
    }

    /** Tire une nouvelle gerbe. */
    void fire() {
        Random random = new Random();
        for (Piece piece : mPieces) {
            piece.mX = range(random, -0.02f, 1.02f);
            piece.mWidth = range(random, 5f, 10f) * mDensity;
            piece.mHeight = piece.mWidth * range(random, 0.45f, 1.5f);
            piece.mColor = PALETTE[random.nextInt(PALETTE.length)];
            piece.mSpin = range(random, -9f, 9f);
            piece.mDelay = range(random, 0f, MAX_DELAY);
            piece.mLifetime = range(random, 1.1f, MAX_LIFETIME);
            piece.mSpeed = range(random, 0.18f, 0.5f);
            piece.mGravity = range(random, 0.7f, 1.5f);
            piece.mSwayWidth = range(random, 10f, 42f) * mDensity;
            piece.mSwayRate = range(random, 4f, 10f);
            piece.mSwayPhase = range(random, 0f, (float) (2 * Math.PI));
            piece.mFlipRate = range(random, 6f, 16f);
            piece.mFlipPhase = range(random, 0f, (float) (2 * Math.PI));
        }
        mStart = SystemClock.uptimeMillis();
        postInvalidateOnAnimation();
    }

    private static float range(Random random, float min, float max) {
        return min + random.nextFloat() * (max - min);
    }

    @Override
    protected void onDraw(Canvas canvas) {
        if (mStart < 0) return;
        float elapsed = (SystemClock.uptimeMillis() - mStart) / 1000f;
        if (elapsed > MAX_DELAY + MAX_LIFETIME) {
            mStart = -1;
            return;
        }
        float width = getWidth();
        float height = getHeight();
        for (Piece piece : mPieces) {
            float age = elapsed - piece.mDelay;
            if (age <= 0) continue;
            float life = age / piece.mLifetime;
            if (life >= 1) continue;

            // Chute : une vitesse initiale propre, puis la pesanteur. Les confettis ne tombent donc
            // pas en bloc, et beaucoup s'effacent avant d'avoir atteint le bas.
            float travel = piece.mSpeed * life + 0.5f * piece.mGravity * life * life;
            float y = -30 * mDensity + travel * height;
            // Dérive : sans elle, ce sont des cailloux, pas du papier.
            float x =
                    piece.mX * width
                            + (float) Math.sin(life * piece.mSwayRate + piece.mSwayPhase)
                                    * piece.mSwayWidth;

            // ⚠️ Le fondu commence à mi-vie et court jusqu'à zéro : la gerbe s'éteint au lieu de
            // traverser l'écran et de disparaître d'un coup au bord.
            float fade =
                    life < 0.45f ? 1f : (float) Math.pow(Math.max(0f, (1 - life) / 0.55f), 0.85);
            if (fade <= 0.02f) continue;

            // Rotation dans le plan + bascule : le rectangle s'aplatit et se rouvre, comme une
            // languette de papier qui tourne.
            float flip =
                    Math.max(
                            0.12f,
                            Math.abs((float) Math.cos(life * piece.mFlipRate + piece.mFlipPhase)));
            canvas.save();
            canvas.translate(x, y);
            canvas.rotate((float) Math.toDegrees(piece.mSpin * life));
            canvas.scale(flip, 1f);
            mPaint.setColor(piece.mColor);
            mPaint.setAlpha(Math.round(255 * fade));
            canvas.drawRect(
                    -piece.mWidth / 2, -piece.mHeight / 2, piece.mWidth / 2, piece.mHeight / 2,
                    mPaint);
            canvas.restore();
        }
        postInvalidateOnAnimation();
    }
}
