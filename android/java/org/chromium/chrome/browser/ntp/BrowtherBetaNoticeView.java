/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.ntp;

import android.content.Context;
import android.content.pm.PackageManager;
import android.util.AttributeSet;
import android.widget.LinearLayout;
import android.widget.TextView;

import androidx.annotation.Nullable;
import androidx.appcompat.widget.AppCompatImageView;

import org.chromium.base.ContextUtils;
import org.chromium.chrome.R;
import org.chromium.chrome.browser.preferences.ChromeSharedPreferences;
import org.chromium.chrome.browser.util.TabUtils;

/**
 * Bandeau « accès anticipé » en tête du NTP — parité desktop
 * {@code browther_beta_notice.tsx} et iOS {@code
 * BrowtherBetaNoticeSectionProvider}.
 *
 * <p>Pourquoi dans l'app et pas sur le site : la plupart des installs viennent
 * de la recherche du store et ne voient jamais browther.devndin.com — et même
 * celui qui vient du site télécharge puis n'y revient pas. Un utilisateur qui
 * rencontre un bug sans savoir qu'il est sur une version en cours de finition
 * conclut que le produit est mauvais : il désinstalle, ou pire, garde l'app
 * sans jamais la rouvrir. Le contexte transforme la déception en patience, et
 * les deux canaux transforment le silence en audience pour la sortie finale.
 *
 * <p>Les deux liens sont des canaux de <b>diffusion</b> auxquels on s'abonne,
 * pas un support : on n'y écrit pas.
 *
 * <p>À retirer quand Browther sort de l'accès anticipé (cette vue, son layout,
 * son fond, les 6 strings et la clé de préférence).
 */
public class BrowtherBetaNoticeView extends LinearLayout {
    /**
     * Version pour laquelle le bandeau a été fermé. Une string et non un
     * booléen : chaque mise à jour redonne le bandeau une fois, ce qui évite le
     * bandeau permanent qu'on finit par ne plus voir. Parité desktop
     * ({@code localStorage}) et iOS ({@code Preferences.General}).
     */
    private static final String PREF_DISMISSED_VERSION = "browther_beta_notice_dismissed_version";

    /**
     * Mêmes URL que l'étape d'onboarding « suivre les canaux dev&din » et que
     * les deux autres plateformes. Doivent rester en phase.
     */
    private static final String WHATSAPP_URL =
            "https://whatsapp.com/channel/0029Vb8ydkv5vKABH78PVX32";

    private static final String TELEGRAM_URL = "https://t.me/devndin_nouveautes";

    private @Nullable Runnable mOnDismissed;

    public BrowtherBetaNoticeView(Context context, @Nullable AttributeSet attrs) {
        super(context, attrs);
    }

    /**
     * Version applicative courante, clé du « déjà vu ». Chaîne vide si le
     * package manager ne répond pas — on montre alors le bandeau, se taire par
     * défaut serait le pire des deux comportements.
     */
    private static String currentVersion() {
        Context context = ContextUtils.getApplicationContext();
        try {
            return context.getPackageManager().getPackageInfo(context.getPackageName(), 0)
                    .versionName;
        } catch (PackageManager.NameNotFoundException e) {
            return "";
        }
    }

    /** Le bandeau doit-il être affiché pour la version en cours ? */
    public static boolean shouldShow() {
        String version = currentVersion();
        if (version == null || version.isEmpty()) {
            return true;
        }
        return !version.equals(
                ChromeSharedPreferences.getInstance().readString(PREF_DISMISSED_VERSION, ""));
    }

    /** @param onDismissed appelé après la fermeture, pour retirer l'item du NTP. */
    public void setOnDismissed(@Nullable Runnable onDismissed) {
        mOnDismissed = onDismissed;
    }

    @Override
    protected void onFinishInflate() {
        super.onFinishInflate();

        ((TextView) findViewById(R.id.browther_beta_title))
                .setText(R.string.browther_beta_notice_title);
        ((TextView) findViewById(R.id.browther_beta_body))
                .setText(R.string.browther_beta_notice_text);
        ((TextView) findViewById(R.id.browther_beta_follow))
                .setText(R.string.browther_beta_notice_follow);

        TextView whatsApp = findViewById(R.id.browther_beta_whatsapp);
        whatsApp.setText(R.string.browther_beta_notice_whatsapp);
        whatsApp.setOnClickListener(v -> TabUtils.openUrlInNewTab(false, WHATSAPP_URL));

        TextView telegram = findViewById(R.id.browther_beta_telegram);
        telegram.setText(R.string.browther_beta_notice_telegram);
        telegram.setOnClickListener(v -> TabUtils.openUrlInNewTab(false, TELEGRAM_URL));

        AppCompatImageView close = findViewById(R.id.browther_beta_close);
        close.setContentDescription(getContext().getString(R.string.browther_beta_notice_dismiss));
        close.setOnClickListener(
                v -> {
                    ChromeSharedPreferences.getInstance()
                            .writeString(PREF_DISMISSED_VERSION, currentVersion());
                    if (mOnDismissed != null) {
                        mOnDismissed.run();
                    }
                });
    }
}
