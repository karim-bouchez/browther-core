/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.sawtunaa;

import android.app.Dialog;
import android.content.Context;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.text.SpannableStringBuilder;
import android.text.Spanned;
import android.text.method.LinkMovementMethod;
import android.text.style.ClickableSpan;
import android.text.style.UnderlineSpan;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.TextView;

import androidx.annotation.Nullable;
import androidx.appcompat.app.AlertDialog;
import androidx.fragment.app.FragmentManager;

import com.google.android.material.bottomsheet.BottomSheetDialog;
import com.google.android.material.bottomsheet.BottomSheetDialogFragment;

import org.chromium.build.annotations.NullMarked;
import org.chromium.chrome.R;
import org.chromium.chrome.browser.browther_analytics.BrowtherAnalyticsBridge;
import org.chromium.chrome.browser.browther_analytics.BrowtherSiteReport;
import org.chromium.chrome.browser.browther_referral.BrowtherReferralController;
import org.chromium.chrome.browser.browther_referral.ReferralExtraPanel;
import org.chromium.chrome.browser.browther_referral.core.ExtraFeature;
import org.chromium.chrome.browser.browther_widgets.BrowtherBigToggleView;
import org.chromium.chrome.browser.browther_widgets.BrowtherEarlyAccess;
import org.chromium.chrome.browser.preferences.BravePref;
import org.chromium.chrome.browser.profiles.ProfileManager;
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
 * <p>Propagation du toggle : SANS rechargement, dans les deux sens (2026-10-01 ; avant,
 * l'allumage rechargeait l'onglet et la vidéo repartait de 0). Le script est injecté sur toutes
 * les pages, en veille quand Sawtunaa est éteint ; le RFO renderer-side reçoit
 * `SetEnabled(...)` via Mojo et dispatche `sawtunaa-state`, le script s'allume ou s'éteint en
 * direct (cf. sawtunaa_render_frame_observer.cc).
 *
 * <p>« Seulement 2 min » : juste après une bascule, tant que la feuille est ouverte, un bouton
 * propose le retour automatique à l'état d'avant ({@link SawtunaaTemporarySwitch}) ; pendant le
 * compte à rebours, une ligne « libellé · 1:42 · Ne pas réactiver » et un anneau sur le bouton
 * rond de l'interrupteur. Rebasculer l'interrupteur revient tout de suite à l'état d'avant.
 */
@NullMarked
public class SawtunaaPanelBottomSheet extends BottomSheetDialogFragment {
    public static final String TAG = "SawtunaaPanel";

    private static final int COLOR_RED = 0xFFEF4444;
    private static final int COLOR_GREEN = 0xFF22C55E;
    private static final int COLOR_AMBER = 0xFFF59E0B;
    private static final long TICK_MS = 500L;

    @Nullable private BrowtherBigToggleView mToggle;
    @Nullable private TextView mStatusText;
    @Nullable private TextView mDescriptionText;
    @Nullable private Button mTempOffer;
    @Nullable private View mTempRow;
    @Nullable private TextView mTempLabel;
    @Nullable private TextView mTempTime;
    @Nullable private Button mTempKeep;

    /**
     * L'utilisateur vient de basculer dans CETTE feuille ouverte : on lui propose le retour
     * automatique. État de la feuille, pas réglage — à la réouverture, la bascule est durable.
     */
    private boolean mOffered;

    private final Handler mHandler = new Handler(Looper.getMainLooper());
    private final Runnable mTick = this::onTick;
    private final SawtunaaTemporarySwitch.Observer mTemporaryObserver = this::refreshTemporary;

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
        mTempOffer = view.findViewById(R.id.sawtunaa_panel_temp_offer);
        mTempRow = view.findViewById(R.id.sawtunaa_panel_temp_row);
        mTempLabel = view.findViewById(R.id.sawtunaa_panel_temp_label);
        mTempTime = view.findViewById(R.id.sawtunaa_panel_temp_time);
        mTempKeep = view.findViewById(R.id.sawtunaa_panel_temp_keep);
        if (mTempOffer != null) {
            mTempOffer.setOnClickListener(
                    v -> {
                        mOffered = false;
                        SawtunaaTemporarySwitch.get().start();
                    });
        }
        if (mTempKeep != null) {
            mTempKeep.setOnClickListener(v -> SawtunaaTemporarySwitch.get().keep());
        }

