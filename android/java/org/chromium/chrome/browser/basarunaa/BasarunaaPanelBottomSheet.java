/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.basarunaa;

import android.app.Dialog;
import android.content.Context;
import android.os.Bundle;
import android.text.SpannableStringBuilder;
import android.text.Spanned;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.RadioButton;
import android.widget.RadioGroup;
import android.widget.SeekBar;
import android.widget.TextView;

import androidx.annotation.Nullable;
import androidx.fragment.app.FragmentManager;

import com.google.android.material.bottomsheet.BottomSheetDialog;
import com.google.android.material.bottomsheet.BottomSheetDialogFragment;
import com.google.android.material.materialswitch.MaterialSwitch;

import org.chromium.build.annotations.NullMarked;
import org.chromium.chrome.R;
import org.chromium.chrome.browser.browther_analytics.BrowtherAnalyticsBridge;
import org.chromium.chrome.browser.browther_widgets.BrowtherBigToggleView;
import org.chromium.chrome.browser.preferences.BravePref;
import org.chromium.chrome.browser.profiles.ProfileManager;
import org.chromium.components.user_prefs.UserPrefs;

/**
 * BottomSheet panel shown when the user taps the Basarunaa button in the URL
 * bar. Mirrors macOS panel WebUI (toggle + mode + sliders + debug + capture).
 *
 * <p>All prefs live in Chromium {@code PrefService} ({@code brave.basarunaa.*})
 * — toggling a control here flips the pref, and the BasarunaaTabHelper picks
 * up the change via its PrefChangeRegistrar and pushes the new config to the
 * renderer (which forwards it to the bundle JS via the V8 binding). No
 * intermediate cache.
 */
@NullMarked
public class BasarunaaPanelBottomSheet extends BottomSheetDialogFragment {
    public static final String TAG = "BasarunaaPanel";

    @Nullable private BrowtherBigToggleView mToggle;
    @Nullable private TextView mStatusText;
    @Nullable private RadioGroup mModeGroup;
    @Nullable private TextView mConfBodyLabel;
    @Nullable private SeekBar mConfBodySlider;
    @Nullable private TextView mGenderLabel;
    @Nullable private SeekBar mGenderSlider;
    @Nullable private RadioGroup mDebugGroup;
    @Nullable private MaterialSwitch mCaptureSwitch;

    /** Convenience: build + show. */
    public static void show(FragmentManager fragmentManager) {
        if (fragmentManager.findFragmentByTag(TAG) != null) {
            return;
        }
        new BasarunaaPanelBottomSheet().show(fragmentManager, TAG);
    }

    @Override
    public Dialog onCreateDialog(@Nullable Bundle savedInstanceState) {
        return new BottomSheetDialog(requireContext(), getTheme());
    }

    @Override
    public View onCreateView(
            LayoutInflater inflater,
            @Nullable ViewGroup container,
            @Nullable Bundle savedInstanceState) {
        return inflater.inflate(R.layout.basarunaa_panel_bottom_sheet, container, false);
    }

    @Override
    public void onViewCreated(View view, @Nullable Bundle savedInstanceState) {
        super.onViewCreated(view, savedInstanceState);

        mToggle = view.findViewById(R.id.basarunaa_panel_toggle);
        mStatusText = view.findViewById(R.id.basarunaa_panel_status);
        mModeGroup = view.findViewById(R.id.basarunaa_panel_mode_group);
        mConfBodyLabel = view.findViewById(R.id.basarunaa_panel_conf_body_label);
        mConfBodySlider = view.findViewById(R.id.basarunaa_panel_conf_body_slider);
        mGenderLabel = view.findViewById(R.id.basarunaa_panel_gender_label);
        mGenderSlider = view.findViewById(R.id.basarunaa_panel_gender_slider);
        mDebugGroup = view.findViewById(R.id.basarunaa_panel_debug_group);
        mCaptureSwitch = view.findViewById(R.id.basarunaa_panel_capture_switch);

        bindToggle();
        bindModeGroup();
        bindSlider(mConfBodySlider, mConfBodyLabel,
                BravePref.BASARUNAA_CONF_BODY, R.string.basarunaa_panel_conf_body_fmt);
        bindSlider(mGenderSlider, mGenderLabel,
                BravePref.BASARUNAA_GENDER_CERTAINTY,
                R.string.basarunaa_panel_gender_fmt);
        bindDebugGroup();
        bindCaptureSwitch();
    }

    private void bindToggle() {
        if (mToggle == null) return;
        final boolean enabled = getPrefBool(BravePref.BASARUNAA_ENABLED);
        mToggle.setCheckedSilently(enabled);
        mToggle.setOnCheckedChangeListener(
                (v, isChecked) -> {
                    setPrefBool(BravePref.BASARUNAA_ENABLED, isChecked);
                    BrowtherAnalyticsBridge.trackWithProps(
                            "feature_toggled",
                            new String[] {"feature", "enabled"},
                            new String[] {"basarunaa", Boolean.toString(isChecked)});
                    updateStatusText(isChecked);
                });
        updateStatusText(enabled);
    }

