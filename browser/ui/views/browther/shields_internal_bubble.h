// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_BROWSER_UI_VIEWS_BROWTHER_SHIELDS_INTERNAL_BUBBLE_H_
#define BRAVE_BROWSER_UI_VIEWS_BROWTHER_SHIELDS_INTERNAL_BUBBLE_H_

#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "ui/base/metadata/metadata_header_macros.h"
#include "ui/views/bubble/bubble_dialog_delegate_view.h"

class Browser;

namespace views {
class Label;
}  // namespace views

namespace browther {

class BrowtherBigToggle;

// Browther: bubble anchored to the Shields toolbar button, shown when the
// active tab is on an internal page (chrome://, about:, file://, …) where the
// WebUI Shields panel is not available. Mirrors the SawtunaaBubbleView layout
// (header lockup + big toggle + status + description) and controls the GLOBAL
// default Brave Shields content setting (empty GURL).
class ShieldsInternalBubble : public views::BubbleDialogDelegateView {
  METADATA_HEADER(ShieldsInternalBubble, views::BubbleDialogDelegateView)

 public:
  // Creates and shows the bubble. If a bubble is already shown, closes it
  // (toggle behavior, mirrors SawtunaaBubbleView).
  static void Show(views::View* anchor, Browser* browser);

  ShieldsInternalBubble(views::View* anchor, Browser* browser);
  ShieldsInternalBubble(const ShieldsInternalBubble&) = delete;
  ShieldsInternalBubble& operator=(const ShieldsInternalBubble&) = delete;
  ~ShieldsInternalBubble() override;

  // views::BubbleDialogDelegate:
  void OnWidgetDestroying(views::Widget* widget) override;

 private:
  void BuildContents();
  void OnTogglePressed(bool on);
  void RestoreToggleOn();
  void UpdateStatusLabel(bool on);

  raw_ptr<Browser> browser_ = nullptr;
  raw_ptr<BrowtherBigToggle> toggle_ = nullptr;
  raw_ptr<views::Label> status_label_ = nullptr;
  raw_ptr<views::Label> info_label_ = nullptr;
  base::WeakPtrFactory<ShieldsInternalBubble> weak_factory_{this};
};

}  // namespace browther

#endif  // BRAVE_BROWSER_UI_VIEWS_BROWTHER_SHIELDS_INTERNAL_BUBBLE_H_
