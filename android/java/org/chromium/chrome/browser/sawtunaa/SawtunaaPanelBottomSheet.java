/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.sawtunaa;

import android.app.Dialog;
import android.content.Context;
import android.os.Bundle;
import android.text.SpannableStringBuilder;
import android.text.Spanned;
import android.text.method.LinkMovementMethod;
import android.text.style.ClickableSpan;
import android.text.style.UnderlineSpan;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.TextView;

import androidx.annotation.Nullable;
import androidx.appcompat.app.AlertDialog;
import androidx.fragment.app.FragmentManager;

import com.google.android.material.bottomsheet.BottomSheetDialog;
import com.google.android.material.bottomsheet.BottomSheetDialogFragment;

import org.chromium.base.Log;
import org.chromium.build.annotations.NullMarked;
import org.chromium.chrome.R;
import org.chromium.chrome.browser.app.BraveActivity;
import org.chromium.chrome.browser.browther_analytics.BrowtherAnalyticsBridge;
import org.chromium.chrome.browser.browther_widgets.BrowtherBigToggleView;
import org.chromium.chrome.browser.preferences.BravePref;
import org.chromium.chrome.browser.profiles.ProfileManager;
import org.chromium.chrome.browser.tab.Tab;
import org.chromium.components.user_prefs.UserPrefs;

/**
 * BottomSheet panel shown when the user taps the Sawtunaa button in the URL
 * bar. Mirrors iOS {@code SawtunaaPanelView} and macOS {@code
 * sawtunaa_bubble_view.cc}.
 *
 * <p>Contents (top to bottom):
 *
 * <ul>
 *   <li>Header: icon-with-bg + Sawtunaa wordmark.
 *   <li>Big animated toggle (96x52 dp) bound to {@link BravePref#SAWTUNAA_ENABLED}.
 *   <li>Status text "Suppression de la musique ACTIVÉE/DÉSACTIVÉE".
 *   <li>Description "Pour l'instant, ça fonctionne uniquement sur YouTube. (en
 *       savoir plus)" — last part is a clickable underlined span that pops an
 *       explanatory AlertDialog.
 * </ul>
 *
 * <p>Telemetry: every flip of the toggle fires {@code feature_toggled} via
 * {@link BrowtherAnalyticsBridge} (parity with iOS).
 *
 * <p>Propagation du toggle (V1) :
 * <ul>
 *   <li>OFF live : le RFO renderer-side reçoit `SetEnabled(false)` via Mojo
 *       et dispatche `sawtunaa-disable` au main world. Le script JS restaure
 *       les descriptors muted/volume natifs sur le `<video>` → audio
 *       original revient sans reload.</li>
 *   <li>ON live : reload du tab. Le RFO renderer-side ne peut pas injecter
 *       le script à la volée parce que le V8 main world peut être en cours
 *       de navigation (DCHECK fatal dans `MainWorldScriptContext()` si
 *       frame provisional). Le reload garantit un `DidClearWindowObject`
 *       propre, qui ré-injecte le script avec la nouvelle pref.</li>
 * </ul>
 */
@NullMarked
public class SawtunaaPanelBottomSheet extends BottomSheetDialogFragment {
    public static final String TAG = "SawtunaaPanel";

    private static final String TAG_LOG = "Sawtunaa";

    @Nullable private BrowtherBigToggleView mToggle;
    @Nullable private TextView mStatusText;
    @Nullable private TextView mDescriptionText;

    /** Convenience: build + show. */
    public static void show(FragmentManager fragmentManager) {
        if (fragmentManager.findFragmentByTag(TAG) != null) {
            // Already showing — re-click acts as dismiss handled by parent.
            return;
        }
        new SawtunaaPanelBottomSheet().show(fragmentManager, TAG);
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
        return inflater.inflate(R.layout.sawtunaa_panel_bottom_sheet, container, false);
    }

