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
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.graphics.drawable.GradientDrawable;
import android.view.Gravity;
import android.view.View;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.SeekBar;
import android.widget.TextView;

import org.chromium.chrome.R;

import java.text.NumberFormat;

/**
 * 4 · Musique. Un <b>extrait réel</b> et sa version passée dans Sawtunaa, joués en parallèle : c'est
 * l'interrupteur qui change de canal (cf. {@link BrowtherIntroAudio}).
 *
 * <p><b>Rien ne démarre tout seul</b> : l'extrait part au geste — le bouton de lecture, ou la mise
 * sur ON de l'interrupteur. Arriver sur un écran qui parle tout seul dans un lieu public est une
 * trahison.
 */
final class BrowtherIntroMusicStep extends BrowtherIntroStepView
        implements BrowtherIntroAudio.Listener {
    private final BrowtherIntroAudio mAudio;
    private final ImageView mPlayGlyph;
    private final View mPlayButton;
    private final BrowtherIntroPlayerViews.Scrubber mScrubber;
    private final ImageView mSpeaker;
    private final SeekBar mVolume;
    private final TextView mVolumeText;
    private final TextView mMutedWarning;
    private final BrowtherIntroPlayerViews.Lane mMusicLane;
    private final TextView mRemoved;
    private final BrowtherIntroWidgets.StampPair mStamps;
    private final BrowtherIntroWidgets.SwitchRow mSwitch;
    private final BrowtherIntroWidgets.AdvanceButton mAdvance;
    private final NumberFormat mPercent = NumberFormat.getPercentInstance();
    private Boolean mMusicOn;
    private boolean mAdjustingVolume;

    BrowtherIntroMusicStep(Context context, BrowtherIntroModel model, BrowtherIntroAudio audio) {
        super(context, model);
        mAudio = audio;
        TextView compat =
                BrowtherIntroUi.text(
                        context,
                        R.string.browther_intro_music_compat,
                        13,
                        BrowtherIntroUi.REGULAR,
                        BrowtherIntroUi.INK_TERTIARY);
        Slots slots =
                template(
                        null,
                        context.getString(R.string.browther_intro_music_title),
                        context.getString(R.string.browther_intro_music_subtitle),
                        compat);

        LinearLayout sceneColumn = BrowtherIntroUi.column(context);
        sceneColumn.setClipChildren(false);
        slots.mScene.addView(sceneColumn, BrowtherIntroUi.frame(MATCH, MATCH, Gravity.TOP));

        FrameLayout cardFrame = new FrameLayout(context);
        cardFrame.setClipChildren(false);
        sceneColumn.addView(cardFrame, new LinearLayout.LayoutParams(MATCH, 0, 1f));

        LinearLayout card = BrowtherIntroUi.column(context);
        card.setBackground(BrowtherIntroUi.rounded(0xFF1B201C, dpf(context, 18)));
        card.setClipToOutline(true);
        cardFrame.addView(card, BrowtherIntroUi.frame(MATCH, MATCH, Gravity.TOP));

        // Le lecteur.
        LinearLayout player = BrowtherIntroUi.column(context);
        player.setGravity(Gravity.CENTER);
        GradientDrawable radial = new GradientDrawable();
        radial.setGradientType(GradientDrawable.RADIAL_GRADIENT);
        radial.setColors(new int[] {0xFF2F3C31, BrowtherIntroUi.PLAYER_INK});
        radial.setGradientCenter(0.5f, 0.2f);
        radial.setGradientRadius(dpf(context, 260));
        player.setBackground(radial);
        player.setPadding(0, dp(context, 18), 0, dp(context, 18));
        card.addView(player, new LinearLayout.LayoutParams(MATCH, 0, 1f));

        FrameLayout play = new FrameLayout(context);
        play.setBackground(BrowtherIntroUi.capsule(BrowtherIntroUi.PLAYER_CREAM));
        play.setClickable(true);
        play.setFocusable(true);
        play.setOnClickListener(v -> mAudio.toggle());
        mPlayGlyph =
                BrowtherIntroUi.glyph(
                        context, R.drawable.browther_intro_glyph_play, 24,
                        BrowtherIntroUi.PLAYER_INK);
        play.addView(mPlayGlyph, BrowtherIntroUi.frame(dp(context, 24), dp(context, 24), Gravity.CENTER));
        mPlayButton = play;
        player.addView(play, BrowtherIntroUi.linear(dp(context, 62), dp(context, 62)));

        mScrubber = new BrowtherIntroPlayerViews.Scrubber(context, mAudio::seek);
        LinearLayout.LayoutParams scrubberParams = BrowtherIntroUi.linear(MATCH, dp(context, 26));
        scrubberParams.topMargin = dp(context, 12);
        scrubberParams.leftMargin = dp(context, 24);
        scrubberParams.rightMargin = dp(context, 24);
        player.addView(mScrubber, scrubberParams);

        // Le son de l'appareil, visible en permanence, et de quoi le régler.
        LinearLayout volumeRow = BrowtherIntroUi.row(context, 10);
        mSpeaker =
                BrowtherIntroUi.glyph(
                        context, R.drawable.browther_intro_glyph_speaker, 14,
                        BrowtherIntroUi.withAlpha(Color.WHITE, 0.72f));
        volumeRow.addView(mSpeaker);
        mVolume = new SeekBar(context);
        mVolume.setContentDescription(context.getString(R.string.browther_intro_volume_label));
        mVolume.setProgressTintList(ColorStateList.valueOf(BrowtherIntroUi.PLAYER_CREAM));
        mVolume.setThumbTintList(ColorStateList.valueOf(BrowtherIntroUi.PLAYER_CREAM));
        mVolume.setProgressBackgroundTintList(
                ColorStateList.valueOf(BrowtherIntroUi.withAlpha(Color.WHITE, 0.4f)));
        mVolume.setPadding(dp(context, 8), 0, dp(context, 8), 0);
        mVolume.setOnSeekBarChangeListener(
                new SeekBar.OnSeekBarChangeListener() {
                    @Override
                    public void onProgressChanged(SeekBar seekBar, int progress, boolean fromUser) {
                        if (fromUser) mAudio.setSystemVolumeStep(progress);
                    }

                    @Override
                    public void onStartTrackingTouch(SeekBar seekBar) {
                        mAdjustingVolume = true;
                    }

                    @Override
                    public void onStopTrackingTouch(SeekBar seekBar) {
                        mAdjustingVolume = false;
                        onAudioStateChanged();
                    }
                });
        volumeRow.addView(mVolume, new LinearLayout.LayoutParams(0, dp(context, 28), 1f));
        mVolumeText =
                BrowtherIntroUi.text(
                        context, 12, BrowtherIntroUi.SEMIBOLD,
                        BrowtherIntroUi.withAlpha(Color.WHITE, 0.72f));
        mVolumeText.setFontFeatureSettings("tnum");
        mVolumeText.setGravity(Gravity.END | Gravity.CENTER_VERTICAL);
        mVolumeText.setMaxLines(1);
        // 100 % est le cas le plus large : sans place pour lui, il passait sur deux lignes.
        volumeRow.addView(mVolumeText, BrowtherIntroUi.linear(dp(context, 46), WRAP));
        LinearLayout.LayoutParams volumeParams = BrowtherIntroUi.linear(MATCH, WRAP);
        volumeParams.topMargin = dp(context, 12);
        volumeParams.leftMargin = dp(context, 22);
        volumeParams.rightMargin = dp(context, 22);
        player.addView(volumeRow, volumeParams);

        // À zéro, la jauge devient un avertissement.
        mMutedWarning =
                BrowtherIntroUi.text(
                        context,
                        R.string.browther_intro_volume_muted,
                        12,
                        BrowtherIntroUi.MEDIUM,
                        BrowtherIntroUi.AMBER);
        mMutedWarning.setGravity(Gravity.CENTER);
        mMutedWarning.setVisibility(GONE);
        LinearLayout.LayoutParams warningParams = BrowtherIntroUi.linear(MATCH, WRAP);
        warningParams.topMargin = dp(context, 5);
        warningParams.leftMargin = dp(context, 22);
        warningParams.rightMargin = dp(context, 22);
        player.addView(mMutedWarning, warningParams);

        // Les deux pistes dessinées.
        LinearLayout lanes = BrowtherIntroUi.column(context);
        BrowtherIntroUi.spacing(lanes, 12);
        lanes.setPadding(dp(context, 14), dp(context, 12), dp(context, 14), dp(context, 12));
        lanes.addView(
                lane(context, R.string.browther_intro_music_lane_voice,
                        new BrowtherIntroPlayerViews.Lane(context, BrowtherIntroUi.SAGE, 0.7),
                        null));
        mMusicLane = new BrowtherIntroPlayerViews.Lane(context, BrowtherIntroUi.GOLD, 1.9);
        mRemoved =
                BrowtherIntroUi.text(
                        context,
                        R.string.browther_intro_music_removed,
                        12,
                        BrowtherIntroUi.SEMIBOLD,
                        BrowtherIntroUi.HALAL_TEXT);
        lanes.addView(lane(context, R.string.browther_intro_music_lane_music, mMusicLane, mRemoved));
        card.addView(lanes, BrowtherIntroUi.linear(MATCH, WRAP));

        mStamps = new BrowtherIntroWidgets.StampPair(context);
        cardFrame.addView(mStamps, BrowtherIntroUi.frame(WRAP, WRAP, Gravity.TOP | Gravity.END));
        BrowtherIntroAdsStep.offsetStamps(mStamps);

        mSwitch =
                new BrowtherIntroWidgets.SwitchRow(
                        context,
                        R.drawable.sawtunaa_icon_toolbar,
                        "Sawtunaa",
                        R.string.browther_intro_music_switch_off,
                        R.string.browther_intro_music_switch_on,
                        () -> mModel.toggleDemo(BrowtherIntroModel.Step.MUSIC));
        sceneColumn.addView(
                mSwitch, BrowtherIntroUi.marginTop(BrowtherIntroUi.linear(MATCH, WRAP), dp(context, 10)));

        mAdvance =
                new BrowtherIntroWidgets.AdvanceButton(
                        context,
                        () -> {
                            // ⛔ Le son s'arrête ici, pas seulement en quittant l'écran : la
                            // feuille de l'accès anticipé garde l'écran monté, et l'extrait
                            // continuerait à jouer derrière elle.
                            mAudio.stop();
                            mModel.activate(BrowtherIntroModel.Feature.SAWTUNAA);
                        });
        slots.mActions.addView(mAdvance);
        bind(false);
    }

    private static View lane(
            Context context, int titleId, BrowtherIntroPlayerViews.Lane lane, TextView trailing) {
        LinearLayout row = BrowtherIntroUi.row(context, 10);
        TextView title =
                BrowtherIntroUi.text(
                        context, titleId, 12, BrowtherIntroUi.SEMIBOLD,
                        BrowtherIntroUi.withAlpha(Color.WHITE, 0.72f));
        BrowtherIntroUi.singleLine(title, 9, 12);
        row.addView(title, BrowtherIntroUi.linear(dp(context, 62), WRAP));
        row.addView(
                lane,
                new LinearLayout.LayoutParams(0, BrowtherIntroPlayerViews.laneHeight(context), 1f));
        if (trailing != null) {
            trailing.setMaxLines(1);
            row.addView(trailing);
        }
        return row;
    }

    @Override
    void bind(boolean animated) {
        boolean on = mModel.isMusicDemoOn();
        mStamps.setOn(on);
        mSwitch.setOn(on);
        mAdvance.setActive(on);
        if (mMusicOn == null || mMusicOn != on) {
            boolean first = mMusicOn == null;
            mMusicOn = on;
            mMusicLane.setFlattened(on, !first);
            mRemoved.setVisibility(on ? VISIBLE : GONE);
            // L'interrupteur ne relance rien : il change de canal, à la même position. S'il n'y a
            // encore rien à entendre, il lance l'extrait — c'est le geste qui décide, jamais
            // l'écran.
            mAudio.setMusicRemoved(on);
            if (on && !first) mAudio.play();
        }
    }

    @Override
    void onActivated() {
        mAudio.setListener(this);
        mAudio.observeSystemVolume(true);
        onAudioStateChanged();
    }

    @Override
    void onDeactivated() {
        mAudio.stop();
        mAudio.observeSystemVolume(false);
    }

    @Override
    protected void onAttachedToWindow() {
        super.onAttachedToWindow();
        mAudio.setListener(this);
        onAudioStateChanged();
    }

    @Override
    public void onAudioStateChanged() {
        boolean playing = mAudio.isPlaying();
        mPlayGlyph.setImageResource(
                playing ? R.drawable.browther_intro_glyph_pause : R.drawable.browther_intro_glyph_play);
        mPlayButton.setContentDescription(
                getContext()
                        .getString(
                                playing
                                        ? R.string.browther_intro_music_pause
                                        : R.string.browther_intro_music_listen));
        mScrubber.setProgress(mAudio.progress());

        float volume = mAudio.systemVolume();
        boolean muted = volume <= 0.001f;
        if (!mAdjustingVolume) {
            mVolume.setMax(mAudio.systemVolumeSteps());
            mVolume.setProgress(mAudio.systemVolumeStep());
        }
        mVolumeText.setText(mPercent.format(volume));
        mSpeaker.setImageResource(
                muted
                        ? R.drawable.browther_intro_glyph_speaker_slash
                        : R.drawable.browther_intro_glyph_speaker);
        mSpeaker.setImageTintList(
                ColorStateList.valueOf(
                        muted ? BrowtherIntroUi.AMBER : BrowtherIntroUi.withAlpha(Color.WHITE, 0.72f)));
        mMutedWarning.setVisibility(muted ? VISIBLE : GONE);
    }
}
