// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_BROWSER_UI_VIEWS_BRAVE_ACTIONS_SAWTUNAA_ACTION_VIEW_H_
#define BRAVE_BROWSER_UI_VIEWS_BRAVE_ACTIONS_SAWTUNAA_ACTION_VIEW_H_

#include "base/memory/raw_ptr.h"
#include "base/memory/raw_ref.h"
#include "chrome/browser/ui/tabs/tab_strip_model_observer.h"
#include "components/prefs/pref_change_registrar.h"
#include "ui/base/metadata/metadata_header_macros.h"
#include "ui/events/event.h"
#include "ui/views/controls/button/label_button.h"

namespace views {
class MenuButtonController;
}  // namespace views

class BrowserWindowInterface;
class PrefService;
class TabStripModel;

// Toolbar button for Sawtunaa (music/noise removal).
// Always visible when enabled, shows active/inactive state
// based on whether the current tab's audio is being processed.
class SawtunaaActionView : public views::LabelButton,
                           public TabStripModelObserver {
  METADATA_HEADER(SawtunaaActionView, views::LabelButton)
 public:
  explicit SawtunaaActionView(
      BrowserWindowInterface* browser_window_interface);
  SawtunaaActionView(const SawtunaaActionView&) = delete;
  SawtunaaActionView& operator=(const SawtunaaActionView&) = delete;
  ~SawtunaaActionView() override;

  void Init();
  void Update();

  // views::LabelButton:
  std::unique_ptr<views::LabelButtonBorder> CreateDefaultBorder()
      const override;
  void OnThemeChanged() override;

 private:
  void UpdateIconState();
  bool IsActive() const;
  gfx::ImageSkia GetIconImage(bool active);
  // Browther: opens the Sawtunaa popup. Re-clicking while it's open closes it.
  void OnButtonPressed(const ui::Event& event);

  // TabStripModelObserver
  void OnTabChangedAt(tabs::TabInterface* tab,
                      int index,
                      TabChangeType change_type) override;
  void OnTabStripModelChanged(
      TabStripModel* tab_strip_model,
      const TabStripModelChange& change,
      const TabStripSelectionChange& selection) override;

  raw_ptr<BrowserWindowInterface> browser_window_interface_ = nullptr;
  raw_ref<PrefService> profile_prefs_;
  raw_ref<TabStripModel> tab_strip_model_;
  PrefChangeRegistrar pref_change_registrar_;
  raw_ptr<views::MenuButtonController> menu_button_controller_ = nullptr;
};

#endif  // BRAVE_BROWSER_UI_VIEWS_BRAVE_ACTIONS_SAWTUNAA_ACTION_VIEW_H_
