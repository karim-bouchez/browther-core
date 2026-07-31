// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/browser/ui/webui/sawtunaa/sawtunaa_panel_ui.h"

#include <memory>
#include <string>
#include <utility>

#include "base/check.h"
#include "brave/components/constants/webui_url_constants.h"
#include "brave/components/sawtunaa/resources/panel/grit/sawtunaa_panel_generated_map.h"
#include "brave/grit/brave_generated_resources.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/webui/theme_source.h"
#include "components/grit/brave_components_resources.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_ui.h"
#include "content/public/browser/web_ui_data_source.h"
#include "content/public/common/bindings_policy.h"
#include "content/public/common/url_constants.h"
#include "ui/webui/untrusted_web_ui_controller.h"
#include "ui/webui/webui_util.h"

SawtunaaPanelUI::SawtunaaPanelUI(content::WebUI* web_ui)
    : ui::UntrustedWebUIController(web_ui) {
  // From MojoWebUIController.
  web_ui->SetBindings(
      content::BindingsPolicySet({content::BindingsPolicyValue::kWebUi}));

  content::WebUIDataSource* source = content::WebUIDataSource::CreateAndAdd(
      web_ui->GetWebContents()->GetBrowserContext(), kSawtunaaPanelURL);

  webui::SetupWebUIDataSource(source, kSawtunaaPanelGenerated,
                              IDR_SAWTUNAA_PANEL_HTML);

  // Browther: expose les assets brand pour le header du panel.
  source->AddResourcePath("brand_icon.png", IDR_SAWTUNAA_BRAND_ICON);
  source->AddResourcePath("wordmark_white.png", IDR_SAWTUNAA_WORDMARK_WHITE);

  // Browther: localized strings consumed by sawtunaa_panel.html (via
  // $i18n{...}) and sawtunaa_panel.ts (via loadTimeData.getString).
  static constexpr struct {
    const char* name;
    int id;
  } kLocalizedStrings[] = {
      {"statusOn", IDS_SAWTUNAA_POPUP_STATUS_ON},
      {"statusOff", IDS_SAWTUNAA_POPUP_STATUS_OFF},
      {"description", IDS_SAWTUNAA_POPUP_DESCRIPTION},
      // Placeholder du status le temps du premier aller-retour mojo. Chaîne
      // PARTAGÉE avec le panel Basarunaa à dessein : « Loading… » n'a rien de
      // spécifique à une feature, et la dupliquer coûterait 66 traductions
      // pour un texte identique.
      {"loading", IDS_BASARUNAA_PANEL_LOADING},
      {"reloadHint", IDS_SAWTUNAA_POPUP_RELOAD_HINT},
      // Deux textes, pas un : sur kBlocked, dire « installez l'app » est FAUX
      // — la page ne joue pas ici, il faut d'abord l'ouvrir ailleurs.
      {"protectedHint", IDS_SAWTUNAA_POPUP_PROTECTED_HINT},
      {"protectedHintBlocked", IDS_SAWTUNAA_POPUP_PROTECTED_HINT_BLOCKED},
      {"installSawtunaa", IDS_BROWTHER_PROTECTED_CONTENT_GET_SAWTUNAA},
  };
  for (const auto& s : kLocalizedStrings) {
    source->AddLocalizedString(s.name, s.id);
  }

  source->OverrideContentSecurityPolicy(
      network::mojom::CSPDirectiveName::StyleSrc,
      std::string("style-src chrome-untrusted://resources "
                  "chrome-untrusted://theme "
                  "'unsafe-inline';"));

  source->OverrideContentSecurityPolicy(
      network::mojom::CSPDirectiveName::FontSrc,
      std::string("font-src "
                  "chrome-untrusted://resources;"));

  source->OverrideContentSecurityPolicy(
      network::mojom::CSPDirectiveName::ImgSrc,
      "img-src 'self' chrome-untrusted://resources;");

  Profile* profile = Profile::FromWebUI(web_ui);
  content::URLDataSource::Add(profile, std::make_unique<ThemeSource>(
                                           profile, /*serve_untrusted=*/true));
}

SawtunaaPanelUI::~SawtunaaPanelUI() = default;

WEB_UI_CONTROLLER_TYPE_IMPL(SawtunaaPanelUI)

void SawtunaaPanelUI::BindInterface(
    mojo::PendingReceiver<sawtunaa::mojom::PanelHandlerFactory> receiver) {
  panel_factory_receiver_.reset();
  panel_factory_receiver_.Bind(std::move(receiver));
}

void SawtunaaPanelUI::CreatePanelHandler(
    mojo::PendingReceiver<sawtunaa::mojom::PanelHandler> panel_receiver) {
  auto* profile = Profile::FromWebUI(web_ui());
  CHECK(profile);
  panel_handler_ = std::make_unique<SawtunaaPanelHandler>(
      std::move(panel_receiver), this, profile);
}

bool UntrustedSawtunaaPanelUIConfig::IsWebUIEnabled(
    content::BrowserContext* browser_context) {
  return true;
}

bool UntrustedSawtunaaPanelUIConfig::ShouldAutoResizeHost() {
  return true;
}

UntrustedSawtunaaPanelUIConfig::UntrustedSawtunaaPanelUIConfig()
    : DefaultTopChromeWebUIConfig(content::kChromeUIUntrustedScheme,
                                  kSawtunaaPanelHost) {}
