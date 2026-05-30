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
import android.widget.TextView;

import androidx.annotation.Nullable;
import androidx.fragment.app.FragmentManager;

import com.google.android.material.bottomsheet.BottomSheetDialog;
import com.google.android.material.bottomsheet.BottomSheetDialogFragment;

import org.chromium.build.annotations.NullMarked;
import org.chromium.chrome.R;
import org.chromium.chrome.browser.browther_analytics.BrowtherAnalyticsBridge;
import org.chromium.chrome.browser.browther_widgets.BrowtherBigToggleView;
import org.chromium.chrome.browser.preferences.BravePref;
import org.chromium.chrome.browser.profiles.ProfileManager;
import org.chromium.components.user_prefs.UserPrefs;

/**
 * BottomSheet panel shown when the user taps the Basarunaa button in the URL
 * bar. Mirrors iOS {@code BasarunaaPanelView} but V1 keeps only the big toggle
 * (the mode radios + detection sliders + debug section from iOS will follow
 * once the Android ML pipeline is in place — Phase 3.1).
 *
 * <p>The toggle flips {@link BravePref#BASARUNAA_ENABLED} but for now the
 * pipeline is a no-op on Android, so we display a "coming soon" notice below
 * the description instead of "(en savoir plus)" like Sawtunaa does.
 */
@NullMarked
public class BasarunaaPanelBottomSheet extends BottomSheetDialogFragment {
    public static final String TAG = "BasarunaaPanel";

    @Nullable private BrowtherBigToggleView mToggle;
    @Nullable private TextView mStatusText;

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

        boolean enabled =
                UserPrefs.get(ProfileManager.getLastUsedRegularProfile())
                        .getBoolean(BravePref.BASARUNAA_ENABLED);

        if (mToggle != null) {
            mToggle.setCheckedSilently(enabled);
            mToggle.setOnCheckedChangeListener(
                    (v, isChecked) -> {
                        UserPrefs.get(ProfileManager.getLastUsedRegularProfile())
                                .setBoolean(BravePref.BASARUNAA_ENABLED, isChecked);
                        BrowtherAnalyticsBridge.trackWithProps(
                                "feature_toggled",
                                new String[] {"feature", "enabled"},
                                new String[] {"basarunaa", Boolean.toString(isChecked)});
                        updateStatusText(isChecked);
                    });
        }

        updateStatusText(enabled);
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
}
