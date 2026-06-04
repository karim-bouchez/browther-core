// Copyright (c) 2026 The Browther Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/components/basarunaa/browser/basarunaa_tab_helper.h"

#include <utility>

#include "base/functional/bind.h"
#include "base/logging.h"
#include "brave/components/basarunaa/common/mojom/basarunaa_android.mojom.h"
#include "brave/components/constants/pref_names.h"
#include "build/build_config.h"
#include "components/prefs/pref_service.h"
#include "components/user_prefs/user_prefs.h"
#include "content/public/browser/browser_context.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/web_contents.h"
#include "mojo/public/cpp/bindings/associated_remote.h"
#include "third_party/blink/public/common/associated_interfaces/associated_interface_provider.h"

#if BUILDFLAG(IS_ANDROID)
// Browther: Basarunaa Android Jalon 2.D — bridges C++↔Java générés par
// generate_jni dans brave/build/android/BUILD.gn :
// - BasarunaaBridge_jni.h : log statique (LogJs / EmitMetric) +
//   onAnalyzeReply (Java → C++ callback du verdict ML, @NativeMethods
//   centralisé ici pour passer R8, cf. note plus bas).
// - BasarunaaTabAnalyzer_jni.h : instance per-WebContents (analyzeImage,
//   cancel, pageReset, destroy)
#include "base/android/jni_android.h"
#include "base/android/jni_array.h"
#include "base/android/jni_string.h"
#include "brave/build/android/jni_headers/BasarunaaBridge_jni.h"
#include "brave/build/android/jni_headers/BasarunaaTabAnalyzer_jni.h"
#endif

namespace {
#if BUILDFLAG(IS_ANDROID)
// Compteur monotone pour identifier les Analyzers Java côté logs.
int g_next_analyzer_instance_id = 0;
#endif
}  // namespace

