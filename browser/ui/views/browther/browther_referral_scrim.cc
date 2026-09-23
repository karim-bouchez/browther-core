// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/browser/ui/views/browther/browther_referral_scrim.h"

#include <memory>

#include "base/no_destructor.h"
#include "base/memory/raw_ptr.h"
#include "base/scoped_observation.h"
#include "third_party/skia/include/core/SkColor.h"
#include "ui/compositor/layer.h"
#include "ui/views/widget/widget.h"
#include "ui/views/widget/widget_observer.h"

namespace browther_referral {

namespace {

// ⚠️ Assez pour qu'on lise « bloqué » d'un coup d'œil, assez peu pour qu'on
// reconnaisse encore sa fenêtre — ⛔ pas un écran noir.
constexpr SkAlpha kScrimAlpha = 0x6E;  // ~43 %
constexpr float kBlurSigma = 6.f;

// Le voile en cours, et la fenêtre qu'il couvre.
class Scrim : public views::WidgetObserver {
 public:
  explicit Scrim(views::Widget* widget) : widget_(widget) {
    layer_ = std::make_unique<ui::Layer>(ui::LAYER_SOLID_COLOR);
    layer_->SetName("BrowtherReferralScrim");
    layer_->SetColor(SkColorSetA(SK_ColorBLACK, kScrimAlpha));
    layer_->SetBackgroundBlur(kBlurSigma);
    // ⛔ Pas de `SetFillsBoundsOpaquely` ici : une couche SOLID_COLOR le refuse
    // net (`CHECK_NE(type_, LAYER_SOLID_COLOR)`, crash immédiat au premier J0,
    // 2026-09-23). Sa transparence vient de l'alpha de sa couleur, point.
    Resize();
    if (ui::Layer* root = widget_->GetLayer()) {
      root->Add(layer_.get());
      root->StackAtTop(layer_.get());
    }
    observation_.Observe(widget_.get());
  }

  ~Scrim() override = default;

  // views::WidgetObserver:
  void OnWidgetBoundsChanged(views::Widget*, const gfx::Rect&) override {
    Resize();
  }
  void OnWidgetDestroying(views::Widget*) override { HideScrim(); }

 private:
  void Resize() {
    gfx::Rect bounds = widget_->GetWindowBoundsInScreen();
    bounds.set_origin(gfx::Point());
    layer_->SetBounds(bounds);
  }

  raw_ptr<views::Widget> widget_;
  std::unique_ptr<ui::Layer> layer_;
  base::ScopedObservation<views::Widget, views::WidgetObserver> observation_{
      this};
};

std::unique_ptr<Scrim>& Current() {
  static base::NoDestructor<std::unique_ptr<Scrim>> scrim;
  return *scrim;
}

}  // namespace

void ShowScrim(views::Widget* browser_widget) {
  if (!browser_widget || Current()) {
    return;
  }
  Current() = std::make_unique<Scrim>(browser_widget);
}

void HideScrim() {
  Current().reset();
}

}  // namespace browther_referral
