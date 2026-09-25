// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/browser/ui/webui/browther_referral/browther_referral_dialog.h"

#include <algorithm>
#include <memory>
#include <string>
#include <vector>

#include "base/functional/bind.h"
#include "base/logging.h"
#include "base/task/sequenced_task_runner.h"
#include "base/time/time.h"
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
constexpr int kMargin = 16;          // d'air au-dessus et en dessous
// ⚠️ 16 et pas 32 : sur un 1080p en 150 %, la fenêtre du navigateur ne fait plus
// que ~693 px utiles et 2×32 de marge suffisaient à rogner le pied de l'écran 2b.
constexpr int kMaxAdjustments = 6;   // ⛔ au-delà, l'écart ne converge pas
constexpr float kCornerRadius = 24.f;

// ⚠️ La fenêtre ne contient QUE la carte : sans cadre, coins arrondis, à ses
// cotes. Le voile, lui, est posé DANS la fenêtre du navigateur
// (`browther_referral_scrim.h`) — une fenêtre ne peut pas assombrir ce qu'il y
// a derrière elle. Sinon on voit un bloc dans un bloc, avec sa propre barre
// de défilement, et rien ne dit que le reste est bloqué (recette Karim,
// 2026-09-23). Les cotes viennent donc de la fenêtre parente, pas d'ici.

// La modale ouverte, s'il y en a une — une seule à la fois par principe.
//
// 🔴 On garde un `views::Widget*`, ⛔ PAS un `gfx::NativeWindow` : les deux
// plateformes exigent l'inverse l'une de l'autre. Sur macOS c'est un objet à
// destructeur (une globale nue déclenche `-Wexit-time-destructors`), sur
// Windows c'est un `aura::Window*` trivial (et `base::NoDestructor` le REFUSE
// par `static_assert`). Un pointeur nu est trivial des deux côtés.
// ⚠️ Remis à zéro par `OnDialogClosed`, quelle que soit la façon dont la
// fenêtre se ferme — sinon il pendouille.
views::Widget*& ModalWidget() {
  static views::Widget* widget = nullptr;
  return widget;
}

// Combien de fois la page a demandé un ajustement pour CETTE modale.
int& Adjustments() {
  static int count = 0;
  return count;
}

// 🔴 **Le filet contre une fenêtre MORTE.** Une modale de fenêtre dont la page
// ne s'affiche pas bloquerait le navigateur sans aucune issue — et sur le J0
// imposé, Échap ne répond pas (c'est le principe). La page donne signe de vie
// dès son premier appel au pont (`getContext`, moins d'une seconde) ; sans ce
// signe au bout du délai, on referme. ⛔ N'affecte en rien le cas normal.
constexpr base::TimeDelta kDeadModalDelay = base::Seconds(12);

bool& ModalAlive() {
  static bool alive = false;
  return alive;
}

// Un compteur pour ne pas refermer la modale SUIVANTE avec le minuteur de la
// précédente.
int& ModalGeneration() {
  static int generation = 0;
  return generation;
}

class ReferralDialogDelegate : public ui::WebDialogDelegate {
 public:
  ReferralDialogDelegate(const std::string& screen, bool chosen)
      : chosen_(chosen) {
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

  // 🔴 **Échap ne ferme QUE ce que la personne a ouvert elle-même.** Sur le J0
  // imposé, il ne faut pas pouvoir sortir sans choisir l'une des trois façons
  // (§ 12.16) — et fermer le navigateur n'y change rien : le circuit est écrit
  // sur le disque, J0 revient au Nouvel Onglet suivant.
  // ⚠️ Le filet contre une fenêtre morte n'est donc PAS Échap, c'est
  // `ArmDeadModalGuard` : si la page ne donne pas signe de vie, on ferme.
  bool ShouldCloseDialogOnEscape() const override { return chosen_; }

  // ⭐ Le voile de la fenêtre du navigateur disparaît AVEC la modale, quelle
  // que soit la façon dont elle se ferme (boutons, Échap, fermeture de l'onglet).
  void OnDialogClosed(const std::string& json_retval) override {
    ModalWidget() = nullptr;
    HideScrim();
  }

  ReferralDialogDelegate(const ReferralDialogDelegate&) = delete;
  ReferralDialogDelegate& operator=(const ReferralDialogDelegate&) = delete;
  ~ReferralDialogDelegate() override = default;

 private:
  const bool chosen_;


};

}  // namespace

