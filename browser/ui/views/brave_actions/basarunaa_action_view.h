// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_BROWSER_UI_VIEWS_BRAVE_ACTIONS_BASARUNAA_ACTION_VIEW_H_
#define BRAVE_BROWSER_UI_VIEWS_BRAVE_ACTIONS_BASARUNAA_ACTION_VIEW_H_

#include "base/memory/raw_ptr.h"
#include "chrome/browser/ui/views/toolbar/toolbar_button.h"
#include "ui/base/metadata/metadata_header_macros.h"
#include "ui/events/event.h"

namespace views {
class MenuButtonController;
}  // namespace views

class Browser;

// Browther: toolbar button for Basarunaa panel. 1:1 mirror of BraveVPNButton
// stripped of the VPN-specific service observation and menu model.
// Click dispatches IDC_SHOW_BASARUNAA_PANEL.
class BasarunaaActionView : public ToolbarButton {
  METADATA_HEADER(BasarunaaActionView, ToolbarButton)
 public:
  explicit BasarunaaActionView(Browser* browser);
  BasarunaaActionView(const BasarunaaActionView&) = delete;
  BasarunaaActionView& operator=(const BasarunaaActionView&) = delete;
  ~BasarunaaActionView() override;

  // Init() is called once after the view is added to the toolbar to refresh
  // the icon. Kept for source-compat with the existing toolbar wiring.
  void Init();

 private:
  // ToolbarButton:
  void UpdateColorsAndInsets() override;

  void OnButtonPressed(const ui::Event& event);

  raw_ptr<Browser> browser_ = nullptr;
  raw_ptr<views::MenuButtonController> menu_button_controller_ = nullptr;
};

#endif  // BRAVE_BROWSER_UI_VIEWS_BRAVE_ACTIONS_BASARUNAA_ACTION_VIEW_H_
