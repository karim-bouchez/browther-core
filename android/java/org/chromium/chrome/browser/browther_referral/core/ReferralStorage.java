// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

package org.chromium.chrome.browser.browther_referral.core;

import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Ce que le parrainage garde sur l'appareil — ⚠️ sous des clés `browther.referral.*`, ⛔ jamais
 * celles de Brave (son programme de codes promo d'installation, toujours dans le fork).
 *
 * <p>Tout est en JSON dans un magasin clé-valeur ({@link Backend} — `SharedPreferences` sur
 * Android, une table en mémoire dans les tests) : illisible = « rien n'a encore été vu », ⛔ jamais
 * une erreur qui éteindrait le parrainage.
 */
public final class ReferralStorage {
    /** Le magasin clé-valeur. {@code put(key, null)} efface la clé. */
    public interface Backend {
        String get(String key);

        void put(String key, String value);
    }

    /** Un magasin en mémoire (tests, aperçus de recette qui ne doivent rien écrire). */
    public static final class MemoryBackend implements Backend {
        private final Map<String, String> values = new HashMap<>();

        @Override
        public synchronized String get(String key) {
            return values.get(key);
        }

        @Override
        public synchronized void put(String key, String value) {
            if (value == null) {
                values.remove(key);
            } else {
                values.put(key, value);
            }
        }
    }

    private final Backend backend;

    public ReferralStorage(Backend backend) {
        this.backend = backend;
    }

    static final class Key {
        static final String prompt = "browther.referral.prompt";
        static final String cachedStatus = "browther.referral.cached-status";
        static final String gaugeUnderstood = "browther.referral.gauge-understood";
        static final String defaultDays = "browther.referral.default-days";
        static final String snapshotDay = "browther.referral.snapshot-day";
        static final String recetteSubject = "browther.referral.recette-subject";
        static final String recetteToken = "browther.referral.recette-token";
        static final String transferredFor = "browther.referral.transferred-for";
    }

    private ReferralJson.Obj read(String key) {
        String text = backend.get(key);
        if (text == null) return null;
        try {
            return ReferralJson.parseObject(text);
        } catch (ReferralJson.JsonException e) {
            return null;
        }
    }

    // MARK: - L'état des sollicitations

    public ReferralPromptState prompt() {
        ReferralJson.Obj o = read(Key.prompt);
        if (o == null) return new ReferralPromptState();
        try {
            return ReferralPromptState.fromJson(o);
        } catch (ReferralJson.JsonException e) {
            return new ReferralPromptState();
        }
    }

    public void setPrompt(ReferralPromptState state) {
        backend.put(Key.prompt, ReferralJson.stringify(state.toJson()));
    }

    // MARK: - Le dernier statut connu (sens de la panne : § 7)

    /**
     * ⚠️ **Le statut se lit avec SON sujet** (§ 12.13) : sinon, le temps que le nouveau arrive,
     * l'écran montrerait le code et la couverture d'un autre.
     */
    public ReferralStatus cachedStatus(String subject) {
        ReferralJson.Obj o = read(Key.cachedStatus);
        if (o == null) return null;
        try {
            if (!subject.equals(o.string("subject"))) return null;
            return ReferralStatus.fromJson(o.obj("status"));
        } catch (ReferralJson.JsonException e) {
            return null;
        }
    }

    public void saveStatus(ReferralStatus status, String subject) {
        Map<String, Object> cached = new LinkedHashMap<>();
        cached.put("subject", subject);
        cached.put("status", status.toJson());
        backend.put(Key.cachedStatus, ReferralJson.stringify(cached));
    }

    // MARK: - La jauge comprise (§ 12.4)

    /**
     * La personne a tiré le curseur ELLE-MÊME jusqu'à « à vie » : plus aucune jauge ne rejoue la
     * démo, nulle part.
     */
    public boolean gaugeUnderstood() {
        return "true".equals(backend.get(Key.gaugeUnderstood));
    }

    public void setGaugeUnderstood(boolean value) {
        backend.put(Key.gaugeUnderstood, value ? "true" : "false");
    }

    // MARK: - La validation du filleul

    public DefaultBrowserDays defaultBrowserDays() {
        ReferralJson.Obj o = read(Key.defaultDays);
        if (o == null) return new DefaultBrowserDays();
        try {
            return DefaultBrowserDays.fromJson(o);
        } catch (ReferralJson.JsonException e) {
            return new DefaultBrowserDays();
        }
    }

    public void setDefaultBrowserDays(DefaultBrowserDays days) {
        backend.put(Key.defaultDays, ReferralJson.stringify(days.toJson()));
    }

    // MARK: - La photo du jour (analytique)

    public String snapshotDay() {
        return backend.get(Key.snapshotDay);
    }

    public void setSnapshotDay(String value) {
        backend.put(Key.snapshotDay, value);
    }

    // MARK: - Le compte (§ 7.1)

    /**
     * Le compte dans lequel CET appareil a déjà été fusionné (`/v1/transfer`) — une fois par
     * compte. ⚠️ Un identifiant, ⛔ jamais le jeton.
     */
    public String transferredFor() {
        return backend.get(Key.transferredFor);
    }

    public void setTransferredFor(String value) {
        backend.put(Key.transferredFor, value);
    }

    // MARK: - 🧪 Recette (§ 12.18)

    /**
     * Une identité de recette posée PAR-DESSUS la vraie (« repartir d'un appareil neuf ») — ⛔ jamais
     * dans un build du store.
     */
    public String recetteSubject() {
        return backend.get(Key.recetteSubject);
    }

    public void setRecetteSubject(String value) {
        backend.put(Key.recetteSubject, value);
    }

    /**
     * 🔴 Le jeton d'administration se SAISIT dans l'outil et reste sur l'appareil : ⛔ jamais une
     * constante de build — il ouvrirait l'accès à vie à qui lit le binaire.
     */
    public String recetteToken() {
        return backend.get(Key.recetteToken);
    }

    public void setRecetteToken(String value) {
        backend.put(Key.recetteToken, value);
    }
}
