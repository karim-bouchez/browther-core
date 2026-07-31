// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/browser/ui/views/toolbar/sawtunaa_panel_controller.h"

#include "base/check.h"
#include "brave/browser/ui/views/frame/brave_browser_view.h"
#include "brave/components/constants/webui_url_constants.h"
#include "brave/grit/brave_generated_resources.h"
#include "chrome/browser/ui/browser.h"
#include "chrome/browser/ui/views/bubble/webui_bubble_manager.h"
#include "url/gurl.h"

SawtunaaPanelController::SawtunaaPanelController(BraveBrowserView* browser_view)
    : browser_view_(browser_view) {
  DCHECK(browser_view_);
}

SawtunaaPanelController::~SawtunaaPanelController() = default;

void SawtunaaPanelController::ShowSawtunaaPanel() {
  // 1:1 mirror of BasarunaaPanelController::ShowSawtunaaPanel.
  auto* anchor_view = browser_view_->GetAnchorViewForSawtunaaPanel();
  if (!anchor_view) {
    return;
  }

  if (!webui_bubble_manager_) {
    webui_bubble_manager_ = WebUIBubbleManager::Create<SawtunaaPanelUI>(
        anchor_view, browser_view_->browser(), GURL(kSawtunaaPanelURL),
        IDS_SAWTUNAA_PANEL_NAME);
  }

  // Re-clic sur le bouton toolbar = ferme la bulle (le MenuButtonController de
  // la vue d'action ignore l'activation, c'est ici qu'on décide).
  if (webui_bubble_manager_->GetBubbleWidget()) {
    webui_bubble_manager_->CloseBubble();
    return;
  }

  webui_bubble_manager_->ShowBubble();
}

void SawtunaaPanelController::ResetBubbleManager() {
  webui_bubble_manager_.reset();
}
