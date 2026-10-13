/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_analytics;

import android.app.role.RoleManager;
import android.content.SharedPreferences;

import org.chromium.base.ContextUtils;
import org.chromium.build.annotations.NullMarked;
import org.chromium.build.annotations.Nullable;
import org.chromium.chrome.browser.browther_referral.core.ReferralDate;
import org.chromium.chrome.browser.preferences.BravePref;
import org.chromium.chrome.browser.preferences.BravePrefServiceBridge;
import org.chromium.chrome.browser.profiles.Profile;
import org.chromium.chrome.browser.profiles.ProfileManager;
import org.chromium.components.prefs.PrefService;
import org.chromium.components.user_prefs.UserPrefs;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

/**
 * {@code app_active} — « actif aujourd'hui » : au plus un par jour calendaire LOCAL et par
 * installation, avec l'ÉTAT des réglages (navigateur par défaut, floutage, musique) et non les
 * gestes. Même event et mêmes propriétés que desktop et iOS (private/docs/ANALYTICS.md).
 *
 * <p>Il porte aussi la valeur délivrée et les pages ouvertes : pour chaque compteur, le total à vie
 * de l'appareil ({@code *_total}) et l'ajout depuis le dernier {@code app_active} envoyé — voir
 * {@link #addCounter}. ⛔ Additionner les ajouts dans PostHog ne doit jamais compter deux fois le
 * même appareil : le dernier total envoyé n'est noté qu'avec le jour, après l'envoi.
 *
 * <p>Appelé à chaque reprise de l'activité principale ({@code BraveActivity.onResumeWithNative}),
 * donc au lancement ET à chaque retour au premier plan : une appli gardée en mémoire plusieurs
 * jours compte chaque jour où elle est réellement rouverte. ⛔ Pas de minuterie : une appli
 * ouverte mais inutilisée ne compte pas.
 *
 * <p>Thread UI, natif chargé (le pont passe par JNI, les réglages par le profil).
 */
@NullMarked
public final class BrowtherDailyActive {
    /** Dernier jour local envoyé ({@code AAAA-MM-JJ}). */
    private static final String KEY_LAST_DAY = "browther.analytics.active-day";

    /**
     * Pages ouvertes depuis que ce compteur existe (il ne remonte pas avant la version qui
     * l'apporte). Un nombre, rien d'autre : ⛔ ni adresse ni domaine.
     */
    private static final String KEY_PAGES_TOTAL = "browther.analytics.pages-total";

    /**
     * Préfixe des totaux partis avec le dernier {@code app_active} — une clé par compteur
     * ({@code …active-sent.blurred}, {@code .music_seconds}, {@code .blocked}, {@code .pages}).
     * Clé absente = jamais envoyé : l'ajout est alors omis, pas calculé depuis zéro.
     */
    private static final String KEY_SENT_PREFIX = "browther.analytics.active-sent.";

    private BrowtherDailyActive() {}

    /**
     * Une vraie page vient de finir de charger — appelé par {@code
     * BrowtherReferralHooks.onPageLoaded}, qui a déjà écarté la navigation privée et tout ce qui
     * n'est pas {@code http(s)} : la même unité que le parrainage. Compté même analytique coupée
     * (c'est un total local, comme ceux du Nouvel Onglet) ; rien ne part d'ici.
     */
    public static void notePageOpened() {
        try {
            SharedPreferences prefs = ContextUtils.getAppSharedPreferences();
            int total = prefs.getInt(KEY_PAGES_TOTAL, 0);
            if (total == Integer.MAX_VALUE) return;
            prefs.edit().putInt(KEY_PAGES_TOTAL, total + 1).apply();
        } catch (RuntimeException e) {
            // ⛔ Un compteur ne casse jamais la navigation.
        }
    }

    /** Reprise de l'activité principale. ⛔ Ne casse jamais la reprise : les erreurs s'avalent. */
    public static void onForeground() {
        try {
            sendIfNewDay();
        } catch (RuntimeException e) {
            // Le jour n'est pas noté : on réessaiera à la prochaine reprise.
        }
    }

