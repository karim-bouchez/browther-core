// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/browser/ui/webui/browther_referral/browther_referral_dialog.h"

#include <algorithm>
#include <memory>
#include <string>
#include <vector>

#include "base/logging.h"
#include "base/no_destructor.h"
#include "base/strings/escape.h"
#include "base/strings/strcat.h"
#include "brave/browser/browther/referral/browther_referral_launch.h"
#include "brave/browser/ui/views/browther/browther_referral_scrim.h"
#include "chrome/browser/ui/views/chrome_web_dialog_view.h"
#include "content/public/browser/web_contents.h"

#include "ui/base/mojom/ui_base_types.mojom.h"
#include "ui/gfx/geometry/rect.h"
#include "ui/gfx/geometry/rounded_corners_f.h"
#include "ui/gfx/geometry/size.h"
#include "ui/views/widget/widget.h"
#include "ui/web_dialogs/web_dialog_delegate.h"

namespace browther_referral {

namespace {

// Les cotes de la carte du flow (`private/webui/referral`) : la fenêtre ne
// contient qu'elle, donc elle fait sa taille et porte ses coins arrondis.
constexpr int kDialogWidth = 468;
constexpr int kDialogHeight = 560;   // avant que la page dise sa vraie hauteur
constexpr int kDialogMinHeight = 320;
constexpr int kDialogMaxHeight = 1000;
constexpr int kMargin = 32;          // d'air au-dessus et en dessous
constexpr float kCornerRadius = 24.f;

// ⚠️ La fenêtre ne contient QUE la carte : sans cadre, coins arrondis, à ses
// cotes. Le voile, lui, est posé DANS la fenêtre du navigateur
// (`browther_referral_scrim.h`) — une fenêtre ne peut pas assombrir ce qu'il y
// a derrière elle. Sinon on voit un bloc dans un bloc, avec sa propre barre
// de défilement, et rien ne dit que le reste est bloqué (recette Karim,
// 2026-09-23). Les cotes viennent donc de la fenêtre parente, pas d'ici.

// La modale ouverte, s'il y en a une — une seule à la fois par principe.
// ⚠️ `base::NoDestructor` : `gfx::NativeWindow` a un destructeur, et Chromium
// interdit les destructeurs de fin de programme sur les globales.
gfx::NativeWindow& ModalWindow() {
  static base::NoDestructor<gfx::NativeWindow> window;
  return *window;
}

class ReferralDialogDelegate : public ui::WebDialogDelegate {
 public:
  ReferralDialogDelegate(const std::string& screen, bool chosen) {
    set_can_close(true);
    set_dialog_modal_type(ui::mojom::ModalType::kWindow);
    set_show_dialog_title(false);
    set_dialog_size(gfx::Size(kDialogWidth, kDialogHeight));
    // `host=modal` : l'app ne monte QUE le flow (⛔ pas l'écran Parrainage
    // derrière), et `screen` lui dit lequel ouvrir (`app.tsx`).
    set_dialog_content_url(GURL(
        base::StrCat({kReferralURL, "?host=modal&screen=",
                      base::EscapeQueryParamValue(screen, false),
                      chosen ? "&chosen=1" : ""})));
  }

  // ⭐ Le voile de la fenêtre du navigateur disparaît AVEC la modale, quelle
  // que soit la façon dont elle se ferme (boutons, Échap, fermeture de l'onglet).
  void OnDialogClosed(const std::string& json_retval) override {
    ModalWindow() = gfx::NativeWindow();
    HideScrim();
  }

  ReferralDialogDelegate(const ReferralDialogDelegate&) = delete;
  ReferralDialogDelegate& operator=(const ReferralDialogDelegate&) = delete;
  ~ReferralDialogDelegate() override = default;


};

}  // namespace

bool ShowModal(content::WebContents* initiator,
               const std::string& screen,
               bool chosen) {
  if (!IsEnabled() || !initiator) {
    return false;
  }
  // Déjà ouverte : on la remet devant plutôt que d'en empiler une deuxième.
  if (ModalWindow()) {
    if (views::Widget* widget =
            views::Widget::GetWidgetForNativeWindow(ModalWindow())) {
      widget->Show();
      return true;
    }
    ModalWindow() = gfx::NativeWindow();
  }
  // ⚠️ La vue PARENTE fait la modalité : sans elle, la fenêtre s'ouvrirait
  // libre et l'on retomberait sur une fenêtre qu'on peut ignorer.
  views::Widget* parent_widget = views::Widget::GetWidgetForNativeWindow(
      initiator->GetTopLevelNativeWindow());
  if (!parent_widget) {
    LOG(ERROR) << "[browther] modale du parrainage : pas de fenêtre parente";
    return false;
  }
  // La fenêtre : exactement la zone de contenu du navigateur, sans cadre ni
  // ombre. ⛔ **Pas translucide** : essayé le 2026-09-23, le fond est ressorti
  // BLANC chez Karim — le cadre de la fenêtre se peint quand même, et la page
  // ne le recouvre que si elle est opaque. C'est donc la PAGE qui peint un
  // voile plein (`app.tsx`, hôte `modal`), ⛔ on ne voit plus le Nouvel Onglet
  // derrière, et c'est assumé : voir au travers n'est pas fiable ici.
  // ⚠️ `rounded_corners` est LU par `ShowWebDialogWithParams` avant d'écraser
  // le reste : c'est le seul moyen d'arrondir les coins de la vue.
  views::Widget::InitParams params(
      views::Widget::InitParams::NATIVE_WIDGET_OWNS_WIDGET,
      views::Widget::InitParams::TYPE_WINDOW);
  params.remove_standard_frame = true;
  params.rounded_corners = gfx::RoundedCornersF(kCornerRadius);
  ShowScrim(parent_widget);
  ModalWindow() = chrome::ShowWebDialogWithParams(
      parent_widget->GetNativeView(), initiator->GetBrowserContext(),
      new ReferralDialogDelegate(screen, chosen), std::move(params));
  if (!ModalWindow()) {
    HideScrim();
    return false;
  }
  return true;
}

void ResizeModal(int delta) {
  if (!ModalWindow() || delta == 0) {
    return;
  }
  views::Widget* widget =
      views::Widget::GetWidgetForNativeWindow(ModalWindow());
  if (!widget) {
    return;
  }
  views::Widget* parent = widget->parent();
  const int room = parent
                       ? parent->GetWindowBoundsInScreen().height() - 2 * kMargin
                       : kDialogMaxHeight;
  gfx::Rect bounds = widget->GetWindowBoundsInScreen();
  const int wanted =
      std::clamp(bounds.height() + delta, kDialogMinHeight,
                 std::min(kDialogMaxHeight, std::max(room, kDialogMinHeight)));
  if (wanted == bounds.height()) {
    return;
  }
  // On garde la fenêtre CENTRÉE sur son parent en grandissant.
  bounds.set_y(bounds.y() - (wanted - bounds.height()) / 2);
  bounds.set_height(wanted);
  widget->SetBounds(bounds);
}

void CloseModal() {
  if (!ModalWindow()) {
    return;
  }
  views::Widget* widget =
      views::Widget::GetWidgetForNativeWindow(ModalWindow());
  ModalWindow() = gfx::NativeWindow();
  HideScrim();
  if (widget) {
    widget->Close();
  }
}

}  // namespace browther_referral
