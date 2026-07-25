// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_BROWSER_BASARUNAA_BASARUNAA_VIDEO_TAP_TAB_HELPER_H_
#define BRAVE_BROWSER_BASARUNAA_BASARUNAA_VIDEO_TAP_TAB_HELPER_H_

#include "components/prefs/pref_change_registrar.h"
#include "content/public/browser/web_contents_observer.h"
#include "content/public/browser/web_contents_user_data.h"

namespace content {
class RenderFrameHost;
class WebContents;
}  // namespace content

namespace basarunaa {

// Browther/Basarunaa — desktop only. Pousse la pref utilisateur
// `kBasarunaaEnabled` aux renderers (mojom::VideoTapConfig::SetEnabled) à la
// création de chaque RenderFrame et à chaque toggle. Jumeau de
// `sawtunaa::SawtunaaTabHelper` (audio tap V2), et même raison d'être : le
// switch `--basarunaa-video-tap` est figé au démarrage du process renderer, il
// ne peut donc pas porter une pref qui change en cours de session.
//
// Sans ce canal : (a) toggle OFF laissait le tap vidéo tourner (readbacks GPU
// + inférence ML) alors que l'extension MV3 était déchargée et que plus rien
// n'était flouté, (b) toggle ON ne réactivait rien tant que le process
// renderer vivait — même un reload d'onglet ne suffisait pas.
//
// Le pipeline Android a son propre TabHelper
// (components/basarunaa/browser/, mojom android) : ce helper-ci ne concerne
// que le tap vidéo natif desktop.
class BasarunaaVideoTapTabHelper
    : public content::WebContentsObserver,
      public content::WebContentsUserData<BasarunaaVideoTapTabHelper> {
 public:
  BasarunaaVideoTapTabHelper(const BasarunaaVideoTapTabHelper&) = delete;
  BasarunaaVideoTapTabHelper& operator=(const BasarunaaVideoTapTabHelper&) =
      delete;
  ~BasarunaaVideoTapTabHelper() override;

  // content::WebContentsObserver:
  void RenderFrameCreated(content::RenderFrameHost* rfh) override;

 private:
  friend class content::WebContentsUserData<BasarunaaVideoTapTabHelper>;
  explicit BasarunaaVideoTapTabHelper(content::WebContents* web_contents);

  void PushEnabledToFrame(content::RenderFrameHost* rfh);
  void OnEnabledPrefChanged();

  PrefChangeRegistrar pref_change_registrar_;

  WEB_CONTENTS_USER_DATA_KEY_DECL();
};

}  // namespace basarunaa

#endif  // BRAVE_BROWSER_BASARUNAA_BASARUNAA_VIDEO_TAP_TAB_HELPER_H_
