// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_BROWSER_UI_VIEWS_TOOLBAR_SAWTUNAA_PANEL_CONTROLLER_H_
#define BRAVE_BROWSER_UI_VIEWS_TOOLBAR_SAWTUNAA_PANEL_CONTROLLER_H_

#include <memory>

#include "base/memory/raw_ptr.h"
#include "brave/browser/ui/webui/sawtunaa/sawtunaa_panel_ui.h"
#include "chrome/browser/ui/views/bubble/webui_bubble_manager.h"

class BraveBrowserView;

// Browther: jumeau de BasarunaaPanelController (lui-même calqué sur
// BraveVPNPanelController). Persistant sur BraveBrowserView, possède le
// WebUIBubbleManager.
class SawtunaaPanelController {
 public:
  explicit SawtunaaPanelController(BraveBrowserView* browser_view);
  ~SawtunaaPanelController();
  SawtunaaPanelController(const SawtunaaPanelController&) = delete;
  SawtunaaPanelController& operator=(const SawtunaaPanelController&) = delete;

  void ShowSawtunaaPanel();
  // Manager should be reset to use different anchor view for bubble.
  void ResetBubbleManager();

 private:
  raw_ptr<BraveBrowserView> browser_view_ = nullptr;
  std::unique_ptr<WebUIBubbleManager> webui_bubble_manager_;
};

#endif  // BRAVE_BROWSER_UI_VIEWS_TOOLBAR_SAWTUNAA_PANEL_CONTROLLER_H_
