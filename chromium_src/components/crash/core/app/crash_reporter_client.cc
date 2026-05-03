/* Copyright (c) 2020 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/. */

// Browther: redirect Crashpad minidump uploads to Sentry (region EU).
// L'URL est embarquée à la compilation depuis private/configs/analytics.env via
// private/scripts/gen-analytics-config.sh.
//
// L'upload reste gaté par la pref kMetricsReportingEnabled (cohérent avec le
// toggle "Send diagnostic reports" de l'onboarding desktop) — Chromium ne push
// rien si le user a opt-out.
//
// Si SENTRY_MINIDUMP_URL est vide (config absente), on retourne une string
// vide → Crashpad ne tentera aucun upload (silencieusement désactivé).

#include "brave/components/browther_analytics/analytics_config.h"

#define BRAVE_CRASH_REPORTER_CLIENT_GET_UPLOAD_URL \
  return std::string(browther_analytics::kSentryMinidumpUrl);

#include <components/crash/core/app/crash_reporter_client.cc>
#undef BRAVE_CRASH_REPORTER_CLIENT_GET_UPLOAD_URL
