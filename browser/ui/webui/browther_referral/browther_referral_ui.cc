// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/browser/ui/webui/browther_referral/browther_referral_ui.h"

#include <memory>

#include "brave/browser/browther/referral/browther_referral_files.h"
#include "brave/browser/browther/referral/browther_referral_launch.h"
#include "brave/browser/ui/webui/browther_referral/browther_referral_handler.h"
#include "chrome/browser/profiles/profile.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_ui.h"
#include "content/public/browser/web_ui_data_source.h"
#include "services/network/public/mojom/content_security_policy.mojom.h"

BrowtherReferralUI::BrowtherReferralUI(content::WebUI* web_ui)
    : content::WebUIController(web_ui) {
  content::WebUIDataSource* source = content::WebUIDataSource::CreateAndAdd(
      Profile::FromWebUI(web_ui), browther_referral::kReferralHost);
  // Tout vient du disque (`browther_referral_files.h`), `index.html` compris.
  browther_referral::AddAppFiles(source, std::string());
  source->OverrideContentSecurityPolicy(
      network::mojom::CSPDirectiveName::ScriptSrc, "script-src 'self';");
  // Les styles de l'app sont injectés par elle (feuilles construites) ; les
  // attributs `style` de React demandent `unsafe-inline`.
  source->OverrideContentSecurityPolicy(
      network::mojom::CSPDirectiveName::StyleSrc,
      "style-src 'self' 'unsafe-inline';");
  source->OverrideContentSecurityPolicy(
      network::mojom::CSPDirectiveName::ImgSrc,
      "img-src 'self' data: blob:;");
  // ⛔ L'app n'appelle AUCUN service elle-même (tout passe par le pont, qui
  // garde le jeton du compte) : seuls ses propres fichiers de textes.
  source->OverrideContentSecurityPolicy(
      network::mojom::CSPDirectiveName::ConnectSrc, "connect-src 'self';");
  // Le QR (SVG construit par React) et les confettis n'écrivent aucun HTML ;
  // Trusted Types coupé comme sur l'introduction (même famille de page).
  source->DisableTrustedTypesCSP();

  web_ui->AddMessageHandler(std::make_unique<BrowtherReferralHandler>(
      BrowtherReferralHandler::Host::kPage));
}

BrowtherReferralUI::~BrowtherReferralUI() = default;

// static
void BrowtherReferralUI::AddToHostPage(content::WebUI* web_ui,
                                       content::WebUIDataSource* source,
                                       bool is_new_tab) {
  browther_referral::AddAppFiles(source, "browther-referral/");
  web_ui->AddMessageHandler(std::make_unique<BrowtherReferralHandler>(
      is_new_tab ? BrowtherReferralHandler::Host::kNewTab
                 : BrowtherReferralHandler::Host::kWelcome));
}

WEB_UI_CONTROLLER_TYPE_IMPL(BrowtherReferralUI)
