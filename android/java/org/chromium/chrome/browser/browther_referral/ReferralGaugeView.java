/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_referral;

import android.animation.ValueAnimator;
import android.content.Context;
import android.graphics.Canvas;
import android.graphics.LinearGradient;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.RectF;
import android.graphics.Shader;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.text.TextUtils;
import android.view.Choreographer;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.VelocityTracker;
import android.view.View;
import android.view.ViewConfiguration;
import android.view.ViewParent;
import android.view.accessibility.AccessibilityNodeInfo;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.TextView;

import androidx.annotation.Nullable;

import org.chromium.chrome.R;
import org.chromium.chrome.browser.browther_referral.core.MilestoneBonus;
import org.chromium.chrome.browser.browther_referral.core.MilestoneScale;

/**
 * La jauge — docs/PARRAINAGE.md § 2.2 et § 12.4, port de {@code ReferralGaugeView.swift} (iOS, la
 * référence : private/docs/PARRAINAGE.md § 8.1).
 *
 * <p>⭐ <b>C'est un JOUET</b> : on la glisse pour voir ce que rapporteraient plus d'invitations. Rien
 * n'est enregistré, rien n'est demandé au serveur. Le barème vient du statut : ⛔ aucun palier
 * recopié ici.
 *
 * <h2>Deux tempéraments (les MÊMES noms partout : ils sortent dans l'analytique)</h2>
 *
 * <ul>
 *   <li><b>{@code toy}</b> (écrans 2b et 4) : « Si j'invite N proches · je gagne M mois », en or.
 *       Elle part d'au moins 1, reste où on la laisse, et se souvient d'un écran à l'autre du même
 *       moment (§ 12.20 : {@code controller.gaugeIntention()}).
 *   <li><b>{@code spring}</b> (écran Parrainage) : au repos elle dit ce qu'on A (vert) ; tirée, ce
 *       qu'on AURAIT (or) ; on ne la tire que vers le HAUT ; relâchée, elle revient en ressort en
 *       partant de l'élan du doigt.
 * </ul>
 *
 * <h2>Pourquoi une physique à la main</h2>
 *
 * <p>Les chiffres défilent EN CHEMIN pendant le retour, la main arrête net la démo là où est le
 * curseur, et le ressort part de l'élan du doigt : un ressort amorti intégré image par image
 * ({@link Motion}, {@link Choreographer}, pas fixe de 1/240 s).
 *
 * <h2>Ce que les recettes mobiles ont appris (§ 12.4, § 12.24)</h2>
 *
 * <ul>
 *   <li>🔴 Horizontal seulement : un doigt qui part à la verticale fait défiler la page — la piste
 *       ne s'engage que si le geste est plus horizontal que vertical, au-delà du seuil du système.
 *   <li>🔴 Le ressort sous le doigt : 0,9 s, amortissement 0,72.
 *   <li>⭐ Un cran se sent par invitation (au doigt seulement), « à vie » atteint au doigt se fête.
 *   <li>⭐ La démo joue à chaque affichage, jusqu'au jour où la personne a tiré le curseur
 *       ELLE-MÊME jusqu'à « à vie ».
 *   <li>⚠️ Hauteurs FIXES au-dessus de la piste : rien ne saute pendant qu'on tire.
 *   <li>⚠️ Piste et chiffres en LTR : 1 → 10 se lit dans ce sens en arabe aussi.
 * </ul>
 */
public class ReferralGaugeView extends LinearLayout {
    public enum Mode {
        TOY("toy"),
        SPRING("spring");

        public final String rawValue;

        Mode(String rawValue) {
            this.rawValue = rawValue;
        }
    }

    private enum MotionSource {
        SYSTEM,
        DEMO,
        USER
    }

    private final Mode mMode;
    private final boolean mDemo;
    private final boolean mPreview;
    private final @Nullable Runnable mOnCelebrate;
    private final ReferralUi.Palette mPalette;
    private final Motion mMotion = new Motion();
    private final Handler mHandler = new Handler(Looper.getMainLooper());

    private int mValidated;
    private MilestoneScale mScale = MilestoneScale.common;
    private boolean mBound;
    private boolean mPulledOnce;
    private boolean mDemoPlayed;
    private long mLastBurst;
    private MotionSource mSource = MotionSource.SYSTEM;
    private boolean mDragging;
    private @Nullable Runnable mOnIntentionChanged;

    // Vues.
    private final TextView mIfLabel;
    private final TextView mLeftNumber;
    private final TextView mLeftUnit;
    private final TextView mThenLabel;
    private final TextView mRightNumber;
    private final TextView mRightUnit;
    private final TextView mBonusLine;
    private final TrackView mTrack;
    private final TicksView mTicks;
    private final @Nullable TextView mFoot;
    private final LifetimeCard mLifetime;

