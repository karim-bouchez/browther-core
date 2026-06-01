/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.shields_panel;

import android.app.Dialog;
import android.content.Context;
import android.graphics.Bitmap;
import android.os.Bundle;
import android.text.SpannableStringBuilder;
import android.text.Spanned;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;

import androidx.annotation.Nullable;
import androidx.appcompat.widget.SwitchCompat;
import androidx.fragment.app.FragmentManager;

import com.google.android.material.bottomsheet.BottomSheetDialog;
import com.google.android.material.bottomsheet.BottomSheetDialogFragment;

import org.chromium.base.Log;
import org.chromium.build.annotations.NullMarked;
import org.chromium.chrome.R;
import org.chromium.chrome.browser.BraveRewardsHelper;
import org.chromium.chrome.browser.app.BraveActivity;
import org.chromium.chrome.browser.browther_widgets.BrowtherBigToggleView;
import org.chromium.chrome.browser.preferences.website.BraveShieldsContentSettings;
import org.chromium.chrome.browser.privacy.settings.BravePrivacySettings;
import org.chromium.chrome.browser.profiles.Profile;
import org.chromium.chrome.browser.profiles.ProfileManager;
import org.chromium.chrome.browser.settings.SettingsNavigationFactory;
import org.chromium.chrome.browser.tab.Tab;
import org.chromium.chrome.browser.toolbar.top.BraveToolbarLayoutImpl;
import org.chromium.components.browser_ui.settings.SettingsNavigation;

/**
 * BottomSheet panel shown when the user taps the Brave Shields button in the
 * URL bar. Adapts the legacy Brave Shields anchored popup into the same
 * Sawtunaa/Basarunaa BottomSheet vocabulary (Browther 2026-06-01 alignment).
 *
 * <p>Always shown:
 *
 * <ul>
 *   <li>Header + big toggle bound to {@code
 *       RESOURCE_IDENTIFIER_BRAVE_SHIELDS} for the current site (per-site
 *       global Shields ON/OFF).
 *   <li>Status text "Boucliers ACTIVÉS/DÉSACTIVÉS".
 * </ul>
 *
 * <p>When Shields is ON for the site:
 *
 * <ul>
 *   <li>Stats card with the ads + trackers blocked count for the active tab,
 *       sourced from {@link BraveToolbarLayoutImpl}.
 *   <li>Collapsible "Réglages avancés" section with per-resource toggles
 *       (trackers, scripts, fingerprint, HTTPS upgrade) + a navigation row
 *       to the global Shields settings page.
 * </ul>
 *
 * <p>When Shields is OFF: a footer hint encourages re-enabling.
 *
 * <p>Each settings flip reloads the active tab to apply the change.
 */
@NullMarked
public class ShieldsPanelBottomSheet extends BottomSheetDialogFragment {
    public static final String TAG = "ShieldsPanel";
    private static final String LOG_TAG = "ShieldsPanel";

    // Persistent across re-opens — kept as a static so the disclosure state
    // survives a dismiss/reopen of the panel.
    private static boolean sAdvancedExpanded;

    @Nullable private ImageView mFaviconView;
    @Nullable private TextView mHostText;
    @Nullable private BrowtherBigToggleView mToggle;
    @Nullable private TextView mStatusText;
    @Nullable private LinearLayout mWhenOnGroup;
    @Nullable private TextView mOffHint;
    @Nullable private TextView mBlockedCount;
    @Nullable private LinearLayout mAdvancedHeader;
    @Nullable private ImageView mAdvancedChevron;
    @Nullable private LinearLayout mAdvancedSection;
    @Nullable private SwitchCompat mSwitchTrackers;
    @Nullable private SwitchCompat mSwitchScripts;
    @Nullable private SwitchCompat mSwitchFingerprint;
    @Nullable private SwitchCompat mSwitchHttps;
    @Nullable private LinearLayout mGlobalSettings;

    @Nullable private String mUrlSpec;
    @Nullable private String mDisplayHost;

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

