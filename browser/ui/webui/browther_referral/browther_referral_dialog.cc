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
#include "chrome/browser/lifetime/application_lifetime.h"
#include "chrome/browser/ui/browser.h"
#include "chrome/browser/ui/browser_finder.h"
#include "chrome/browser/ui/browser_window.h"
#include "chrome/browser/ui/views/chrome_web_dialog_view.h"
#include "components/sessions/core/session_id.h"
#include "content/public/browser/web_contents.h"

#include "ui/base/accelerators/accelerator.h"
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
// 🔴 **Quand la place manque en hauteur, on ÉLARGIT — ⛔ on ne rapetisse pas le
// contenu.** Rétrécir la carte (`zoom`) la faisait tenir, mais Karim ne lisait
// plus rien : « ne rends pas son contenu plus petit, ce n'est pas trop visible »
// (2026-09-25). Élargir raccourcit la carte (les textes se replient moins) sans
// toucher à la taille des caractères.
constexpr int kDialogMaxWidth = 760;
constexpr int kWidenStep = 80;
constexpr int kMargin = 16;          // d'air au-dessus et en dessous
// ⚠️ 16 et pas 32 : sur un 1080p en 150 %, la fenêtre du navigateur ne fait plus
// que ~693 px utiles et 2×32 de marge suffisaient à rogner le pied de l'écran 2b.
constexpr int kMaxAdjustments = 6;   // ⛔ au-delà, l'écart ne converge pas
constexpr float kCornerRadius = 24.f;

// 🔴 **La sortie de secours du J0 imposé.** Une modale de FENÊTRE désactive sa
// fenêtre parente : ⌘W, ⌘Q, « Quitter » du Dock, la croix et le clic droit de
// la barre des tâches ne font plus rien — c'est l'OS qui honore la modalité
// qu'on a demandée, ⛔ pas un défaut qu'on peut corriger. Il faut donc une
// issue qui ne passe NI par la fenêtre du navigateur, NI par un bouton de la
// page (qui n'existe plus si la page est cassée) : Échap est le seul événement
// qui arrive jusqu'ici quoi qu'il arrive.
// ⚠️ TROIS fois de suite, ⛔ pas une : à une, ce serait la fermeture qu'on
// refuse justement au J0 imposé. Un utilisateur ne tombe pas dessus par hasard.
constexpr int kEscapesToLeave = 3;
constexpr base::TimeDelta kEscapeBurst = base::Seconds(2);

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

// 🔴 **La fenêtre du navigateur qui porte la modale.** Gardée par son
// identifiant de session, ⛔ pas par un pointeur : entre l'ouverture et la
// fermeture, la fenêtre peut avoir disparu, et un `Browser*` nu pendouillerait.
SessionID& ModalBrowserId() {
  static SessionID id = SessionID::InvalidValue();
  return id;
}

