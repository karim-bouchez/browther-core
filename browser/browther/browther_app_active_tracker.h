// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_BROWSER_BROWTHER_BROWTHER_APP_ACTIVE_TRACKER_H_
#define BRAVE_BROWSER_BROWTHER_BROWTHER_APP_ACTIVE_TRACKER_H_

#include "base/memory/weak_ptr.h"
#include "base/values.h"
#include "chrome/browser/shell_integration.h"
#include "chrome/browser/ui/browser_list_observer.h"

class Browser;

// Browther : `app_active` — « actif aujourd'hui » (desktop). Au plus un par
// jour calendaire LOCAL et par installation, avec l'ÉTAT des réglages
// (navigateur par défaut, floutage, musique) et non les gestes. Même event et
// mêmes propriétés qu'Android (`BrowtherDailyActive.java`) et iOS
// (private/docs/ANALYTICS.md).
//
// Déclencheurs : une fenêtre de navigateur s'ouvre (le lancement) ou repasse
// au premier plan. Un navigateur resté ouvert plusieurs jours compte donc
// chaque jour où on y revient. ⛔ Pas de minuteur : un navigateur ouvert mais
// inutilisé ne compte pas.
//
// Le jour et le consentement sont tenus par `BrowtherAnalyticsService`
// (`IsAppActiveDue` / `TrackAppActive`) ; ici, seulement le branchement sur les
// fenêtres et la lecture de l'état. Une instance pour le processus, jamais
// détruite (comme `brave::BraveWindowTracker`).
class BrowtherAppActiveTracker : public BrowserListObserver {
 public:
  BrowtherAppActiveTracker();
  BrowtherAppActiveTracker(const BrowtherAppActiveTracker&) = delete;
  BrowtherAppActiveTracker& operator=(const BrowtherAppActiveTracker&) = delete;
  ~BrowtherAppActiveTracker() override;

  // Après `BrowtherAnalyticsService::Initialize`.
  static void CreateInstance();

 private:
  // BrowserListObserver:
  void OnBrowserAdded(Browser* browser) override;
  void OnBrowserSetLastActive(Browser* browser) override;

  void MaybeTrack(Browser* browser);
  void OnDefaultBrowserChecked(base::DictValue properties,
                               shell_integration::DefaultWebClientState state);

  // Une question au système est déjà partie : les activations de fenêtre qui
  // arrivent avant sa réponse n'en posent pas une deuxième.
  bool check_pending_ = false;

  base::WeakPtrFactory<BrowtherAppActiveTracker> weak_factory_{this};
};

#endif  // BRAVE_BROWSER_BROWTHER_BROWTHER_APP_ACTIVE_TRACKER_H_