        mFaviconView = view.findViewById(R.id.shields_panel_favicon);
        mHostText = view.findViewById(R.id.shields_panel_host);
        mToggle = view.findViewById(R.id.shields_panel_toggle);
        mStatusText = view.findViewById(R.id.shields_panel_status);
        mWhenOnGroup = view.findViewById(R.id.shields_panel_when_on);
        mOffHint = view.findViewById(R.id.shields_panel_off_hint);
        mBlockedCount = view.findViewById(R.id.shields_panel_blocked_count);
        mAdvancedHeader = view.findViewById(R.id.shields_panel_advanced_header);
        mAdvancedChevron = view.findViewById(R.id.shields_panel_advanced_chevron);
        mAdvancedSection = view.findViewById(R.id.shields_panel_advanced_section);
        mSwitchTrackers = view.findViewById(R.id.shields_panel_switch_trackers);
        mSwitchScripts = view.findViewById(R.id.shields_panel_switch_scripts);
        mSwitchFingerprint = view.findViewById(R.id.shields_panel_switch_fingerprint);
        mSwitchHttps = view.findViewById(R.id.shields_panel_switch_https);
        mGlobalSettings = view.findViewById(R.id.shields_panel_global_settings);

        // Defensive NTP / internal-URL guard. BraveToolbarLayoutImpl already
        // skips opening the panel on non-http(s) URLs, but if we somehow get
        // shown on an internal page we dismiss rather than rendering a
        // misleading per-site toggle that has no effect.
        mUrlSpec = currentTabUrlSpec();
        if (!isWebUrl(mUrlSpec)) {
            dismissAllowingStateLoss();
            return;
        }
        mDisplayHost = formatDisplayHost(mUrlSpec);
        if (mHostText != null && mDisplayHost != null) {
            mHostText.setText(mDisplayHost);
        }
        fetchFavicon();

        Profile profile = ProfileManager.getLastUsedRegularProfile();
        boolean shieldsOn = true;
        if (profile != null) {
            shieldsOn =
                    BraveShieldsContentSettings.getShields(
                            profile,
                            mUrlSpec,
                            BraveShieldsContentSettings.RESOURCE_IDENTIFIER_BRAVE_SHIELDS);
        }

        if (mToggle != null) {
            mToggle.setCheckedSilently(shieldsOn);
            mToggle.setOnCheckedChangeListener(
                    (v, isChecked) -> {
                        Profile p = ProfileManager.getLastUsedRegularProfile();
                        if (p != null && mUrlSpec != null) {
                            BraveShieldsContentSettings.setShields(
                                    p,
                                    mUrlSpec,
                                    BraveShieldsContentSettings.RESOURCE_IDENTIFIER_BRAVE_SHIELDS,
                                    isChecked,
                                    /* fromTopShields= */ true);
                            reloadCurrentTab();
                        }
                        applyShieldsState(isChecked);
                    });
        }

