// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_BROWSER_UI_VIEWS_BRAVE_ACTIONS_BASARUNAA_ACTION_VIEW_H_
#define BRAVE_BROWSER_UI_VIEWS_BRAVE_ACTIONS_BASARUNAA_ACTION_VIEW_H_

#include "base/memory/raw_ptr.h"
#include "base/memory/raw_ref.h"
#include "chrome/browser/ui/views/toolbar/toolbar_button.h"
#include "components/prefs/pref_change_registrar.h"
#include "ui/base/metadata/metadata_header_macros.h"
#include "ui/events/event.h"

namespace views {
class MenuButtonController;
}  // namespace views

class Browser;
class PrefService;

// Browther: toolbar button for Basarunaa panel. 1:1 mirror of BraveVPNButton.
// Click dispatches IDC_SHOW_BASARUNAA_PANEL. Displays a green/red badge that
// reflects the kBasarunaaEnabled pref.
class BasarunaaActionView : public ToolbarButton {
  METADATA_HEADER(BasarunaaActionView, ToolbarButton)
 public:
  explicit BasarunaaActionView(Browser* browser);
  BasarunaaActionView(const BasarunaaActionView&) = delete;
  BasarunaaActionView& operator=(const BasarunaaActionView&) = delete;
  ~BasarunaaActionView() override;

  void Init();

 private:
  // ToolbarButton:
  void UpdateColorsAndInsets() override;

  void OnButtonPressed(const ui::Event& event);
  bool IsActive() const;
  void OnPrefChanged();

  raw_ptr<Browser> browser_ = nullptr;
  raw_ref<PrefService> profile_prefs_;
  PrefChangeRegistrar pref_change_registrar_;
  raw_ptr<views::MenuButtonController> menu_button_controller_ = nullptr;
};

#endif  // BRAVE_BROWSER_UI_VIEWS_BRAVE_ACTIONS_BASARUNAA_ACTION_VIEW_H_
