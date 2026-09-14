/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_intro;

import android.app.Activity;
import android.app.role.RoleManager;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.graphics.Color;
import android.media.AudioManager;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;
import android.view.View;
import android.view.Window;
import android.widget.FrameLayout;

import org.chromium.base.IntentUtils;
import org.chromium.base.Log;
import org.chromium.chrome.browser.browther_analytics.BrowtherAnalyticsBridge;
import org.chromium.chrome.browser.browther_widgets.BrowtherEarlyAccess;
import org.chromium.chrome.browser.customtabs.CustomTabActivity;
import org.chromium.chrome.browser.preferences.BravePref;
import org.chromium.chrome.browser.profiles.Profile;
import org.chromium.chrome.browser.profiles.ProfileManager;
import org.chromium.chrome.browser.set_default_browser.BraveSetDefaultBrowserUtils;
import org.chromium.chrome.browser.util.BraveConstants;
import org.chromium.components.user_prefs.UserPrefs;

/**
 * Branche l'introduction Browther dans l'activité du premier lancement ({@code
 * WelcomeOnboardingActivity}) : c'est ici, et seulement ici, que l'introduction touche Chromium —
 * préférences, analytique, rôle de navigateur par défaut, ouverture des canaux.
 *
 * <p>Elle REMPLACE le parcours Brave au premier lancement. L'ancien parcours reste joignable en
 * développement : {@link #EXTRA_LEGACY_ONBOARDING} (Réglages › Browther — recette).
 */
public final class BrowtherIntroController implements BrowtherIntroModel.Host {
    private static final String TAG = "BrowtherIntro";

    /** Extra d'intent : ouvrir l'ancien parcours Brave au lieu de l'introduction. */
    public static final String EXTRA_LEGACY_ONBOARDING = "browther_legacy_onboarding";

    private static final String[] WHATSAPP_PACKAGES = {"com.whatsapp", "com.whatsapp.w4b"};
    private static final String[] TELEGRAM_PACKAGES = {
        "org.telegram.messenger", "org.telegram.messenger.web", "org.thunderdog.challegram"
    };

    private final Activity mActivity;
    private final Runnable mOnFinished;
    private final FrameLayout mContainer;
    private BrowtherIntroModel mModel;
    private BrowtherIntroView mView;

    /** L'introduction plutôt que l'ancien parcours ? */
    public static boolean shouldShow(Intent intent) {
        return !IntentUtils.safeGetBooleanExtra(intent, EXTRA_LEGACY_ONBOARDING, false);
    }

    /** Intent pour rejouer l'introduction depuis les réglages (ou l'ancien parcours). */
    public static Intent replayIntent(Activity from, Class<?> onboardingActivity, boolean legacy) {
        Intent intent = new Intent(from, onboardingActivity);
        intent.putExtra(EXTRA_LEGACY_ONBOARDING, legacy);
        return intent;
    }

    /**
     * @param onFinished la fin de parcours de l'activité (écrit la fin du premier lancement et
     *     passe la main au navigateur).
     */
    public BrowtherIntroController(Activity activity, Runnable onFinished) {
        mActivity = activity;
        mOnFinished = onFinished;
        mContainer = new FrameLayout(activity);
        mContainer.setBackgroundColor(BrowtherIntroUi.BACKGROUND);
        prepareWindow();
    }

    /** La vue à poser dès l'inflation : noire tant que le natif n'est pas prêt. */
    public View getView() {
        return mContainer;
    }

    /**
     * Le natif est prêt (préférences, analytique) : l'introduction peut commencer.
     *
     * <p>Pas avant : l'analytique passe par JNI, et l'écran « navigateur par défaut » dépend d'un
     * état qu'on mesure maintenant.
     */
    public void start() {
        if (mModel != null) return;
        boolean isDefault = BraveSetDefaultBrowserUtils.isBraveSetAsDefaultBrowser(mActivity);
        mModel = new BrowtherIntroModel(this, isDefault, BrowtherEarlyAccess.ENABLED);
        // Le choix affiché part du réglage du moteur (même défaut : les femmes).
        mView = new BrowtherIntroView(BrowtherIntroView.darkContext(mActivity), mModel);
        mContainer.addView(
                mView,
                new FrameLayout.LayoutParams(
                        FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT));
        mView.requestApplyInsets();
        mModel.start();
    }

    /** Le bouton retour : jamais de sortie de l'introduction. */
    public void handleBackPress() {
        if (mView != null) mView.handleBack();
    }

