/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.shields_panel;

import android.app.Dialog;
import android.content.Context;
import android.os.Bundle;
import android.text.SpannableStringBuilder;
import android.text.Spanned;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.TextView;

import androidx.annotation.Nullable;
import androidx.fragment.app.FragmentManager;

import com.google.android.material.bottomsheet.BottomSheetDialog;
import com.google.android.material.bottomsheet.BottomSheetDialogFragment;

import org.chromium.base.Log;
import org.chromium.build.annotations.NullMarked;
import org.chromium.chrome.R;
import org.chromium.chrome.browser.app.BraveActivity;
import org.chromium.chrome.browser.browther_widgets.BrowtherBigToggleView;
import org.chromium.chrome.browser.preferences.website.BraveShieldsContentSettings;
import org.chromium.chrome.browser.profiles.Profile;
import org.chromium.chrome.browser.profiles.ProfileManager;
import org.chromium.chrome.browser.tab.Tab;

/**
 * BottomSheet panel shown when the user taps the Brave Shields button in the
 * URL bar. Mirrors the Sawtunaa/Basarunaa panels for visual coherence
 * (Browther 2026-06-01 design alignment) — V1 keeps it minimal: a per-site
 * Shields ON/OFF toggle bound to {@code RESOURCE_IDENTIFIER_BRAVE_SHIELDS}.
 *
 * <p>Advanced Shields settings (per-resource toggles, fingerprinting policy,
 * etc.) remain accessible via Settings → Brave Shields. The legacy anchored
 * popup is no longer shown from the URL bar button.
 */
@NullMarked
public class ShieldsPanelBottomSheet extends BottomSheetDialogFragment {
    public static final String TAG = "ShieldsPanel";
    private static final String LOG_TAG = "ShieldsPanel";

    @Nullable private BrowtherBigToggleView mToggle;
    @Nullable private TextView mStatusText;
    @Nullable private String mCurrentHost;

    /** Convenience: build + show. */
    public static void show(FragmentManager fragmentManager) {
        if (fragmentManager.findFragmentByTag(TAG) != null) {
            return;
        }
        new ShieldsPanelBottomSheet().show(fragmentManager, TAG);
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
        return inflater.inflate(R.layout.shields_panel_bottom_sheet, container, false);
    }

    @Override
    public void onViewCreated(View view, @Nullable Bundle savedInstanceState) {
        super.onViewCreated(view, savedInstanceState);

        mToggle = view.findViewById(R.id.shields_panel_toggle);
        mStatusText = view.findViewById(R.id.shields_panel_status);

        Profile profile = ProfileManager.getLastUsedRegularProfile();
        mCurrentHost = currentTabHost();
        boolean enabled = true;
        if (profile != null && mCurrentHost != null) {
            enabled =
                    BraveShieldsContentSettings.getShields(
                            profile,
                            mCurrentHost,
                            BraveShieldsContentSettings.RESOURCE_IDENTIFIER_BRAVE_SHIELDS);
        }

        if (mToggle != null) {
            mToggle.setCheckedSilently(enabled);
            mToggle.setOnCheckedChangeListener(
                    (v, isChecked) -> {
                        Profile p = ProfileManager.getLastUsedRegularProfile();
                        if (p != null && mCurrentHost != null) {
                            BraveShieldsContentSettings.setShields(
                                    p,
                                    mCurrentHost,
                                    BraveShieldsContentSettings.RESOURCE_IDENTIFIER_BRAVE_SHIELDS,
                                    isChecked);
                            reloadCurrentTab();
                        }
                        updateStatusText(isChecked);
                    });
        }

        updateStatusText(enabled);
    }

    private @Nullable String currentTabHost() {
        try {
            Tab tab = BraveActivity.getBraveActivity().getActivityTab();
            if (tab == null || tab.getUrl() == null) return null;
            return tab.getUrl().getHost();
        } catch (BraveActivity.BraveActivityNotFoundException e) {
            Log.e(LOG_TAG, "currentTabHost " + e);
            return null;
        }
    }

    private void reloadCurrentTab() {
        try {
            Tab tab = BraveActivity.getBraveActivity().getActivityTab();
            if (tab != null) tab.reload();
        } catch (BraveActivity.BraveActivityNotFoundException e) {
            Log.e(LOG_TAG, "reloadCurrentTab " + e);
        }
    }

    private void updateStatusText(boolean enabled) {
        if (mStatusText == null) return;
        Context context = mStatusText.getContext();
        String prefix = context.getString(R.string.shields_panel_status_prefix);
        String suffix =
                enabled
                        ? context.getString(R.string.shields_panel_status_on)
                        : context.getString(R.string.shields_panel_status_off);
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
}
