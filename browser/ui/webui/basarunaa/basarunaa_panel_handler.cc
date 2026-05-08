// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/browser/ui/webui/basarunaa/basarunaa_panel_handler.h"

#include <utility>

#include "brave/browser/ui/webui/basarunaa/basarunaa_panel_ui.h"
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
