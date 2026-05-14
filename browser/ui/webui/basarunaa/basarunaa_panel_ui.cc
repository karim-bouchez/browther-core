// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/browser/ui/webui/basarunaa/basarunaa_panel_ui.h"

#include <memory>
#include <string>
#include <utility>

#include "base/check.h"
#include "brave/components/basarunaa/resources/panel/grit/basarunaa_panel_generated_map.h"
#include "brave/components/constants/webui_url_constants.h"
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

BasarunaaPanelUI::BasarunaaPanelUI(content::WebUI* web_ui)
    : ui::UntrustedWebUIController(web_ui) {
  // From MojoWebUIController.
  web_ui->SetBindings(
      content::BindingsPolicySet({content::BindingsPolicyValue::kWebUi}));

  content::WebUIDataSource* source = content::WebUIDataSource::CreateAndAdd(
      web_ui->GetWebContents()->GetBrowserContext(), kBasarunaaPanelURL);

  webui::SetupWebUIDataSource(source, kBasarunaaPanelGenerated,
                              IDR_BASARUNAA_PANEL_HTML);

  // Browther: expose les assets brand pour le header du panel.
  source->AddResourcePath("brand_icon.png", IDR_BASARUNAA_BRAND_ICON);
  source->AddResourcePath("wordmark_white.png",
                          IDR_BASARUNAA_WORDMARK_WHITE);

  // Browther: localized strings consumed by basarunaa_panel.html (via
  // $i18n{...}) and basarunaa_panel.ts (via loadTimeData.getString).
  static constexpr struct {
    const char* name;
    int id;
  } kLocalizedStrings[] = {
      {"statusOn", IDS_BASARUNAA_POPUP_STATUS_ON},
      {"statusOff", IDS_BASARUNAA_POPUP_STATUS_OFF},
      {"description", IDS_BASARUNAA_POPUP_DESCRIPTION},
      {"modeLabel", IDS_BASARUNAA_PANEL_MODE_LABEL},
      {"modeFemale", IDS_BASARUNAA_PANEL_MODE_FEMALE},
      {"modeMale", IDS_BASARUNAA_PANEL_MODE_MALE},
      {"modeAll", IDS_BASARUNAA_PANEL_MODE_ALL},
      {"detectionLabel", IDS_BASARUNAA_PANEL_DETECTION_LABEL},
      {"confBody", IDS_BASARUNAA_PANEL_CONF_BODY},
      {"confFace", IDS_BASARUNAA_PANEL_CONF_FACE},
      {"genderCertainty", IDS_BASARUNAA_PANEL_GENDER_CERTAINTY},
      {"loading", IDS_BASARUNAA_PANEL_LOADING},
      {"toggleAria", IDS_BASARUNAA_PANEL_TOGGLE_ARIA},
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

BasarunaaPanelUI::~BasarunaaPanelUI() = default;

WEB_UI_CONTROLLER_TYPE_IMPL(BasarunaaPanelUI)

void BasarunaaPanelUI::BindInterface(
    mojo::PendingReceiver<basarunaa::mojom::PanelHandlerFactory> receiver) {
  panel_factory_receiver_.reset();
  panel_factory_receiver_.Bind(std::move(receiver));
}

void BasarunaaPanelUI::CreatePanelHandler(
    mojo::PendingReceiver<basarunaa::mojom::PanelHandler> panel_receiver) {
  auto* profile = Profile::FromWebUI(web_ui());
  CHECK(profile);
  panel_handler_ = std::make_unique<BasarunaaPanelHandler>(
      std::move(panel_receiver), this, profile);
}

bool UntrustedBasarunaaPanelUIConfig::IsWebUIEnabled(
    content::BrowserContext* browser_context) {
  return true;
}

bool UntrustedBasarunaaPanelUIConfig::ShouldAutoResizeHost() {
  return true;
}

UntrustedBasarunaaPanelUIConfig::UntrustedBasarunaaPanelUIConfig()
    : DefaultTopChromeWebUIConfig(content::kChromeUIUntrustedScheme,
                                  kBasarunaaPanelHost) {}
