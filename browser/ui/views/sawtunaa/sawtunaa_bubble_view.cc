// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/browser/ui/views/sawtunaa/sawtunaa_bubble_view.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <memory>
#include <utility>

#include "base/check.h"
#include "base/functional/bind.h"
#include "base/time/time.h"
#include "base/timer/timer.h"
#include "base/values.h"
#include "brave/components/browther_analytics/browther_analytics_service.h"
#include "brave/components/constants/pref_names.h"
#include "cc/paint/paint_flags.h"
#include "cc/paint/paint_shader.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser.h"
#include "components/grit/brave_components_resources.h"
#include "components/prefs/pref_service.h"
#include "third_party/skia/include/core/SkColor.h"
#include "ui/base/metadata/metadata_impl_macros.h"
#include "ui/base/mojom/dialog_button.mojom.h"
#include "ui/base/resource/resource_bundle.h"
#include "ui/events/event.h"
#include "ui/gfx/canvas.h"
#include "ui/gfx/geometry/insets.h"
#include "ui/gfx/geometry/rect_f.h"
#include "ui/gfx/geometry/size.h"
#include "ui/gfx/image/image_skia.h"
#include "ui/views/animation/ink_drop.h"
#include "ui/views/controls/button/button.h"
#include "ui/views/controls/image_view.h"
#include "ui/views/controls/label.h"
#include "ui/views/layout/box_layout.h"
#include "ui/views/layout/box_layout_view.h"
#include "ui/views/widget/widget.h"

namespace browther {

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

// Track the active widget to mirror the BraveVPN/Basarunaa toggle-on-reclick
// behavior without owning a controller object.
views::Widget* g_active_widget = nullptr;

gfx::FontList DeriveFont(int font_size, gfx::Font::Weight weight) {
  gfx::FontList list;
  return list.DeriveWithSizeDelta(font_size - list.GetFontSize())
      .DeriveWithWeight(weight);
}

// Browther: large pill toggle inspired by ShieldsSwitchView on iOS.
// Renders a tall pill track with a circular thumb and a soft glow when ON.
// Pure custom paint to control size, glow and color cycle without inheriting
// the upstream views::ToggleButton 36×20 sizing & native ink drop.
class SawtunaaBigToggle : public views::Button {
  METADATA_HEADER(SawtunaaBigToggle, views::Button)
 public:
  static constexpr int kTrackWidth = 96;
  static constexpr int kTrackHeight = 52;
  static constexpr int kThumbInset = 6;
  static constexpr int kGlowMargin = 4;

  using ToggleCallback = base::RepeatingCallback<void(bool)>;

  explicit SawtunaaBigToggle(ToggleCallback callback)
      : views::Button(base::BindRepeating(&SawtunaaBigToggle::OnPressed,
                                          base::Unretained(this))),
        toggle_callback_(std::move(callback)) {
    // Disable the default ink drop so hovering / tapping stays neutral —
    // we draw the visual feedback ourselves on the track.
    views::InkDrop::Get(this)->SetMode(views::InkDropHost::InkDropMode::OFF);
    SetHasInkDropActionOnClick(false);
    SetAccessibleName(u"Sawtunaa");
  }

  ~SawtunaaBigToggle() override = default;

  void SetIsOn(bool on) {
    if (is_on_ == on) {
      return;
    }
    is_on_ = on;
    UpdateAnimation();
    SchedulePaint();
  }

  bool GetIsOn() const { return is_on_; }

  // views::Button:
  gfx::Size CalculatePreferredSize(
      const views::SizeBounds& available_size) const override {
    return gfx::Size(kTrackWidth + 2 * kGlowMargin,
                     kTrackHeight + 2 * kGlowMargin);
  }

