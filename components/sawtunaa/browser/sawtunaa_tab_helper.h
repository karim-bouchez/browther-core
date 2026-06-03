/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * you can obtain one at https://mozilla.org/MPL/2.0/. */

#ifndef BRAVE_COMPONENTS_SAWTUNAA_BROWSER_SAWTUNAA_TAB_HELPER_H_
#define BRAVE_COMPONENTS_SAWTUNAA_BROWSER_SAWTUNAA_TAB_HELPER_H_

#include <string>
#include <vector>

#include "base/memory/raw_ptr.h"
#include "brave/components/sawtunaa/common/mojom/sawtunaa.mojom.h"
#include "build/build_config.h"
#include "components/prefs/pref_change_registrar.h"
#include "content/public/browser/web_contents_observer.h"
#include "content/public/browser/web_contents_user_data.h"
#include "mojo/public/cpp/bindings/pending_receiver.h"
#include "mojo/public/cpp/bindings/receiver_set.h"

#if BUILDFLAG(IS_ANDROID)
#include "base/android/scoped_java_ref.h"
#endif

namespace content {
class RenderFrameHost;
class WebContents;
}  // namespace content

namespace sawtunaa {

// Per-WebContents helper, créé à `AttachTabHelpers` (cf. brave_tab_helpers.cc),
// donc disponible quel que soit l'état initial de la pref `kSawtunaaEnabled`.
//
// Rôles :
//   1. Implémente `mojom::Sawtunaa` (renderer → browser) — reçoit les chunks
//      audio, métriques, page resets, etc. du script JS injecté.
//   2. Implémente `WebContentsObserver` — `RenderFrameCreated` pour push la
//      valeur courante de la pref au renderer (via `SawtunaaConfig`).
//   3. Observe la pref `kSawtunaaEnabled` via `PrefChangeRegistrar` ; sur
//      changement, itère les RFH actifs et push la nouvelle valeur. Permet
//      le toggle live sans reload.
//
// Plusieurs RenderFrameHost peuvent partager le même TabHelper (un par
// WebContents) — chaque frame reçoit son propre Mojo receiver via
// `ReceiverSet` keyed sur le RFH.
class SawtunaaTabHelper
    : public content::WebContentsObserver,
      public content::WebContentsUserData<SawtunaaTabHelper>,
      public mojom::Sawtunaa {
 public:
  // Binder Mojo : appelé par BraveContentBrowserClient::
  // RegisterBrowserInterfaceBindersForFrame. Pas de gating sur la pref ici :
  // c'est `SawtunaaConfig::SetEnabled(false)` push au renderer qui inhibe la
  // pipeline (sinon impossible de propager un toggle ON live à un frame qui
  // n'a jamais demandé `mojom::Sawtunaa` parce qu'il était OFF au boot).
  static void BindSawtunaa(
      content::RenderFrameHost* rfh,
      mojo::PendingReceiver<mojom::Sawtunaa> receiver);

  SawtunaaTabHelper(const SawtunaaTabHelper&) = delete;
  SawtunaaTabHelper& operator=(const SawtunaaTabHelper&) = delete;
  ~SawtunaaTabHelper() override;

  // content::WebContentsObserver
  void RenderFrameCreated(content::RenderFrameHost* rfh) override;

  // mojom::Sawtunaa
  void LogJs(const std::string& message) override;
  void EmitMetric(const std::string& metric_json) override;
  void PreprocessChunk(double timestamp_ms,
                       const std::vector<float>& samples) override;
  void PlayAt(double timestamp_ms) override;
  void ClearChunks() override;
  void PageReset(const std::string& url) override;
  void SeekTo(double to_ms) override;
  void EvictRange(double start_ms, double end_ms) override;
  void SyncRanges(std::vector<mojom::TimeRangePtr> ranges) override;
  void PauseAudio() override;
  void ResumeAudio() override;

 private:
  friend class content::WebContentsUserData<SawtunaaTabHelper>;
  explicit SawtunaaTabHelper(content::WebContents* web_contents);

  // Push la valeur courante de `kSawtunaaEnabled` au renderer du RFH donné.
  // Utilise `GetRemoteAssociatedInterfaces()` pour obtenir un
  // `AssociatedRemote<mojom::SawtunaaConfig>`.
  void PushEnabledToFrame(content::RenderFrameHost* rfh);

  // PrefChangeRegistrar callback : itère tous les RFH actifs et push.
  void OnEnabledPrefChanged();

  PrefChangeRegistrar pref_change_registrar_;

  mojo::ReceiverSet<mojom::Sawtunaa, raw_ptr<content::RenderFrameHost>>
      receivers_;

#if BUILDFLAG(IS_ANDROID)
  // Instance Java SawtunaaPlayer associée à ce WebContents. Créée au
  // constructeur via `Java_SawtunaaPlayer_create(instance_id)`, détruite au
  // destructeur. C'est elle qui pilote AudioTrack + NSNet2 — la couche
  // C++ ne fait que router les actions Mojo vers les @CalledByNative.
  base::android::ScopedJavaGlobalRef<jobject> java_player_;
#endif

  WEB_CONTENTS_USER_DATA_KEY_DECL();
};

}  // namespace sawtunaa

#endif  // BRAVE_COMPONENTS_SAWTUNAA_BROWSER_SAWTUNAA_TAB_HELPER_H_