// 🔴 **Qui referme la modale ?** Le FLOW (la personne a choisi l'une des trois
// façons, la page appelle `closeModal`) ou un geste de FENÊTRE (Alt+F4, ⌘W).
// Les deux n'ont pas le même sens : le second dit « je m'en vais », et sur le
// J0 imposé il doit fermer LA FENÊTRE DU NAVIGATEUR — sinon il n'est qu'une
// échappatoire de plus, incohérente avec Échap qu'on bloque juste à côté.
bool& ClosedByFlow() {
  static bool by_flow = false;
  return by_flow;
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

  // 🔴 **Échap ×3 = quitter.** Appelé AVANT `ShouldCloseDialogOnEscape` par
  // `WebDialogView::AcceleratorPressed`, donc on voit passer chaque Échap même
  // quand on refuse d'en faire une fermeture. C'est la seule issue qui survit à
  // une page cassée (cf. `kEscapesToLeave`).
  // ⚠️ En tâche postée : on est dans le traitement du raccourci, fermer la
  // fenêtre ici ferait rentrer la pile dans elle-même.
  bool AcceleratorPressed(const ui::Accelerator& accelerator) override {
    if (chosen_ || accelerator.key_code() != ui::VKEY_ESCAPE) {
      return false;
    }
    const base::TimeTicks now = base::TimeTicks::Now();
    if (now - last_escape_ > kEscapeBurst) {
      escapes_ = 0;
    }
    last_escape_ = now;
    if (++escapes_ < kEscapesToLeave) {
      return true;  // avalé : le J0 reste imposé
    }
    LOG(WARNING) << "[browther] J0 imposé : sortie de secours (Échap ×"
                 << kEscapesToLeave << ")";
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce(&QuitFromModal, /*whole_app=*/false));
    return true;
  }

  // ⭐ Le voile de la fenêtre du navigateur disparaît AVEC la modale, quelle
  // que soit la façon dont elle se ferme (boutons, Échap, fermeture de l'onglet).
  //
  // 🔴 **Fermer le J0 IMPOSÉ, c'est QUITTER.** Une modale de fenêtre désactive
  // sa fenêtre parente (`EnableWindow(FALSE)` sur Windows, feuille modale sur
  // macOS) : tant qu'elle est là, le navigateur ne se ferme plus — Karim n'a
  // pas pu le fermer, ni sous Windows ni sous macOS (2026-09-25). Et Alt+F4
  // fermait la modale seule, ce qui rendait le J0 contournable par un geste
  // MOINS visible qu'Échap, qu'on bloque juste au-dessus.
  // ⇒ Un geste de fenêtre sur le J0 imposé ferme LA FENÊTRE DU NAVIGATEUR :
  // c'est la sortie coûteuse déjà admise (le circuit est sur le disque, J0
  // revient au lancement suivant), et elle ne se déclenche jamais quand c'est
  // le flow qui referme.
  // ⚠️ En tâche postée : on est dans la fermeture de la modale, refermer sa
  // fenêtre parente au milieu ferait rentrer la pile dans elle-même.
  void OnDialogClosed(const std::string& json_retval) override {
    ModalWidget() = nullptr;
    HideScrim();
    if (chosen_ || ClosedByFlow()) {
      return;
    }
    base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindOnce([](SessionID id) {
          Browser* browser = chrome::FindBrowserWithID(id);
          if (browser && browser->window()) {
            browser->window()->Close();
          }
        }, ModalBrowserId()));
  }

  ReferralDialogDelegate(const ReferralDialogDelegate&) = delete;
  ReferralDialogDelegate& operator=(const ReferralDialogDelegate&) = delete;
  ~ReferralDialogDelegate() override = default;

 private:
  const bool chosen_;
  int escapes_ = 0;
  base::TimeTicks last_escape_;


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
  ClosedByFlow() = false;
  Browser* browser = chrome::FindBrowserWithTab(initiator);
  ModalBrowserId() = browser ? browser->session_id() : SessionID::InvalidValue();
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

