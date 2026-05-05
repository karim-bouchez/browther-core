// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_BROWSER_UI_VIEWS_BRAVE_ACTIONS_BASARUNAA_ACTION_VIEW_H_
#define BRAVE_BROWSER_UI_VIEWS_BRAVE_ACTIONS_BASARUNAA_ACTION_VIEW_H_

#include "base/memory/raw_ptr.h"
#include "base/memory/raw_ref.h"
#include "chrome/browser/ui/tabs/tab_strip_model_observer.h"
#include "components/prefs/pref_change_registrar.h"
#include "ui/base/metadata/metadata_header_macros.h"
#include "ui/views/controls/button/label_button.h"

class BrowserWindowInterface;
class PrefService;
class TabStripModel;

// Toolbar button for Basarunaa (gender-blur on images/videos).
// Always visible, click toggles the kBasarunaaEnabled pref which
// loads/unloads the built-in extension via BraveComponentLoader.
class BasarunaaActionView : public views::LabelButton,
                            public TabStripModelObserver {
  METADATA_HEADER(BasarunaaActionView, views::LabelButton)
 public:
  explicit BasarunaaActionView(
      BrowserWindowInterface* browser_window_interface);
  BasarunaaActionView(const BasarunaaActionView&) = delete;
  BasarunaaActionView& operator=(const BasarunaaActionView&) = delete;
  ~BasarunaaActionView() override;

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

  // TabStripModelObserver
  void OnTabStripModelChanged(
      TabStripModel* tab_strip_model,
      const TabStripModelChange& change,
      const TabStripSelectionChange& selection) override;

  raw_ptr<BrowserWindowInterface> browser_window_interface_ = nullptr;
  raw_ref<PrefService> profile_prefs_;
  raw_ref<TabStripModel> tab_strip_model_;
  PrefChangeRegistrar pref_change_registrar_;
};

#endif  // BRAVE_BROWSER_UI_VIEWS_BRAVE_ACTIONS_BASARUNAA_ACTION_VIEW_H_
