/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * you can obtain one at https://mozilla.org/MPL/2.0/. */

#ifndef BRAVE_COMPONENTS_BASARUNAA_BROWSER_BASARUNAA_TAB_HELPER_H_
#define BRAVE_COMPONENTS_BASARUNAA_BROWSER_BASARUNAA_TAB_HELPER_H_

#include <cstdint>
#include <map>
#include <string>
#include <vector>

#include "base/memory/raw_ptr.h"
#include "brave/components/basarunaa/common/mojom/basarunaa_android.mojom.h"
#include "build/build_config.h"
#include "components/prefs/pref_change_registrar.h"
#include "content/public/browser/global_routing_id.h"
#include "content/public/browser/web_contents_observer.h"
#include "content/public/browser/web_contents_user_data.h"
#include "mojo/public/cpp/bindings/associated_remote.h"
#include "mojo/public/cpp/bindings/pending_receiver.h"
#include "mojo/public/cpp/bindings/receiver_set.h"

#if BUILDFLAG(IS_ANDROID)
#include "base/android/jni_android.h"
#include "base/android/scoped_java_ref.h"
#endif

namespace content {
class RenderFrameHost;
class WebContents;
}  // namespace content

namespace basarunaa {

// Per-WebContents helper, créé à `AttachTabHelpers` (cf. brave_tab_helpers.cc)
// — gating #if BUILDFLAG(IS_ANDROID) car le pipeline natif Basarunaa Java
// est Android-only. Pour macOS/Windows le pipeline reste MV3 (extension
// chargée par BraveComponentLoader, cf. Phase 3.1 § Étape 2/3).
//
// Rôles :
//   1. Implémente `android::mojom::BasarunaaAndroid` (renderer → browser) —
//      reçoit les events JS (LogJs, EmitMetric, AnalyzeImage, CancelAnalyze,
//      PageReset).
//   2. Implémente `content::WebContentsObserver` — `RenderFrameCreated`
//      pour push la valeur courante de la config au renderer (via
//      `BasarunaaConfig`).
//   3. Observe les prefs `kBasarunaaEnabled`/`kBasarunaaMode`/`kBasarunaa*`
//      via `PrefChangeRegistrar` ; sur changement, push la nouvelle config
//      à tous les RFH. Permet le toggle live sans reload du panel BottomSheet.
//
// Plusieurs RenderFrameHost peuvent partager le même TabHelper (un par
// WebContents) — chaque frame reçoit son propre Mojo receiver via
// `ReceiverSet` keyed sur le RFH.
//
// Note Jalon 2.C : pas encore de JNI vers Java côté actions Mojo (LogJs etc
// loggue seulement). Le bridge Java arrive en Jalon 2.D, ainsi que la
// méthode `OnAnalyzeReply` pour pousser `BasarunaaApply` au renderer.
class BasarunaaTabHelper
    : public content::WebContentsObserver,
      public content::WebContentsUserData<BasarunaaTabHelper>,
      public android::mojom::BasarunaaAndroid {
 public:
  // Binder Mojo : appelé par BraveContentBrowserClient::
  // RegisterBrowserInterfaceBindersForFrame (gated `BUILDFLAG(IS_ANDROID)`).
  // Pas de gating sur la pref ici : c'est `BasarunaaConfig::SetConfig` push
  // au renderer qui inhibe la pipeline (sinon impossible de propager un
  // toggle ON live à un frame qui n'a jamais demandé `BasarunaaAndroid`
  // parce qu'il était OFF au boot). Pattern parité Sawtunaa.
  static void BindBasarunaaAndroid(
      content::RenderFrameHost* rfh,
      mojo::PendingReceiver<android::mojom::BasarunaaAndroid> receiver);

  BasarunaaTabHelper(const BasarunaaTabHelper&) = delete;
  BasarunaaTabHelper& operator=(const BasarunaaTabHelper&) = delete;
  ~BasarunaaTabHelper() override;

  // content::WebContentsObserver
  void RenderFrameCreated(content::RenderFrameHost* rfh) override;
  void RenderFrameDeleted(content::RenderFrameHost* rfh) override;

  // android::mojom::BasarunaaAndroid
  void LogJs(const std::string& message) override;
  void EmitMetric(const std::string& metric_json) override;
  void AnalyzeImage(int32_t image_id,
                    const std::vector<uint8_t>& image_bytes) override;
  void CancelAnalyze(int32_t image_id) override;
  void PageReset(const std::string& url) override;

#if BUILDFLAG(IS_ANDROID)
  // Appelé par BasarunaaTabAnalyzer.java via BasarunaaBridge.notifyAnalyzeReply.
  // Trouve le RFH source de l'AnalyzeImage initial dans `pending_analyses_`
  // et push `BasarunaaApply::Apply` au renderer.
  void OnAnalyzeReply(int32_t image_id,
                      const std::string& decision,
                      const std::string& persons_json,
                      double elapsed_ms);

  // Overload JNI : signature attendue par jni_zero pour le @NativeMethods
  // `onAnalyzeReply(long nativeHelper, int imageId, String, String, double)`
  // de BasarunaaBridge.java. jni_zero détecte le pattern `long native*` en
  // 1er param et génère `Helper::OnAnalyzeReply(JNIEnv*, ...)` (cf. fichier
  // BasarunaaBridge_jni.h généré). Cette overload convertit les jstring vers
  // std::string et délègue à l'overload du dessus.
  //
  // Le `using Helper = BasarunaaTabHelper` requis par jni_zero est dans le
  // .cc, juste avant le `DEFINE_JNI(BasarunaaBridge)` final.
  void OnAnalyzeReply(JNIEnv* env,
                      jint image_id,
                      const base::android::JavaParamRef<jstring>& j_decision,
                      const base::android::JavaParamRef<jstring>& j_persons_json,
                      jdouble elapsed_ms);
#endif

 private:
  friend class content::WebContentsUserData<BasarunaaTabHelper>;
  explicit BasarunaaTabHelper(content::WebContents* web_contents);

  // Lit l'état pref courant (enabled + mode + sliders) et push au renderer
  // du RFH donné via `BasarunaaConfig::SetConfig`. Utilise
  // `GetRemoteAssociatedInterfaces()`.
  void PushConfigToFrame(content::RenderFrameHost* rfh);

  // PrefChangeRegistrar callback : itère tous les RFH actifs et push la
  // config courante. Pousse à toutes les prefs Basarunaa pour limiter le
  // nombre d'observers (une seule callback pour les 6 prefs).
  void OnAnyBasarunaaPrefChanged();

  PrefChangeRegistrar pref_change_registrar_;

  mojo::ReceiverSet<android::mojom::BasarunaaAndroid,
                    raw_ptr<content::RenderFrameHost>>
      receivers_;

#if BUILDFLAG(IS_ANDROID)
  // Instance Java BasarunaaTabAnalyzer associée à ce WebContents. Créée
  // dans le ctor via Java_BasarunaaTabAnalyzer_create(instance_id, this),
  // détruite dans le dtor via Java_BasarunaaTabAnalyzer_destroy.
  base::android::ScopedJavaGlobalRef<jobject> java_analyzer_;

  // image_id (côté JS) → RFH source du AnalyzeImage initial. Permet à
  // OnAnalyzeReply (callback Java) de router la reply BasarunaaApply::Apply
  // au bon renderer. Cleanup au RenderFrameDeleted pour éviter dangling.
  std::map<int32_t, content::GlobalRenderFrameHostId> pending_analyses_;
#endif

  WEB_CONTENTS_USER_DATA_KEY_DECL();
};

}  // namespace basarunaa

#endif  // BRAVE_COMPONENTS_BASARUNAA_BROWSER_BASARUNAA_TAB_HELPER_H_