    public ReferralGaugeView(
            Context context,
            Mode mode,
            boolean demo,
            boolean preview,
            @Nullable Runnable onCelebrate) {
        super(context);
        mMode = mode;
        mDemo = demo;
        mPreview = preview;
        mOnCelebrate = onCelebrate;
        mPalette = ReferralUi.palette(context);
        setOrientation(VERTICAL);
        ReferralUi.Palette p = mPalette;

        LinearLayout panel = ReferralUi.column(context);
        int padH = ReferralUi.dp(context, 16);
        panel.setPadding(padH, ReferralUi.dp(context, 12), padH, ReferralUi.dp(context, 10));
        panel.setBackground(ReferralUi.rounded(p.panel, ReferralUi.dp(context, 20)));
        // Les nombres se lisent de gauche à droite, même en arabe.
        panel.setLayoutDirection(LAYOUT_DIRECTION_LTR);

        // Les deux nombres — ⚠️ hauteurs FIXES.
        LinearLayout numbers = ReferralUi.row(context);
        numbers.setGravity(Gravity.TOP);
        LinearLayout left = ReferralUi.column(context);
        mIfLabel = singleLine(ReferralUi.text(context, 13, ReferralUi.REGULAR, p.text2));
        left.addView(mIfLabel);
        LinearLayout leftRow = baselineRow(context);
        mLeftNumber = bigNumber(context);
        mLeftUnit = singleLine(ReferralUi.text(context, 15, ReferralUi.REGULAR, p.text2));
        leftRow.addView(mLeftNumber);
        leftRow.addView(mLeftUnit, unitParams(context));
        left.addView(leftRow, new LayoutParams(ReferralUi.WRAP, ReferralUi.dp(context, 42)));
        numbers.addView(left, new LayoutParams(0, ReferralUi.WRAP, 1));

        LinearLayout right = ReferralUi.column(context);
        right.setGravity(Gravity.END);
        mThenLabel = singleLine(ReferralUi.text(context, 13, ReferralUi.REGULAR, p.text2));
        mThenLabel.setGravity(Gravity.END);
        right.addView(mThenLabel, new LayoutParams(ReferralUi.WRAP, ReferralUi.WRAP));
        LinearLayout rightRow = baselineRow(context);
        rightRow.setGravity(Gravity.BOTTOM | Gravity.END);
        mRightNumber = bigNumber(context);
        mRightUnit = singleLine(ReferralUi.text(context, 15, ReferralUi.REGULAR, p.text2));
        rightRow.addView(mRightNumber);
        rightRow.addView(mRightUnit, unitParams(context));
        right.addView(rightRow, new LayoutParams(ReferralUi.WRAP, ReferralUi.dp(context, 42)));
        numbers.addView(right, new LayoutParams(0, ReferralUi.WRAP, 1));
        panel.addView(numbers, ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP));

        mBonusLine = singleLine(ReferralUi.text(context, 13, ReferralUi.REGULAR, p.text2));
        mBonusLine.setGravity(Gravity.END);
        panel.addView(mBonusLine, ReferralUi.linear(ReferralUi.MATCH, ReferralUi.dp(context, 20)));

        mTrack = new TrackView(context);
        panel.addView(mTrack, ReferralUi.linear(ReferralUi.MATCH, ReferralUi.dp(context, THUMB_DP + 14)));
        mTicks = new TicksView(context);
        panel.addView(mTicks, ReferralUi.linear(ReferralUi.MATCH, ReferralUi.dp(context, 32)));

