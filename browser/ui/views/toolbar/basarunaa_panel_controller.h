// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_BROWSER_UI_VIEWS_TOOLBAR_BASARUNAA_PANEL_CONTROLLER_H_
#define BRAVE_BROWSER_UI_VIEWS_TOOLBAR_BASARUNAA_PANEL_CONTROLLER_H_

#include <memory>

#include "base/memory/raw_ptr.h"
#include "brave/browser/ui/webui/basarunaa/basarunaa_panel_ui.h"
#include "chrome/browser/ui/views/bubble/webui_bubble_manager.h"

class BraveBrowserView;

// Browther: 1:1 mirror of BraveVPNPanelController. Kept persistent on
// BraveBrowserView, owns the WebUIBubbleManager.
class BasarunaaPanelController {
 public:
  explicit BasarunaaPanelController(BraveBrowserView* browser_view);
  ~BasarunaaPanelController();
  BasarunaaPanelController(const BasarunaaPanelController&) = delete;
  BasarunaaPanelController& operator=(const BasarunaaPanelController&) = delete;

  void ShowBasarunaaPanel();
  // Manager should be reset to use different anchor view for bubble.
  void ResetBubbleManager();

 private:
  raw_ptr<BraveBrowserView> browser_view_ = nullptr;
  std::unique_ptr<WebUIBubbleManager> webui_bubble_manager_;
};

#endif  // BRAVE_BROWSER_UI_VIEWS_TOOLBAR_BASARUNAA_PANEL_CONTROLLER_H_
