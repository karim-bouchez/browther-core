// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/browser/ui/browther_status_dot_image_source.h"

#include <algorithm>

#include "cc/paint/paint_flags.h"
#include "third_party/skia/include/core/SkPath.h"
#include "third_party/skia/include/core/SkPathBuilder.h"
#include "third_party/skia/include/core/SkRect.h"
#include "skia/ext/image_operations.h"
#include "ui/gfx/canvas.h"
#include "ui/gfx/image/image_skia_operations.h"
#include "ui/gfx/geometry/rect.h"
#include "ui/gfx/geometry/rect_f.h"
#include "ui/gfx/geometry/size.h"

namespace browther {

BrowtherStatusDotImageSource::BrowtherStatusDotImageSource(
    const gfx::Size& size,
    GetColorProviderCallback get_color_provider_callback,
    int content_image_size)
    : IconWithBadgeImageSource(size, std::move(get_color_provider_callback)),
      content_image_size_(content_image_size) {}

BrowtherStatusDotImageSource::~BrowtherStatusDotImageSource() = default;

// static
int BrowtherStatusDotImageSource::RingIconSize(int content_image_size) {
  return static_cast<int>(std::lround(content_image_size * 0.62f));
}

// static
gfx::ImageSkia BrowtherStatusDotImageSource::ShrinkIconForRing(
    const gfx::ImageSkia& icon,
    int content_image_size) {
  const int s = RingIconSize(content_image_size);
  return gfx::ImageSkiaOperations::CreateResizedImage(
      icon, skia::ImageOperations::RESIZE_BEST, gfx::Size(s, s));
}

std::optional<int> BrowtherStatusDotImageSource::GetCustomGraphicSize() {
  if (!ring_fraction_) {
    return std::nullopt;
  }
  return RingIconSize(content_image_size_);
}

std::optional<int> BrowtherStatusDotImageSource::GetCustomGraphicXOffset() {
  if (!ring_fraction_) {
    return std::nullopt;
  }
  return (size().width() - RingIconSize(content_image_size_)) / 2;
}

std::optional<int> BrowtherStatusDotImageSource::GetCustomGraphicYOffset() {
  if (!ring_fraction_) {
    return std::nullopt;
  }
  return (size().height() - RingIconSize(content_image_size_)) / 2;
}

void BrowtherStatusDotImageSource::PaintRing(gfx::Canvas* canvas) {
  // Cercle au bord du bouton, autour de l'icône réduite (cf.
  // ShrinkIconForRing) : il ne touche plus le dessin.
  constexpr float kStroke = 1.5f;
  const float cx = size().width() / 2.0f;
  const float cy = size().height() / 2.0f;
  // Marge de 3 px sous le bord du canvas : le bouton rogne les derniers
  // pixels (insets), l'anneau au ras du bord était coupé (recette 2026-10-02).
  const float radius =
      std::min(size().width(), size().height()) / 2.0f - kStroke / 2.0f - 4.5f;
  const SkRect oval =
      SkRect::MakeLTRB(cx - radius, cy - radius, cx + radius, cy + radius);

  cc::PaintFlags track;
  track.setAntiAlias(true);
  track.setStyle(cc::PaintFlags::kStroke_Style);
  track.setStrokeWidth(kStroke);
  track.setColor(SkColorSetA(dot_color_, 0x40));
  canvas->DrawPath(SkPath::Oval(oval), track);

  const float fraction = std::clamp(*ring_fraction_, 0.0f, 1.0f);
  if (fraction <= 0.0f) {
    return;
  }
  cc::PaintFlags ring = track;
  ring.setColor(dot_color_);
  ring.setStrokeCap(cc::PaintFlags::kRound_Cap);
  // 360° pile ferait un ovale fermé ambigu pour addArc : on plafonne juste
  // en dessous.
  const SkPath arc =
      SkPathBuilder()
          .addArc(oval, -90.0f, std::min(359.9f, 360.0f * fraction))
          .detach();
  canvas->DrawPath(arc, ring);
}

void BrowtherStatusDotImageSource::PaintBadge(gfx::Canvas* canvas) {
  if (dot_color_ == SK_ColorTRANSPARENT) {
    return;
  }
  if (ring_fraction_) {
    PaintRing(canvas);
    return;
  }

  // L'icône est centrée dans le canvas. On positionne le dot dans le coin
  // bas-droite de l'icône (complètement à l'intérieur, pas chevauchant), avec
  // une safety margin par rapport au bord du canvas (les boutons UIButton ont
  // souvent des paddings internes qui clippent les derniers pixels).
  constexpr int kSafetyMargin = 3;
  const int canvas_w = size().width();
  const int canvas_h = size().height();
  const int icon_x = (canvas_w - content_image_size_) / 2;
  const int icon_y = (canvas_h - content_image_size_) / 2;
  const int icon_right = icon_x + content_image_size_;
  const int icon_bottom = icon_y + content_image_size_;

  // Coin bas-droite de l'icône, mais clampé pour rester à kSafetyMargin du
  // bord du canvas pour éviter le clipping.
  int dot_x = std::min(icon_right - kDotSize, canvas_w - kDotSize - kSafetyMargin);
  int dot_y = std::min(icon_bottom - kDotSize, canvas_h - kDotSize - kSafetyMargin);
  dot_x = std::max(dot_x, 0);
  dot_y = std::max(dot_y, 0);

  const gfx::RectF dot_rect(static_cast<float>(dot_x),
                            static_cast<float>(dot_y),
                            static_cast<float>(kDotSize),
                            static_cast<float>(kDotSize));
  const float radius = static_cast<float>(kDotSize) / 2.0f;

  // Bordure blanche fine pour mieux ressortir sur n'importe quel fond.
  cc::PaintFlags border_flags;
  border_flags.setAntiAlias(true);
  border_flags.setColor(SK_ColorWHITE);
  border_flags.setStyle(cc::PaintFlags::kStroke_Style);
  border_flags.setStrokeWidth(1.0f);

  cc::PaintFlags fill_flags;
  fill_flags.setAntiAlias(true);
  fill_flags.setColor(dot_color_);
  fill_flags.setStyle(cc::PaintFlags::kFill_Style);

  canvas->DrawRoundRect(dot_rect, radius, fill_flags);
  canvas->DrawRoundRect(dot_rect, radius, border_flags);
}

}  // namespace browther