    @Override
    public void onViewCreated(View view, @Nullable Bundle savedInstanceState) {
        super.onViewCreated(view, savedInstanceState);

        mToggle = view.findViewById(R.id.sawtunaa_panel_toggle);
        mStatusText = view.findViewById(R.id.sawtunaa_panel_status);
        mDescriptionText = view.findViewById(R.id.sawtunaa_panel_description);

        boolean enabled =
                UserPrefs.get(ProfileManager.getLastUsedRegularProfile())
                        .getBoolean(BravePref.SAWTUNAA_ENABLED);

        if (mToggle != null) {
            mToggle.setCheckedSilently(enabled);
            mToggle.setOnCheckedChangeListener(
                    (v, isChecked) -> {
                        UserPrefs.get(ProfileManager.getLastUsedRegularProfile())
                                .setBoolean(BravePref.SAWTUNAA_ENABLED, isChecked);
                        BrowtherAnalyticsBridge.trackWithProps(
                                "feature_toggled",
                                new String[] {"feature", "enabled"},
                                new String[] {"sawtunaa", Boolean.toString(isChecked)});
                        updateStatusText(isChecked);
                        if (isChecked) {
                            // OFF → ON : reload du tab. Tenter d'injecter le
                            // script live depuis le RFO crash si le main
                            // world V8 est en cours de navigation
                            // (DCHECK dans MainWorldScriptContext). Le reload
                            // garantit un DidClearWindowObject propre.
                            reloadActiveTab();
                        }
                        // OFF live : pas de reload. Le RFO renderer-side
                        // reçoit `SawtunaaConfig::SetEnabled(false)` via Mojo
                        // (poussé par `SawtunaaTabHelper` C++ qui observe la
                        // pref via `PrefChangeRegistrar`) et dispatche
                        // `sawtunaa-disable` au main world. Le script JS
                        // restaure le mute natif live.
                    });
        }

        updateStatusText(enabled);
        installDescription();
    }

    private void updateStatusText(boolean enabled) {
        if (mStatusText == null) return;
        Context context = mStatusText.getContext();
        String prefix = context.getString(R.string.sawtunaa_panel_status_prefix);
        String suffix =
                enabled
                        ? context.getString(R.string.sawtunaa_panel_status_on)
                        : context.getString(R.string.sawtunaa_panel_status_off);
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

    private void installDescription() {
        if (mDescriptionText == null) return;
        Context context = mDescriptionText.getContext();
        String body = context.getString(R.string.sawtunaa_panel_description);
        String link = context.getString(R.string.sawtunaa_panel_learn_more);

        SpannableStringBuilder sb = new SpannableStringBuilder();
        sb.append(body).append(' ').append(link);
        int linkStart = body.length() + 1;
        int linkEnd = sb.length();
        sb.setSpan(new UnderlineSpan(), linkStart, linkEnd, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
        sb.setSpan(
                new ClickableSpan() {
                    @Override
                    public void onClick(View widget) {
                        showLimitationsDialog();
                    }
                },
                linkStart,
                linkEnd,
                Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);

        mDescriptionText.setText(sb);
        mDescriptionText.setMovementMethod(LinkMovementMethod.getInstance());
    }

    private void showLimitationsDialog() {
        Context context = requireContext();
        new AlertDialog.Builder(context)
                .setTitle(R.string.sawtunaa_panel_limitations_title)
                .setMessage(R.string.sawtunaa_panel_limitations_message)
                .setPositiveButton(android.R.string.ok, null)
                .show();
    }

    private void reloadActiveTab() {
        try {
            Tab tab = BraveActivity.getBraveActivity().getActivityTab();
            if (tab != null) {
                Log.i(TAG_LOG, "Reloading active tab after Sawtunaa ON toggle");
                tab.reload();
            }
        } catch (BraveActivity.BraveActivityNotFoundException e) {
            Log.e(TAG_LOG, "reloadActiveTab " + e);
        }
    }
}
