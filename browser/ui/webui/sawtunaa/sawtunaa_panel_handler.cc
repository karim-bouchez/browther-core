// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/browser/ui/webui/sawtunaa/sawtunaa_panel_handler.h"

#include <utility>

#include "base/notreached.h"
#include "base/values.h"
#include "brave/browser/browther/browther_protected_content_tab_helper.h"
#include "brave/browser/ui/webui/sawtunaa/sawtunaa_panel_ui.h"
#include "brave/components/browther_analytics/browther_analytics_service.h"
#include "brave/components/browther_analytics/site_report.h"
#include "brave/components/constants/pref_names.h"
#include "chrome/browser/ui/browser.h"
#include "chrome/browser/ui/browser_commands.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/recently_audible_helper.h"
#include "chrome/browser/ui/singleton_tabs.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/webui/webui_embedding_context.h"
#include "components/prefs/pref_service.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_ui.h"
#include "ui/base/window_open_disposition.h"
#include "url/gurl.h"

namespace {
// La seule voie qui reste pour du DRM : l'app autonome + son extension.
constexpr char kSawtunaaAppURL[] = "https://sawtunaa.devndin.com";
}  // namespace

SawtunaaPanelHandler::SawtunaaPanelHandler(
    mojo::PendingReceiver<sawtunaa::mojom::PanelHandler> receiver,
    SawtunaaPanelUI* panel_controller,
    Profile* profile)
    : receiver_(this, std::move(receiver)),
      panel_controller_(panel_controller),
      profile_(profile) {}

SawtunaaPanelHandler::~SawtunaaPanelHandler() = default;

BrowserWindowInterface* SawtunaaPanelHandler::GetBrowserWindowInterface() {
  // Volontairement re-résolu à chaque appel : la WebContents du panel est mise
  // en cache et peut changer de fenêtre entre deux ouvertures.
  return webui::GetBrowserWindowInterface(
      panel_controller_->web_ui()->GetWebContents());
}

content::WebContents* SawtunaaPanelHandler::GetActiveWebContents() {
  auto* browser_window_interface = GetBrowserWindowInterface();
  return browser_window_interface
             ? browser_window_interface->GetTabStripModel()
                   ->GetActiveWebContents()
             : nullptr;
}

void SawtunaaPanelHandler::ShowUI() {
  if (auto embedder = panel_controller_->embedder()) {
    embedder->ShowUI();
  }
}

void SawtunaaPanelHandler::CloseUI() {
  if (auto embedder = panel_controller_->embedder()) {
    embedder->CloseUI();
  }
}

bool SawtunaaPanelHandler::ShouldShowReloadHint() {
  // Uniquement pour le tap natif : ailleurs (Windows / anciens builds), c'est
  // l'extension MV3 qui traite l'audio et elle prend le toggle en compte sans
  // reload.
  if (!profile_->GetPrefs()->GetBoolean(kSawtunaaNativeTapActive)) {
    return false;
  }
  content::WebContents* web_contents = GetActiveWebContents();
  if (!web_contents) {
    return false;
  }
  // « Un média joue dans l'onglet » : le helper de la tab strip retient aussi
  // le média mis en pause (WasEverAudible) — son WebMediaPlayer existe déjà,
  // donc lui aussi restera non tappé jusqu'au reload.
  auto* audible = RecentlyAudibleHelper::FromWebContents(web_contents);
  return audible ? audible->WasEverAudible()
                 : web_contents->IsCurrentlyAudible();
}

sawtunaa::mojom::ProtectedContentState
SawtunaaPanelHandler::GetProtectedContentState() {
  // Même gate que le badge ambre : sans tap natif (Windows aujourd'hui), c'est
  // l'extension bundlée qui capture via chrome.tabCapture — et elle, elle
  // fonctionne sur du DRM. Annoncer une panne là-bas serait faux.
  auto* prefs = profile_->GetPrefs();
  if (!prefs->GetBoolean(kSawtunaaEnabled) ||
      !prefs->GetBoolean(kSawtunaaNativeTapActive)) {
    return sawtunaa::mojom::ProtectedContentState::kNone;
  }
  switch (BrowtherProtectedContentTabHelper::StateFor(GetActiveWebContents())) {
    case BrowtherProtectedContentTabHelper::ProtectedState::kUnknown:
      return sawtunaa::mojom::ProtectedContentState::kNone;
    case BrowtherProtectedContentTabHelper::ProtectedState::kBlocked:
      return sawtunaa::mojom::ProtectedContentState::kBlocked;
    case BrowtherProtectedContentTabHelper::ProtectedState::kUnfiltered:
      return sawtunaa::mojom::ProtectedContentState::kUnfiltered;
  }
  NOTREACHED();
}

void SawtunaaPanelHandler::GetState(GetStateCallback callback) {
  const bool enabled = profile_->GetPrefs()->GetBoolean(kSawtunaaEnabled);
  const auto report =
      browther_analytics::GetSiteReportState(GetActiveWebContents());
  std::move(callback).Run(enabled, enabled && ShouldShowReloadHint(),
                          GetProtectedContentState(), report.can_report,
                          report.domain, report.analytics_off);
}

void SawtunaaPanelHandler::ReportSite(ReportSiteCallback callback) {
  std::move(callback).Run(
      browther_analytics::ReportSite(GetActiveWebContents(), "sawtunaa"));
}

void SawtunaaPanelHandler::SetEnabled(bool enabled) {
  profile_->GetPrefs()->SetBoolean(kSawtunaaEnabled, enabled);
  if (auto* analytics =
          browther_analytics::BrowtherAnalyticsService::GetInstance()) {
    base::DictValue props;
    props.Set("feature", "sawtunaa");
    props.Set("enabled", enabled);
    analytics->Track("feature_toggled", std::move(props));
  }
}

void SawtunaaPanelHandler::ReloadActiveTab() {
  auto* browser_window_interface = GetBrowserWindowInterface();
  Browser* browser = browser_window_interface
                         ? browser_window_interface->GetBrowserForMigrationOnly()
                         : nullptr;
  if (browser) {
    chrome::Reload(browser, WindowOpenDisposition::CURRENT_TAB);
  }
  // Fermée même si on n'a pas pu recharger : l'utilisateur a cliqué, laisser la
  // bulle ouverte donnerait l'impression que le clic n'a pas été pris.
  CloseUI();
}

void SawtunaaPanelHandler::OpenSawtunaaAppPage() {
  auto* browser_window_interface = GetBrowserWindowInterface();
  Browser* browser = browser_window_interface
                         ? browser_window_interface->GetBrowserForMigrationOnly()
                         : nullptr;
  if (browser) {
    ShowSingletonTab(browser, GURL(kSawtunaaAppURL));
  }
  CloseUI();
}
