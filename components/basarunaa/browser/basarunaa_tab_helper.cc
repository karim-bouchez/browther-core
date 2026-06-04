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
  // qui re-push l'intégralité de la config (cheap : 6 fields struct passés
  // en Mojo, négligeable vs un round-trip par pref).
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

  // Jalon 2.D créera l'instance Java BasarunaaTabAnalyzer ici. Pour 2.C,
  // java_analyzer_ reste null et les méthodes Mojo loggent seulement.
}

void BasarunaaTabHelper::RenderFrameCreated(content::RenderFrameHost* rfh) {
  PushConfigToFrame(rfh);
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
  // Jalon 2.D détruira l'instance Java ici.
}

// --- android::mojom::BasarunaaAndroid stubs (Jalon 2.C — log-only) ---
// Le bridge Java vers BasarunaaTabAnalyzer arrive en 2.D.

void BasarunaaTabHelper::LogJs(const std::string& message) {
  LOG(INFO) << "[Basarunaa/JS] " << message;
}

void BasarunaaTabHelper::EmitMetric(const std::string& metric_json) {
  LOG(INFO) << "[Basarunaa/metric] " << metric_json;
}

void BasarunaaTabHelper::AnalyzeImage(int32_t image_id,
                                      const std::vector<uint8_t>& image_bytes) {
  LOG(INFO) << "[Basarunaa/AnalyzeImage] id=" << image_id
            << " bytes=" << image_bytes.size();
  // Jalon 2.D : PostTask Java pool + appel Java_BasarunaaTabAnalyzer_analyzeImage.
}

void BasarunaaTabHelper::CancelAnalyze(int32_t image_id) {
  LOG(INFO) << "[Basarunaa/CancelAnalyze] id=" << image_id;
}

void BasarunaaTabHelper::PageReset(const std::string& url) {
  LOG(INFO) << "[Basarunaa/PageReset] " << url;
}

WEB_CONTENTS_USER_DATA_KEY_IMPL(BasarunaaTabHelper);

}  // namespace basarunaa
