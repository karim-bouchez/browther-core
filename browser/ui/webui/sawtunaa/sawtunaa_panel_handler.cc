// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/browser/ui/webui/sawtunaa/sawtunaa_panel_handler.h"

#include <utility>

#include "base/notreached.h"
#include "base/values.h"
#include "brave/browser/browther/browther_protected_content_tab_helper.h"
#include "base/strings/utf_string_conversions.h"
#include "brave/browser/browther/referral/browther_referral_access.h"
#include "brave/browser/browther/referral/browther_referral_files.h"
#include "brave/browser/ui/webui/browther_referral/browther_referral_dialog.h"
#include "brave/browser/browther/referral/browther_referral_launch.h"
#include "brave/browser/ui/webui/sawtunaa/sawtunaa_panel_ui.h"
#include "brave/browser/sawtunaa/sawtunaa_temporary_switch.h"
#include "brave/components/browther_analytics/browther_analytics_service.h"
#include "brave/components/browther_analytics/site_report.h"
#include "brave/components/constants/pref_names.h"
#include "base/strings/strcat.h"
#include "chrome/browser/browser_process.h"
#include "chrome/browser/ui/browser.h"
#include "chrome/browser/ui/browser_commands.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/singleton_tabs.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/webui/webui_embedding_context.h"
#include "components/prefs/pref_service.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_ui.h"
#include "url/gurl.h"

namespace {
// La seule voie qui reste pour du DRM : l'app autonome + son extension.
constexpr char kSawtunaaAppURL[] = "https://sawtunaa.devndin.com";
// Browther : chaînes de DIFFUSION dev&din (sens unique). Recopiées
// volontairement plutôt que centralisées — elles vivent déjà à l'identique dans
// le bandeau NTP, l'onboarding desktop, Android et iOS, et un header partagé
// traverserait quatre plateformes pour deux constantes. Si elles changent,
// `grep 0029Vb8ydkv5vKABH78PVX32`.
constexpr char kWhatsAppChannelURL[] =
    "https://whatsapp.com/channel/0029Vb8ydkv5vKABH78PVX32";
constexpr char kTelegramChannelURL[] = "https://t.me/devndin_nouveautes";
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
  const auto protected_state = GetProtectedContentState();
  auto* temporary = SawtunaaTemporarySwitch::GetForProfile(profile_);
  const bool temp_active = temporary && temporary->IsActive();
  const int32_t temp_remaining_ms =
      temp_active
          ? static_cast<int32_t>(temporary->Remaining().InMilliseconds())
          : 0;
  const bool extras_paused =
      browther_referral::IsMusicRemovalPaused(g_browser_process->local_state());
  // ⭐ Dire la pause DANS le panneau, avec SES propres surfaces (l'état sous
  // l'interrupteur, la description, une action) — ⛔ pas un encadré de plus :
  // l'écran du parrainage annonçait la pause et la popup n'en savait rien
  // (recette Karim, 2026-09-23), puis un encadré ambre ajouté par-dessus a été
  // écarté (« j'aime pas l'UI »). Les textes ne partent QUE quand c'est vrai.
  const auto text = [&](std::string_view key) {
    return extras_paused ? base::UTF16ToUTF8(browther_referral::Text(key))
                         : std::string();
  };
  std::move(callback).Run(
      enabled, temp_active, temp_remaining_ms, protected_state,
      report.can_report,
      report.domain, report.analytics_off, extras_paused,
      text(browther_referral::kPausedStatus),
      text(browther_referral::kPausedBody), text(browther_referral::kPausedCta));
}

void SawtunaaPanelHandler::ReportSite(ReportSiteCallback callback) {
  std::move(callback).Run(
      browther_analytics::ReportSite(GetActiveWebContents(), "sawtunaa"));
}

void SawtunaaPanelHandler::SetEnabled(bool enabled) {
  // Browther : la garde du parrainage, côté browser aussi — ⛔ un bouton
  // masqué ne suffit pas (§ 11.2). Éteindre, lui, reste toujours possible.
  if (enabled &&
      browther_referral::IsMusicRemovalPaused(g_browser_process->local_state())) {
    return;
  }
  profile_->GetPrefs()->SetBoolean(kSawtunaaEnabled, enabled);
  if (auto* analytics =
          browther_analytics::BrowtherAnalyticsService::GetInstance()) {
    base::DictValue props;
    props.Set("feature", "sawtunaa");
    props.Set("enabled", enabled);
    analytics->Track("feature_toggled", std::move(props));
  }
}

void SawtunaaPanelHandler::StartTemporary() {
  if (auto* temporary = SawtunaaTemporarySwitch::GetForProfile(profile_)) {
    temporary->Start();
  }
}

void SawtunaaPanelHandler::KeepTemporary() {
  if (auto* temporary = SawtunaaTemporarySwitch::GetForProfile(profile_)) {
    temporary->Keep();
  }
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

// 🔴 « Débloquer » ouvre la MODALE sur l'écran qui EXPLIQUE la pause (J0), ⛔
// plus l'écran Parrainage dans un onglet. Ça envoyait la personne sur une page
// de gestion avec un toast, alors qu'elle venait de voir sa fonctionnalité
// bloquée : perte de contexte totale (recette Karim, 2026-09-24). Elle doit
// d'abord lire POURQUOI c'est en pause et ce qu'on lui demande ; les trois
// façons viennent après, par le bouton de cet écran.
void SawtunaaPanelHandler::OpenReferralSupport() {
  content::WebContents* contents = GetActiveWebContents();
  CloseUI();
  if (contents) {
    // ⭐ `chosen` : la personne a cliqué elle-même, donc la fenêtre se ferme
    // normalement (croix, Échap) et n'arme pas le circuit des trois façons —
    // « une fenêtre qu'on pouvait fermer n'en ouvre pas une qu'on ne peut plus
    // fermer » (`docs/PARRAINAGE.md` § 12.16).
    browther_referral::ShowModal(contents, "paused", /*chosen=*/true);
  }
}

// Browther : « fonctionnalité en cours de développement » → suivre les canaux.
// Passe par le browser (et non par un <a href>) : la WebContents de la bulle
// n'a pas de délégué capable d'ouvrir un onglet, un lien ordinaire y est mort.
void SawtunaaPanelHandler::OpenFollowChannel(
    sawtunaa::mojom::FollowChannel channel) {
  auto* browser_window_interface = GetBrowserWindowInterface();
  Browser* browser = browser_window_interface
                         ? browser_window_interface->GetBrowserForMigrationOnly()
                         : nullptr;
  if (browser) {
    ShowSingletonTab(
        browser,
        GURL(channel == sawtunaa::mojom::FollowChannel::kWhatsApp
                 ? kWhatsAppChannelURL
                 : kTelegramChannelURL));
  }
  // Fermée même si on n'a pas pu ouvrir : laisser la bulle ouverte donnerait
  // l'impression que le clic n'a pas été pris.
  CloseUI();
}
