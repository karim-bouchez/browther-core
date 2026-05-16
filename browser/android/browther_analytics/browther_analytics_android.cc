/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

#include <jni.h>

#include <string>
#include <vector>

#include "base/android/jni_array.h"
#include "base/android/jni_string.h"
#include "base/values.h"
#include "brave/build/android/jni_headers/BrowtherAnalyticsBridge_jni.h"
#include "brave/components/browther_analytics/browther_analytics_service.h"
#include "brave/components/p3a/pref_names.h"
#include "chrome/browser/browser_process.h"
#include "components/metrics/metrics_pref_names.h"
#include "components/prefs/pref_service.h"

namespace browther_analytics::android {

namespace {

// Lit une pref locale gardée par g_browser_process. Retourne false si le
// process global n'est pas encore prêt (très tôt au démarrage).
bool ReadLocalStateBool(const char* pref_name) {
  if (!g_browser_process) {
    return false;
  }
  PrefService* local_state = g_browser_process->local_state();
  if (!local_state) {
    return false;
  }
  return local_state->GetBoolean(pref_name);
}

}  // namespace

void JNI_BrowtherAnalyticsBridge_Track(
    JNIEnv* env,
    const base::android::JavaRef<jstring>& jevent_name) {
  auto* service = BrowtherAnalyticsService::GetInstance();
  if (!service) {
    return;
  }
  service->Track(base::android::ConvertJavaStringToUTF8(env, jevent_name));
}

void JNI_BrowtherAnalyticsBridge_TrackWithProps(
    JNIEnv* env,
    const base::android::JavaRef<jstring>& jevent_name,
    const base::android::JavaRef<jobjectArray>& jkeys,
    const base::android::JavaRef<jobjectArray>& jvalues) {
  auto* service = BrowtherAnalyticsService::GetInstance();
  if (!service) {
    return;
  }
  std::vector<std::string> keys;
  std::vector<std::string> values;
  base::android::AppendJavaStringArrayToStringVector(env, jkeys, &keys);
  base::android::AppendJavaStringArrayToStringVector(env, jvalues, &values);
  base::DictValue props;
  for (size_t i = 0; i < keys.size() && i < values.size(); ++i) {
    props.Set(keys[i], values[i]);
  }
  service->Track(base::android::ConvertJavaStringToUTF8(env, jevent_name),
                 std::move(props));
}

jboolean JNI_BrowtherAnalyticsBridge_IsPostHogEnabled(JNIEnv* env) {
  return ReadLocalStateBool(p3a::kP3AEnabled);
}

jboolean JNI_BrowtherAnalyticsBridge_IsMetricsReportingEnabled(
    JNIEnv* env) {
  return ReadLocalStateBool(metrics::prefs::kMetricsReportingEnabled);
}

}  // namespace browther_analytics::android

DEFINE_JNI(BrowtherAnalyticsBridge)
