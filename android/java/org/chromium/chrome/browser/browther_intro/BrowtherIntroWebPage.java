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
import android.graphics.Color;
import android.graphics.drawable.GradientDrawable;
import android.os.SystemClock;
import android.view.Gravity;
import android.view.View;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.TextView;

import org.chromium.chrome.R;

import java.util.Locale;

/**
 * Une page de recettes quelconque, avec sa pub avant la vidéo et sa bannière.
 *
 * <p>La page <b>se déroule vraiment</b> : « Annonce · 0:15 » décompte, « Passer dans 5 s » aussi,
 * puis la vidéo démarre quelques secondes, puis la pub revient — un cycle de 9 s. Interrupteur sur
 * ON : plus de pub avant la vidéo, plus de bannière, la vidéo joue.
 *
 * <p>⛔ Aucun nom de service réel : ce qui fait reconnaître la scène, c'est la pub avant la vidéo et
 * son « Passer dans 5 s », pas une marque (règles des stores).
 */
final class BrowtherIntroWebPage extends LinearLayout {
    private static final long AD_MS = 5000;
    private static final long VIDEO_MS = 4000;
    private static final long CYCLE_MS = AD_MS + VIDEO_MS;
    private static final long TICK_MS = 250;

    private final View mBlockedBadge;
    private final View mPreroll;
    private final TextView mAdCountdown;
    private final TextView mSkip;
    private final ProgressBar mProgress;
    private final View mBanner;
    private final String mAdLabel;
    private final long mEpoch = SystemClock.uptimeMillis();
    private boolean mBlocked;
    private boolean mTicking;
    private Boolean mAdShown;

    private final Runnable mTick =
            new Runnable() {
                @Override
                public void run() {
                    update(true);
                    if (mTicking) postDelayed(this, TICK_MS);
                }
            };

