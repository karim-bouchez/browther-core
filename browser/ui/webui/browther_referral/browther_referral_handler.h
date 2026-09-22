// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_BROWSER_UI_WEBUI_BROWTHER_REFERRAL_BROWTHER_REFERRAL_HANDLER_H_
#define BRAVE_BROWSER_UI_WEBUI_BROWTHER_REFERRAL_BROWTHER_REFERRAL_HANDLER_H_

#include <string>

#include "base/memory/weak_ptr.h"
#include "base/values.h"
#include "content/public/browser/web_ui_message_handler.h"

// Le pont entre l'app web du parrainage (`private/webui/referral/`) et le
// navigateur — le MÊME pour les trois pages qui l'accueillent : l'écran
// Parrainage (`browther://referral`), le Nouvel Onglet (les écrans du flow au
// moment de mérite) et l'introduction (l'étape « code d'un proche »).
//
// Un seul message, `browtherReferral(id, méthode, charge)` ; la réponse revient
// par `browtherReferralReply(id, ok, résultat)`. ⭐ Le pont ne DÉCIDE rien — les
// règles (accès, cadence, rappels, paliers) sont dans l'app, testées à part — :
// il fournit ce que seul le navigateur a (identité d'appareil, faits d'usage,
// défaut exact, verrou du jour, stockage, réseau vers trois services dev&din,
// compte chiffré) et exécute des gestes (ouvrir, copier, régler par défaut).
class BrowtherReferralHandler : public content::WebUIMessageHandler {
 public:
  enum class Host { kPage, kNewTab, kWelcome };

  explicit BrowtherReferralHandler(Host host);
  BrowtherReferralHandler(const BrowtherReferralHandler&) = delete;
  BrowtherReferralHandler& operator=(const BrowtherReferralHandler&) = delete;
  ~BrowtherReferralHandler() override;

  // content::WebUIMessageHandler:
  void RegisterMessages() override;
  void OnJavascriptDisallowed() override;

 private:
  void HandleCall(const base::ListValue& args);
  void Reply(const std::string& id, bool ok, base::Value result);

  base::Value BuildContext();
  base::Value StoreSet(const base::DictValue& payload);
  base::Value ClaimDay(const base::DictValue& payload);
  base::Value Track(const base::DictValue& payload);
  base::Value OpenPage(const base::DictValue& payload);
  base::Value OpenUrl(const base::DictValue& payload);
  base::Value CopyText(const base::DictValue& payload);
  base::Value EnforcePause();
  base::Value Recette(const base::DictValue& payload);
  void Request(const std::string& id, const base::DictValue& payload);
  void SetDefaultBrowser(const std::string& id);
  void CheckDefault(const std::string& id);

  Host host_;
  base::WeakPtrFactory<BrowtherReferralHandler> weak_factory_{this};
};

#endif  // BRAVE_BROWSER_UI_WEBUI_BROWTHER_REFERRAL_BROWTHER_REFERRAL_HANDLER_H_
