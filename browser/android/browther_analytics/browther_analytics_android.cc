/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

#include <jni.h>

#include <string>
#include <vector>

#include "base/android/jni_array.h"
#include "base/android/jni_string.h"
#include "base/functional/bind.h"
#include "base/task/single_thread_task_runner.h"
#include "base/values.h"
#include "brave/build/android/jni_headers/BrowtherAnalyticsBridge_jni.h"
#include "brave/components/browther_analytics/browther_analytics_service.h"
#include "brave/components/browther_analytics/pref_names.h"
#include "brave/components/p3a/pref_names.h"
#include "chrome/browser/browser_process.h"
#include "components/metrics/metrics_pref_names.h"
#include "components/prefs/pref_service.h"
#include "content/public/browser/browser_thread.h"

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

// Lit un compteur cumulatif kStats*Total (Integer = Int32) depuis local_state.
// Retourne 0 si pas init. Utilisé par la NTP pour afficher musique/floutées.
int ReadLocalStateInteger(const char* pref_name) {
  if (!g_browser_process) {
    return 0;
  }
  PrefService* local_state = g_browser_process->local_state();
  if (!local_state) {
    return 0;
  }
  return local_state->GetInteger(pref_name);
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

void JNI_BrowtherAnalyticsBridge_IncrementMusicSeconds(JNIEnv* env,
                                                       jint jdelta) {
  // `SawtunaaPlayer.java` appelle ce bridge depuis son `Sawtunaa-NSNet2`
  // preprocess thread. `BrowtherAnalyticsService::IncrementMusicSeconds`
  // touche `PrefService` (kStatsMusicSecondsPending) qui a un
  // SequenceChecker bound au UI thread → DCHECK fatal sinon. On post sur
  // l'UI thread pour respecter le contrat (parité avec les autres callers
  // C++ qui hookent déjà UI-thread-side).
  const int delta = static_cast<int>(jdelta);
  content::GetUIThreadTaskRunner({})->PostTask(
      FROM_HERE, base::BindOnce([](int d) {
        auto* service = BrowtherAnalyticsService::GetInstance();
        if (!service) {
          return;
        }
        service->IncrementMusicSeconds(d);
      }, delta));
}

void JNI_BrowtherAnalyticsBridge_IncrementPersonsBlurred(JNIEnv* env,
                                                         jint jdelta) {
  // Même contrat que IncrementMusicSeconds : caller peut être hors UI thread
  // (pipeline Basarunaa Android), service touche PrefService UI-bound.
  const int delta = static_cast<int>(jdelta);
  content::GetUIThreadTaskRunner({})->PostTask(
      FROM_HERE, base::BindOnce([](int d) {
        auto* service = BrowtherAnalyticsService::GetInstance();
        if (!service) {
          return;
        }
        service->IncrementPersonsBlurred(d);
      }, delta));
}

jlong JNI_BrowtherAnalyticsBridge_GetMusicSecondsTotal(JNIEnv* env) {
  // Synchrone (read-only). Appelé depuis le UI thread (BraveNtpAdapter).
  // long Java cast OK : Integer Int32 ≤ jlong Int64.
  return static_cast<jlong>(ReadLocalStateInteger(prefs::kStatsMusicSecondsTotal));
}

jlong JNI_BrowtherAnalyticsBridge_GetPersonsBlurredTotal(JNIEnv* env) {
  return static_cast<jlong>(
      ReadLocalStateInteger(prefs::kStatsPersonsBlurredTotal));
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