    /** Réponse de la feuille système du rôle « navigateur ». */
    public boolean onActivityResult(int requestCode, int resultCode) {
        if (requestCode != BraveConstants.DEFAULT_BROWSER_ROLE_REQUEST_CODE || mModel == null) {
            return false;
        }
        mModel.onDefaultBrowserResult(
                resultCode == Activity.RESULT_OK
                        || BraveSetDefaultBrowserUtils.isBraveSetAsDefaultBrowser(mActivity));
        return true;
    }

    public void destroy() {
        if (mView != null) mView.release();
    }

    /**
     * Toujours sombre et bord à bord : le fond de l'accueil passe sous les barres système, dont les
     * icônes restent claires — sinon l'heure disparaît sur un appareil en thème clair.
     */
    @SuppressWarnings("deprecation")
    private void prepareWindow() {
        Window window = mActivity.getWindow();
        window.setStatusBarColor(Color.TRANSPARENT);
        window.setNavigationBarColor(Color.TRANSPARENT);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(false);
            android.view.WindowInsetsController controller = window.getInsetsController();
            if (controller != null) {
                controller.setSystemBarsAppearance(
                        0,
                        android.view.WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS
                                | android.view.WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS);
            }
        } else {
            window.getDecorView()
                    .setSystemUiVisibility(
                            View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                                    | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                                    | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION);
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.setNavigationBarContrastEnforced(false);
        }
        // Les touches de volume règlent le son de l'extrait, pas la sonnerie.
        mActivity.setVolumeControlStream(AudioManager.STREAM_MUSIC);
    }

    // -------------------- BrowtherIntroModel.Host --------------------

    @Override
    public void writeBasarunaaMode(String mode) {
        Profile profile = ProfileManager.getLastUsedRegularProfile();
        UserPrefs.get(profile).setString(BravePref.BASARUNAA_MODE, mode);
    }

    @Override
    public void enableFeature(BrowtherIntroModel.Feature feature) {
        Profile profile = ProfileManager.getLastUsedRegularProfile();
        UserPrefs.get(profile)
                .setBoolean(
                        feature == BrowtherIntroModel.Feature.BASARUNAA
                                ? BravePref.BASARUNAA_ENABLED
                                : BravePref.SAWTUNAA_ENABLED,
                        true);
    }

    @Override
    public boolean requestDefaultBrowser() {
        RoleManager roleManager = mActivity.getSystemService(RoleManager.class);
        if (roleManager != null && roleManager.isRoleAvailable(RoleManager.ROLE_BROWSER)) {
            if (roleManager.isRoleHeld(RoleManager.ROLE_BROWSER)) return false;
            try {
                mActivity.startActivityForResult(
                        roleManager.createRequestRoleIntent(RoleManager.ROLE_BROWSER),
                        BraveConstants.DEFAULT_BROWSER_ROLE_REQUEST_CODE);
                return true;
            } catch (ActivityNotFoundException e) {
                Log.w(TAG, "Feuille du rôle navigateur indisponible", e);
            }
        }
        try {
            mActivity.startActivity(new Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS));
        } catch (ActivityNotFoundException e) {
            Log.w(TAG, "Réglages des applications par défaut indisponibles", e);
        }
        return false;
    }

    /**
     * Ouvre un canal dans son application. ⚠️ Un {@code ACTION_VIEW} https sans paquet revient à
     * Browther, navigateur par défaut ou candidat — et en plein premier lancement, ça relancerait le
     * parcours. On vise donc l'app (WhatsApp, Telegram), puis, à défaut, un onglet personnalisé.
     */
    @Override
    public void openUrl(String url) {
        String[] packages =
                url.contains("whatsapp.com")
                        ? WHATSAPP_PACKAGES
                        : url.contains("t.me") ? TELEGRAM_PACKAGES : new String[0];
        for (String packageName : packages) {
            Intent intent = new Intent(Intent.ACTION_VIEW, Uri.parse(url));
            intent.setPackage(packageName);
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            try {
                mActivity.startActivity(intent);
                return;
            } catch (ActivityNotFoundException e) {
                // Pas installée : on essaie la suivante.
            }
        }
        CustomTabActivity.showInfoPage(mActivity, url);
    }

    @Override
    public void track(String event, Object... keyValues) {
        BrowtherAnalyticsBridge.trackTyped(event, keyValues);
    }

    @Override
    public void finish() {
        mOnFinished.run();
    }
}
