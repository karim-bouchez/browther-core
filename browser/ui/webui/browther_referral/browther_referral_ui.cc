// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/browser/ui/webui/browther_referral/browther_referral_ui.h"

#include <memory>
#include <string>

#include "brave/browser/browther/referral/browther_referral_files.h"
#include "brave/browser/browther/referral/browther_referral_launch.h"
#include "brave/browser/ui/webui/browther_referral/browther_referral_handler.h"
#include "chrome/browser/profiles/profile.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_ui.h"
#include "content/public/browser/web_ui_data_source.h"
#include "net/base/url_util.h"
#include "services/network/public/mojom/content_security_policy.mojom.h"

namespace {

// Le site de Browther : le manifeste et les vidéos du statut WhatsApp.
constexpr char kSiteOrigin[] = "https://browther.devndin.com";

// 🔴 La fenêtre de partage MONTRE ce qui partira du téléphone
// (`ShareWindow.tsx`, `devndin/docs/PARRAINAGE.md` § 12.45) : elle lit UN
// fichier public du site (le manifeste des vidéos — aucun jeton n'y part,
// ⛔ ce n'est pas un appel de service : ceux-là passent par le pont), lit la
// vidéo en APERÇU par `<video>` (⛔ jamais téléchargée), et dessine l'image
// du statut avec ses polices, embarquées dans `app.js` (`data:`).
// `connect_base` = ce que la page autorisait déjà (le Nouvel Onglet a les
// sources de Chromium, `ui/webui/webui_util.cc`) : on y AJOUTE le site ;
// `'self'` reste aussi pour les médias et les polices.
void AllowSharePreview(content::WebUIDataSource* source,
                       const std::string& connect_base) {
  source->OverrideContentSecurityPolicy(
      network::mojom::CSPDirectiveName::ConnectSrc,
      connect_base + " " + kSiteOrigin + ";");
  source->OverrideContentSecurityPolicy(
      network::mojom::CSPDirectiveName::MediaSrc,
      std::string("media-src 'self' ") + kSiteOrigin + ";");
  source->OverrideContentSecurityPolicy(
      network::mojom::CSPDirectiveName::FontSrc,
      "font-src chrome://resources 'self' data:;");
}

}  // namespace

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
  // garde le jeton du compte) : ses propres fichiers de textes, et UN fichier
  // public du site — le manifeste des vidéos du statut WhatsApp, que la
  // fenêtre de partage lit pour MONTRER la vidéo (`ShareWindow.tsx`,
  // `devndin/docs/PARRAINAGE.md` § 12.45). Aucun jeton n'y part.
  AllowSharePreview(source, "connect-src 'self'");
  // Le QR (SVG construit par React) et les confettis n'écrivent aucun HTML ;
  // Trusted Types coupé comme sur l'introduction (même famille de page).
  source->DisableTrustedTypesCSP();

  // ⚠️ La MÊME adresse sert l'écran Parrainage et la modale de fenêtre : c'est
  // `?host=modal` qui les distingue (`browther_referral_dialog.cc`). L'app n'y
  // monte alors que le flow, et le pont refuse d'y rouvrir une modale.
  std::string host_param;
  const bool modal =
      net::GetValueForKeyInQuery(web_ui->GetWebContents()->GetVisibleURL(),
                                 "host", &host_param) &&
      host_param == "modal";
  web_ui->AddMessageHandler(std::make_unique<BrowtherReferralHandler>(
      modal ? BrowtherReferralHandler::Host::kModal
            : BrowtherReferralHandler::Host::kPage));
}

BrowtherReferralUI::~BrowtherReferralUI() = default;

// static
void BrowtherReferralUI::AddToHostPage(content::WebUI* web_ui,
                                       content::WebUIDataSource* source,
                                       bool is_new_tab) {
  browther_referral::AddAppFiles(source, "browther-referral/");
  // Le partage proposé s'ouvre sur le Nouvel Onglet (⛔ jamais dans
  // l'introduction : elle a ses propres médias, on n'y touche pas).
  // ⚠️ Appelé APRÈS les réglages de la page (`new_tab_page_initializer.cc`) :
  // ce qui suit les complète, les sources de connexion de Chromium y restent.
  if (is_new_tab) {
    AllowSharePreview(source,
                      "connect-src chrome://webui-test chrome://resources "
                      "chrome://theme 'self'");
  }
  web_ui->AddMessageHandler(std::make_unique<BrowtherReferralHandler>(
      is_new_tab ? BrowtherReferralHandler::Host::kNewTab
                 : BrowtherReferralHandler::Host::kWelcome));
}

WEB_UI_CONTROLLER_TYPE_IMPL(BrowtherReferralUI)