    BrowtherIntroWebPage(Context context) {
        super(context);
        setOrientation(VERTICAL);
        setBackground(BrowtherIntroUi.rounded(BrowtherIntroUi.SURFACE, dpf(context, 18)));
        setClipToOutline(true);
        mAdLabel = context.getString(R.string.browther_intro_demo_ad_label);

        // Barre d'adresse de la page.
        LinearLayout bar = BrowtherIntroUi.row(context, 8);
        bar.setPadding(dp(context, 12), 0, dp(context, 12), 0);
        bar.addView(
                BrowtherIntroUi.glyph(
                        context, R.drawable.browther_intro_glyph_lock, 11, BrowtherIntroUi.INK_SOFT));
        TextView site =
                BrowtherIntroUi.text(
                        context,
                        R.string.browther_intro_demo_site_name,
                        12,
                        BrowtherIntroUi.SEMIBOLD,
                        BrowtherIntroUi.INK);
        BrowtherIntroUi.singleLine(site, 10, 12);
        bar.addView(site, new LayoutParams(0, WRAP, 1f));
        LinearLayout badge = BrowtherIntroUi.row(context, 4);
        badge.setPadding(dp(context, 8), dp(context, 4), dp(context, 8), dp(context, 4));
        badge.setBackground(
                BrowtherIntroUi.capsule(BrowtherIntroUi.withAlpha(BrowtherIntroUi.HALAL, 0.14f)));
        badge.addView(
                BrowtherIntroUi.glyph(
                        context,
                        R.drawable.browther_intro_glyph_shield,
                        11,
                        BrowtherIntroUi.HALAL_TEXT));
        badge.addView(
                BrowtherIntroUi.text(
                        context,
                        R.string.browther_intro_demo_blocked_count,
                        11,
                        BrowtherIntroUi.BOLD,
                        BrowtherIntroUi.HALAL_TEXT));
        badge.setAlpha(0f);
        mBlockedBadge = badge;
        bar.addView(badge);
        addView(bar, new LayoutParams(MATCH, dp(context, 38)));

        View divider = new View(context);
        divider.setBackgroundColor(BrowtherIntroUi.withAlpha(Color.WHITE, 0.12f));
        addView(divider, new LayoutParams(MATCH, Math.max(1, dp(context, 0.5f))));

        // Le lecteur vidéo.
        FrameLayout video = new FrameLayout(context);
        video.setBackground(
                new GradientDrawable(
                        GradientDrawable.Orientation.TL_BR, new int[] {0xFF2E3A31, 0xFF161B18}));
        FrameLayout play = new FrameLayout(context);
        play.setBackground(BrowtherIntroUi.capsule(BrowtherIntroUi.withAlpha(Color.WHITE, 0.18f)));
        play.addView(
                BrowtherIntroUi.glyph(
                        context, R.drawable.browther_intro_glyph_play, 20, Color.WHITE),
                new FrameLayout.LayoutParams(dp(context, 20), dp(context, 20), Gravity.CENTER));
        video.addView(
                play, new FrameLayout.LayoutParams(dp(context, 44), dp(context, 44), Gravity.CENTER));

        mProgress = new ProgressBar(context, null, android.R.attr.progressBarStyleHorizontal);
        mProgress.setMax(100);
        mProgress.setProgressTintList(android.content.res.ColorStateList.valueOf(Color.WHITE));
        mProgress.setProgressBackgroundTintList(
                android.content.res.ColorStateList.valueOf(
                        BrowtherIntroUi.withAlpha(Color.WHITE, 0.35f)));
        FrameLayout.LayoutParams progressParams =
                new FrameLayout.LayoutParams(MATCH, dp(context, 4), Gravity.BOTTOM);
        progressParams.leftMargin = dp(context, 10);
        progressParams.rightMargin = dp(context, 10);
        progressParams.bottomMargin = dp(context, 8);
        video.addView(mProgress, progressParams);

        // La pub avant la vidéo.
        FrameLayout preroll = new FrameLayout(context);
        preroll.setBackground(
                new GradientDrawable(
                        GradientDrawable.Orientation.TL_BR, new int[] {0xFF7B2D58, 0xFFC55A3B}));
        preroll.addView(
                BrowtherIntroUi.glyph(
                        context,
                        R.drawable.browther_intro_glyph_photo,
                        40,
                        BrowtherIntroUi.withAlpha(Color.WHITE, 0.4f)),
                new FrameLayout.LayoutParams(dp(context, 40), dp(context, 40), Gravity.CENTER));
        LinearLayout chips = BrowtherIntroUi.row(context, 6);
        mAdCountdown = BrowtherIntroUi.text(context, 11, BrowtherIntroUi.BOLD, Color.BLACK);
        mAdCountdown.setFontFeatureSettings("tnum");
        mAdCountdown.setPadding(dp(context, 7), dp(context, 3), dp(context, 7), dp(context, 3));
        mAdCountdown.setBackground(BrowtherIntroUi.rounded(0xFFF5C542, dpf(context, 6)));
        chips.addView(mAdCountdown);
        LinearLayout sound = BrowtherIntroUi.row(context, 4);
        sound.setPadding(dp(context, 7), dp(context, 3), dp(context, 7), dp(context, 3));
        sound.setBackground(
                BrowtherIntroUi.rounded(BrowtherIntroUi.withAlpha(Color.BLACK, 0.5f), dpf(context, 6)));
        sound.addView(
                BrowtherIntroUi.glyph(
                        context, R.drawable.browther_intro_glyph_music_note, 11, Color.WHITE));
        sound.addView(
                BrowtherIntroUi.text(
                        context,
                        R.string.browther_intro_demo_ad_sound,
                        11,
                        BrowtherIntroUi.SEMIBOLD,
                        Color.WHITE));
        chips.addView(sound);
        FrameLayout.LayoutParams chipsParams =
                new FrameLayout.LayoutParams(WRAP, WRAP, Gravity.TOP | Gravity.START);
        chipsParams.setMargins(dp(context, 8), dp(context, 8), dp(context, 8), dp(context, 8));
        preroll.addView(chips, chipsParams);
        mSkip = BrowtherIntroUi.text(context, 11, BrowtherIntroUi.SEMIBOLD, Color.WHITE);
        mSkip.setFontFeatureSettings("tnum");
        mSkip.setPadding(dp(context, 9), dp(context, 5), dp(context, 9), dp(context, 5));
        mSkip.setBackground(
                BrowtherIntroUi.rounded(BrowtherIntroUi.withAlpha(Color.BLACK, 0.6f), dpf(context, 6)));
        FrameLayout.LayoutParams skipParams =
                new FrameLayout.LayoutParams(WRAP, WRAP, Gravity.BOTTOM | Gravity.END);
        skipParams.setMargins(dp(context, 8), dp(context, 8), dp(context, 8), dp(context, 8));
        preroll.addView(mSkip, skipParams);
        mPreroll = preroll;
        video.addView(preroll, new FrameLayout.LayoutParams(MATCH, MATCH));
        addView(video, new LayoutParams(MATCH, dp(context, 132)));

        // L'article et sa bannière.
        LinearLayout article = BrowtherIntroUi.column(context);
        article.setPadding(dp(context, 12), dp(context, 12), dp(context, 12), dp(context, 12));
        TextView title =
                BrowtherIntroUi.text(
                        context,
                        R.string.browther_intro_demo_article_title,
                        15,
                        BrowtherIntroUi.BOLD,
                        BrowtherIntroUi.INK);
        article.addView(title);
        TextView body =
                BrowtherIntroUi.text(
                        context,
                        R.string.browther_intro_demo_article_body,
                        12,
                        BrowtherIntroUi.REGULAR,
                        BrowtherIntroUi.INK_SOFT);
        body.setMaxLines(2);
        body.setEllipsize(android.text.TextUtils.TruncateAt.END);
        article.addView(
                body, BrowtherIntroUi.marginTop(BrowtherIntroUi.linear(MATCH, WRAP), dp(context, 8)));

        LinearLayout banner = BrowtherIntroUi.row(context, 10);
        banner.setPadding(dp(context, 10), 0, dp(context, 10), 0);
        GradientDrawable bannerFill =
                new GradientDrawable(
                        GradientDrawable.Orientation.LEFT_RIGHT, new int[] {0xFFF4DAC8, 0xFFE3AB91});
        bannerFill.setCornerRadius(dpf(context, 10));
        banner.setBackground(bannerFill);
        FrameLayout bannerImage = new FrameLayout(context);
        bannerImage.setBackground(
                BrowtherIntroUi.rounded(BrowtherIntroUi.withAlpha(Color.WHITE, 0.55f), dpf(context, 8)));
        bannerImage.addView(
                BrowtherIntroUi.glyph(context, R.drawable.browther_intro_glyph_photo, 20, 0xFF9A5A3C),
                new FrameLayout.LayoutParams(dp(context, 20), dp(context, 20), Gravity.CENTER));
        banner.addView(bannerImage, new LayoutParams(dp(context, 44), dp(context, 44)));
        LinearLayout bannerText = BrowtherIntroUi.column(context);
        bannerText.addView(
                BrowtherIntroUi.text(
                        context,
                        R.string.browther_intro_demo_ad_label,
                        12,
                        BrowtherIntroUi.BOLD,
                        0xFF5B2D1C));
        TextView sponsored =
                BrowtherIntroUi.text(
                        context,
                        R.string.browther_intro_demo_ad_sponsored,
                        11,
                        BrowtherIntroUi.REGULAR,
                        0xFF5B2D1C);
        bannerText.addView(
                sponsored,
                BrowtherIntroUi.marginTop(BrowtherIntroUi.linear(WRAP, WRAP), dp(context, 2)));
        banner.addView(bannerText, new LayoutParams(0, WRAP, 1f));
        mBanner = banner;
        article.addView(
                banner, BrowtherIntroUi.marginTop(new LayoutParams(MATCH, dp(context, 62)), dp(context, 8)));
        addView(article, new LayoutParams(MATCH, WRAP));

        update(false);
    }

