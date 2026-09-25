// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_BROWSER_UI_WEBUI_BROWTHER_REFERRAL_BROWTHER_REFERRAL_DIALOG_H_
#define BRAVE_BROWSER_UI_WEBUI_BROWTHER_REFERRAL_BROWTHER_REFERRAL_DIALOG_H_

#include <string>

namespace content {
class WebContents;
}

// 🔴 **Les fenêtres du flow qui ATTENDENT une réponse sont des MODALES DE
// FENÊTRE**, ⛔ pas des cartes posées sur le Nouvel Onglet.
//
// Une carte dans une page se contourne sans rien décider : on tape dans la
// barre d'adresse, on passe sur un autre onglet, et elle disparaît avec la page
// (recette Karim, 2026-09-23 : « la personne va juste ignorer »). Or J0 est le
// seul moment où Browther demande vraiment quelque chose, une fois par semaine
// au plus : il faut qu'il se lise et qu'il se termine par un choix.
//
// Ce que ça change, concrètement : la fenêtre du navigateur (barre d'adresse et
// onglets compris) n'accepte plus rien tant que la modale est là.
//
// ⚠️ **Échappatoire volontaire : Échap ferme la modale.** Un build où l'app ne
// se charge pas (fichiers non déployés) laisserait sinon une fenêtre morte.
// Échap est un geste EXPLICITE, ⛔ pas « ignorer » : l'écran revient.
// ⚠️ La modale n'est pas un kiosque : une AUTRE fenêtre (⌘N) reste utilisable.
// C'est voulu — un navigateur qu'on ne peut plus piloter, on le désinstalle.
namespace browther_referral {

// Ouvre (ou réutilise) la modale sur l'écran demandé — `paused`, `announce`…
// tel que l'app les nomme. ⭐ Rend `false` quand elle n'a PAS pu s'ouvrir (pas
// de fenêtre parente) : l'app affiche alors l'écran dans la page — contournable,
// mais VU. ⛔ Jamais d'échec silencieux : ce serait perdre le seul moment où
// Browther demande quelque chose.
// ⭐ `chosen` : la personne a OUVERT l'écran elle-même (« Débloquer » de la
// popup Sawtunaa). Il se ferme alors normalement — croix, Échap — et n'arme pas
// le circuit : « une fenêtre qu'on pouvait fermer n'en ouvre pas une qu'on ne
// peut plus fermer » (`docs/PARRAINAGE.md` § 12.16).
bool ShowModal(content::WebContents* initiator,
               const std::string& screen,
               bool chosen = false);

// ⭐ La fenêtre prend la hauteur de la carte : chaque écran du flow a la sienne,
// et une taille fixe faisait défiler alors que la place ne manquait pas.
//
// 🔴 **Un CALCUL, ⛔ pas une boucle.** La page envoie la hauteur NATURELLE de la
// carte (`card`) ET sa zone visible (`viewport`) : la différence entre la
// fenêtre et cette zone visible donne l'épaisseur du CADRE, qu'on mesure au lieu
// de la deviner. La bonne hauteur tombe alors d'un coup, sans convergence.
// La première version faisait converger la fenêtre par ajustements successifs :
// six symptômes, six rustines, et Karim voyait encore la carte déborder
// (2026-09-25). ⛔ Ne pas y revenir.
struct ResizeResult {
  // Tout tient. Sinon la page resserre ses espacements, puis fait défiler.
  bool fits = true;
};
ResizeResult FitModal(int card, int viewport);

// 🔴 **La sortie de secours, celle qui marche quoi qu'il arrive.** Une modale
// de fenêtre désactive sa fenêtre parente : tant qu'elle est là, ⌘W, ⌘Q, le
// « Quitter » du Dock et le clic droit de la barre des tâches ne font RIEN
// (constaté sur macOS ET Windows, 2026-09-25). La page de la modale, elle,
// reçoit toujours le clavier — c'est donc ELLE qui appelle ceci sur ⌘W / ⌘Q /
// Alt+F4, et le navigateur se ferme comme la personne le demandait.
// ⚠️ `whole_app` : ⌘Q quitte l'application, ⌘W ne ferme que la fenêtre.
void QuitFromModal(bool whole_app);

// ⭐ La page de la modale a donné signe de vie (premier appel au pont). Sans ce
// signe, la modale se referme d'elle-même au bout de quelques secondes : sur le
// J0 imposé, Échap ne répond pas, et une page qui ne s'affiche pas laisserait
// le navigateur bloqué sans issue.
void NoteModalAlive();

// Referme celle qui est ouverte, s'il y en a une (appelée quand l'app a fini).
void CloseModal();

}  // namespace browther_referral

#endif  // BRAVE_BROWSER_UI_WEBUI_BROWTHER_REFERRAL_BROWTHER_REFERRAL_DIALOG_H_