    private static void sendIfNewDay() {
        SharedPreferences prefs = ContextUtils.getAppSharedPreferences();
        String today = ReferralDate.localDayKey(Instant.now());
        if (today.equals(prefs.getString(KEY_LAST_DAY, null))) return;

        // Analytique coupée (ou état local pas encore prêt) : l'appel serait un no-op côté natif.
        // On ne note pas le jour — si la personne la rallume aujourd'hui, l'event partira.
        if (!BrowtherAnalyticsBridge.isPostHogEnabled()) return;

        // Sans profil, l'état des réglages est inconnu : plutôt réessayer à la prochaine reprise
        // qu'envoyer le seul event du jour avec des valeurs fausses.
        Profile profile = ProfileManager.getLastUsedRegularProfile();
        if (profile == null) return;
        PrefService userPrefs = UserPrefs.get(profile);

        List<Object> props = new ArrayList<>();
        Boolean isDefault = isDefaultBrowser();
        // ⛔ Jamais `false` par défaut : état inconnu = propriété absente.
        if (isDefault != null) {
            props.add("default_browser");
            props.add(isDefault);
        }
        // Les réglages globaux — pas la bascule « seulement 5 min », qui écrit la même pref :
        // c'est l'état du moment, celui que la personne voit sur l'interrupteur.
        props.add("basarunaa_enabled");
        props.add(userPrefs.getBoolean(BravePref.BASARUNAA_ENABLED));
        props.add("sawtunaa_enabled");
        props.add(userPrefs.getBoolean(BravePref.SAWTUNAA_ENABLED));
        props.add("locale");
        props.add(locale());

        // Les totaux du widget du Nouvel Onglet, lus aux mêmes sources que lui
        // (`BraveNtpAdapter`) — pas de second comptage. Les derniers totaux envoyés s'écrivent
        // dans la même transaction que le jour, après l'envoi.
        SharedPreferences.Editor sent = prefs.edit();
        addCounter(props, prefs, sent, "blurred", BrowtherAnalyticsBridge.getPersonsBlurredTotal());
        addCounter(
                props,
                prefs,
                sent,
                "music_seconds",
                BrowtherAnalyticsBridge.getMusicSecondsTotal());
        BravePrefServiceBridge shields = BravePrefServiceBridge.getInstance();
        addCounter(
                props,
                prefs,
                sent,
                "blocked",
                shields.getTrackersBlockedCount(profile) + shields.getAdsBlockedCount(profile));
        addCounter(props, prefs, sent, "pages", prefs.getInt(KEY_PAGES_TOTAL, 0));

        BrowtherAnalyticsBridge.trackTyped("app_active", props.toArray());
        sent.putString(KEY_LAST_DAY, today).apply();
    }

    /**
     * Ajoute {@code <name>_total} (toujours, 0 compris) et {@code <name>}, l'ajout depuis le dernier
     * {@code app_active} envoyé, puis prépare dans {@code sent} le total à retenir.
     *
     * <ul>
     *   <li>⛔ aucun total retenu (premier event après la mise à jour) : l'ajout est OMIS —
     *       envoyer tout l'historique de l'appareil d'un coup fausserait la journée ;
     *   <li>total plus petit que le retenu (données effacées, compteur remis à zéro) : l'ajout est
     *       le total actuel ;
     *   <li>jamais négatif.
     * </ul>
     *
     * <p>⚠️ Les valeurs partent en {@code Integer} : {@code trackTyped} ne type que {@code Integer}
     * et {@code Boolean}, un {@code Long} arriverait dans PostHog en chaîne. D'où le bornage à
     * {@code Integer.MAX_VALUE} (les totaux musique et floutage sont déjà des Int32 côté natif).
     */
    private static void addCounter(
            List<Object> props,
            SharedPreferences prefs,
            SharedPreferences.Editor sent,
            String name,
            long total) {
        int current = (int) Math.max(0, Math.min(total, Integer.MAX_VALUE));
        props.add(name + "_total");
        props.add(current);

        String key = KEY_SENT_PREFIX + name;
        if (prefs.contains(key)) {
            int last = prefs.getInt(key, 0);
            props.add(name);
            props.add(current < last ? current : current - last);
        }
        sent.putInt(key, current);
    }

    /**
     * Browther est-il le navigateur par défaut ? — le rôle {@code ROLE_BROWSER} du système, la même
     * preuve que le parrainage ({@code BrowtherReferralController.isDefaultBrowser}). {@code null}
     * quand le système ne sait pas répondre (pas de gestionnaire de rôles, rôle indisponible).
     */
    private static @Nullable Boolean isDefaultBrowser() {
        try {
            RoleManager roles =
                    ContextUtils.getApplicationContext().getSystemService(RoleManager.class);
            if (roles == null || !roles.isRoleAvailable(RoleManager.ROLE_BROWSER)) return null;
            return roles.isRoleHeld(RoleManager.ROLE_BROWSER);
        } catch (RuntimeException e) {
            return null;
        }
    }

    /** Langue de l'interface au format d'iOS ({@code fr_FR} ; {@code fr} sans région). */
    private static String locale() {
        Locale locale = Locale.getDefault();
        String language = locale.getLanguage();
        String country = locale.getCountry();
        return country.isEmpty() ? language : language + "_" + country;
    }
}