    void setBlocked(boolean blocked) {
        if (mBlocked == blocked) return;
        mBlocked = blocked;
        mBlockedBadge.animate().alpha(blocked ? 1f : 0f).setDuration(320).start();
        mBanner.animate()
                .alpha(blocked ? 0f : 1f)
                .scaleX(blocked ? 0.96f : 1f)
                .scaleY(blocked ? 0.96f : 1f)
                .setDuration(320)
                .start();
        update(true);
    }

    @Override
    protected void onAttachedToWindow() {
        super.onAttachedToWindow();
        mTicking = true;
        removeCallbacks(mTick);
        post(mTick);
    }

    @Override
    protected void onDetachedFromWindow() {
        mTicking = false;
        removeCallbacks(mTick);
        super.onDetachedFromWindow();
    }

    private void update(boolean animated) {
        long phase = (SystemClock.uptimeMillis() - mEpoch) % CYCLE_MS;
        boolean adShown = !mBlocked && phase < AD_MS;
        if (mAdShown == null || mAdShown != adShown) {
            boolean first = mAdShown == null;
            mAdShown = adShown;
            if (animated && !first) {
                mPreroll.animate()
                        .alpha(adShown ? 1f : 0f)
                        .scaleX(adShown ? 1f : 1.04f)
                        .scaleY(adShown ? 1f : 1.04f)
                        .setDuration(320)
                        .start();
            } else {
                mPreroll.setAlpha(adShown ? 1f : 0f);
            }
        }
        // La vidéo tourne : une barre qui avance suffit à le dire.
        mProgress.setAlpha(adShown ? 0f : 1f);
        mProgress.setProgress(mBlocked ? 42 : 18);
        if (adShown) {
            // Le compte à rebours descend vraiment : 0:15 → 0:10 pour l'annonce, 5 → 0 pour
            // « Passer ».
            float elapsed = phase / 1000f;
            int remainingAd = Math.max(0, 15 - (int) elapsed);
            int remainingSkip = Math.max(0, (int) Math.ceil(AD_MS / 1000f - elapsed));
            mAdCountdown.setText(
                    String.format(Locale.US, "%s · 0:%02d", mAdLabel, remainingAd));
            mSkip.setText(
                    remainingSkip > 0
                            ? getResources()
                                    .getString(R.string.browther_intro_demo_ad_skip, remainingSkip)
                            : getResources().getString(R.string.browther_intro_demo_ad_skip_now));
        }
    }
}