  void PaintButtonContents(gfx::Canvas* canvas) override {
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

 private:
  void OnPressed(const ui::Event& event) {
    is_on_ = !is_on_;
    UpdateAnimation();
    SchedulePaint();
    toggle_callback_.Run(is_on_);
  }

  void UpdateAnimation() {
    if (is_on_) {
      // ~33fps; cycle complet en 1.8s.
      animation_timer_.Start(
          FROM_HERE, base::Milliseconds(33),
          base::BindRepeating(&SawtunaaBigToggle::OnAnimationTick,
                              base::Unretained(this)));
    } else {
      animation_timer_.Stop();
      phase_ = 0.f;
    }
  }

  void OnAnimationTick() {
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

  ToggleCallback toggle_callback_;
  bool is_on_ = false;
  float phase_ = 0.f;
  base::RepeatingTimer animation_timer_;
};

BEGIN_METADATA(SawtunaaBigToggle)
END_METADATA

}  // namespace browther

using browther::SawtunaaBigToggle;
using browther::g_active_widget;
using browther::DeriveFont;

// static
void SawtunaaBubbleView::Show(views::View* anchor, Browser* browser) {
  CHECK(anchor);
  CHECK(browser);
  // If already open, treat the call as a close request (anchor re-click).
  if (g_active_widget) {
    g_active_widget->Close();
    return;
  }

  auto bubble = std::make_unique<SawtunaaBubbleView>(anchor, browser);
  SawtunaaBubbleView* bubble_ptr = bubble.get();
  views::Widget* widget =
      views::BubbleDialogDelegateView::CreateBubble(std::move(bubble));
  g_active_widget = widget;
  // Browther: highlight the anchor button while the bubble is open so that
  // re-clicking the toolbar button closes (rather than re-opens) the bubble.
  if (auto* anchor_button = views::Button::AsButton(anchor)) {
    bubble_ptr->SetHighlightedButton(anchor_button);
  }
  widget->Show();
}

// static
bool SawtunaaBubbleView::IsShowing() {
  return g_active_widget != nullptr;
}

SawtunaaBubbleView::SawtunaaBubbleView(views::View* anchor, Browser* browser)
    : BubbleDialogDelegateView(anchor,
                               views::BubbleBorder::TOP_RIGHT,
                               views::BubbleBorder::STANDARD_SHADOW,
                               /*autosize=*/true),
      browser_(browser),
      profile_prefs_(browser->profile()->GetPrefs()) {
  CHECK(profile_prefs_);
  SetShowCloseButton(false);
  SetShowTitle(false);
  SetButtons(static_cast<int>(ui::mojom::DialogButton::kNone));
  SetTitle(u"Sawtunaa");  // accessibility only — frame title hidden
  set_fixed_width(320);
  set_margins(gfx::Insets::TLBR(20, 20, 22, 20));

  BuildContents();

  pref_change_registrar_.Init(profile_prefs_);
  pref_change_registrar_.Add(
      kSawtunaaEnabled,
      base::BindRepeating(&SawtunaaBubbleView::OnPrefChanged,
                          base::Unretained(this)));
}

SawtunaaBubbleView::~SawtunaaBubbleView() = default;

void SawtunaaBubbleView::OnWidgetDestroying(views::Widget* widget) {
  if (g_active_widget == widget) {
    g_active_widget = nullptr;
  }
  BubbleDialogDelegateView::OnWidgetDestroying(widget);
}

void SawtunaaBubbleView::BuildContents() {
  auto* layout = SetLayoutManager(std::make_unique<views::BoxLayout>(
      views::BoxLayout::Orientation::kVertical, gfx::Insets(),
      /*between_child_spacing=*/14));
  layout->set_cross_axis_alignment(
      views::BoxLayout::CrossAxisAlignment::kCenter);

  // ----- Header : brand icon (with bg) + wordmark white, on one line -----
  ui::ResourceBundle& rb = ui::ResourceBundle::GetSharedInstance();
  auto* header = AddChildView(std::make_unique<views::BoxLayoutView>());
  header->SetOrientation(views::BoxLayout::Orientation::kHorizontal);
  header->SetCrossAxisAlignment(
      views::BoxLayout::CrossAxisAlignment::kCenter);
  header->SetBetweenChildSpacing(10);

  const SkBitmap brand_bm =
      rb.GetImageNamed(IDR_SAWTUNAA_BRAND_ICON).AsBitmap();
  if (!brand_bm.isNull()) {
    auto* icon_view = header->AddChildView(std::make_unique<views::ImageView>(
        ui::ImageModel::FromImageSkia(
            gfx::ImageSkia::CreateFrom1xBitmap(brand_bm))));
    icon_view->SetImageSize(gfx::Size(40, 40));
  }
  const SkBitmap wm_bm =
      rb.GetImageNamed(IDR_SAWTUNAA_WORDMARK_WHITE).AsBitmap();
  if (!wm_bm.isNull()) {
    constexpr int kWmHeight = 26;
    const int wm_w = static_cast<int>(static_cast<float>(kWmHeight) *
                                      wm_bm.width() / wm_bm.height());
    auto* wm_view = header->AddChildView(std::make_unique<views::ImageView>(
        ui::ImageModel::FromImageSkia(
            gfx::ImageSkia::CreateFrom1xBitmap(wm_bm))));
    wm_view->SetImageSize(gfx::Size(wm_w, kWmHeight));
  }

  // ----- Big toggle (custom paint, no native hover/violet glitch) -----
  auto big = std::make_unique<SawtunaaBigToggle>(base::BindRepeating(
      [](SawtunaaBubbleView* self, bool on) {
        self->profile_prefs_->SetBoolean(kSawtunaaEnabled, on);
        if (auto* analytics = browther_analytics::BrowtherAnalyticsService::
                GetInstance()) {
          base::DictValue props;
          props.Set("feature", "sawtunaa");
          props.Set("enabled", on);
          analytics->Track("feature_toggled", std::move(props));
        }
      },
      base::Unretained(this)));
  big->SetIsOn(profile_prefs_->GetBoolean(kSawtunaaEnabled));
  toggle_ = AddChildView(std::move(big));

  // ----- Status label (color-coded ON / OFF) -----
  status_label_ = AddChildView(std::make_unique<views::Label>());
  status_label_->SetFontList(DeriveFont(13, gfx::Font::Weight::SEMIBOLD));
  status_label_->SetHorizontalAlignment(gfx::ALIGN_CENTER);
  status_label_->SetAutoColorReadabilityEnabled(false);
  UpdateStatusLabel();

  // ----- Description user-friendly -----
  auto* desc = AddChildView(std::make_unique<views::Label>(
      u"Supprime la musique et les bruits de fond des vidéos en temps réel "
      u"sur n'importe quel site, pour ne garder que la voix."));
  desc->SetFontList(DeriveFont(12, gfx::Font::Weight::NORMAL));
  desc->SetHorizontalAlignment(gfx::ALIGN_CENTER);
  desc->SetMultiLine(true);
  desc->SetMaximumWidth(280);
}

void SawtunaaBubbleView::OnPrefChanged() {
  if (toggle_) {
    const bool value = profile_prefs_->GetBoolean(kSawtunaaEnabled);
    if (toggle_->GetIsOn() != value) {
      toggle_->SetIsOn(value);
    }
  }
  UpdateStatusLabel();
}

void SawtunaaBubbleView::UpdateStatusLabel() {
  if (!status_label_) {
    return;
  }
  const bool active = profile_prefs_->GetBoolean(kSawtunaaEnabled);
  status_label_->SetText(active
                             ? u"Suppression de la musique ACTIVÉE"
                             : u"Suppression de la musique DÉSACTIVÉE");
  // Browther: gris neutre (~70% blanc) pour matcher le rendu iOS — pas de
  // sémantique chromatique sur ce label, le toggle porte déjà l'état.
  status_label_->SetEnabledColor(SkColorSetA(SK_ColorWHITE, 0xB3));
}

BEGIN_METADATA(SawtunaaBubbleView)
END_METADATA
