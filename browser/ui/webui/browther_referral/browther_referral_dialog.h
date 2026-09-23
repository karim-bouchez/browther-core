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
// tel que l'app les nomme. ⛔ Sans navigateur trouvable, rien ne s'ouvre.
void ShowModal(content::WebContents* initiator, const std::string& screen);

// Referme celle qui est ouverte, s'il y en a une (appelée quand l'app a fini).
void CloseModal();

}  // namespace browther_referral

#endif  // BRAVE_BROWSER_UI_WEBUI_BROWTHER_REFERRAL_BROWTHER_REFERRAL_DIALOG_H_
