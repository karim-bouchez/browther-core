// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/browser/ui/views/toolbar/basarunaa_panel_controller.h"

#include <optional>
#include <string>

#include "base/check.h"
#include "brave/browser/ui/views/frame/brave_browser_view.h"
#include "brave/components/constants/webui_url_constants.h"
#include "brave/grit/brave_generated_resources.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser.h"
#include "chrome/browser/ui/views/bubble/webui_bubble_manager.h"
#include "ui/views/bubble/bubble_border.h"
#include "url/gurl.h"

BasarunaaPanelController::BasarunaaPanelController(
    BraveBrowserView* browser_view)
    : browser_view_(browser_view) {
  DCHECK(browser_view_);
}

BasarunaaPanelController::~BasarunaaPanelController() = default;

void BasarunaaPanelController::ShowBasarunaaPanel() {
  // 1:1 mirror of BraveVPNPanelController::ShowBraveVPNPanel.
  auto* anchor_view = browser_view_->GetAnchorViewForBasarunaaPanel();
  if (!anchor_view) {
    return;
  }

  if (!webui_bubble_manager_) {
    webui_bubble_manager_ = WebUIBubbleManager::Create<BasarunaaPanelUI>(
        anchor_view, browser_view_->browser(), GURL(kBasarunaaPanelURL),
        IDS_BASARUNAA_PANEL_NAME);
  }

  if (webui_bubble_manager_->GetBubbleWidget()) {
    webui_bubble_manager_->CloseBubble();
    return;
  }

  // [Browther 2026-08-09] TOP_CENTER au lieu du TOP_RIGHT par défaut : ancrée à
  // droite, la bulle partait entièrement vers la gauche et l'icône cliquée se
  // retrouvait pile dans son coin haut-droit — ça ne se lit pas comme « cette
  // bulle sort de ce bouton ». Centrée sous l'icône, le lien est immédiat.
  // Pas de valeur en dur : quand il n'y a pas la place à droite (icône près du
  // bord de l'écran), Views recale la bulle tout seul pour la garder visible —
  // on retombe alors sur l'ancien rendu, ce qui est le comportement voulu.
  // ⚠️ Diverge volontairement de BraveVPNPanelController (dont ce fichier est
  // par ailleurs un miroir), qui garde le défaut upstream.
  webui_bubble_manager_->ShowBubble(
      /*anchor=*/std::nullopt, views::BubbleBorder::TOP_CENTER);
}

void BasarunaaPanelController::ResetBubbleManager() {
  webui_bubble_manager_.reset();
}
