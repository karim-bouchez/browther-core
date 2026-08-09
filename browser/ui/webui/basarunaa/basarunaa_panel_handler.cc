// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/browser/ui/webui/basarunaa/basarunaa_panel_handler.h"

#include <utility>

#include "brave/browser/browther/browther_protected_content_tab_helper.h"
#include "brave/browser/ui/webui/basarunaa/basarunaa_panel_ui.h"
#include "brave/components/browther_analytics/site_report.h"
#include "brave/components/constants/pref_names.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/webui/webui_embedding_context.h"
#include "components/prefs/pref_service.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_ui.h"

BasarunaaPanelHandler::BasarunaaPanelHandler(
    mojo::PendingReceiver<basarunaa::mojom::PanelHandler> receiver,
    BasarunaaPanelUI* panel_controller,
    Profile* profile)
    : receiver_(this, std::move(receiver)),
      panel_controller_(panel_controller),
      profile_(profile) {}

BasarunaaPanelHandler::~BasarunaaPanelHandler() = default;

BrowserWindowInterface* BasarunaaPanelHandler::GetBrowserWindowInterface() {
  // Volontairement re-résolu à chaque appel : la WebContents du panel est mise
  // en cache et peut changer de fenêtre entre deux ouvertures.
  return webui::GetBrowserWindowInterface(
      panel_controller_->web_ui()->GetWebContents());
}

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

void BasarunaaPanelHandler::GetProtectedContent(
    GetProtectedContentCallback callback) {
  // Même condition que le badge ambre de BasarunaaActionView, à la lettre :
  // feature ON + verdict DRM rendu sur l'onglet actif. Pas de gate
  // `native_tap_active` (contrairement à Sawtunaa) : le floutage est coupé sur
  // du DRM partout, il n'existe aucune voie de repli.
  if (!profile_->GetPrefs()->GetBoolean(kBasarunaaEnabled)) {
    std::move(callback).Run(false);
    return;
  }
  auto* browser_window_interface = GetBrowserWindowInterface();
  content::WebContents* web_contents =
      browser_window_interface
          ? browser_window_interface->GetTabStripModel()->GetActiveWebContents()
          : nullptr;
  std::move(callback).Run(
      BrowtherProtectedContentTabHelper::StateFor(web_contents) !=
      BrowtherProtectedContentTabHelper::ProtectedState::kUnknown);
}

content::WebContents* BasarunaaPanelHandler::GetActiveWebContents() {
  auto* browser_window_interface = GetBrowserWindowInterface();
  return browser_window_interface
             ? browser_window_interface->GetTabStripModel()
                   ->GetActiveWebContents()
             : nullptr;
}

void BasarunaaPanelHandler::GetReportSiteState(
    GetReportSiteStateCallback callback) {
  const auto state =
      browther_analytics::GetSiteReportState(GetActiveWebContents());
  std::move(callback).Run(state.can_report, state.domain, state.analytics_off);
}

void BasarunaaPanelHandler::ReportSite(ReportSiteCallback callback) {
  std::move(callback).Run(
      browther_analytics::ReportSite(GetActiveWebContents(), "basarunaa"));
}

void BasarunaaPanelHandler::GetMode(GetModeCallback callback) {
  std::move(callback).Run(profile_->GetPrefs()->GetString(kBasarunaaMode));
}

void BasarunaaPanelHandler::SetMode(const std::string& mode) {
  profile_->GetPrefs()->SetString(kBasarunaaMode, mode);
}

void BasarunaaPanelHandler::GetCensorEyes(GetCensorEyesCallback callback) {
  std::move(callback).Run(
      profile_->GetPrefs()->GetBoolean(kBasarunaaCensorEyes));
}

void BasarunaaPanelHandler::SetCensorEyes(bool enabled) {
  profile_->GetPrefs()->SetBoolean(kBasarunaaCensorEyes, enabled);
}

void BasarunaaPanelHandler::GetNsfwEnabled(GetNsfwEnabledCallback callback) {
  std::move(callback).Run(
      profile_->GetPrefs()->GetBoolean(kBasarunaaNsfwEnabled));
}

void BasarunaaPanelHandler::SetNsfwEnabled(bool enabled) {
  profile_->GetPrefs()->SetBoolean(kBasarunaaNsfwEnabled, enabled);
}

void BasarunaaPanelHandler::GetSliders(GetSlidersCallback callback) {
  auto* prefs = profile_->GetPrefs();
  std::move(callback).Run(prefs->GetDouble(kBasarunaaConfBody),
                          prefs->GetDouble(kBasarunaaGenderCertainty),
                          prefs->GetDouble(kBasarunaaSentinelConf),
                          prefs->GetDouble(kBasarunaaMinSkeleton),
                          prefs->GetDouble(kBasarunaaNsfwConf),
                          prefs->GetDouble(kBasarunaaNudenetConf));
}

void BasarunaaPanelHandler::SetConfBody(double value) {
  profile_->GetPrefs()->SetDouble(kBasarunaaConfBody, value);
}

void BasarunaaPanelHandler::SetGenderCertainty(double value) {
  profile_->GetPrefs()->SetDouble(kBasarunaaGenderCertainty, value);
}

void BasarunaaPanelHandler::SetSentinelConf(double value) {
  profile_->GetPrefs()->SetDouble(kBasarunaaSentinelConf, value);
}

void BasarunaaPanelHandler::SetMinSkeleton(double value) {
  profile_->GetPrefs()->SetDouble(kBasarunaaMinSkeleton, value);
}

void BasarunaaPanelHandler::SetNsfwConf(double value) {
  profile_->GetPrefs()->SetDouble(kBasarunaaNsfwConf, value);
}

void BasarunaaPanelHandler::SetNudenetConf(double value) {
  profile_->GetPrefs()->SetDouble(kBasarunaaNudenetConf, value);
}

void BasarunaaPanelHandler::GetDevSettings(GetDevSettingsCallback callback) {
  auto* prefs = profile_->GetPrefs();
  std::move(callback).Run(prefs->GetString(kBasarunaaDebugMode),
                          prefs->GetBoolean(kBasarunaaCaptureMode),
                          prefs->GetBoolean(kBasarunaaBlurEnabled));
}

void BasarunaaPanelHandler::SetDebugMode(const std::string& mode) {
  profile_->GetPrefs()->SetString(kBasarunaaDebugMode, mode);
}

void BasarunaaPanelHandler::SetCaptureMode(bool enabled) {
  profile_->GetPrefs()->SetBoolean(kBasarunaaCaptureMode, enabled);
}

void BasarunaaPanelHandler::SetBlurEnabled(bool enabled) {
  profile_->GetPrefs()->SetBoolean(kBasarunaaBlurEnabled, enabled);
}
