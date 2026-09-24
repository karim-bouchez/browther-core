// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

package org.chromium.chrome.browser.browther_referral.core;

import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.format.DateTimeParseException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * La validation du filleul Browther — `docs/PARRAINAGE.md` § 9 (2026-09-22) : **3 journées
 * distinctes où Browther, navigateur PAR DÉFAUT, a chargé une vraie page**.
 *
 * <h3>Pourquoi deux registres</h3>
 *
 * Un jour compte quand deux faits tombent LE MÊME JOUR LOCAL :
 *
 * <ul>
 *   <li>**une preuve du défaut** — ⚠️ une PREUVE, ⛔ jamais un « probablement ». Android : le
 *       système dit que Browther tient le rôle de navigateur (`RoleManager.ROLE_BROWSER`), ou un
 *       lien `http(s)` est arrivé d'une autre app (le système ne l'envoie qu'au navigateur par
 *       défaut, sauf choix explicite dans le sélecteur) ;
 *   <li>**une vraie page chargée** (l'unité d'usage de Browther, § 9) — ouvrir le navigateur et le
 *       refermer ne prouve rien.
 * </ul>
 *
 * <p>⚠️ **Seuls les jours qui SUIVENT la saisie du code comptent** (§ 12.8 : la validation ne compte
 * qu'après la saisie). Un par jour local, jamais deux fois (`eventKey` = `default:&lt;jour&gt;`, le
 * service déduplique aussi).
 */
public final class DefaultBrowserDays {
    /** Jours locaux où le défaut a été PROUVÉ. */
    public final List<String> proofDays = new ArrayList<>();
    /** Jours locaux où une vraie page a fini de charger. */
    public final List<String> browsingDays = new ArrayList<>();
    /** Jours déjà déclarés au service. */
    public final List<String> reportedDays = new ArrayList<>();

    /**
     * On ne garde que ce qui peut encore servir : un filleul valide en quelques jours, et un
     * registre qui grandirait sans fin n'apprendrait rien de plus.
     */
    static final int keptDays = 60;

    public DefaultBrowserDays() {}

    public void recordProof(Instant on, ZoneId zone) {
        insert(ReferralDate.localDayKey(on, zone), proofDays);
    }

    public void recordProof(Instant on) {
        recordProof(on, ZoneId.systemDefault());
    }

    public void recordBrowsing(Instant on, ZoneId zone) {
        insert(ReferralDate.localDayKey(on, zone), browsingDays);
    }

    public void recordBrowsing(Instant on) {
        recordBrowsing(on, ZoneId.systemDefault());
    }

    public void markReported(String day) {
        insert(day, reportedDays);
    }

    public boolean hasProof(Instant date, ZoneId zone) {
        return proofDays.contains(ReferralDate.localDayKey(date, zone));
    }

    public boolean hasProof(Instant date) {
        return hasProof(date, ZoneId.systemDefault());
    }

    /**
     * Les jours à déclarer, du plus ancien au plus récent : prouvés ET navigués, depuis la saisie du
     * code, pas encore déclarés.
     */
    public List<String> daysToReport(Instant redeemedAt, int limit, ZoneId zone) {
        String from = redeemedAt == null ? null : ReferralDate.localDayKey(redeemedAt, zone);
        Set<String> browsing = new HashSet<>(browsingDays);
        Set<String> reported = new HashSet<>(reportedDays);
        List<String> result = new ArrayList<>();
        for (String day : proofDays) {
            if (!browsing.contains(day) || reported.contains(day)) continue;
            if (from != null && day.compareTo(from) < 0) continue;
            result.add(day);
        }
        Collections.sort(result);
        return result.size() > limit ? new ArrayList<>(result.subList(0, limit)) : result;
    }

    public List<String> daysToReport(Instant redeemedAt) {
        return daysToReport(redeemedAt, 10, ZoneId.systemDefault());
    }

    /**
     * L'instant à déclarer pour un jour : midi LOCAL — ⚠️ le service compte des journées UTC, et
     * midi reste dans la même date UTC pour tous les fuseaux de ±11 h.
     */
    public static Instant occurredAt(String day, ZoneId zone) {
        try {
            return LocalDate.parse(day).atTime(12, 0).atZone(zone).toInstant();
        } catch (DateTimeParseException e) {
            return null;
        }
    }

    public static Instant occurredAt(String day) {
        return occurredAt(day, ZoneId.systemDefault());
    }

    private static void insert(String day, List<String> list) {
        if (list.contains(day)) return;
        list.add(day);
        Collections.sort(list);
        if (list.size() > keptDays) list.subList(0, list.size() - keptDays).clear();
    }

    // MARK: - JSON

    public Map<String, Object> toJson() {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("proofDays", new ArrayList<Object>(proofDays));
        m.put("browsingDays", new ArrayList<Object>(browsingDays));
        m.put("reportedDays", new ArrayList<Object>(reportedDays));
        return m;
    }

    public static DefaultBrowserDays fromJson(ReferralJson.Obj o) throws ReferralJson.JsonException {
        DefaultBrowserDays days = new DefaultBrowserDays();
        read(o, "proofDays", days.proofDays);
        read(o, "browsingDays", days.browsingDays);
        read(o, "reportedDays", days.reportedDays);
        return days;
    }

    private static void read(ReferralJson.Obj o, String key, List<String> into)
            throws ReferralJson.JsonException {
        for (Object item : o.array(key)) {
            if (!(item instanceof String)) throw new ReferralJson.JsonException("jour attendu : " + key);
            into.add((String) item);
        }
    }
}
