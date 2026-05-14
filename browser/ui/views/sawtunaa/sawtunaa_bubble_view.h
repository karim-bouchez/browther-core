// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_BROWSER_UI_VIEWS_SAWTUNAA_SAWTUNAA_BUBBLE_VIEW_H_
#define BRAVE_BROWSER_UI_VIEWS_SAWTUNAA_SAWTUNAA_BUBBLE_VIEW_H_

#include "base/memory/raw_ptr.h"
#include "components/prefs/pref_change_registrar.h"
#include "ui/base/metadata/metadata_header_macros.h"
#include "ui/views/bubble/bubble_dialog_delegate_view.h"

namespace views {
class Label;
}  // namespace views

namespace browther {
class SawtunaaBigToggle;
}  // namespace browther

class Browser;
class PrefService;

// Browther: native popup anchored to the Sawtunaa toolbar button.
// Contains the on/off toggle for the Sawtunaa feature plus a short
// explanation of why it currently only targets YouTube.
class SawtunaaBubbleView : public views::BubbleDialogDelegateView {
  METADATA_HEADER(SawtunaaBubbleView, views::BubbleDialogDelegateView)

 public:
  // Creates and shows the bubble. If a bubble is already shown, closes it
  // (toggle behavior, mirrors BraveVPN/Basarunaa panel pattern).
  static void Show(views::View* anchor, Browser* browser);

  // Whether a bubble is currently shown anywhere (used by the toolbar
  // button's MenuButtonController to ignore the activation that occurs when
  // re-clicking the anchor).
  static bool IsShowing();

  SawtunaaBubbleView(views::View* anchor, Browser* browser);
  SawtunaaBubbleView(const SawtunaaBubbleView&) = delete;
  SawtunaaBubbleView& operator=(const SawtunaaBubbleView&) = delete;
  ~SawtunaaBubbleView() override;

  // views::BubbleDialogDelegate:
  void OnWidgetDestroying(views::Widget* widget) override;

 private:
  void BuildContents();
  void OnTogglePressed();
  void OnPrefChanged();

  raw_ptr<Browser> browser_ = nullptr;
  raw_ptr<PrefService> profile_prefs_ = nullptr;
  raw_ptr<browther::SawtunaaBigToggle> toggle_ = nullptr;
  raw_ptr<views::Label> status_label_ = nullptr;
  PrefChangeRegistrar pref_change_registrar_;

  void UpdateStatusLabel();
};

#endif  // BRAVE_BROWSER_UI_VIEWS_SAWTUNAA_SAWTUNAA_BUBBLE_VIEW_H_
