/* Copyright (c) 2026 dev&din. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

// Browther : on RÉ-ACTIVE le prompt "définir Browther par défaut" (type Chrome).
// Brave neutralisait l'app-menu item (forçait `show_app_menu_item_ = false`),
// supprimant tout rappel pour l'utilisateur. On laisse passer le comportement
// Chromium upstream : chip dans le menu ⋮ + cooldown natif
// (DefaultBrowserPromptManager::ShouldShowPrompts : ré-affichage après 21 jours
// si refusé, max 5 fois). Piloté par la pref kDefaultBrowserPromptEnabled
// (déjà enregistrée à `true` dans brave_local_state_prefs.cc). Ne s'affiche pas
// si Browther est déjà le navigateur par défaut.
//
// NB : override volontairement "pass-through" (et non supprimé) pour que tout
// retour de la suppression côté Brave lors d'un `git merge upstream` ressorte
// en conflit visible plutôt que de re-désactiver silencieusement le prompt.

#include <chrome/browser/ui/startup/default_browser_prompt/default_browser_prompt_manager.cc>
