// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/browser/browther/feature_temporary_switch.h"

#include <algorithm>
#include <memory>
#include <string>

#include "base/functional/bind.h"
#include "base/values.h"
#include "brave/browser/browther/referral/browther_referral_access.h"
#include "brave/components/browther_analytics/browther_analytics_service.h"
#include "brave/components/constants/pref_names.h"
#include "chrome/browser/browser_process.h"
#include "chrome/browser/profiles/profile.h"
#include "components/prefs/pref_service.h"

namespace {

const char* UserDataKey(FeatureTemporarySwitch::Feature feature) {
  return feature == FeatureTemporarySwitch::Feature::kSawtunaa
             ? "browther_sawtunaa_temporary_switch"
             : "browther_basarunaa_temporary_switch";
}

}  // namespace

// static
FeatureTemporarySwitch* FeatureTemporarySwitch::GetForProfile(
    Profile* profile,
    Feature feature) {
  if (!profile) {
    return nullptr;
  }
  const char* key = UserDataKey(feature);
  auto* existing =
      static_cast<FeatureTemporarySwitch*>(profile->GetUserData(key));
  if (existing) {
    return existing;
  }
  auto created = std::make_unique<FeatureTemporarySwitch>(profile, feature);
  auto* raw = created.get();
  profile->SetUserData(key, std::move(created));
  return raw;
}

// static
const char* FeatureTemporarySwitch::RevertAtPref(Feature feature) {
  return feature == Feature::kSawtunaa ? kSawtunaaTempRevertAt
                                       : kBasarunaaTempRevertAt;
}

FeatureTemporarySwitch::FeatureTemporarySwitch(Profile* profile,
                                               Feature feature)
    : profile_(profile), feature_(feature) {
  pref_change_registrar_.Init(profile_->GetPrefs());
  pref_change_registrar_.Add(
      EnabledPref(),
      base::BindRepeating(&FeatureTemporarySwitch::OnEnabledChanged,
                          base::Unretained(this)));
  if (IsActive()) {
    if (Remaining().is_zero()) {
      // Le navigateur était fermé à l'échéance : on rétablit sans attendre.
      Finish("relaunch");
    } else {
      Arm();
    }
  }
}

FeatureTemporarySwitch::~FeatureTemporarySwitch() = default;

const char* FeatureTemporarySwitch::EnabledPref() const {
  return feature_ == Feature::kSawtunaa ? kSawtunaaEnabled : kBasarunaaEnabled;
}

const char* FeatureTemporarySwitch::RevertToPref() const {
  return feature_ == Feature::kSawtunaa ? kSawtunaaTempRevertTo
                                        : kBasarunaaTempRevertTo;
}

const char* FeatureTemporarySwitch::FeatureName() const {
  return feature_ == Feature::kSawtunaa ? "sawtunaa" : "basarunaa";
}

bool FeatureTemporarySwitch::IsActive() const {
  return !profile_->GetPrefs()->GetTime(RevertAtPref(feature_)).is_null();
}

base::TimeDelta FeatureTemporarySwitch::Remaining() const {
  const base::Time at = profile_->GetPrefs()->GetTime(RevertAtPref(feature_));
  if (at.is_null()) {
    return base::TimeDelta();
  }
  return std::max(base::TimeDelta(), at - base::Time::Now());
}

void FeatureTemporarySwitch::Start() {
  PrefService* prefs = profile_->GetPrefs();
  const bool enabled = prefs->GetBoolean(EnabledPref());
  // Revert-to d'abord : l'UI se redessine sur le changement de l'échéance.
  prefs->SetBoolean(RevertToPref(), !enabled);
  prefs->SetTime(RevertAtPref(feature_), base::Time::Now() + kDuration);
  Arm();
  if (auto* analytics =
          browther_analytics::BrowtherAnalyticsService::GetInstance()) {
    base::DictValue props;
    props.Set("feature", FeatureName());
    props.Set("enabled", enabled);
    props.Set("minutes", static_cast<int>(kDuration.InMinutes()));
    analytics->Track("feature_temporary", std::move(props));
  }
}

void FeatureTemporarySwitch::Keep() {
  if (!IsActive()) {
    return;
  }
  Clear();
  Track("feature_temporary_end", "keep");
}

void FeatureTemporarySwitch::OnEnabledChanged() {
  PrefService* prefs = profile_->GetPrefs();
  if (!IsActive() ||
      prefs->GetBoolean(EnabledPref()) != prefs->GetBoolean(RevertToPref())) {
    return;
  }
  // Quelqu'un est revenu à l'état d'avant : plus rien à rétablir.
  Clear();
  Track("feature_temporary_end", "toggle");
}

void FeatureTemporarySwitch::Finish(std::string_view reason) {
  PrefService* prefs = profile_->GetPrefs();
  const bool target = prefs->GetBoolean(RevertToPref());
  Clear();
  // ⛔ Pas de rallumage du retrait de la musique pendant la pause du
  // parrainage : elle garde Sawtunaa éteint
  // (`BrowtherReferralHandler::EnforcePause`), le rallumer ici la
  // contournerait. Basarunaa n'est pas concerné par la pause.
  if (feature_ == Feature::kSawtunaa && target &&
      browther_referral::IsMusicRemovalPaused(
          g_browser_process->local_state())) {
    Track("feature_temporary_end", "referral_paused");
    return;
  }
  prefs->SetBoolean(EnabledPref(), target);
  Track("feature_temporary_end", reason);
}

void FeatureTemporarySwitch::Clear() {
  timer_.Stop();
  profile_->GetPrefs()->SetTime(RevertAtPref(feature_), base::Time());
}

void FeatureTemporarySwitch::Arm() {
  timer_.Start(FROM_HERE, Remaining(),
               base::BindOnce(&FeatureTemporarySwitch::Finish,
                              base::Unretained(this), std::string("timer")));
}

void FeatureTemporarySwitch::Track(std::string_view event,
                                   std::string_view reason) {
  auto* analytics = browther_analytics::BrowtherAnalyticsService::GetInstance();
  if (!analytics) {
    return;
  }
  base::DictValue props;
  props.Set("feature", FeatureName());
  props.Set("reason", reason);
  analytics->Track(std::string(event), std::move(props));
}
