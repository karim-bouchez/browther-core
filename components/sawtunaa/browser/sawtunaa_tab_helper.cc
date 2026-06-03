// Copyright (c) 2026 The Browther Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/components/sawtunaa/browser/sawtunaa_tab_helper.h"

#include <utility>

#include "base/functional/bind.h"
#include "base/logging.h"
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
// Browther: Sawtunaa Voie B (Jalons 2.B.5 + 2.D) — bridges C++→Java générés
// par generate_jni dans brave/build/android/BUILD.gn :
// - SawtunaaBridge_jni.h : statiques de logging (LogJs / EmitMetric)
// - SawtunaaPlayer_jni.h : instance per-WebContents (audio pipeline)
#include "base/android/jni_android.h"
#include "base/android/jni_array.h"
#include "base/android/jni_string.h"
#include "brave/build/android/jni_headers/SawtunaaBridge_jni.h"
#include "brave/build/android/jni_headers/SawtunaaPlayer_jni.h"
#endif

namespace {
#if BUILDFLAG(IS_ANDROID)
// Compteur monotone pour identifier les Player Java côté logs.
int g_next_player_instance_id = 0;
#endif
}  // namespace

namespace sawtunaa {

// static
void SawtunaaTabHelper::BindSawtunaa(
    content::RenderFrameHost* rfh,
    mojo::PendingReceiver<mojom::Sawtunaa> receiver) {
  auto* web_contents = content::WebContents::FromRenderFrameHost(rfh);
  if (!web_contents) {
    return;
  }
  // Pas de gating sur la pref ici : le renderer ne demande `mojom::Sawtunaa`
  // que si son `window.__sawtunaa.isEnabled()` retourne true (lui-même
  // contrôlé par le push `SawtunaaConfig::SetEnabled` depuis ici). Si la
  // pref est OFF, le binder est appelé seulement si le user vient de
  // toggler ON (on doit accepter le receiver, sinon impasse).
  // Le TabHelper existe systématiquement (créé via AttachTabHelpers).
  auto* helper = SawtunaaTabHelper::FromWebContents(web_contents);
  if (!helper) {
    return;
  }
  helper->receivers_.Add(helper, std::move(receiver), rfh);
}

SawtunaaTabHelper::SawtunaaTabHelper(content::WebContents* web_contents)
    : content::WebContentsObserver(web_contents),
      content::WebContentsUserData<SawtunaaTabHelper>(*web_contents) {
  LOG(INFO) << "[Sawtunaa] TabHelper created for WebContents";

  // Observer la pref `kSawtunaaEnabled` : à chaque changement, on push aux
  // renderers via `SawtunaaConfig::SetEnabled`, ce qui (a) restaure ou
  // installe le force-mute côté JS, (b) injecte/désactive le script.
  auto* prefs = user_prefs::UserPrefs::Get(web_contents->GetBrowserContext());
  if (prefs) {
    pref_change_registrar_.Init(prefs);
    pref_change_registrar_.Add(
        kSawtunaaEnabled,
        base::BindRepeating(&SawtunaaTabHelper::OnEnabledPrefChanged,
                            base::Unretained(this)));
  }

#if BUILDFLAG(IS_ANDROID)
  // Jalon 2.D — crée l'instance Java SawtunaaPlayer associée à ce tab.
  // C'est elle qui pilote AudioTrack + NSNet2 (port direct du Swift).
  // Coût : ~25 MB modèle ONNX. On la crée pour tous les WC pour préserver
  // la simplicité (pas de re-create au toggle live ON). Optim future
  // possible : lazy au premier preprocessChunk.
  JNIEnv* env = base::android::AttachCurrentThread();
  int instance_id = ++g_next_player_instance_id;
  java_player_.Reset(Java_SawtunaaPlayer_create(env, instance_id));
#endif
}

void SawtunaaTabHelper::RenderFrameCreated(content::RenderFrameHost* rfh) {
  // Push la valeur initiale dès qu'un nouveau frame existe. Le RFO
  // renderer-side a déjà enregistré son receiver SawtunaaConfig au ctor,
  // donc le Mojo channel est dispo. `GetRemoteAssociatedInterfaces()`
  // bind le pipe.
  PushEnabledToFrame(rfh);
}

void SawtunaaTabHelper::PushEnabledToFrame(content::RenderFrameHost* rfh) {
  if (!rfh) {
    return;
  }
  auto* prefs = user_prefs::UserPrefs::Get(
      web_contents()->GetBrowserContext());
  const bool enabled = prefs && prefs->GetBoolean(kSawtunaaEnabled);
  mojo::AssociatedRemote<mojom::SawtunaaConfig> config;
  rfh->GetRemoteAssociatedInterfaces()->GetInterface(&config);
  config->SetEnabled(enabled);
  LOG(INFO) << "[Sawtunaa] Pushed SetEnabled(" << (enabled ? "true" : "false")
            << ") to RFH " << rfh->GetGlobalId();
}

void SawtunaaTabHelper::OnEnabledPrefChanged() {
  // Itère tous les RFH du WebContents et push la nouvelle valeur.
  web_contents()->ForEachRenderFrameHost(
      [this](content::RenderFrameHost* rfh) {
        PushEnabledToFrame(rfh);
      });
}

SawtunaaTabHelper::~SawtunaaTabHelper() {
#if BUILDFLAG(IS_ANDROID)
  if (!java_player_.is_null()) {
    JNIEnv* env = base::android::AttachCurrentThread();
    Java_SawtunaaPlayer_destroy(env, java_player_);
    java_player_.Reset();
  }
#endif
}

// --- mojom::Sawtunaa stubs (Jalon 2.B.5 — LOG(INFO) côté C++ + JNI vers
// SawtunaaBridge.java sur Android) ---

void SawtunaaTabHelper::LogJs(const std::string& message) {
  LOG(INFO) << "[Sawtunaa/JS] " << message;
#if BUILDFLAG(IS_ANDROID)
  JNIEnv* env = base::android::AttachCurrentThread();
  Java_SawtunaaBridge_onLogJs(
      env, base::android::ConvertUTF8ToJavaString(env, message));
#endif
}

void SawtunaaTabHelper::EmitMetric(const std::string& metric_json) {
  LOG(INFO) << "[Sawtunaa/metric] " << metric_json;
#if BUILDFLAG(IS_ANDROID)
  JNIEnv* env = base::android::AttachCurrentThread();
  Java_SawtunaaBridge_onMetric(
      env, base::android::ConvertUTF8ToJavaString(env, metric_json));
#endif
}

void SawtunaaTabHelper::PreprocessChunk(double timestamp_ms,
                                        const std::vector<float>& samples) {
  // Pas de LOG ici — un chunk par 100-1000 ms × N onglets = trop verbeux.
  // Le metric event `chunk_preprocess_done` côté Java logge déjà le besoin.
#if BUILDFLAG(IS_ANDROID)
  if (java_player_.is_null()) {
    return;
  }
  JNIEnv* env = base::android::AttachCurrentThread();
  base::android::ScopedJavaLocalRef<jfloatArray> j_samples =
      base::android::ToJavaFloatArray(env, samples);
  Java_SawtunaaPlayer_preprocessChunk(env, java_player_, timestamp_ms,
                                       j_samples);
#endif
}

void SawtunaaTabHelper::PlayAt(double timestamp_ms) {
#if BUILDFLAG(IS_ANDROID)
  if (java_player_.is_null()) {
    return;
  }
  Java_SawtunaaPlayer_playChunksUpTo(base::android::AttachCurrentThread(),
                                      java_player_, timestamp_ms);
#endif
}

void SawtunaaTabHelper::ClearChunks() {
#if BUILDFLAG(IS_ANDROID)
  if (java_player_.is_null()) {
    return;
  }
  Java_SawtunaaPlayer_clearChunks(base::android::AttachCurrentThread(),
                                   java_player_);
#endif
}

void SawtunaaTabHelper::PageReset(const std::string& url) {
  LOG(INFO) << "[Sawtunaa/pageReset] " << url;
#if BUILDFLAG(IS_ANDROID)
  if (java_player_.is_null()) {
    return;
  }
  JNIEnv* env = base::android::AttachCurrentThread();
  Java_SawtunaaPlayer_pageReset(
      env, java_player_,
      base::android::ConvertUTF8ToJavaString(env, url));
#endif
}

void SawtunaaTabHelper::SeekTo(double to_ms) {
#if BUILDFLAG(IS_ANDROID)
  if (java_player_.is_null()) {
    return;
  }
  Java_SawtunaaPlayer_seekTo(base::android::AttachCurrentThread(),
                              java_player_, to_ms);
#endif
}

void SawtunaaTabHelper::EvictRange(double start_ms, double end_ms) {
#if BUILDFLAG(IS_ANDROID)
  if (java_player_.is_null()) {
    return;
  }
  Java_SawtunaaPlayer_evictRange(base::android::AttachCurrentThread(),
                                  java_player_, start_ms, end_ms);
#endif
}

void SawtunaaTabHelper::SyncRanges(std::vector<mojom::TimeRangePtr> ranges) {
#if BUILDFLAG(IS_ANDROID)
  if (java_player_.is_null()) {
    return;
  }
  // Flatten en {s0, e0, s1, e1, ...} pour traverser JNI en un seul array.
  std::vector<double> flat;
  flat.reserve(ranges.size() * 2);
  for (const auto& r : ranges) {
    flat.push_back(r->start_ms);
    flat.push_back(r->end_ms);
  }
  JNIEnv* env = base::android::AttachCurrentThread();
  base::android::ScopedJavaLocalRef<jdoubleArray> j_flat =
      base::android::ToJavaDoubleArray(env, flat);
  Java_SawtunaaPlayer_syncRanges(env, java_player_, j_flat);
#endif
}

void SawtunaaTabHelper::PauseAudio() {
#if BUILDFLAG(IS_ANDROID)
  if (java_player_.is_null()) {
    return;
  }
  Java_SawtunaaPlayer_pauseAudio(base::android::AttachCurrentThread(),
                                  java_player_);
#endif
}

void SawtunaaTabHelper::ResumeAudio() {
#if BUILDFLAG(IS_ANDROID)
  if (java_player_.is_null()) {
    return;
  }
  Java_SawtunaaPlayer_resumeAudio(base::android::AttachCurrentThread(),
                                   java_player_);
#endif
}

WEB_CONTENTS_USER_DATA_KEY_IMPL(SawtunaaTabHelper);

}  // namespace sawtunaa
