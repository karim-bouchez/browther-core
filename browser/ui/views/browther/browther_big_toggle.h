// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_BROWSER_UI_VIEWS_BROWTHER_BROWTHER_BIG_TOGGLE_H_
#define BRAVE_BROWSER_UI_VIEWS_BROWTHER_BROWTHER_BIG_TOGGLE_H_

#include "base/functional/callback.h"
#include "base/timer/timer.h"
#include "ui/base/metadata/metadata_header_macros.h"
#include "ui/views/controls/button/button.h"

namespace gfx {
class Canvas;
}  // namespace gfx

namespace ui {
class Event;
}  // namespace ui

namespace browther {

// Browther: large pill toggle inspired by ShieldsSwitchView on iOS.
// Renders a tall pill track with a circular thumb and a soft glow when ON.
// Pure custom paint to control size, glow and color cycle without inheriting
// the upstream views::ToggleButton 36×20 sizing & native ink drop.
//
// Reusable across Browther feature panels (Sawtunaa, Basarunaa, …). Each
// caller is expected to set its own accessible name after construction.
class BrowtherBigToggle : public views::Button {
  METADATA_HEADER(BrowtherBigToggle, views::Button)
 public:
  static constexpr int kTrackWidth = 96;
  static constexpr int kTrackHeight = 52;
  static constexpr int kThumbInset = 6;
  static constexpr int kGlowMargin = 4;

  using ToggleCallback = base::RepeatingCallback<void(bool)>;

  explicit BrowtherBigToggle(ToggleCallback callback);
  BrowtherBigToggle(const BrowtherBigToggle&) = delete;
  BrowtherBigToggle& operator=(const BrowtherBigToggle&) = delete;
  ~BrowtherBigToggle() override;

  void SetIsOn(bool on);
  bool GetIsOn() const { return is_on_; }

  // views::Button:
  gfx::Size CalculatePreferredSize(
      const views::SizeBounds& available_size) const override;
  void PaintButtonContents(gfx::Canvas* canvas) override;

 private:
  void OnPressed(const ui::Event& event);
  void UpdateAnimation();
  void OnAnimationTick();

  ToggleCallback toggle_callback_;
  bool is_on_ = false;
  float phase_ = 0.f;
  base::RepeatingTimer animation_timer_;
};

}  // namespace browther

#endif  // BRAVE_BROWSER_UI_VIEWS_BROWTHER_BROWTHER_BIG_TOGGLE_H_