        // ⛔ Rien sous le ressort de l'écran Parrainage : la démo montre qu'il se tire (§ 12.26).
        if (mode == Mode.TOY) {
            mFoot = ReferralUi.text(context, 13, ReferralUi.REGULAR, p.text2);
            // Le texte, lui, suit la langue (la ligne d'aide n'est pas un nombre).
            mFoot.setTextDirection(TEXT_DIRECTION_LOCALE);
            mFoot.setTextAlignment(TEXT_ALIGNMENT_VIEW_START);
            mFoot.setPadding(0, ReferralUi.dp(context, 2), 0, 0);
            panel.addView(mFoot, ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP));
        } else {
            mFoot = null;
        }
        addView(panel, ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP));

        mLifetime = new LifetimeCard(context, p);
        addView(mLifetime, ReferralUi.linear(ReferralUi.MATCH, ReferralUi.WRAP, ReferralUi.dp(context, 8)));

        setImportantForAccessibility(IMPORTANT_FOR_ACCESSIBILITY_NO);
        render();
    }

    /** L'état réel : invitations validées et barème (lu dans le statut). */
    public void bind(int validated, MilestoneScale scale) {
        MilestoneScale next = scale == null ? MilestoneScale.common : scale;
        boolean changed = mBound && validated != mValidated;
        mValidated = validated;
        mScale = next;
        if (!mBound) {
            mBound = true;
            mMotion.jump(rest());
        } else if (changed && mMode == Mode.SPRING && !mDragging) {
            // L'état réel change (une invitation validée) : la jauge au repos le suit, sans
            // à-coup — ⛔ pas pendant qu'on la tient, ⛔ jamais le jouet.
            mMotion.animate(rest(), 0.35, 1, 0, false, null);
        }
        render();
        playDemoIfNeeded();
    }

    /** Le jouet a été posé ailleurs (le bouton de 2b reprend son nombre, § 12.30). */
    public void setOnIntentionChanged(@Nullable Runnable listener) {
        mOnIntentionChanged = listener;
    }

    // -------------------- Valeurs --------------------

    private int maxValue() {
        return mScale.lifetimeAt;
    }

    private int actual() {
        return Math.max(0, Math.min(maxValue(), mValidated));
    }

    private @Nullable Integer intention() {
        return BrowtherReferralController.get().gaugeIntention();
    }

    private double rest() {
        if (mMode == Mode.SPRING) return actual();
        Integer intention = intention();
        return Math.max(intention != null ? intention : actual(), 1);
    }

    /** Le ressort ne se tire que vers le HAUT : sous l'acquis, il n'y a rien à voir. */
    private double minimum() {
        return mMode == Mode.SPRING ? actual() : 1;
    }

    private int shown() {
        return (int) Math.round(mMotion.position);
    }

    private boolean pulled() {
        return mMode == Mode.SPRING && mSource != MotionSource.SYSTEM && shown() > actual();
    }

    private boolean gold() {
        return mMode == Mode.TOY || pulled();
    }

    // -------------------- Rendu --------------------

    private void render() {
        Context context = getContext();
        ReferralUi.Palette p = mPalette;
        MilestoneScale.Reading reading = mScale.reading(mMotion.position);
        boolean pulled = pulled();
        boolean gold = gold();
        int accentText = gold ? p.gold : p.green;
        int labelColor = gold ? p.gold : p.text2;

        String ifKey = mMode == Mode.TOY ? "gauge.if" : pulled ? "gauge.ifElastic" : "gauge.restIf";
        String thenKey =
                mMode == Mode.TOY ? "gauge.then" : pulled ? "gauge.thenElastic" : "gauge.restThen";
        mIfLabel.setText(ReferralStrings.get(context, ifKey));
        mIfLabel.setTextColor(labelColor);
        mThenLabel.setText(ReferralStrings.get(context, thenKey));
        mThenLabel.setTextColor(labelColor);

        mLeftNumber.setText(String.valueOf(reading.invitations));
        mLeftNumber.setTextColor(p.text);
        mLeftUnit.setText(
                ReferralStrings.plural(
                        context,
                        mMode == Mode.SPRING ? "gauge.unitInv" : "gauge.unit",
                        reading.invitations));

        if (reading.lifetime) {
            mRightNumber.setText(ReferralStrings.get(context, "gauge.lifetime"));
            mRightNumber.setTextColor(p.gold);
            mRightNumber.setTextSize(28);
            mRightUnit.setVisibility(GONE);
        } else {
            mRightNumber.setText(String.valueOf(reading.months));
            mRightNumber.setTextColor(accentText);
            mRightNumber.setTextSize(34);
            mRightUnit.setVisibility(VISIBLE);
            mRightUnit.setText(ReferralStrings.plural(context, "gauge.months", reading.months));
        }

        if (!reading.lifetime && reading.bonusMonths > 0) {
            mBonusLine.setText(
                    ReferralUi.rich(
                            ReferralStrings.fill(
                                    ReferralStrings.get(context, "gauge.bonus"),
                                    "bonus",
                                    String.valueOf(reading.bonusMonths))));
        } else {
            mBonusLine.setText(" ");
        }

        if (mFoot != null) {
            int actual = actual();
            mFoot.setText(
                    actual > 0
                            ? ReferralStrings.plural(context, "gauge.now", actual)
                            : ReferralStrings.get(context, "gauge.help"));
        }

        mLifetime.update(shown(), reading.lifetime, maxValue());
        mTrack.setContentDescription(
                ReferralStrings.get(context, "gauge.a11y")
                        + " : "
                        + reading.invitations
                        + " · "
                        + (reading.lifetime
                                ? ReferralStrings.get(context, "gauge.lifetime")
                                : reading.months
                                        + " "
                                        + ReferralStrings.plural(context, "gauge.months", reading.months)));
        mTrack.invalidate();
        mTicks.invalidate();
    }

    // -------------------- Le geste --------------------

    private double mGrabbedAt;

    private void grab() {
        // ⭐ La main arrête net la démo ou le retour en cours.
        mMotion.stop();
        mDragging = true;
        mSource = MotionSource.USER;
        mGrabbedAt = mMotion.position;
        mTrack.invalidate();
        if (!mPulledOnce) {
            mPulledOnce = true;
            // ⚠️ Une fois par jauge affichée : « on y a touché », pas combien.
            BrowtherReferralController.get()
                    .note("referral_gauge_pulled", mPreview, "mode", mMode.rawValue);
        }
    }

    private void drag(float translation) {
        float span = mTrack.span();
        if (span <= 0) return;
        double next = mGrabbedAt + translation / span * maxValue();
        mMotion.setByHand(Math.max(minimum(), Math.min(maxValue(), next)));
    }

    private void release(int landed, double velocityValuesPerSecond) {
        mDragging = false;
        if (mMode == Mode.SPRING) {
            mMotion.animate(rest(), 0.9, 0.72, velocityValuesPerSecond, true, null);
        } else {
            mMotion.animate(landed, 0.35, 1, velocityValuesPerSecond, false, null);
            setIntention(landed);
        }
        mTrack.invalidate();
    }

    private void tap(float x) {
        float span = mTrack.span();
        if (span <= 0) return;
        double target = Math.round((x - mTrack.edge()) / span * maxValue());
        double landed = Math.max(minimum(), Math.min(maxValue(), target));
        grab();
        mDragging = false;
        if (mMode == Mode.SPRING) {
            // Toucher un palier le montre, puis le ressort ramène à l'acquis.
            mMotion.animate(
                    landed,
                    0.35,
                    1,
                    0,
                    true,
                    () ->
                            mHandler.postDelayed(
                                    () -> {
                                        if (mDragging) return;
                                        mMotion.animate(rest(), 0.9, 0.72, 0, true, null);
                                    },
                                    450));
        } else {
            mMotion.animate(landed, 0.35, 1, 0, true, null);
            setIntention((int) landed);
        }
    }

    private void setIntention(int value) {
        BrowtherReferralController.get().setGaugeIntention(value);
        if (mOnIntentionChanged != null) mOnIntentionChanged.run();
    }

    private void notch(int value, boolean byHand) {
        if (!byHand) return;
        ReferralUi.tick(this);
        if (mScale.understood(value, true)) BrowtherReferralController.get().setGaugeUnderstood();
        if (value >= maxValue()) {
            ReferralUi.success(this);
            // Un va-et-vient au bout de la piste ne tire pas une rafale.
            long now = SystemClock.uptimeMillis();
            if (now - mLastBurst > 2_500) {
                mLastBurst = now;
                if (mOnCelebrate != null) mOnCelebrate.run();
            }
        }
    }

    // -------------------- La démo (§ 12.4) --------------------

    private void playDemoIfNeeded() {
        if (!mDemo || !mBound || mDemoPlayed || mPulledOnce) return;
        if (ReferralUi.reduceMotion(getContext()) || mTrack.span() <= 0) return;
        // ⛔ Pas de démo par-dessus une réponse déjà donnée (§ 12.20).
        if (mMode == Mode.TOY && intention() != null) return;
        if (BrowtherReferralController.get().isGaugeUnderstood()) return;
        Integer target = mScale.demoTarget((int) rest());
        if (target == null) return;
        mDemoPlayed = true;
        mHandler.postDelayed(
                () -> {
                    if (mDragging || mSource == MotionSource.USER) return;
                    mSource = MotionSource.DEMO;
                    mMotion.animate(
                            target,
                            0.9,
                            1,
                            0,
                            false,
                            () ->
                                    mHandler.postDelayed(
                                            () -> {
                                                if (mDragging || mSource != MotionSource.DEMO) return;
                                                mMotion.animate(
                                                        rest(),
                                                        0.9,
                                                        0.72,
                                                        0,
                                                        false,
                                                        () -> {
                                                            if (mSource == MotionSource.DEMO) {
                                                                mSource = MotionSource.SYSTEM;
                                                                render();
                                                            }
                                                        });
                                            },
                                            900));
                },
                600);
    }

    @Override
    protected void onDetachedFromWindow() {
        super.onDetachedFromWindow();
        mMotion.stop();
        mHandler.removeCallbacksAndMessages(null);
    }

    // -------------------- Le ressort, image par image --------------------

    /**
     * Un ressort amorti intégré à chaque image : la position EN COURS (les chiffres qui défilent en
     * chemin), la vitesse (l'élan du doigt), et l'arrêt net. {@code duration} / {@code damping} :
     * la grammaire de Reanimated (§ 12.4) — la pulsation propre vient de la durée, l'amortissement
     * du ratio (1 = sans rebond).
     */
    private final class Motion implements Choreographer.FrameCallback {
        double position;
        private double mTarget;
        private double mVelocity;
        private double mStiffness;
        private double mDampingCoef;
        private boolean mByHand;
        private @Nullable Runnable mCompletion;
        private boolean mRunning;
        private long mLastFrame;
        private int mLastNotch;

        void jump(double value) {
            stop();
            position = value;
            mLastNotch = (int) Math.round(value);
        }

        void setByHand(double value) {
            position = value;
            emitNotch(true);
            render();
        }

        void animate(
                double value,
                double duration,
                double ratio,
                double velocity,
                boolean byHand,
                @Nullable Runnable completion) {
            double omega = 2 * Math.PI / Math.max(duration, 0.05);
            mTarget = value;
            mVelocity = velocity;
            mStiffness = omega * omega;
            mDampingCoef = 2 * ratio * omega;
            mByHand = byHand;
            mCompletion = completion;
            mLastFrame = 0;
            if (!mRunning) {
                mRunning = true;
                Choreographer.getInstance().postFrameCallback(this);
            }
        }

        void stop() {
            if (mRunning) Choreographer.getInstance().removeFrameCallback(this);
            mRunning = false;
            mCompletion = null;
            mVelocity = 0;
        }

        @Override
        public void doFrame(long frameTimeNanos) {
            if (!mRunning) return;
            if (mLastFrame == 0) {
                mLastFrame = frameTimeNanos;
                Choreographer.getInstance().postFrameCallback(this);
                return;
            }
            // Pas fixe de 1/240 s pour la stabilité, quelle que soit la cadence d'écran.
            double remaining = Math.min((frameTimeNanos - mLastFrame) / 1e9, 1.0 / 20);
            mLastFrame = frameTimeNanos;
            double dt = 1.0 / 240;
            double x = position;
            double v = mVelocity;
            while (remaining > 0) {
                double h = Math.min(dt, remaining);
                double acceleration = -mStiffness * (x - mTarget) - mDampingCoef * v;
                v += acceleration * h;
                x += v * h;
                remaining -= h;
            }
            mVelocity = v;
            position = x;
            emitNotch(mByHand);
            if (Math.abs(x - mTarget) < 0.002 && Math.abs(v) < 0.01) {
                position = mTarget;
                emitNotch(mByHand);
                mRunning = false;
                Runnable done = mCompletion;
                mCompletion = null;
                // Le retour se pose d'un petit choc, au doigt seulement.
                if (mByHand && mMode == Mode.SPRING) ReferralUi.tick(ReferralGaugeView.this);
                render();
                if (done != null) done.run();
                return;
            }
            render();
            Choreographer.getInstance().postFrameCallback(this);
        }

        private void emitNotch(boolean byHand) {
            int value = (int) Math.round(position);
            if (value == mLastNotch) return;
            mLastNotch = value;
            notch(value, byHand);
        }
    }

    // -------------------- La piste --------------------

    private static final float THUMB_DP = 28;

    private final class TrackView extends View {
        private final Paint mPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final float mThumb;
        private final int mSlop;
        private @Nullable VelocityTracker mVelocity;
        private float mDownX;
        private float mDownY;
        private boolean mEngaged;
        private boolean mRefused;

        TrackView(Context context) {
            super(context);
            mThumb = ReferralUi.dp(context, THUMB_DP);
            mSlop = ViewConfiguration.get(context).getScaledTouchSlop();
            setLayoutDirection(LAYOUT_DIRECTION_LTR);
            setFocusable(true);
            setImportantForAccessibility(IMPORTANT_FOR_ACCESSIBILITY_YES);
        }

        float edge() {
            return mThumb / 2;
        }

        float span() {
            return Math.max(0, getWidth() - mThumb);
        }

        float xFor(double value) {
            return edge() + (float) (value / maxValue()) * span();
        }

        @Override
        protected void onSizeChanged(int w, int h, int oldw, int oldh) {
            super.onSizeChanged(w, h, oldw, oldh);
            post(ReferralGaugeView.this::playDemoIfNeeded);
        }

        @Override
        protected void onDraw(Canvas canvas) {
            if (span() <= 0) return;
            ReferralUi.Palette p = mPalette;
            float cy = getHeight() / 2f;
            float half = ReferralUi.dp(getContext(), 3);
            int accent = gold() ? p.goldFill : p.greenFill;
            int max = maxValue();

            mPaint.setStyle(Paint.Style.FILL);
            mPaint.setColor(p.track);
            canvas.drawRoundRect(edge(), cy - half, getWidth() - edge(), cy + half, half, half, mPaint);
            // Le tiré (or), sous l'acquis (vert) : ⚠️ l'acquis est TOUJOURS peint.
            mPaint.setColor(accent);
            canvas.drawRoundRect(0, cy - half, xFor(mMotion.position), cy + half, half, half, mPaint);
            if (actual() > 0) {
                mPaint.setColor(p.greenFill);
                canvas.drawRoundRect(0, cy - half, xFor(actual()), cy + half, half, half, mPaint);
            }
            // Un cran PAR invitation — ⛔ pas seulement aux paliers.
            int shown = shown();
            float dot = ReferralUi.dp(getContext(), 2);
            for (int at = 1; at < max; at++) {
                mPaint.setColor(at <= shown ? 0xCCFFFFFF : ReferralUi.withAlpha(p.text2, 0.7f));
                canvas.drawCircle(xFor(at), cy, dot, mPaint);
            }
            // ⚠️ Un vrai disque derrière le curseur (⛔ pas une ombre colorée, invisible en clair).
            float x = xFor(mMotion.position);
            float scale = mDragging ? 1.12f : 1f;
            float radius = mThumb / 2 * scale;
            mPaint.setColor(ReferralUi.withAlpha(accent, 0.22f));
            canvas.drawCircle(x, cy, radius + ReferralUi.dp(getContext(), 7), mPaint);
            mPaint.setColor(0x2E000000);
            canvas.drawCircle(x, cy + ReferralUi.dp(getContext(), 2), radius, mPaint);
            mPaint.setColor(0xFFFFFFFF);
            canvas.drawCircle(x, cy, radius, mPaint);
            mPaint.setStyle(Paint.Style.STROKE);
            float stroke = ReferralUi.dp(getContext(), 4);
            mPaint.setStrokeWidth(stroke);
            mPaint.setColor(accent);
            canvas.drawCircle(x, cy, radius - stroke / 2, mPaint);
        }

        @Override
        public boolean onTouchEvent(MotionEvent event) {
            switch (event.getActionMasked()) {
                case MotionEvent.ACTION_DOWN:
                    mDownX = event.getX();
                    mDownY = event.getY();
                    mEngaged = false;
                    mRefused = false;
                    mVelocity = VelocityTracker.obtain();
                    mVelocity.addMovement(event);
                    return true;
                case MotionEvent.ACTION_MOVE:
                    if (mVelocity != null) mVelocity.addMovement(event);
                    if (mRefused) return false;
                    float dx = event.getX() - mDownX;
                    float dy = event.getY() - mDownY;
                    if (!mEngaged) {
                        if (Math.abs(dy) > mSlop && Math.abs(dy) >= Math.abs(dx)) {
                            // 🔴 Un doigt qui part à la verticale fait défiler la page.
                            mRefused = true;
                            return false;
                        }
                        if (Math.abs(dx) <= mSlop || Math.abs(dx) <= Math.abs(dy)) return true;
                        mEngaged = true;
                        ViewParent parent = getParent();
                        if (parent != null) parent.requestDisallowInterceptTouchEvent(true);
                        grab();
                    }
                    drag(dx);
                    return true;
                case MotionEvent.ACTION_UP:
                case MotionEvent.ACTION_CANCEL:
                    boolean engaged = mEngaged;
                    double velocity = 0;
                    if (mVelocity != null) {
                        mVelocity.addMovement(event);
                        mVelocity.computeCurrentVelocity(1000);
                        velocity = mVelocity.getXVelocity();
                        mVelocity.recycle();
                        mVelocity = null;
                    }
                    mEngaged = false;
                    if (engaged) {
                        // 🔴 Un relâchement ne se perd jamais : annulé ou non, on relâche.
                        float span = span();
                        double values = span > 0 ? velocity / span * maxValue() : 0;
                        release((int) Math.round(mMotion.position), values);
                    } else if (!mRefused && event.getActionMasked() == MotionEvent.ACTION_UP) {
                        performClick();
                        tap(event.getX());
                    }
                    return true;
                default:
                    return true;
            }
        }

        @Override
        public boolean performClick() {
            return super.performClick();
        }

        @Override
        public void onInitializeAccessibilityNodeInfo(AccessibilityNodeInfo info) {
            super.onInitializeAccessibilityNodeInfo(info);
            info.setClassName("android.widget.SeekBar");
            info.addAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_SCROLL_FORWARD);
            info.addAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_SCROLL_BACKWARD);
        }

        @Override
        public boolean performAccessibilityAction(int action, @Nullable Bundle arguments) {
            int step;
            if (action == AccessibilityNodeInfo.ACTION_SCROLL_FORWARD) {
                step = 1;
            } else if (action == AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD) {
                step = -1;
            } else {
                return super.performAccessibilityAction(action, arguments);
            }
            double next =
                    Math.max(minimum(), Math.min(maxValue(), Math.round(mMotion.position) + step));
            grab();
            mMotion.animate(next, 0.35, 1, 0, true, null);
            release((int) next, 0);
            announceForAccessibility(getContentDescription());
            return true;
        }
    }

    /** Les repères sous la piste : 1, chaque palier bonus (« +N mois »), et « à vie ». */
    private final class TicksView extends View {
        private final Paint mNumber = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint mLabel = new Paint(Paint.ANTI_ALIAS_FLAG);

        TicksView(Context context) {
            super(context);
            setLayoutDirection(LAYOUT_DIRECTION_LTR);
            mNumber.setTypeface(ReferralUi.typeface(ReferralUi.SEMIBOLD));
            mNumber.setTextSize(ReferralUi.dp(context, 12));
            mNumber.setTextAlign(Paint.Align.CENTER);
            mLabel.setTypeface(ReferralUi.typeface(ReferralUi.REGULAR));
            mLabel.setTextSize(ReferralUi.dp(context, 11));
            mLabel.setTextAlign(Paint.Align.CENTER);
            setImportantForAccessibility(IMPORTANT_FOR_ACCESSIBILITY_NO);
        }

        @Override
        protected void onDraw(Canvas canvas) {
            float span = mTrack.span();
            if (span <= 0) return;
            ReferralUi.Palette p = mPalette;
            int accentText = gold() ? p.gold : p.green;
            int shown = shown();
            Context context = getContext();
            float numberY = ReferralUi.dp(context, 12);
            float labelY = ReferralUi.dp(context, 26);
            drawTick(canvas, 1, null, shown, accentText, numberY, labelY);
            for (MilestoneBonus bonus : mScale.bonuses) {
                drawTick(
                        canvas,
                        bonus.at,
                        ReferralStrings.plural(context, "gauge.tickBonus", bonus.months),
                        shown,
                        accentText,
                        numberY,
                        labelY);
            }
            drawTick(
                    canvas,
                    maxValue(),
                    ReferralStrings.get(context, "gauge.tickLifetime"),
                    shown,
                    accentText,
                    numberY,
                    labelY);
        }

        private void drawTick(
                Canvas canvas,
                int at,
                @Nullable String label,
                int shown,
                int accentText,
                float numberY,
                float labelY) {
            boolean reached = shown >= at;
            float x = mTrack.xFor(at);
            // Le dernier repère ne déborde pas de la carte.
            float half = ReferralUi.dp(getContext(), 30);
            float cx = Math.max(half / 2, Math.min(getWidth() - half / 2, x));
            mNumber.setColor(reached ? accentText : mPalette.text2);
            canvas.drawText(String.valueOf(at), x, numberY, mNumber);
            if (label != null) {
                mLabel.setColor(reached ? accentText : ReferralUi.withAlpha(mPalette.text2, 0.7f));
                canvas.drawText(label, cx, labelY, mLabel);
            }
        }
    }

    // -------------------- La carte « À vie » (§ 12.5) --------------------

    /**
     * ⭐ Elle brille toujours (un reflet la balaie, puis un temps) ; elle s'allume au palier « à
     * vie » : fond et bord dorés, un grossissement à peine, un halo qui pulse DEUX fois (⛔ jamais
     * en boucle). 🔴 Allumée, elle reste LISIBLE (§ 12.24) : l'or en halo DERRIÈRE, le texte dans
     * l'encre normale. Mouvement réduit : elle s'allume, c'est tout.
     */
    private static final class LifetimeCard extends FrameLayout {
        private final ReferralUi.Palette mP;
        private final FrameLayout mBadge;
        private final android.widget.ImageView mBadgeIcon;
        private final TextView mSub;
        private final TextView mCounter;
        private final Paint mShine = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Path mClip = new Path();
        private final RectF mRect = new RectF();
        private @Nullable ValueAnimator mShimmer;
        private float mShimmerAt = -0.5f;
        private boolean mLit;
        private int mLifetimeAt = 10;
        private int mCount = -1;

        LifetimeCard(Context context, ReferralUi.Palette p) {
            super(context);
            mP = p;
            setWillNotDraw(false);
            LinearLayout row = ReferralUi.row(context);
            int pad = ReferralUi.dp(context, 12);
            row.setPadding(pad, pad, pad, pad);

            mBadge = new FrameLayout(context);
            mBadgeIcon =
                    ReferralUi.glyph(context, R.drawable.browther_referral_glyph_infinity, 16, p.gold);
            int icon = ReferralUi.dp(context, 16);
            mBadge.addView(mBadgeIcon, ReferralUi.frame(icon, icon, Gravity.CENTER));
            int badge = ReferralUi.dp(context, 32);
            LinearLayout.LayoutParams badgeParams = new LinearLayout.LayoutParams(badge, badge);
            badgeParams.setMarginEnd(ReferralUi.dp(context, 12));
            row.addView(mBadge, badgeParams);

            LinearLayout texts = ReferralUi.column(context);
            texts.addView(
                    ReferralUi.text(
                            context,
                            ReferralStrings.get(context, "gauge.lifeTitle"),
                            17,
                            ReferralUi.SEMIBOLD,
                            p.gold));
            mSub = ReferralUi.text(context, 13, ReferralUi.REGULAR, p.text2);
            texts.addView(mSub);
            row.addView(texts, new LinearLayout.LayoutParams(0, ReferralUi.WRAP, 1));

            mCounter = ReferralUi.text(context, 13, ReferralUi.SEMIBOLD, p.text2);
            // Un compteur se lit de gauche à droite, même en arabe.
            mCounter.setTextDirection(TEXT_DIRECTION_LTR);
            int padH = ReferralUi.dp(context, 8);
            int padV = ReferralUi.dp(context, 3);
            mCounter.setPadding(padH, padV, padH, padV);
            LinearLayout.LayoutParams counterParams =
                    new LinearLayout.LayoutParams(ReferralUi.WRAP, ReferralUi.WRAP);
            counterParams.setMarginStart(ReferralUi.dp(context, 4));
            row.addView(mCounter, counterParams);
            addView(row, new LayoutParams(ReferralUi.MATCH, ReferralUi.WRAP));
            if (android.os.Build.VERSION.SDK_INT >= 28) {
                setOutlineSpotShadowColor(Palette_GOLD);
                setOutlineAmbientShadowColor(Palette_GOLD);
            }
            applyLit(false, false);
        }

        private static final int Palette_GOLD = ReferralUi.Palette.GOLD_FILL;

        void update(int count, boolean lit, int lifetimeAt) {
            Context context = getContext();
            mLifetimeAt = lifetimeAt;
            int shown = Math.min(count, lifetimeAt);
            if (shown != mCount) {
                mCount = shown;
                mCounter.setText(shown + "/" + lifetimeAt);
            }
            mSub.setText(
                    lit
                            ? ReferralStrings.get(context, "gauge.lifeReached")
                            : ReferralStrings.plural(context, "gauge.lifeSub", lifetimeAt));
            if (lit != mLit) applyLit(lit, true);
        }

        private void applyLit(boolean lit, boolean animated) {
            mLit = lit;
            Context context = getContext();
            float radius = ReferralUi.dp(context, 14);
            setBackground(
                    ReferralUi.rounded(
                            lit ? mP.goldSurface : mP.panel, radius, 1, lit ? mP.gold : mP.line));
            mBadge.setBackground(ReferralUi.oval(lit ? mP.goldFill : mP.goldSurface));
            mBadgeIcon.setImageTintList(
                    android.content.res.ColorStateList.valueOf(
                            lit ? ReferralUi.Palette.INK : mP.gold));
            mSub.setTextColor(lit ? mP.text : mP.text2);
            mCounter.setTextColor(lit ? mP.gold : mP.text2);
            mCounter.setBackground(
                    ReferralUi.rounded(
                            0, ReferralUi.dp(context, 100), 1, lit ? mP.gold : mP.line));
            boolean reduce = ReferralUi.reduceMotion(context);
            float scale = lit && !reduce ? 1.02f : 1f;
            if (!animated || reduce) {
                setScaleX(scale);
                setScaleY(scale);
                setElevation(lit ? ReferralUi.dp(context, 6) : 0);
                return;
            }
            animate().scaleX(scale).scaleY(scale).setDuration(300)
                    .setInterpolator(ReferralUi.EASE_OUT).start();
            if (!lit) {
                setElevation(0);
                return;
            }
            // Deux pulsations, puis une lueur qui reste — ⛔ pas une boucle.
            float high = ReferralUi.dp(context, 16);
            float low = ReferralUi.dp(context, 5);
            ValueAnimator halo = ValueAnimator.ofFloat(0, high, low, high, ReferralUi.dp(context, 6));
            halo.setDuration(1_860);
            halo.addUpdateListener(a -> setElevation((float) a.getAnimatedValue()));
            halo.start();
        }

        @Override
        protected void onAttachedToWindow() {
            super.onAttachedToWindow();
            if (ReferralUi.reduceMotion(getContext())) return;
            // Un balayage, puis un long repos : un reflet permanent fatiguerait l'œil.
            mShimmer = ValueAnimator.ofFloat(-0.5f, 1.1f);
            mShimmer.setDuration(1_300);
            mShimmer.setStartDelay(400);
            mShimmer.addUpdateListener(
                    a -> {
                        mShimmerAt = (float) a.getAnimatedValue();
                        invalidate();
                    });
            mShimmer.addListener(
                    new android.animation.AnimatorListenerAdapter() {
                        @Override
                        public void onAnimationEnd(android.animation.Animator animation) {
                            mShimmerAt = -0.5f;
                            invalidate();
                            if (isAttachedToWindow() && mShimmer != null) {
                                mShimmer.setStartDelay(3_600);
                                mShimmer.start();
                            }
                        }
                    });
            mShimmer.start();
        }

        @Override
        protected void onDetachedFromWindow() {
            super.onDetachedFromWindow();
            ValueAnimator shimmer = mShimmer;
            mShimmer = null;
            if (shimmer != null) shimmer.cancel();
        }

        @Override
        protected void dispatchDraw(Canvas canvas) {
            super.dispatchDraw(canvas);
            if (mShimmerAt <= -0.5f || getWidth() == 0) return;
            float w = getWidth();
            float band = w * 0.4f;
            float x = mShimmerAt * w * 1.6f;
            mShine.setShader(
                    new LinearGradient(
                            x, 0, x + band, 0,
                            new int[] {0x00FFFFFF, 0x29FFFFFF, 0x00FFFFFF},
                            null,
                            Shader.TileMode.CLAMP));
            float radius = ReferralUi.dp(getContext(), 14);
            mRect.set(0, 0, w, getHeight());
            mClip.reset();
            mClip.addRoundRect(mRect, radius, radius, Path.Direction.CW);
            canvas.save();
            canvas.clipPath(mClip);
            canvas.drawRect(x, 0, x + band, getHeight(), mShine);
            canvas.restore();
        }
    }

    // -------------------- Utilitaires --------------------

    private static TextView singleLine(TextView view) {
        view.setSingleLine(true);
        view.setEllipsize(TextUtils.TruncateAt.END);
        return view;
    }

    private static LinearLayout baselineRow(Context context) {
        LinearLayout row = ReferralUi.row(context);
        row.setGravity(Gravity.BOTTOM);
        row.setBaselineAligned(true);
        return row;
    }

    private static LinearLayout.LayoutParams unitParams(Context context) {
        LinearLayout.LayoutParams params =
                new LinearLayout.LayoutParams(ReferralUi.WRAP, ReferralUi.WRAP);
        params.setMarginStart(ReferralUi.dp(context, 6));
        return params;
    }

    private TextView bigNumber(Context context) {
        TextView view = ReferralUi.text(context, 34, ReferralUi.SEMIBOLD, mPalette.text);
        view.setFontFeatureSettings("tnum");
        view.setIncludeFontPadding(false);
        view.setSingleLine(true);
        return view;
    }
}
