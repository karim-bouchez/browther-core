// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_BROWSER_UI_WEBUI_BROWTHER_REFERRAL_BROWTHER_REFERRAL_UI_H_
#define BRAVE_BROWSER_UI_WEBUI_BROWTHER_REFERRAL_BROWTHER_REFERRAL_UI_H_

#include "content/public/browser/web_ui_controller.h"

namespace content {
class WebUIDataSource;
}

// L'écran « Parrainage » (écran 6 de `PARRAINAGE.md`, en onglets) —
// `browther://referral`, l'entrée permanente du menu ⋯ (§ 12.12). Page de
// CONFIANCE plein onglet (`chrome://`), ⛔ pas une bulle : on y revient, on la
// garde ouverte le temps d'une invitation.
class BrowtherReferralUI : public content::WebUIController {
 public:
  explicit BrowtherReferralUI(content::WebUI* web_ui);
  BrowtherReferralUI(const BrowtherReferralUI&) = delete;
  BrowtherReferralUI& operator=(const BrowtherReferralUI&) = delete;
  ~BrowtherReferralUI() override;

  // Ce que les pages hôtes (Nouvel Onglet, introduction) ajoutent pour
  // accueillir l'app : ses fichiers sous `browther-referral/` et le pont.
  static void AddToHostPage(content::WebUI* web_ui,
                            content::WebUIDataSource* source,
                            bool is_new_tab);

  WEB_UI_CONTROLLER_TYPE_DECL();
};

#endif  // BRAVE_BROWSER_UI_WEBUI_BROWTHER_REFERRAL_BROWTHER_REFERRAL_UI_H_
