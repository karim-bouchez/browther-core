/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

package org.chromium.chrome.browser.browther_referral;

import android.content.Context;
import android.text.format.DateFormat;

import java.text.SimpleDateFormat;
import java.time.Instant;
import java.util.Date;
import java.util.Locale;

/** Les dates et les prix tels que la personne les lit — pendant de {@code formatDate} iOS. */
public final class ReferralFormat {
    private ReferralFormat() {}

    /** La langue de l'app (celle des chaînes), ⛔ pas forcément celle du système. */
    public static Locale locale(Context context) {
        return context.getResources().getConfiguration().getLocales().get(0);
    }

    /** Une date de fin, dans la langue de l'app (« 3 novembre », ou « 3 novembre 2026 »). */
    public static String date(Context context, Instant instant, boolean withYear) {
        if (instant == null) return "";
        Locale locale = locale(context);
        String pattern = DateFormat.getBestDateTimePattern(locale, withYear ? "dMMMMy" : "dMMMM");
        return new SimpleDateFormat(pattern, locale).format(new Date(instant.toEpochMilli()));
    }
}
