// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Onboarding
import Preferences

/// Rejouer l'introduction sans réinstaller l'app — **builds de développement
/// uniquement** (la ligne vit dans la section de débogage des Réglages, qui
/// n'apparaît qu'hors build officiel ou après saisie du code développeur).
///
/// ⚠️ À ne pas confondre avec « Onboarding Debug Menu », juste au-dessus dans
/// la même section : celui-là reconstruit sa propre liste d'étapes (avec le
/// splash Brave, sans l'étape des canaux) et ne montre donc **pas** ce que voit
/// un nouvel arrivant. Le vrai parcours est celui de
/// `BrowserViewController.presentFocusOnboarding()`.
enum BrowtherOnboardingReplay {

  /// Remet l'app dans l'état « personne n'a encore vu l'introduction ».
  ///
  /// ⛔ Ne touche pas aux surfaces dev&din : la fin de l'introduction re-marque
  /// « Ce qui a changé » comme vu et ré-arme le verrou de 3 jours, exactement
  /// comme chez un nouvel arrivant. C'est voulu — sinon on testerait un
  /// enchaînement qui n'existe pour personne.
  static func reset() {
    Preferences.Onboarding.basicOnboardingCompleted.value = OnboardingState.unseen.rawValue
    Preferences.FocusOnboarding.focusOnboardingFinished.value = false
    Preferences.FocusOnboarding.urlBarIndicatorShowBeShown.value = false
  }
}