ResizeResult ResizeModal(int delta, bool fresh) {
  views::Widget* widget = ModalWidget();
  if (!widget || delta == 0) {
    return ResizeResult();
  }
  // 🔴 **Le compte d'ajustements se remet à zéro à CHAQUE écran**, ⛔ pas une
  // fois par modale : le flow en enchaîne plusieurs (J0 → 2b → inviter) et un
  // budget global de six tours s'épuisait en route, laissant les derniers
  // écrans à la taille du précédent. La page dit `fresh` au premier ajustement
  // qui suit un changement de hauteur.
  if (fresh) {
    Adjustments() = 0;
  }
  views::Widget* parent = widget->parent();
  gfx::Rect bounds = widget->GetWindowBoundsInScreen();
  const gfx::Rect room = parent ? parent->GetWindowBoundsInScreen() : bounds;
  const int target = bounds.height() + delta;
  // 🔴 **Le plafond part du HAUT RÉEL de la modale, ⛔ pas de la hauteur de la
  // fenêtre.** Sur macOS la modale est une FEUILLE (`sheet`) : AppKit l'accroche
  // sous la barre d'outils du parent et IGNORE le `y` qu'on demande — mesuré
  // deux fois le 2026-09-25, toujours 77 px sous le haut de la fenêtre, quoi
  // qu'on pose. Croire qu'on l'a recentrée et raisonner sur la hauteur totale
  // faisait dépasser la carte par le bas tout en laissant un blanc en haut.
  // ⚠️ `bounds` est lu AVANT tout `SetBounds` de ce tour : c'est la seule
  // lecture fiable (voir l'avertissement plus bas).
  const int ceiling = std::clamp(room.bottom() - bounds.y() - kMargin,
                                 kDialogMinHeight, kDialogMaxHeight);
  const int wanted = std::clamp(target, kDialogMinHeight, ceiling);
  // 🔴 **La place manque : il faut le DIRE.** Sinon la page croit la fenêtre à
  // la bonne taille et laisse la carte coupée net, sans barre de défilement ni
  // rien qui le signale (la sortie « du'a » de l'écran 2b avait disparu —
  // recette Karim, 2026-09-25). Prévenue, elle rétrécit la carte pour que tout
  // tienne. ⚠️ Calculé AVANT la borne d'ajustements : une fenêtre qui ne bouge
  // plus reste trop courte, et c'est justement ce cas-là qu'il faut remonter.
  const bool clamped = target > ceiling;

  // 🔴 **Un nombre d'ajustements BORNÉ, remis à zéro à chaque écran.** L'écart
  // vient de la page ; rien ne garantit qu'il converge (l'échelle d'affichage
  // fait que la zone visible ne grandit pas exactement de ce qu'on demande) —
  // sans borne, la fenêtre a GLISSÉ hors de l'écran (2026-09-24). ⛔ Mais le
  // budget ne peut pas être PAR MODALE : le flow enchaîne plusieurs écrans
  // (J0 → 2b → inviter) et six tours s'épuisaient en route, laissant les
  // derniers à la taille du précédent — c'est ce qui a fait déborder 2b chez
  // Karim (2026-09-25).
  ResizeResult result;
  result.clamped = clamped;

  // ⭐ Il manque de la hauteur : on prend de la LARGEUR. Un cran à la fois, la
  // page se remesure entre chaque — la carte raccourcit à mesure qu'elle
  // s'élargit. ⚠️ Monotone : on n'élargit jamais à l'envers, sinon la mise en
  // page oscillerait (plus large → plus court → ça rentre → plus étroit → …).
  if (clamped) {
    const int widest = std::min(kDialogMaxWidth,
                                std::max(kDialogWidth, room.width() - 2 * kMargin));
    if (bounds.width() < widest) {
      bounds.set_width(std::min(widest, bounds.width() + kWidenStep));
      result.widened = true;
    }
  }
  if (++Adjustments() > kMaxAdjustments ||
      (wanted == bounds.height() && !result.widened)) {
    return result;
  }
  // 🔴 On RECENTRE sur la fenêtre parente à chaque fois, ⛔ on ne décale PAS y
  // d'une fraction de la croissance : un décalage relatif se cumule et la
  // fenêtre finit par sortir de l'écran. Recentrer est idempotent.
  // ⛔ **Ne JAMAIS relire `GetWindowBoundsInScreen()` juste après un
  // `SetBounds()` pour enchaîner** : sur macOS il rend encore l'ANCIENNE
  // position (un appel de retard). Un premier placement suivi d'un
  // redimensionnement bâti sur cette lecture remettait la fenêtre là où elle
  // était — le bug exact du 2026-09-25 (mesuré : on posait y=240, on relisait
  // 301, on re-posait 301). Un seul `SetBounds`, bâti sur `room`.
  bounds.set_height(wanted);
  bounds.set_x(room.x() + (room.width() - bounds.width()) / 2);
  bounds.set_y(room.y() + (room.height() - wanted) / 2);
  widget->SetBounds(bounds);
  return result;
}

void QuitFromModal(bool whole_app) {
  const SessionID id = ModalBrowserId();
  // ⚠️ C'est un départ VOULU et explicite : on passe par le chemin du flow pour
  // que `OnDialogClosed` ne referme pas la fenêtre une deuxième fois.
  ClosedByFlow() = true;
  views::Widget* widget = ModalWidget();
  ModalWidget() = nullptr;
  HideScrim();
  if (widget) {
    widget->Close();
  }
  // ⚠️ En tâche postée : la modale est en train de se fermer, s'attaquer à sa
  // fenêtre parente au milieu ferait rentrer la pile dans elle-même.
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(
                     [](SessionID id, bool whole_app) {
                       if (whole_app) {
                         chrome::AttemptUserExit();
                         return;
                       }
                       Browser* browser = chrome::FindBrowserWithID(id);
                       if (browser && browser->window()) {
                         browser->window()->Close();
                       }
                     },
                     id, whole_app));
}

void CloseModal() {
  // ⭐ C'est le FLOW qui referme (choix fait, ou filet du minuteur) : ⛔ ne pas
  // fermer la fenêtre du navigateur avec.
  ClosedByFlow() = true;
  views::Widget* widget = ModalWidget();
  ModalWidget() = nullptr;
  HideScrim();
  if (widget) {
    widget->Close();
  }
}

}  // namespace browther_referral
