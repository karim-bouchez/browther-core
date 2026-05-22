// Copyright (c) 2026 The Browther Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/components/sawtunaa/browser/sawtunaa_tab_helper.h"

#include <utility>

#include "base/logging.h"
#include "build/build_config.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/web_contents.h"

#if BUILDFLAG(IS_ANDROID)
// Browther: Sawtunaa Voie B (Jalon 2.B.5) — bridge C++→Java généré depuis
// brave/android/java/.../sawtunaa/SawtunaaBridge.java par generate_jni dans
// brave/build/android/BUILD.gn.
#include "base/android/jni_android.h"
#include "base/android/jni_string.h"
#include "brave/build/android/jni_headers/SawtunaaBridge_jni.h"
#endif

namespace sawtunaa {

// static
void SawtunaaTabHelper::BindSawtunaa(
    content::RenderFrameHost* rfh,
    mojo::PendingReceiver<mojom::Sawtunaa> receiver) {
  auto* web_contents = content::WebContents::FromRenderFrameHost(rfh);
  if (!web_contents) {
    return;
  }
  SawtunaaTabHelper::CreateForWebContents(web_contents);
  auto* helper = SawtunaaTabHelper::FromWebContents(web_contents);
  if (!helper) {
    return;
  }
  helper->receivers_.Add(helper, std::move(receiver), rfh);
}

SawtunaaTabHelper::SawtunaaTabHelper(content::WebContents* web_contents)
    : content::WebContentsUserData<SawtunaaTabHelper>(*web_contents) {
  LOG(INFO) << "[Sawtunaa] TabHelper created for WebContents";
}

SawtunaaTabHelper::~SawtunaaTabHelper() = default;

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
  LOG(INFO) << "[Sawtunaa/chunk] ts=" << timestamp_ms
            << " n=" << samples.size();
#if BUILDFLAG(IS_ANDROID)
  // Jalon 2.B.5 : on passe juste le count à Java. Le marshaling
  // float[] (~192 KB par chunk) arrivera au Jalon 2.D quand
  // SawtunaaAudioPlayer Java consommera vraiment les samples.
  JNIEnv* env = base::android::AttachCurrentThread();
  Java_SawtunaaBridge_onPreprocessChunk(
      env, timestamp_ms, static_cast<jint>(samples.size()));
#endif
}

void SawtunaaTabHelper::PlayAt(double timestamp_ms) {
  LOG(INFO) << "[Sawtunaa/playAt] ms=" << timestamp_ms;
#if BUILDFLAG(IS_ANDROID)
  JNIEnv* env = base::android::AttachCurrentThread();
  Java_SawtunaaBridge_onPlayAt(env, timestamp_ms);
#endif
}

void SawtunaaTabHelper::ClearChunks() {
  LOG(INFO) << "[Sawtunaa/clearChunks]";
#if BUILDFLAG(IS_ANDROID)
  Java_SawtunaaBridge_onClearChunks(base::android::AttachCurrentThread());
#endif
}

void SawtunaaTabHelper::PageReset(const std::string& url) {
  LOG(INFO) << "[Sawtunaa/pageReset] " << url;
#if BUILDFLAG(IS_ANDROID)
  JNIEnv* env = base::android::AttachCurrentThread();
  Java_SawtunaaBridge_onPageReset(
      env, base::android::ConvertUTF8ToJavaString(env, url));
#endif
}

void SawtunaaTabHelper::SeekTo(double to_ms) {
  LOG(INFO) << "[Sawtunaa/seekTo] ms=" << to_ms;
#if BUILDFLAG(IS_ANDROID)
  JNIEnv* env = base::android::AttachCurrentThread();
  Java_SawtunaaBridge_onSeekTo(env, to_ms);
#endif
}

void SawtunaaTabHelper::EvictRange(double start_ms, double end_ms) {
  LOG(INFO) << "[Sawtunaa/evictRange] " << start_ms << " -> " << end_ms;
#if BUILDFLAG(IS_ANDROID)
  JNIEnv* env = base::android::AttachCurrentThread();
  Java_SawtunaaBridge_onEvictRange(env, start_ms, end_ms);
#endif
}

void SawtunaaTabHelper::SyncRanges(std::vector<mojom::TimeRangePtr> ranges) {
  LOG(INFO) << "[Sawtunaa/syncRanges] count=" << ranges.size();
#if BUILDFLAG(IS_ANDROID)
  // Jalon 2.B.5 : count seulement (idem PreprocessChunk).
  Java_SawtunaaBridge_onSyncRanges(base::android::AttachCurrentThread(),
                                   static_cast<jint>(ranges.size()));
#endif
}

void SawtunaaTabHelper::PauseAudio() {
  LOG(INFO) << "[Sawtunaa/pauseAudio]";
#if BUILDFLAG(IS_ANDROID)
  Java_SawtunaaBridge_onPauseAudio(base::android::AttachCurrentThread());
#endif
}

void SawtunaaTabHelper::ResumeAudio() {
  LOG(INFO) << "[Sawtunaa/resumeAudio]";
#if BUILDFLAG(IS_ANDROID)
  Java_SawtunaaBridge_onResumeAudio(base::android::AttachCurrentThread());
#endif
}

WEB_CONTENTS_USER_DATA_KEY_IMPL(SawtunaaTabHelper);

}  // namespace sawtunaa
