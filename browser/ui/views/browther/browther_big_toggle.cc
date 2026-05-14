// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/browser/ui/views/browther/browther_big_toggle.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <utility>

#include "base/functional/bind.h"
#include "base/time/time.h"
#include "cc/paint/paint_flags.h"
#include "cc/paint/paint_shader.h"
#include "third_party/skia/include/core/SkColor.h"
#include "ui/base/metadata/metadata_impl_macros.h"
#include "ui/events/event.h"
#include "ui/gfx/canvas.h"
#include "ui/gfx/geometry/rect_f.h"
#include "ui/gfx/geometry/size.h"
#include "ui/views/animation/ink_drop.h"

namespace browther {

namespace {

// Browther: matches the in-app palette used on iOS BrowtherFeaturePanels.
constexpr SkColor kTrackOff = SkColorSetRGB(0x55, 0x55, 0x55);

// 8-bit channel lerp, clamped — Skia abort si on lui passe une couleur
// avec un canal hors plage (ex: phase float qui drift au-delà de 1.0).
SkColor LerpColor(SkColor a, SkColor b, float t) {
  if (t < 0.f) {
    t = 0.f;
  } else if (t > 1.f) {
    t = 1.f;
  }
  auto lerp = [](U8CPU x, U8CPU y, float k) {
    const int v = static_cast<int>(static_cast<float>(x) +
                                   (static_cast<float>(y) -
                                    static_cast<float>(x)) *
                                       k);
    return static_cast<U8CPU>(std::clamp(v, 0, 255));
  };
  return SkColorSetARGB(
      lerp(SkColorGetA(a), SkColorGetA(b), t),
      lerp(SkColorGetR(a), SkColorGetR(b), t),
      lerp(SkColorGetG(a), SkColorGetG(b), t),
      lerp(SkColorGetB(a), SkColorGetB(b), t));
}

// Browther: 6 keyframes du gradient ON, copie 1:1 de
// `ShieldsSwitch.swift::steps` côté iOS.
//   {gradient inner, gradient outer}
constexpr int kGradientStepCount = 6;
using GradientStep = std::array<SkColor, 2>;
constexpr std::array<GradientStep, kGradientStepCount> kGradientSteps = {{
    {SkColorSetRGB(0x86, 0xEF, 0xAC), SkColorSetRGB(0x4A, 0xDE, 0x80)},
    {SkColorSetRGB(0x4A, 0xDE, 0x80), SkColorSetRGB(0x22, 0xC5, 0x5E)},
    {SkColorSetRGB(0x22, 0xC5, 0x5E), SkColorSetRGB(0x16, 0xA3, 0x4A)},
    {SkColorSetRGB(0x16, 0xA3, 0x4A), SkColorSetRGB(0x10, 0xB9, 0x81)},
    {SkColorSetRGB(0x10, 0xB9, 0x81), SkColorSetRGB(0x34, 0xD3, 0x99)},
    {SkColorSetRGB(0x34, 0xD3, 0x99), SkColorSetRGB(0x86, 0xEF, 0xAC)},
}};

}  // namespace

BrowtherBigToggle::BrowtherBigToggle(ToggleCallback callback)
    : views::Button(base::BindRepeating(&BrowtherBigToggle::OnPressed,
                                         base::Unretained(this))),
      toggle_callback_(std::move(callback)) {
  // Disable the default ink drop so hovering / tapping stays neutral —
  // we draw the visual feedback ourselves on the track.
  views::InkDrop::Get(this)->SetMode(views::InkDropHost::InkDropMode::OFF);
  SetHasInkDropActionOnClick(false);
}

BrowtherBigToggle::~BrowtherBigToggle() = default;

void BrowtherBigToggle::SetIsOn(bool on) {
  if (is_on_ == on) {
    return;
  }
  is_on_ = on;
  UpdateAnimation();
  SchedulePaint();
}

gfx::Size BrowtherBigToggle::CalculatePreferredSize(
    const views::SizeBounds& available_size) const {
  return gfx::Size(kTrackWidth + 2 * kGlowMargin,
                   kTrackHeight + 2 * kGlowMargin);
}

void BrowtherBigToggle::PaintButtonContents(gfx::Canvas* canvas) {
  const gfx::Rect content = GetContentsBounds();
  const float track_x = content.x() + kGlowMargin;
  const float track_y = content.y() + kGlowMargin;
  const gfx::RectF track(track_x, track_y, kTrackWidth, kTrackHeight);
  const float radius = kTrackHeight / 2.0f;

  cc::PaintFlags track_flags;
  track_flags.setAntiAlias(true);
  if (is_on_) {
    // Browther: gradient radial animé, mirror exact de iOS
    // ShieldsSwitch.beginGradientAnimations() — 6 keyframes paced sur 4.5s.
    // fmod garantit phase ∈ [0, kGradientStepCount) malgré la dérive float.
    const float p_mod =
        std::fmod(phase_, static_cast<float>(kGradientStepCount));
    const int idx = static_cast<int>(p_mod);
    const int next_idx = (idx + 1) % kGradientStepCount;
    const float t = p_mod - static_cast<float>(idx);
    const SkColor inner =
        LerpColor(kGradientSteps[idx][0], kGradientSteps[next_idx][0], t);
    const SkColor outer =
        LerpColor(kGradientSteps[idx][1], kGradientSteps[next_idx][1], t);

    // iOS : startPoint=(1,1) bottom-right (couleur 0), endPoint=(0,0)
    // top-left (couleur 1). Gradient radial Skia centré sur bottom-right.
    const SkPoint center =
        SkPoint::Make(track_x + kTrackWidth, track_y + kTrackHeight);
    const SkScalar grad_radius = std::hypot(
        static_cast<float>(kTrackWidth), static_cast<float>(kTrackHeight));
    const std::array<SkColor4f, 2> colors = {SkColor4f::FromColor(inner),
                                              SkColor4f::FromColor(outer)};
    const std::array<SkScalar, 2> pos = {0.f, 1.f};
    track_flags.setShader(cc::PaintShader::MakeRadialGradient(
        center, grad_radius, colors.data(), pos.data(), 2,
        SkTileMode::kClamp));
  } else {
    track_flags.setColor(kTrackOff);
  }
  canvas->DrawRoundRect(track, radius, track_flags);

  // Thumb.
  const float thumb_diameter = kTrackHeight - 2 * kThumbInset;
  const float thumb_radius = thumb_diameter / 2.0f;
  const float thumb_x =
      is_on_ ? (track_x + kTrackWidth - kThumbInset - thumb_radius)
             : (track_x + kThumbInset + thumb_radius);
  const float thumb_y = track_y + kTrackHeight / 2.0f;

  cc::PaintFlags thumb_flags;
  thumb_flags.setAntiAlias(true);
  thumb_flags.setColor(SK_ColorWHITE);
  canvas->DrawCircle(gfx::PointF(thumb_x, thumb_y), thumb_radius,
                     thumb_flags);
}

void BrowtherBigToggle::OnPressed(const ui::Event& event) {
  is_on_ = !is_on_;
  UpdateAnimation();
  SchedulePaint();
  toggle_callback_.Run(is_on_);
}

void BrowtherBigToggle::UpdateAnimation() {
  if (is_on_) {
    // ~33fps; cycle complet en 1.8s.
    animation_timer_.Start(
        FROM_HERE, base::Milliseconds(33),
        base::BindRepeating(&BrowtherBigToggle::OnAnimationTick,
                            base::Unretained(this)));
  } else {
    animation_timer_.Stop();
    phase_ = 0.f;
  }
}

void BrowtherBigToggle::OnAnimationTick() {
  // Browther: phase ∈ [0, 6) — un cycle complet (6 steps × 0.75s = 4.5s)
  // pour matcher iOS ShieldsSwitch.beginGradientAnimations().
  constexpr float kPeriodMs = 4500.f;
  constexpr float kFrameMs = 33.f;
  constexpr float kStep = kFrameMs / kPeriodMs * kGradientStepCount;
  phase_ += kStep;
  if (phase_ >= static_cast<float>(kGradientStepCount)) {
    phase_ -= static_cast<float>(kGradientStepCount);
  }
  SchedulePaint();
}

BEGIN_METADATA(BrowtherBigToggle)
END_METADATA

}  // namespace browther