        applyShieldsState(shieldsOn);
        wireAdvancedDisclosure();
        wireGlobalSettings();
    }

    /**
     * Returns true iff {@code spec} is an http(s) URL we can attach per-site
     * Shields settings to. Mirrors {@code BraveToolbarLayoutImpl
     * #isValidProtocolForShields} and iOS {@code url.isWebPage(...)}.
     */
    private static boolean isWebUrl(@Nullable String spec) {
        if (spec == null || spec.isEmpty()) return false;
        return spec.startsWith("http://") || spec.startsWith("https://");
    }

    /**
     * Strips the scheme + trailing slash + optional "www." prefix for display.
     * Cheap parity with iOS {@code URLFormatter.formatURLOrigin(...
     * OmitSchemePathAndTrivialSubdomains:)}.
     */
    private static @Nullable String formatDisplayHost(@Nullable String spec) {
        if (spec == null) return null;
        try {
            java.net.URI uri = java.net.URI.create(spec);
            String host = uri.getHost();
            if (host == null || host.isEmpty()) return null;
            if (host.startsWith("www.")) host = host.substring(4);
            return host;
        } catch (IllegalArgumentException e) {
            return null;
        }
    }

    /** Toggles the visibility of the ON/OFF groups + refreshes their contents. */
    private void applyShieldsState(boolean shieldsOn) {
        updateStatusText(shieldsOn);
        if (mWhenOnGroup != null) {
            mWhenOnGroup.setVisibility(shieldsOn ? View.VISIBLE : View.GONE);
        }
        if (mOffHint != null) {
            mOffHint.setVisibility(shieldsOn ? View.GONE : View.VISIBLE);
        }
        if (shieldsOn) {
            updateBlockedCount();
            populateAdvancedSwitches();
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

    private void updateBlockedCount() {
        if (mBlockedCount == null) return;
        int count = 0;
        try {
            BraveActivity activity = BraveActivity.getBraveActivity();
            BraveToolbarLayoutImpl toolbar = activity.findViewById(R.id.toolbar);
            Tab tab = activity.getActivityTab();
            if (toolbar != null && tab != null) {
                count = toolbar.getShieldsAdsAndTrackersBlockedCount(tab.getId());
            }
        } catch (BraveActivity.BraveActivityNotFoundException e) {
            Log.e(LOG_TAG, "updateBlockedCount " + e);
        }
        mBlockedCount.setText(String.valueOf(count));
    }

    /** Reads the current per-resource states from native and reflects them on the switches. */
    private void populateAdvancedSwitches() {
        Profile profile = ProfileManager.getLastUsedRegularProfile();
        if (profile == null || mUrlSpec == null) return;

        // Trackers + Ads: tri-state stored as a string. "allow" means OFF.
        if (mSwitchTrackers != null) {
            String trackers =
                    BraveShieldsContentSettings.getShieldsValue(
                            profile,
                            mUrlSpec,
                            BraveShieldsContentSettings.RESOURCE_IDENTIFIER_TRACKERS);
            mSwitchTrackers.setOnCheckedChangeListener(null);
            mSwitchTrackers.setChecked(
                    !BraveShieldsContentSettings.ALLOW_RESOURCE.equals(trackers));
            mSwitchTrackers.setOnCheckedChangeListener(
                    (v, isChecked) -> setShieldsValue(
                            BraveShieldsContentSettings.RESOURCE_IDENTIFIER_TRACKERS,
                            isChecked
                                    ? BraveShieldsContentSettings.DEFAULT
                                    : BraveShieldsContentSettings.ALLOW_RESOURCE));
        }

        // Scripts: binary, exposed via setShields/getShields.
        if (mSwitchScripts != null) {
            boolean scriptsBlocked =
                    BraveShieldsContentSettings.getShields(
                            profile,
                            mUrlSpec,
                            BraveShieldsContentSettings.RESOURCE_IDENTIFIER_JAVASCRIPTS);
            mSwitchScripts.setOnCheckedChangeListener(null);
            mSwitchScripts.setChecked(scriptsBlocked);
            mSwitchScripts.setOnCheckedChangeListener(
                    (v, isChecked) -> setShieldsBool(
                            BraveShieldsContentSettings.RESOURCE_IDENTIFIER_JAVASCRIPTS,
                            isChecked));
        }

        // Fingerprint: tri-state. "allow" means OFF.
        if (mSwitchFingerprint != null) {
            String fp =
                    BraveShieldsContentSettings.getShieldsValue(
                            profile,
                            mUrlSpec,
                            BraveShieldsContentSettings.RESOURCE_IDENTIFIER_FINGERPRINTING);
            mSwitchFingerprint.setOnCheckedChangeListener(null);
            mSwitchFingerprint.setChecked(
                    !BraveShieldsContentSettings.ALLOW_RESOURCE.equals(fp));
            mSwitchFingerprint.setOnCheckedChangeListener(
                    (v, isChecked) -> setShieldsValue(
                            BraveShieldsContentSettings.RESOURCE_IDENTIFIER_FINGERPRINTING,
                            isChecked
                                    ? BraveShieldsContentSettings.DEFAULT
                                    : BraveShieldsContentSettings.ALLOW_RESOURCE));
        }

        // HTTPS upgrade: tri-state.
        if (mSwitchHttps != null) {
            String https =
                    BraveShieldsContentSettings.getShieldsValue(
                            profile,
                            mUrlSpec,
                            BraveShieldsContentSettings.RESOURCE_IDENTIFIER_HTTPS_UPGRADE);
            mSwitchHttps.setOnCheckedChangeListener(null);
            mSwitchHttps.setChecked(
                    !BraveShieldsContentSettings.ALLOW_RESOURCE.equals(https));
            mSwitchHttps.setOnCheckedChangeListener(
                    (v, isChecked) -> setShieldsValue(
                            BraveShieldsContentSettings.RESOURCE_IDENTIFIER_HTTPS_UPGRADE,
                            isChecked
                                    ? BraveShieldsContentSettings.DEFAULT
                                    : BraveShieldsContentSettings.ALLOW_RESOURCE));
        }
    }

    private void setShieldsValue(String resource, String settingOption) {
        Profile p = ProfileManager.getLastUsedRegularProfile();
        if (p == null || mUrlSpec == null) return;
        BraveShieldsContentSettings.setShieldsValue(
                p, mUrlSpec, resource, settingOption, /* fromTopShields= */ false);
        reloadCurrentTab();
    }

    private void setShieldsBool(String resource, boolean value) {
        Profile p = ProfileManager.getLastUsedRegularProfile();
        if (p == null || mUrlSpec == null) return;
        BraveShieldsContentSettings.setShields(
                p, mUrlSpec, resource, value, /* fromTopShields= */ false);
        reloadCurrentTab();
    }

    private void wireAdvancedDisclosure() {
        if (mAdvancedHeader == null) return;
        applyAdvancedExpansion(sAdvancedExpanded);
        mAdvancedHeader.setOnClickListener(
                v -> {
                    sAdvancedExpanded = !sAdvancedExpanded;
                    applyAdvancedExpansion(sAdvancedExpanded);
                });
    }

    private void applyAdvancedExpansion(boolean expanded) {
        if (mAdvancedSection != null) {
            mAdvancedSection.setVisibility(expanded ? View.VISIBLE : View.GONE);
        }
        if (mAdvancedChevron != null) {
            // 90° = rotated chevron from "▸" to "▾".
            mAdvancedChevron.setRotation(expanded ? 90f : 0f);
        }
    }

    private void wireGlobalSettings() {
        if (mGlobalSettings == null) return;
        mGlobalSettings.setOnClickListener(
                v -> {
                    try {
                        BraveActivity activity = BraveActivity.getBraveActivity();
                        SettingsNavigation nav =
                                SettingsNavigationFactory.createSettingsNavigation();
                        nav.startSettings(activity, BravePrivacySettings.class);
                        dismissAllowingStateLoss();
                    } catch (BraveActivity.BraveActivityNotFoundException e) {
                        Log.e(LOG_TAG, "wireGlobalSettings " + e);
                    }
                });
    }

    private @Nullable String currentTabUrlSpec() {
        try {
            Tab tab = BraveActivity.getBraveActivity().getActivityTab();
            if (tab == null || tab.getUrl() == null) return null;
            return tab.getUrl().getSpec();
        } catch (BraveActivity.BraveActivityNotFoundException e) {
            Log.e(LOG_TAG, "currentTabUrlSpec " + e);
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

    /**
     * Loads the favicon for the active tab using the same LargeIconBridge path
     * the legacy Brave Shields popup uses. If the icon doesn't arrive in time
     * (or fetch fails), the placeholder shield icon stays visible — no error
     * surface needed.
     */
    private void fetchFavicon() {
        if (mFaviconView == null || mUrlSpec == null) return;
        try {
            Tab tab = BraveActivity.getBraveActivity().getActivityTab();
            if (tab == null) return;
            BraveRewardsHelper helper = new BraveRewardsHelper(tab);
            helper.retrieveLargeIcon(
                    mUrlSpec,
                    (Bitmap icon) -> {
                        if (icon != null && mFaviconView != null) {
                            mFaviconView.setImageBitmap(
                                    BraveRewardsHelper.getCircularBitmap(icon));
                        }
                    });
        } catch (BraveActivity.BraveActivityNotFoundException e) {
            Log.e(LOG_TAG, "fetchFavicon " + e);
        }
    }
}