bool ShowModal(content::WebContents* initiator,
               const std::string& screen,
               bool chosen) {
  if (!IsEnabled() || !initiator) {
    return false;
  }
  // Déjà ouverte : on la remet devant plutôt que d'en empiler une deuxième.
  if (ModalWidget()) {
    ModalWidget()->Show();
    return true;
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
  Adjustments() = 0;
  ModalAlive() = false;
  ModalWidget() = views::Widget::GetWidgetForNativeWindow(
      chrome::ShowWebDialogWithParams(
          parent_widget->GetNativeView(), initiator->GetBrowserContext(),
          new ReferralDialogDelegate(screen, chosen), std::move(params)));
  if (!ModalWidget()) {
    HideScrim();
    return false;
  }
  const int generation = ++ModalGeneration();
  base::SequencedTaskRunner::GetCurrentDefault()->PostDelayedTask(
      FROM_HERE, base::BindOnce(
                     [](int generation) {
                       if (ModalGeneration() != generation || ModalAlive()) {
                         return;
                       }
                       LOG(ERROR) << "[browther] la modale du parrainage n'a "
                                     "pas répondu : fermeture";
                       CloseModal();
                     },
                     generation),
      kDeadModalDelay);
  return true;
}

void NoteModalAlive() {
  ModalAlive() = true;
}

bool ResizeModal(int delta) {
  views::Widget* widget = ModalWidget();
  if (!widget || delta == 0) {
    return false;
  }
  views::Widget* parent = widget->parent();
  gfx::Rect bounds = widget->GetWindowBoundsInScreen();
  const gfx::Rect room =
      parent ? parent->GetWindowBoundsInScreen() : bounds;
  const int ceiling =
      std::min(kDialogMaxHeight, std::max(kDialogMinHeight,
                                          room.height() - 2 * kMargin));
  const int target = bounds.height() + delta;
  const int wanted = std::clamp(target, kDialogMinHeight, ceiling);
  // 🔴 **La place manque : il faut le DIRE.** La page croit sinon la fenêtre à
  // la bonne taille et laisse la carte coupée net, sans barre de défilement ni
  // rien qui le signale (la sortie « du'a » de l'écran 2b, recette Karim
  // 2026-09-25). On le calcule AVANT toute sortie anticipée : une fenêtre déjà
  // au plafond ne bouge plus, mais elle reste trop courte, et c'est justement
  // ce cas-là qu'il faut remonter.
  const bool clamped = target > ceiling;
  // 🔴 **Un nombre d'ajustements BORNÉ.** L'écart vient de la page ; rien ne
  // garantit qu'il converge (sur Windows, l'échelle d'affichage fait que la
  // zone visible ne grandit pas exactement de ce qu'on demande). Sans cette
  // borne, la page redemande sans fin — la fenêtre a GLISSÉ hors de l'écran
  // chez Karim (2026-09-24). Deux ou trois tours suffisent quand ça converge.
  if (++Adjustments() > kMaxAdjustments) {
    return clamped;
  }
  if (wanted == bounds.height()) {
    return clamped;
  }
  // 🔴 On RECENTRE sur la fenêtre parente à chaque fois, ⛔ on ne décale PAS y
  // de la moitié de la croissance : un décalage relatif se cumule, et une
  // suite d'ajustements qui ne converge pas fait descendre la fenêtre jusqu'à
  // la faire disparaître. Recentrer est idempotent.
  bounds.set_height(wanted);
  bounds.set_x(room.x() + (room.width() - bounds.width()) / 2);
  bounds.set_y(room.y() + (room.height() - wanted) / 2);
  widget->SetBounds(bounds);
  return clamped;
}

void CloseModal() {
  views::Widget* widget = ModalWidget();
  ModalWidget() = nullptr;
  HideScrim();
  if (widget) {
    widget->Close();
  }
}

}  // namespace browther_referral
