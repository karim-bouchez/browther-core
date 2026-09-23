// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_BROWSER_UI_VIEWS_BROWTHER_BROWTHER_REFERRAL_SCRIM_H_
#define BRAVE_BROWSER_UI_VIEWS_BROWTHER_BROWTHER_REFERRAL_SCRIM_H_

namespace views {
class Widget;
}

// 🔴 **Le voile de la modale du parrainage, posé DANS la fenêtre du navigateur.**
//
// La modale est une fenêtre à part : elle ne peut ni assombrir ni flouter ce
// qu'il y a derrière elle — `backdrop-filter` ne voit que ce qui est peint dans
// SA fenêtre. Assombrir depuis la page revenait donc à peindre un grand
// rectangle noir, qui masquait tout (recette Karim, 2026-09-23 : « pourquoi tu
// me mets l'écran en noir ? »).
//
// ⭐ Le voile est donc une COUCHE du compositeur ajoutée à la fenêtre du
// navigateur, par-dessus tout : onglets, barre d'adresse et contenu. Elle
// assombrit ET floute pour de vrai (`ui::Layer::SetBackgroundBlur`), parce
// qu'elle vit dans le même compositeur que ce qu'elle recouvre.
//
// ⚠️ Une COUCHE, ⛔ pas une `views::View` : une vue enfant entrerait dans le
// layout de `BrowserView` et serait redimensionnée par lui.
namespace browther_referral {

// Pose le voile sur la fenêtre (idempotent), ou le retire.
void ShowScrim(views::Widget* browser_widget);
void HideScrim();

}  // namespace browther_referral

#endif  // BRAVE_BROWSER_UI_VIEWS_BROWTHER_BROWTHER_REFERRAL_SCRIM_H_
