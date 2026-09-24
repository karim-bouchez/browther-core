// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

package org.chromium.chrome.browser.browther_referral.core;

import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Ce qui est persisté entre deux lancements (JSON).
 *
 * <p>⚠️ **Une annonce se voit une fois par INSTALLATION, pas par sujet** (§ 12.11) : cet état vit
 * sur l'appareil.
 *
 * <p>Tous les champs sont optionnels ({@code null} = jamais écrit), comme en Swift. {@link #copy()}
 * rend une copie indépendante : les fonctions de {@link ReferralPrompt} ne modifient jamais l'état
 * reçu.
 */
public final class ReferralPromptState {
    /** Jour LOCAL (`YYYY-MM-DD`) du dernier jour de navigation compté. */
    public String lastDay;
    /** Jours de navigation DISTINCTS (une vraie page chargée) — l'unité d'usage de Browther (§ 9). */
    public Integer days;
    /** L'écran O a été vu (dans l'introduction) — ⛔ il ne revient jamais. */
    public Boolean welcomed;
    /** L'annonce a été montrée — ⛔ elle ne revient jamais (§ 3, « une seule fois »). */
    public Boolean announced;
    /**
     * La fin de couverture pour laquelle un rappel a déjà été montré (ISO). ⚠️ On mémorise
     * l'ÉCHÉANCE, pas une date d'affichage : c'est ce qui fait « une fois par palier et par fin »
     * alors que les échéances se succèdent.
     */
    public String reminderShownFor;
    /** Le palier déjà montré pour cette échéance (10 puis 3). */
    public Integer reminderStageShown;
    /** Dernier affichage de l'écran J0 (ISO). */
    public String pausedShownAt;
    /** Affichages de J0 depuis que la couverture est tombée — pilote la cadence. */
    public Integer pausedShownCount;
    /** L'échéance à laquelle la couverture s'est éteinte — remet la cadence à zéro. */
    public String pausedSince;
    /**
     * 🔴 **Le circuit des trois façons est OUVERT** (§ 12.16), et l'écran par lequel on y est
     * entré. Il ne se referme que par une de ses trois sorties — inviter, payer, une du'a —, ⛔ pas
     * par un redémarrage de l'app. ⚠️ **Seulement s'il part de J0** : une fenêtre qu'on pouvait
     * fermer n'en ouvre pas une qu'on ne peut plus fermer.
     */
    public Circuit circuit;
    /** Le jour local dont le moment de mérite a déjà servi — un par jour. */
    public String meritUsedDay;
    /**
     * Le nombre d'invitations validées déjà ANNONCÉ (écran 8). ⚠️ Persisté : le parrain apprend la
     * validation « à sa prochaine ouverture » (§ 7.3).
     */
    public Integer seenValidated;
    /** Ce que le FILLEUL a déjà vu de sa propre validation (écran 8 bis, § 5.3). */
    public SeenReferee seenRefereeStatus;

    public enum Circuit {
        PAUSED("paused"),
        SUPPORT("support");

        public final String rawValue;

        Circuit(String rawValue) {
            this.rawValue = rawValue;
        }

        public static Circuit fromRaw(String raw) {
            for (Circuit value : values()) {
                if (value.rawValue.equals(raw)) return value;
            }
            return null;
        }
    }

    public enum SeenReferee {
        NONE("none"),
        INSTALLED("installed"),
        VALIDATED("validated");

        public final String rawValue;

        SeenReferee(String rawValue) {
            this.rawValue = rawValue;
        }

        public static SeenReferee fromRaw(String raw) {
            for (SeenReferee value : values()) {
                if (value.rawValue.equals(raw)) return value;
            }
            return null;
        }
    }

    public ReferralPromptState() {}

    public ReferralPromptState copy() {
        ReferralPromptState c = new ReferralPromptState();
        c.lastDay = lastDay;
        c.days = days;
        c.welcomed = welcomed;
        c.announced = announced;
        c.reminderShownFor = reminderShownFor;
        c.reminderStageShown = reminderStageShown;
        c.pausedShownAt = pausedShownAt;
        c.pausedShownCount = pausedShownCount;
        c.pausedSince = pausedSince;
        c.circuit = circuit;
        c.meritUsedDay = meritUsedDay;
        c.seenValidated = seenValidated;
        c.seenRefereeStatus = seenRefereeStatus;
        return c;
    }

    // MARK: - JSON

    /** ⚠️ Comme l'encodeur Swift : une valeur absente n'est pas écrite. */
    public Map<String, Object> toJson() {
        Map<String, Object> m = new LinkedHashMap<>();
        put(m, "lastDay", lastDay);
        put(m, "days", days);
        put(m, "welcomed", welcomed);
        put(m, "announced", announced);
        put(m, "reminderShownFor", reminderShownFor);
        put(m, "reminderStageShown", reminderStageShown);
        put(m, "pausedShownAt", pausedShownAt);
        put(m, "pausedShownCount", pausedShownCount);
        put(m, "pausedSince", pausedSince);
        put(m, "circuit", circuit == null ? null : circuit.rawValue);
        put(m, "meritUsedDay", meritUsedDay);
        put(m, "seenValidated", seenValidated);
        put(m, "seenRefereeStatus", seenRefereeStatus == null ? null : seenRefereeStatus.rawValue);
        return m;
    }

    private static void put(Map<String, Object> m, String key, Object value) {
        if (value != null) m.put(key, value);
    }

    public static ReferralPromptState fromJson(ReferralJson.Obj o) throws ReferralJson.JsonException {
        ReferralPromptState s = new ReferralPromptState();
        s.lastDay = o.optString("lastDay");
        s.days = o.optInteger("days");
        s.welcomed = o.optBool("welcomed");
        s.announced = o.optBool("announced");
        s.reminderShownFor = o.optString("reminderShownFor");
        s.reminderStageShown = o.optInteger("reminderStageShown");
        s.pausedShownAt = o.optString("pausedShownAt");
        s.pausedShownCount = o.optInteger("pausedShownCount");
        s.pausedSince = o.optString("pausedSince");
        String circuit = o.optString("circuit");
        s.circuit = circuit == null ? null : Circuit.fromRaw(circuit);
        s.meritUsedDay = o.optString("meritUsedDay");
        s.seenValidated = o.optInteger("seenValidated");
        String seen = o.optString("seenRefereeStatus");
        s.seenRefereeStatus = seen == null ? null : SeenReferee.fromRaw(seen);
        return s;
    }

    @Override
    public boolean equals(Object other) {
        return other instanceof ReferralPromptState
                && toJson().equals(((ReferralPromptState) other).toJson());
    }

    @Override
    public int hashCode() {
        return toJson().hashCode();
    }
}