namespace basarunaa {

// static
void BasarunaaTabHelper::BindBasarunaaAndroid(
    content::RenderFrameHost* rfh,
    mojo::PendingReceiver<android::mojom::BasarunaaAndroid> receiver) {
  auto* web_contents = content::WebContents::FromRenderFrameHost(rfh);
  if (!web_contents) {
    return;
  }
  auto* helper = BasarunaaTabHelper::FromWebContents(web_contents);
  if (!helper) {
    return;
  }
  helper->receivers_.Add(helper, std::move(receiver), rfh);
}

BasarunaaTabHelper::BasarunaaTabHelper(content::WebContents* web_contents)
    : content::WebContentsObserver(web_contents),
      content::WebContentsUserData<BasarunaaTabHelper>(*web_contents) {
  LOG(INFO) << "[Basarunaa] TabHelper created for WebContents";

  // Observer toutes les prefs Basarunaa. On factorise sur une seule callback
  // qui re-push l'intégralité de la config.
  auto* prefs = user_prefs::UserPrefs::Get(web_contents->GetBrowserContext());
  if (prefs) {
    pref_change_registrar_.Init(prefs);
    auto cb = base::BindRepeating(
        &BasarunaaTabHelper::OnAnyBasarunaaPrefChanged, base::Unretained(this));
    pref_change_registrar_.Add(kBasarunaaEnabled, cb);
    pref_change_registrar_.Add(kBasarunaaMode, cb);
    pref_change_registrar_.Add(kBasarunaaConfBody, cb);
    pref_change_registrar_.Add(kBasarunaaConfFace, cb);
    pref_change_registrar_.Add(kBasarunaaGenderCertainty, cb);
    pref_change_registrar_.Add(kBasarunaaDebugMode, cb);
  }

#if BUILDFLAG(IS_ANDROID)
  // Jalon 2.D — crée l'instance Java BasarunaaTabAnalyzer associée à ce tab.
  // Le pointer `this` est passé pour permettre les callbacks Java→C++ via
  // OnAnalyzeReply (cf. BasarunaaTabAnalyzerJni::onAnalyzeReply). Coût léger
  // (juste l'objet Java + un long natif), l'engine ML est lazy (singleton
  // chargé au premier analyzeImage, cf. BasarunaaEngine.getInstance).
  JNIEnv* env = base::android::AttachCurrentThread();
  int instance_id = ++g_next_analyzer_instance_id;
  java_analyzer_.Reset(Java_BasarunaaTabAnalyzer_create(
      env, instance_id, reinterpret_cast<jlong>(this)));
#endif
}

void BasarunaaTabHelper::RenderFrameCreated(content::RenderFrameHost* rfh) {
  PushConfigToFrame(rfh);
}

void BasarunaaTabHelper::RenderFrameDeleted(content::RenderFrameHost* rfh) {
#if BUILDFLAG(IS_ANDROID)
  // Cleanup pending_analyses_ pour éviter des entrées dangling. La reply
  // de BasarunaaTabAnalyzer arrivera après destruction du RFH = no-op
  // côté OnAnalyzeReply (RFH not found dans la map).
  const auto rfh_id = rfh->GetGlobalId();
  for (auto it = pending_analyses_.begin(); it != pending_analyses_.end();) {
    if (it->second == rfh_id) {
      it = pending_analyses_.erase(it);
    } else {
      ++it;
    }
  }
#endif
}

void BasarunaaTabHelper::PushConfigToFrame(content::RenderFrameHost* rfh) {
  if (!rfh) {
    return;
  }
  auto* prefs =
      user_prefs::UserPrefs::Get(web_contents()->GetBrowserContext());
  if (!prefs) {
    return;
  }
  auto settings = android::mojom::BasarunaaSettings::New();
  settings->enabled = prefs->GetBoolean(kBasarunaaEnabled);
  settings->mode = prefs->GetString(kBasarunaaMode);
  settings->conf_body = prefs->GetDouble(kBasarunaaConfBody);
  settings->conf_face = prefs->GetDouble(kBasarunaaConfFace);
  settings->gender_certainty = prefs->GetDouble(kBasarunaaGenderCertainty);
  settings->debug_mode = prefs->GetString(kBasarunaaDebugMode);

  mojo::AssociatedRemote<android::mojom::BasarunaaConfig> config;
  rfh->GetRemoteAssociatedInterfaces()->GetInterface(&config);
  config->SetConfig(std::move(settings));
  LOG(INFO) << "[Basarunaa] Pushed SetConfig(enabled=" << prefs->GetBoolean(kBasarunaaEnabled)
            << ", mode=" << prefs->GetString(kBasarunaaMode)
            << ") to RFH " << rfh->GetGlobalId();
}

void BasarunaaTabHelper::OnAnyBasarunaaPrefChanged() {
  web_contents()->ForEachRenderFrameHost(
      [this](content::RenderFrameHost* rfh) { PushConfigToFrame(rfh); });
}

BasarunaaTabHelper::~BasarunaaTabHelper() {
#if BUILDFLAG(IS_ANDROID)
  if (!java_analyzer_.is_null()) {
    JNIEnv* env = base::android::AttachCurrentThread();
    Java_BasarunaaTabAnalyzer_destroy(env, java_analyzer_);
    java_analyzer_.Reset();
  }
#endif
}

// --- android::mojom::BasarunaaAndroid impl ---

void BasarunaaTabHelper::LogJs(const std::string& message) {
  LOG(INFO) << "[Basarunaa/JS] " << message;
#if BUILDFLAG(IS_ANDROID)
  JNIEnv* env = base::android::AttachCurrentThread();
  Java_BasarunaaBridge_onLogJs(
      env, base::android::ConvertUTF8ToJavaString(env, message));
#endif
}

void BasarunaaTabHelper::EmitMetric(const std::string& metric_json) {
  LOG(INFO) << "[Basarunaa/metric] " << metric_json;
#if BUILDFLAG(IS_ANDROID)
  JNIEnv* env = base::android::AttachCurrentThread();
  Java_BasarunaaBridge_onMetric(
      env, base::android::ConvertUTF8ToJavaString(env, metric_json));
#endif
}

void BasarunaaTabHelper::AnalyzeImage(
    int32_t image_id,
    const std::vector<uint8_t>& image_bytes) {
  LOG(INFO) << "[Basarunaa/AnalyzeImage] id=" << image_id
            << " bytes=" << image_bytes.size();
#if BUILDFLAG(IS_ANDROID)
  if (java_analyzer_.is_null()) {
    return;
  }
  // Mémorise le RFH source pour pouvoir router le verdict ML.
  content::RenderFrameHost* rfh = receivers_.current_context();
  if (!rfh) {
    return;
  }
  pending_analyses_[image_id] = rfh->GetGlobalId();

  auto* prefs =
      user_prefs::UserPrefs::Get(web_contents()->GetBrowserContext());
  if (!prefs) {
    return;
  }

  JNIEnv* env = base::android::AttachCurrentThread();
  base::android::ScopedJavaLocalRef<jbyteArray> j_bytes =
      base::android::ToJavaByteArray(env, image_bytes);
  Java_BasarunaaTabAnalyzer_analyzeImage(
      env, java_analyzer_, image_id, j_bytes,
      base::android::ConvertUTF8ToJavaString(env,
                                             prefs->GetString(kBasarunaaMode)),
      prefs->GetDouble(kBasarunaaConfBody),
      prefs->GetDouble(kBasarunaaConfFace),
      prefs->GetDouble(kBasarunaaGenderCertainty));
#endif
}

void BasarunaaTabHelper::CancelAnalyze(int32_t image_id) {
  LOG(INFO) << "[Basarunaa/CancelAnalyze] id=" << image_id;
#if BUILDFLAG(IS_ANDROID)
  pending_analyses_.erase(image_id);
  if (java_analyzer_.is_null()) {
    return;
  }
  Java_BasarunaaTabAnalyzer_cancelAnalyze(
      base::android::AttachCurrentThread(), java_analyzer_, image_id);
#endif
}

void BasarunaaTabHelper::PageReset(const std::string& url) {
  LOG(INFO) << "[Basarunaa/PageReset] " << url;
#if BUILDFLAG(IS_ANDROID)
  // Clear seul les pending de ce RFH (PageReset vient d'un frame spécifique).
  // Si on clear tout, on casse les autres frames qui peuvent tourner.
  content::RenderFrameHost* rfh = receivers_.current_context();
  if (rfh) {
    const auto rfh_id = rfh->GetGlobalId();
    for (auto it = pending_analyses_.begin(); it != pending_analyses_.end();) {
      if (it->second == rfh_id) {
        it = pending_analyses_.erase(it);
      } else {
        ++it;
      }
    }
  }
  if (java_analyzer_.is_null()) {
    return;
  }
  JNIEnv* env = base::android::AttachCurrentThread();
  Java_BasarunaaTabAnalyzer_pageReset(
      env, java_analyzer_,
      base::android::ConvertUTF8ToJavaString(env, url));
#endif
}

#if BUILDFLAG(IS_ANDROID)
void BasarunaaTabHelper::OnAnalyzeReply(int32_t image_id,
                                        const std::string& decision,
                                        const std::string& persons_json,
                                        double elapsed_ms) {
  auto it = pending_analyses_.find(image_id);
  if (it == pending_analyses_.end()) {
    LOG(WARNING) << "[Basarunaa/reply] dropped: no pending RFH for image_id="
                 << image_id << " (rfh deleted during inference?)";
    return;
  }
  const auto rfh_id = it->second;
  pending_analyses_.erase(it);

  content::RenderFrameHost* rfh = content::RenderFrameHost::FromID(rfh_id);
  if (!rfh) {
    LOG(WARNING) << "[Basarunaa/reply] dropped: RFH gone for image_id="
                 << image_id;
    return;
  }

  auto* prefs =
      user_prefs::UserPrefs::Get(web_contents()->GetBrowserContext());
  const std::string debug_mode =
      prefs ? prefs->GetString(kBasarunaaDebugMode) : "none";

  mojo::AssociatedRemote<android::mojom::BasarunaaApply> apply;
  rfh->GetRemoteAssociatedInterfaces()->GetInterface(&apply);
  apply->Apply(image_id, decision, persons_json, debug_mode, elapsed_ms);
  LOG(INFO) << "[Basarunaa/reply] image_id=" << image_id
            << " decision=" << decision
            << " elapsed_ms=" << elapsed_ms;
}

// Overload JNI : signature attendue par jni_zero pour
// `@NativeMethods.onAnalyzeReply(long nativeHelper, int, String, String, double)`.
// jni_zero détecte le `long native*` 1er param → génère
//   Helper* _ptr = reinterpret_cast<Helper*>(nativeHelper);
//   _ptr->OnAnalyzeReply(env, imageId, decision_ref, personsJson_ref, elapsedMs);
// dans `BasarunaaBridge_jni.h`. Le `using Helper = BasarunaaTabHelper` est juste
// avant le `DEFINE_JNI(BasarunaaBridge)` plus bas.
void BasarunaaTabHelper::OnAnalyzeReply(
    JNIEnv* env,
    jint image_id,
    const base::android::JavaParamRef<jstring>& j_decision,
    const base::android::JavaParamRef<jstring>& j_persons_json,
    jdouble elapsed_ms) {
  OnAnalyzeReply(image_id,
                 base::android::ConvertJavaStringToUTF8(env, j_decision),
                 base::android::ConvertJavaStringToUTF8(env, j_persons_json),
                 elapsed_ms);
}

// Alias requis par jni_zero pattern "long native pointer" — le `_jni.h` généré
// fait `Helper* _ptr = reinterpret_cast<Helper*>(nativeHelper)` puis
// `_ptr->OnAnalyzeReply(...)`. Doit être dans namespace basarunaa parce que
// l'@JNINamespace("basarunaa") Java fait `using namespace basarunaa` côté C++.
using Helper = BasarunaaTabHelper;
#endif  // BUILDFLAG(IS_ANDROID)

WEB_CONTENTS_USER_DATA_KEY_IMPL(BasarunaaTabHelper);

}  // namespace basarunaa

#if BUILDFLAG(IS_ANDROID)
// Macro jni_zero qui génère `Java_J_N_M*` (la fonction native side Java→C++)
// dans libchrome.so. Sans ça, le runtime ART lève
// `UnsatisfiedLinkError: No implementation found for J.N.M*` (cf. crash 2026-06-04
// à l'appel BasarunaaBridge.notifyAnalyzeReply). Doit être HORS du namespace
// `basarunaa` et après l'include du `BasarunaaBridge_jni.h`. Cf.
// `chrome/browser/android/httpclient/http_client_bridge.cc:DEFINE_JNI(SimpleHttpClient)`.
DEFINE_JNI(BasarunaaBridge)
#endif
