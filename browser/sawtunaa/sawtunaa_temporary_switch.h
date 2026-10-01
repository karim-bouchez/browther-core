// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_BROWSER_SAWTUNAA_SAWTUNAA_TEMPORARY_SWITCH_H_
#define BRAVE_BROWSER_SAWTUNAA_SAWTUNAA_TEMPORARY_SWITCH_H_

#include <string_view>

#include "base/memory/raw_ptr.h"
#include "base/supports_user_data.h"
#include "base/time/time.h"
#include "base/timer/timer.h"
#include "components/prefs/pref_change_registrar.h"

class Profile;

// Browther : Sawtunaa « seulement 2 min » (desktop). Port de
// `SawtunaaTemporarySwitch.swift` (iOS, la référence de comportement de la
// maquette validée par Karim le 2026-10-01) :
//  - juste après une bascule, le panneau propose de revenir automatiquement à
//    l'état d'avant dans 2 min, dans les deux sens ;
//  - l'interrupteur montre toujours l'état ACTUEL : la pref n'est touchée qu'à
//    l'échéance ;
//  - revenir plus tôt = rebasculer l'interrupteur (le clic sur l'icône ouvre
//    le panneau, recette iOS 2026-10-01) ; toute bascule qui rejoint l'état d'avant, d'où qu'elle
//    vienne (réglages, pause du parrainage…), annule le retour ;
//  - échéance enregistrée (`kSawtunaaTempRevertAt`) : un navigateur fermé
//    pendant le compte à rebours retrouve l'état d'avant au lancement ;
//  - ⛔ pas de rallumage pendant la pause du parrainage.
//
// Une instance par profil, accrochée au Profile (SupportsUserData) et créée à
// la première demande — l'icône de la barre d'outils la demande à
// l'ouverture de chaque fenêtre, ce qui la crée dès le lancement. L'UI
// observe `kSawtunaaTempRevertAt` (PrefChangeRegistrar) pour se redessiner.
class SawtunaaTemporarySwitch : public base::SupportsUserData::Data {
 public:
  static constexpr base::TimeDelta kDuration = base::Minutes(2);

  static SawtunaaTemporarySwitch* GetForProfile(Profile* profile);

  explicit SawtunaaTemporarySwitch(Profile* profile);
  SawtunaaTemporarySwitch(const SawtunaaTemporarySwitch&) = delete;
  SawtunaaTemporarySwitch& operator=(const SawtunaaTemporarySwitch&) = delete;
  ~SawtunaaTemporarySwitch() override;

  bool IsActive() const;
  // Temps restant (zéro si rien n'est programmé).
  base::TimeDelta Remaining() const;

  // Programme le retour à l'état d'AVANT la bascule qui vient d'avoir lieu.
  void Start();
  // « Ne pas réactiver » / « Ne pas couper » : l'état actuel devient durable.
  void Keep();
 private:
  void OnEnabledChanged();
  void Finish(std::string_view reason);
  void Clear();
  void Arm();
  void Track(std::string_view event, std::string_view reason);

  raw_ptr<Profile> profile_;
  PrefChangeRegistrar pref_change_registrar_;
  base::OneShotTimer timer_;
};

#endif  // BRAVE_BROWSER_SAWTUNAA_SAWTUNAA_TEMPORARY_SWITCH_H_
