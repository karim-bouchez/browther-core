// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_BROWSER_UI_BROWTHER_STATUS_DOT_IMAGE_SOURCE_H_
#define BRAVE_BROWSER_UI_BROWTHER_STATUS_DOT_IMAGE_SOURCE_H_

#include <optional>


#include "chrome/browser/ui/extensions/icon_with_badge_image_source.h"
#include "third_party/skia/include/core/SkColor.h"

namespace gfx {
class Canvas;
class RectF;
}  // namespace gfx

namespace browther {

// Browther: image source qui compose une icône avec un petit dot de statut 8pt
// en bas-droite (style iOS). Remplace le `BraveIconWithBadgeImageSource` quand
// on veut juste indiquer un état ON/OFF visuellement discret, sans afficher
// du texte de badge (compteur, etc.).
//
// Usage typique : `SetIcon(...)` puis `SetDotColor(SK_ColorGREEN)` pour ON,
// `SK_ColorRED` pour OFF. La taille de l'icône n'est pas réduite (pas de
// override de GetIconAreaRect), le dot vient juste en overlay.
class BrowtherStatusDotImageSource : public IconWithBadgeImageSource {
 public:
  static constexpr int kDotSize = 8;

  // `content_image_size` = taille effective de l'icône rendue (centrée dans le
  // canvas). Permet de positionner le dot précisément à cheval sur son coin
  // bas-droite, au lieu du coin du canvas total.
  BrowtherStatusDotImageSource(
      const gfx::Size& size,
      GetColorProviderCallback get_color_provider_callback,
      int content_image_size);

  BrowtherStatusDotImageSource(const BrowtherStatusDotImageSource&) = delete;
  BrowtherStatusDotImageSource& operator=(
      const BrowtherStatusDotImageSource&) = delete;

  ~BrowtherStatusDotImageSource() override;

  void SetDotColor(SkColor color) { dot_color_ = color; }
  // « Seulement 5 min » (Sawtunaa, Basarunaa) : anneau qui se vide, dessiné
  // par le BOUTON (PaintButtonContents) à la taille de sa zone de survol, et
  // non dans cette image : l'image est plus petite que le bouton, l'anneau y
  // était rogné ou forçait à réduire l'icône (recette Karim 2026-10-02).
  // Pendant le compte à rebours, l'appelant cache le dot (SK_ColorTRANSPARENT).
  static void PaintCountdownRing(gfx::Canvas* canvas,
                                 const gfx::RectF& bounds,
                                 SkColor color,
                                 float fraction);

 private:
  void PaintBadge(gfx::Canvas* canvas) override;

  int content_image_size_;
  SkColor dot_color_ = SK_ColorTRANSPARENT;
};

}  // namespace browther

#endif  // BRAVE_BROWSER_UI_BROWTHER_STATUS_DOT_IMAGE_SOURCE_H_