    private void bindModeGroup() {
        if (mModeGroup == null) return;
        final String mode = getPrefStr(BravePref.BASARUNAA_MODE, "blur-female");
        final int checkedId =
                "blur-male".equals(mode)
                        ? R.id.basarunaa_panel_mode_male
                        : "blur-all".equals(mode)
                                ? R.id.basarunaa_panel_mode_all
                                : R.id.basarunaa_panel_mode_female;
        mModeGroup.check(checkedId);
        mModeGroup.setOnCheckedChangeListener(
                (group, id) -> {
                    final String newMode;
                    if (id == R.id.basarunaa_panel_mode_male) newMode = "blur-male";
                    else if (id == R.id.basarunaa_panel_mode_all) newMode = "blur-all";
                    else newMode = "blur-female";
                    setPrefStr(BravePref.BASARUNAA_MODE, newMode);
                });
    }

    private void bindSlider(
            @Nullable SeekBar slider,
            @Nullable TextView label,
            String prefKey,
            int labelFmtRes) {
        if (slider == null || label == null) return;
        final double value = getPrefDouble(prefKey);
        final int progress = (int) Math.round(value * 100.0);
        slider.setProgress(progress);
        label.setText(label.getContext().getString(labelFmtRes, progress));
        slider.setOnSeekBarChangeListener(
                new SeekBar.OnSeekBarChangeListener() {
                    @Override
                    public void onProgressChanged(SeekBar bar, int p, boolean fromUser) {
                        label.setText(label.getContext().getString(labelFmtRes, p));
                    }

                    @Override
                    public void onStartTrackingTouch(SeekBar bar) {}

                    @Override
                    public void onStopTrackingTouch(SeekBar bar) {
                        // Push pref seulement à la fin du drag pour éviter
                        // de spammer PrefChangeRegistrar → SetConfig au renderer.
                        setPrefDouble(prefKey, bar.getProgress() / 100.0);
                    }
                });
    }

    private void bindDebugGroup() {
        if (mDebugGroup == null) return;
        final String mode = getPrefStr(BravePref.BASARUNAA_DEBUG_MODE, "none");
        final int checkedId =
                "debug".equals(mode)
                        ? R.id.basarunaa_panel_debug_full
                        : "boxes".equals(mode)
                                ? R.id.basarunaa_panel_debug_boxes
                                : R.id.basarunaa_panel_debug_none;
        mDebugGroup.check(checkedId);
        mDebugGroup.setOnCheckedChangeListener(
                (group, id) -> {
                    final String newMode;
                    if (id == R.id.basarunaa_panel_debug_boxes) newMode = "boxes";
                    else if (id == R.id.basarunaa_panel_debug_full) newMode = "debug";
                    else newMode = "none";
                    setPrefStr(BravePref.BASARUNAA_DEBUG_MODE, newMode);
                });
    }

    private void bindCaptureSwitch() {
        if (mCaptureSwitch == null) return;
        mCaptureSwitch.setChecked(getPrefBool(BravePref.BASARUNAA_CAPTURE_MODE));
        mCaptureSwitch.setOnCheckedChangeListener(
                (v, isChecked) -> setPrefBool(BravePref.BASARUNAA_CAPTURE_MODE, isChecked));
    }

    private void updateStatusText(boolean enabled) {
        if (mStatusText == null) return;
        Context context = mStatusText.getContext();
        String prefix = context.getString(R.string.basarunaa_panel_status_prefix);
        String suffix =
                enabled
                        ? context.getString(R.string.basarunaa_panel_status_on)
                        : context.getString(R.string.basarunaa_panel_status_off);
        SpannableStringBuilder sb = new SpannableStringBuilder();
        sb.append(prefix).append(' ').append(suffix);
        int boldStart = prefix.length() + 1;
        sb.setSpan(
                new android.text.style.StyleSpan(android.graphics.Typeface.BOLD),
                boldStart,
                sb.length(),
                Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
        mStatusText.setText(sb);
    }

    // ─── Pref helpers ────────────────────────────────────────────────────

    private static boolean getPrefBool(String key) {
        return UserPrefs.get(ProfileManager.getLastUsedRegularProfile()).getBoolean(key);
    }

    private static void setPrefBool(String key, boolean value) {
        UserPrefs.get(ProfileManager.getLastUsedRegularProfile()).setBoolean(key, value);
    }

    private static String getPrefStr(String key, String fallback) {
        final String v = UserPrefs.get(ProfileManager.getLastUsedRegularProfile()).getString(key);
        return v != null && !v.isEmpty() ? v : fallback;
    }

    private static void setPrefStr(String key, String value) {
        UserPrefs.get(ProfileManager.getLastUsedRegularProfile()).setString(key, value);
    }

    private static double getPrefDouble(String key) {
        return UserPrefs.get(ProfileManager.getLastUsedRegularProfile()).getDouble(key);
    }

    private static void setPrefDouble(String key, double value) {
        UserPrefs.get(ProfileManager.getLastUsedRegularProfile()).setDouble(key, value);
    }
}
