/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

#include <jni.h>

#include <memory>
#include <string>
#include <vector>

#include "base/android/jni_android.h"
#include "base/android/jni_array.h"
#include "base/android/jni_string.h"
#include "base/android/scoped_java_ref.h"
#include "base/functional/bind.h"
#include "base/logging.h"
#include "base/memory/scoped_refptr.h"
#include "base/no_destructor.h"
#include "brave/build/android/jni_headers/BrowtherAdsBridge_jni.h"
#include "brave/components/browther_ads/ads_client.h"
#include "chrome/browser/browser_process.h"
#include "services/network/public/cpp/shared_url_loader_factory.h"
#include "url/gurl.h"

namespace browther_ads::android {

namespace {

// Client unique pour tout le process navigateur. Côté desktop chaque NTP a son
// propre AdsClient, mais ici toutes les pubs sont indexées par `id` (globalement
// unique) : partager un seul client entre les onglets est sûr (cache id→ad,
// impressions idempotentes par id, click résolu par id) et évite un pointeur
// natif par-instance côté Java. Créé paresseusement au 1er serve avec
// l'URLLoaderFactory système (parité BrowtherAnalyticsService::Initialize ;
// credentials_mode kOmit ⇒ pas besoin de la factory d'un profil). Tous les
// appels viennent du UI thread (BraveNtpAdapter) — SimpleURLLoader + OneShotTimer
// y sont valides.
AdsClient* GetAdsClient() {
  static base::NoDestructor<std::unique_ptr<AdsClient>> client;
  if (!*client) {
    // Config compile-time : si vide, IsConfigured() restera false → la
    // bannière ne s'affiche jamais, inutile d'instancier quoi que ce soit.
    if (!AdsClient::IsConfigured() || !g_browser_process) {
      return nullptr;
    }
    scoped_refptr<network::SharedURLLoaderFactory> url_loader_factory =
        g_browser_process->shared_url_loader_factory();
    if (!url_loader_factory) {
      return nullptr;
    }
    *client = std::make_unique<AdsClient>(std::move(url_loader_factory));
  }
  return client->get();
}

// Renvoie les pubs servies au Java : seuls id + image_url traversent le JNI
// (parité mojom BrowtherAd desktop ; click_url + impression_token restent ici).
void OnAdsServed(const base::android::ScopedJavaGlobalRef<jobject>& callback,
                 std::vector<ServedAd> ads) {
  JNIEnv* env = base::android::AttachCurrentThread();
  std::vector<std::string> ids;
  std::vector<std::string> image_urls;
  ids.reserve(ads.size());
  image_urls.reserve(ads.size());
  for (const ServedAd& ad : ads) {
    ids.push_back(ad.id);
    image_urls.push_back(ad.image_url);
  }
  // [BrowtherAds][debug] trace bout-en-bout (logcat tag "chromium").
  LOG(INFO) << "[BrowtherAds] OnAdsServed: " << ads.size() << " ad(s)";
  Java_BrowtherAdsBridge_onAdsServed(
      env, callback, base::android::ToJavaArrayOfStrings(env, ids),
      base::android::ToJavaArrayOfStrings(env, image_urls));
}

}  // namespace

jboolean JNI_BrowtherAdsBridge_IsConfigured(JNIEnv* env) {
  return AdsClient::IsConfigured();
}

void JNI_BrowtherAdsBridge_Serve(
    JNIEnv* env,
    const base::android::JavaRef<jobject>& jcallback) {
  base::android::ScopedJavaGlobalRef<jobject> callback(jcallback);
  AdsClient* client = GetAdsClient();
  LOG(INFO) << "[BrowtherAds] JNI Serve called: configured="
            << AdsClient::IsConfigured() << " client=" << (client != nullptr)
            << " browser_process=" << (g_browser_process != nullptr);
  if (!client) {
    // Best effort : rappelle le callback avec un tableau vide (bannière masquée).
    OnAdsServed(callback, {});
    return;
  }
  // Placement dashboard dev&din ; carousel jusqu'à 3 bannières (ratio 3.2:1),
  // parité NewTabPageHandler::GetBrowtherAds desktop.
  client->Serve("browther-ntp-banner", /*count=*/3,
                base::BindOnce(&OnAdsServed, std::move(callback)));
}

void JNI_BrowtherAdsBridge_MarkVisible(
    JNIEnv* env,
    const base::android::JavaRef<jstring>& jid) {
  AdsClient* client = GetAdsClient();
  if (!client) {
    return;
  }
  client->MarkVisible(base::android::ConvertJavaStringToUTF8(env, jid));
}

base::android::ScopedJavaLocalRef<jstring> JNI_BrowtherAdsBridge_GetClickUrl(
    JNIEnv* env,
    const base::android::JavaRef<jstring>& jid) {
  AdsClient* client = GetAdsClient();
  if (!client) {
    return base::android::ConvertUTF8ToJavaString(env, std::string());
  }
  const GURL click_url =
      client->GetClickURL(base::android::ConvertJavaStringToUTF8(env, jid));
  return base::android::ConvertUTF8ToJavaString(
      env, click_url.is_valid() ? click_url.spec() : std::string());
}

}  // namespace browther_ads::android

DEFINE_JNI(BrowtherAdsBridge)
