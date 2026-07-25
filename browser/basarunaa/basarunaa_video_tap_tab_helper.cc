// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/browser/basarunaa/basarunaa_video_tap_tab_helper.h"

#include "base/functional/bind.h"
#include "base/logging.h"
#include "brave/components/basarunaa/common/mojom/basarunaa.mojom.h"
#include "brave/components/constants/pref_names.h"
#include "components/prefs/pref_service.h"
#include "components/user_prefs/user_prefs.h"
#include "content/public/browser/browser_context.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/web_contents.h"
#include "mojo/public/cpp/bindings/associated_remote.h"
#include "third_party/blink/public/common/associated_interfaces/associated_interface_provider.h"

namespace basarunaa {

BasarunaaVideoTapTabHelper::BasarunaaVideoTapTabHelper(
    content::WebContents* web_contents)
    : content::WebContentsObserver(web_contents),
      content::WebContentsUserData<BasarunaaVideoTapTabHelper>(*web_contents) {
  auto* prefs = user_prefs::UserPrefs::Get(web_contents->GetBrowserContext());
  if (prefs) {
    pref_change_registrar_.Init(prefs);
    pref_change_registrar_.Add(
        kBasarunaaEnabled,
        base::BindRepeating(
            &BasarunaaVideoTapTabHelper::OnEnabledPrefChanged,
            base::Unretained(this)));
  }
  // Anti-course : les frames déjà vivants au moment où le helper est attaché
  // ne verront jamais RenderFrameCreated.
  web_contents->ForEachRenderFrameHost(
      [this](content::RenderFrameHost* rfh) { PushEnabledToFrame(rfh); });
}

BasarunaaVideoTapTabHelper::~BasarunaaVideoTapTabHelper() = default;

void BasarunaaVideoTapTabHelper::RenderFrameCreated(
    content::RenderFrameHost* rfh) {
  // Push la valeur initiale dès qu'un frame existe : le RFO renderer a
  // enregistré son receiver VideoTapConfig dans son constructeur, donc bien
  // avant qu'un WebMediaPlayer ne demande le sink.
  PushEnabledToFrame(rfh);
}

void BasarunaaVideoTapTabHelper::PushEnabledToFrame(
    content::RenderFrameHost* rfh) {
  if (!rfh || !rfh->IsRenderFrameLive()) {
    return;
  }
  auto* prefs =
      user_prefs::UserPrefs::Get(web_contents()->GetBrowserContext());
  const bool enabled = prefs && prefs->GetBoolean(kBasarunaaEnabled);
  mojo::AssociatedRemote<mojom::VideoTapConfig> config;
  rfh->GetRemoteAssociatedInterfaces()->GetInterface(&config);
  config->SetEnabled(enabled);
}

void BasarunaaVideoTapTabHelper::OnEnabledPrefChanged() {
  web_contents()->ForEachRenderFrameHost(
      [this](content::RenderFrameHost* rfh) { PushEnabledToFrame(rfh); });
}

WEB_CONTENTS_USER_DATA_KEY_IMPL(BasarunaaVideoTapTabHelper);

}  // namespace basarunaa
