// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

package org.chromium.chrome.browser.browther_referral.core;

import java.time.Instant;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;
import java.util.Locale;

/**
 * Les dates du service sont en ISO 8601 avec millisecondes (`2026-11-08T10:00:00.000Z`) — on les
 * accepte aussi sans, et avec un décalage explicite (`+01:00`).
 */
public final class ReferralDate {
    private ReferralDate() {}

    private static final DateTimeFormatter WRITE =
            DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.ROOT)
                    .withZone(ZoneOffset.UTC);

    public static Instant parse(String value) {
        if (value == null || value.isEmpty()) return null;
        try {
            return OffsetDateTime.parse(value, DateTimeFormatter.ISO_OFFSET_DATE_TIME).toInstant();
        } catch (DateTimeParseException e) {
            return null;
        }
    }

    public static String string(Instant date) {
        return WRITE.format(date);
    }

    /**
     * Le jour LOCAL (`YYYY-MM-DD`) — ⚠️ pas l'UTC : « une fois par jour » se vit dans le fuseau de
     * la personne.
     */
    public static String localDayKey(Instant date, ZoneId zone) {
        LocalDate day = date.atZone(zone).toLocalDate();
        return String.format(
                Locale.ROOT,
                "%04d-%02d-%02d",
                day.getYear(),
                day.getMonthValue(),
                day.getDayOfMonth());
    }

    public static String localDayKey(Instant date) {
        return localDayKey(date, ZoneId.systemDefault());
    }
}