        boolean enabled =
                UserPrefs.get(ProfileManager.getLastUsedRegularProfile())
                        .getBoolean(BravePref.SAWTUNAA_ENABLED);

        BrowtherEarlyAccess.bindNotice(view, this::dismiss);
        applyEarlyAccess(view, enabled);

        if (mToggle != null) {
            mToggle.setCheckedSilently(enabled);
            mToggle.setOnCheckedChangeListener(
                    (v, isChecked) -> {
                        // Browther : la garde du parrainage (§ 2.14) — l'interrupteur est déjà
                        // verrouillé en pause ; ceci ne sert que si le verrou a manqué.
                        if (isChecked
                                && !BrowtherReferralController.get()
                                        .requireExtra(
                                                ExtraFeature.MUSIC_REMOVAL, requireActivity())) {
                            if (mToggle != null) mToggle.setCheckedSilently(false);
                            return;
                        }
                        // Une bascule pendant le compte à rebours = revenir tout de suite :
                        // elle rejoint l'état d'avant, le retour s'annule tout seul
                        // (SawtunaaTemporarySwitch), et on ne repropose rien.
                        boolean wasTemporary = SawtunaaTemporarySwitch.get().isActive();
                        UserPrefs.get(ProfileManager.getLastUsedRegularProfile())
                                .setBoolean(BravePref.SAWTUNAA_ENABLED, isChecked);
                        mOffered = !wasTemporary;
                        BrowtherAnalyticsBridge.trackWithProps(
                                "feature_toggled",
                                new String[] {"feature", "enabled"},
                                new String[] {"sawtunaa", Boolean.toString(isChecked)});
                        updateStatusText(isChecked);
                        applyEarlyAccess(view, isChecked);
                        refreshTemporary();
                        // Pas de rechargement : la pref poussée au renderer
                        // allume / éteint le script en direct.
                    });
        }

        updateStatusText(enabled);
        refreshTemporary();
        installDescription();
        bindReferral(view);

