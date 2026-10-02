// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_BROWSER_BROWTHER_FEATURE_TEMPORARY_SWITCH_H_
#define BRAVE_BROWSER_BROWTHER_FEATURE_TEMPORARY_SWITCH_H_

#include <string_view>

#include "base/memory/raw_ptr.h"
#include "base/supports_user_data.h"
#include "base/time/time.h"
#include "base/timer/timer.h"
#include "components/prefs/pref_change_registrar.h"

class Profile;

// Browther : « seulement 5 min » (desktop), pour Sawtunaa et Basarunaa. Port
// de `FeatureTemporarySwitch.swift` (iOS, la référence de comportement de la
// maquette validée par Karim le 2026-10-01) :
//  - juste après une bascule, le panneau propose de revenir automatiquement à
//    l'état d'avant dans 5 min, dans les deux sens ;
//  - l'interrupteur montre toujours l'état ACTUEL : la pref n'est touchée qu'à
//    l'échéance ;
//  - revenir plus tôt = rebasculer l'interrupteur (le clic sur l'icône ouvre
//    le panneau, recette iOS 2026-10-01) ; toute bascule qui rejoint l'état
//    d'avant, d'où qu'elle vienne (réglages, pause du parrainage…), annule le
//    retour ;
//  - échéance enregistrée (prefs `*_temp_revert_at/to`) : un navigateur fermé
//    pendant le compte à rebours retrouve l'état d'avant au lancement ;
//  - ⛔ Sawtunaa : pas de rallumage pendant la pause du parrainage.
//
// Une instance par profil ET par fonctionnalité, accrochée au Profile
// (SupportsUserData) et créée à la première demande — l'icône de la barre
// d'outils la demande à l'ouverture de chaque fenêtre, ce qui la crée dès le
// lancement. L'UI observe la pref d'échéance (PrefChangeRegistrar) pour se
// redessiner.

// Basarunaa (2026-10-01). Déclarées ici plutôt que dans
// components/constants/pref_names.h : cet en-tête est inclus presque partout,
// et y toucher recompile une bonne partie du navigateur (~3 h sur le Mac).
inline constexpr char kBasarunaaTempRevertAt[] =
    "brave.basarunaa.temp_revert_at";
inline constexpr char kBasarunaaTempRevertTo[] =
    "brave.basarunaa.temp_revert_to";

class FeatureTemporarySwitch : public base::SupportsUserData::Data {
 public:
  enum class Feature { kSawtunaa, kBasarunaa };

  static constexpr base::TimeDelta kDuration = base::Minutes(5);

  static FeatureTemporarySwitch* GetForProfile(Profile* profile,
                                               Feature feature);
  // Pref d'échéance de |feature| (à observer pour redessiner l'UI).
  static const char* RevertAtPref(Feature feature);

  FeatureTemporarySwitch(Profile* profile, Feature feature);
  FeatureTemporarySwitch(const FeatureTemporarySwitch&) = delete;
  FeatureTemporarySwitch& operator=(const FeatureTemporarySwitch&) = delete;
  ~FeatureTemporarySwitch() override;

  bool IsActive() const;
  // Temps restant (zéro si rien n'est programmé).
  base::TimeDelta Remaining() const;

  // Programme le retour à l'état d'AVANT la bascule qui vient d'avoir lieu.
  void Start();
  // « Ne pas réactiver » / « Ne pas couper » : l'état actuel devient durable.
  void Keep();

 private:
  const char* EnabledPref() const;
  const char* RevertToPref() const;
  const char* FeatureName() const;

  void OnEnabledChanged();
  void Finish(std::string_view reason);
  void Clear();
  void Arm();
  void Track(std::string_view event, std::string_view reason);

  raw_ptr<Profile> profile_;
  const Feature feature_;
  PrefChangeRegistrar pref_change_registrar_;
  base::OneShotTimer timer_;
};

#endif  // BRAVE_BROWSER_BROWTHER_FEATURE_TEMPORARY_SWITCH_H_
