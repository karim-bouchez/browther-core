// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/browser/ui/webui/basarunaa/basarunaa_panel_handler.h"

#include <utility>

#include "base/functional/bind.h"
#include "base/logging.h"
#include "base/task/thread_pool.h"
#include "brave/browser/basarunaa/basarunaa_service_factory.h"
#include "brave/browser/ui/webui/basarunaa/basarunaa_panel_ui.h"
#include "brave/components/basarunaa/core/basarunaa_service.h"
#include "brave/components/constants/pref_names.h"
#include "components/prefs/pref_service.h"

BasarunaaPanelHandler::BasarunaaPanelHandler(
    mojo::PendingReceiver<basarunaa::mojom::PanelHandler> receiver,
    BasarunaaPanelUI* panel_controller,
    Profile* profile)
    : receiver_(this, std::move(receiver)),
      panel_controller_(panel_controller),
      profile_(profile) {}

BasarunaaPanelHandler::~BasarunaaPanelHandler() = default;

void BasarunaaPanelHandler::ShowUI() {
  if (auto embedder = panel_controller_->embedder()) {
    embedder->ShowUI();
  }
}

void BasarunaaPanelHandler::CloseUI() {
  if (auto embedder = panel_controller_->embedder()) {
    embedder->CloseUI();
  }
}

void BasarunaaPanelHandler::GetEnabled(GetEnabledCallback callback) {
  std::move(callback).Run(profile_->GetPrefs()->GetBoolean(kBasarunaaEnabled));
}

void BasarunaaPanelHandler::SetEnabled(bool enabled) {
  profile_->GetPrefs()->SetBoolean(kBasarunaaEnabled, enabled);
}

void BasarunaaPanelHandler::GetMode(GetModeCallback callback) {
  std::move(callback).Run(profile_->GetPrefs()->GetString(kBasarunaaMode));
}

void BasarunaaPanelHandler::SetMode(const std::string& mode) {
  profile_->GetPrefs()->SetString(kBasarunaaMode, mode);
}

void BasarunaaPanelHandler::GetSliders(GetSlidersCallback callback) {
  auto* prefs = profile_->GetPrefs();
  std::move(callback).Run(prefs->GetDouble(kBasarunaaConfBody),
                          prefs->GetDouble(kBasarunaaConfFace),
                          prefs->GetDouble(kBasarunaaGenderCertainty));
}

void BasarunaaPanelHandler::SetConfBody(double value) {
  profile_->GetPrefs()->SetDouble(kBasarunaaConfBody, value);
}

void BasarunaaPanelHandler::SetConfFace(double value) {
  profile_->GetPrefs()->SetDouble(kBasarunaaConfFace, value);
}

void BasarunaaPanelHandler::SetGenderCertainty(double value) {
  profile_->GetPrefs()->SetDouble(kBasarunaaGenderCertainty, value);
}

void BasarunaaPanelHandler::GetDevSettings(GetDevSettingsCallback callback) {
  auto* prefs = profile_->GetPrefs();
  std::move(callback).Run(prefs->GetString(kBasarunaaDebugMode),
                          prefs->GetBoolean(kBasarunaaCaptureMode));
}

void BasarunaaPanelHandler::SetDebugMode(const std::string& mode) {
  profile_->GetPrefs()->SetString(kBasarunaaDebugMode, mode);
}

void BasarunaaPanelHandler::SetCaptureMode(bool enabled) {
  profile_->GetPrefs()->SetBoolean(kBasarunaaCaptureMode, enabled);
}

void BasarunaaPanelHandler::AnalyzeTestImage(
    AnalyzeTestImageCallback callback) {
  LOG(INFO) << "[Basarunaa] AnalyzeTestImage() reached panel handler";
  auto* service =
      basarunaa::BasarunaaServiceFactory::GetForProfile(profile_);
  if (!service) {
    LOG(WARNING) << "[Basarunaa] no service for profile";
    std::move(callback).Run(0);
    return;
  }
  // Schedule on a MayBlock pool — the service reads a file synchronously and
  // we cannot block the UI thread. ORT's Session::Run is thread-safe and the
  // service members are not mutated during inference, so passing the raw
  // pointer is safe for the lifetime of the profile.
  base::ThreadPool::PostTaskAndReplyWithResult(
      FROM_HERE, {base::MayBlock(), base::TaskPriority::USER_VISIBLE},
      base::BindOnce(
          [](basarunaa::BasarunaaService* svc) {
            return static_cast<int>(svc->AnalyzeTestImage().size());
          },
          base::Unretained(service)),
      std::move(callback));
}