        // Browther : « ça ne marche pas ici ? ». Toutes les règles (domaine seul,
        // consentement, page interne) vivent dans le helper partagé.
        BrowtherSiteReport.bind(view, "sawtunaa");
    }

    /**
     * Browther : le parrainage dans le panneau (private/docs/PARRAINAGE.md § 2.14) — en pause,
     * interrupteur verrouillé + « Débloquer » ; sinon l'encadré doré « La garder à vie ».
     */
    private void bindReferral(View root) {
        ViewGroup slot = root.findViewById(R.id.sawtunaa_panel_referral);
        if (mToggle == null || mStatusText == null || mDescriptionText == null || slot == null) {
            return;
        }
        ReferralExtraPanel.bind(
                requireActivity(), mToggle, mStatusText, mDescriptionText, slot, this::dismiss);
    }

    /**
     * Accès anticipé : encadré « encore en développement » + gros toggle ambre
     * tant que la feature est ON. Cf. {@link BrowtherEarlyAccess}.
     */
    private void applyEarlyAccess(View root, boolean enabled) {
        BrowtherEarlyAccess.setNoticeVisible(root, enabled);
        if (mToggle != null) mToggle.setAmber(BrowtherEarlyAccess.ENABLED);
    }

    private void updateStatusText(boolean enabled) {
        if (mStatusText == null) return;
        // Une string COMPLÈTE par état, jamais une concaténation préfixe +
        // suffixe : l'ordre des mots change d'une langue à l'autre, et un
        // `prefix.length()` pour placer le gras ne veut rien dire en arabe.
        // Textes alignés sur le panel desktop, ce qui permet en prime de
        // réutiliser ses traductions (cf. private/docs/TODO.md).
        mStatusText.setText(
                mStatusText
                        .getContext()
                        .getString(
                                enabled
                                        ? R.string.sawtunaa_panel_status_on
                                        : R.string.sawtunaa_panel_status_off));
        mStatusText.setTypeface(mStatusText.getTypeface(), android.graphics.Typeface.BOLD);
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

    @Override
    public void onStart() {
        super.onStart();
        SawtunaaTemporarySwitch.get().addObserver(mTemporaryObserver);
        refreshTemporary();
    }

    @Override
    public void onStop() {
        SawtunaaTemporarySwitch.get().removeObserver(mTemporaryObserver);
        mHandler.removeCallbacks(mTick);
        super.onStop();
    }

    private static boolean isEnabledPref() {
        return UserPrefs.get(ProfileManager.getLastUsedRegularProfile())
                .getBoolean(BravePref.SAWTUNAA_ENABLED);
    }

    /** Couleur de l'état ACTUEL : rouge coupé, ambre (accès anticipé) / vert allumé. */
    private static int stateColor(boolean enabled) {
        if (!enabled) return COLOR_RED;
        return BrowtherEarlyAccess.ENABLED ? COLOR_AMBER : COLOR_GREEN;
    }

    /** Proposition, ligne de compte à rebours et anneau, selon l'état du retour automatique. */
    private void refreshTemporary() {
        SawtunaaTemporarySwitch temporary = SawtunaaTemporarySwitch.get();
        boolean enabled = isEnabledPref();
        boolean paused = BrowtherReferralController.get().isPaused();
        boolean active = temporary.isActive();
        if (active) mOffered = false;
        if (mTempOffer != null) {
            mTempOffer.setVisibility(mOffered && !active && !paused ? View.VISIBLE : View.GONE);
            mTempOffer.setText(
                    enabled
                            ? R.string.sawtunaa_temp_offer_disable
                            : R.string.sawtunaa_temp_offer_reenable);
        }
        if (mTempRow != null) mTempRow.setVisibility(active ? View.VISIBLE : View.GONE);
        if (mTempLabel != null) {
            mTempLabel.setText(
                    enabled
                            ? R.string.sawtunaa_temp_countdown_disable
                            : R.string.sawtunaa_temp_countdown_reenable);
            mTempLabel.setTextColor(stateColor(enabled));
        }
        if (mTempKeep != null) {
            mTempKeep.setText(
                    enabled ? R.string.sawtunaa_temp_keep_on : R.string.sawtunaa_temp_keep_off);
        }
        if (mTempTime != null) mTempTime.setTextColor(stateColor(enabled));
        mHandler.removeCallbacks(mTick);
        if (active) {
            onTick();
        } else if (mToggle != null) {
            mToggle.setCountdown(-1f, 0);
        }
    }

    private void onTick() {
        SawtunaaTemporarySwitch temporary = SawtunaaTemporarySwitch.get();
        temporary.checkDue();
        if (!temporary.isActive()) return; // l'observateur a déjà tout rafraîchi
        long remaining = temporary.remainingMs();
        if (mTempTime != null) mTempTime.setText(formatCountdown(remaining));
        if (mToggle != null) {
            mToggle.setCountdown(
                    remaining / (float) SawtunaaTemporarySwitch.DURATION_MS,
                    stateColor(isEnabledPref()));
        }
        mHandler.postDelayed(mTick, TICK_MS);
    }

    /** « 1:42 ». */
    static String formatCountdown(long remainingMs) {
        long s = (remainingMs + 999) / 1000;
        return String.format(java.util.Locale.ROOT, "%d:%02d", s / 60, s % 60);
    }
}
