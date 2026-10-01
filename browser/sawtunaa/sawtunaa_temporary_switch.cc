// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/browser/sawtunaa/sawtunaa_temporary_switch.h"

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
constexpr char kUserDataKey[] = "browther_sawtunaa_temporary_switch";
}  // namespace

// static
SawtunaaTemporarySwitch* SawtunaaTemporarySwitch::GetForProfile(
    Profile* profile) {
  if (!profile) {
    return nullptr;
  }
  auto* existing =
      static_cast<SawtunaaTemporarySwitch*>(profile->GetUserData(kUserDataKey));
  if (existing) {
    return existing;
  }
  auto created = std::make_unique<SawtunaaTemporarySwitch>(profile);
  auto* raw = created.get();
  profile->SetUserData(kUserDataKey, std::move(created));
  return raw;
}

SawtunaaTemporarySwitch::SawtunaaTemporarySwitch(Profile* profile)
    : profile_(profile) {
  pref_change_registrar_.Init(profile_->GetPrefs());
  pref_change_registrar_.Add(
      kSawtunaaEnabled,
      base::BindRepeating(&SawtunaaTemporarySwitch::OnEnabledChanged,
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

SawtunaaTemporarySwitch::~SawtunaaTemporarySwitch() = default;

bool SawtunaaTemporarySwitch::IsActive() const {
  return !profile_->GetPrefs()->GetTime(kSawtunaaTempRevertAt).is_null();
}

base::TimeDelta SawtunaaTemporarySwitch::Remaining() const {
  const base::Time at = profile_->GetPrefs()->GetTime(kSawtunaaTempRevertAt);
  if (at.is_null()) {
    return base::TimeDelta();
  }
  return std::max(base::TimeDelta(), at - base::Time::Now());
}

void SawtunaaTemporarySwitch::Start() {
  PrefService* prefs = profile_->GetPrefs();
  const bool enabled = prefs->GetBoolean(kSawtunaaEnabled);
  // Revert-to d'abord : l'UI se redessine sur le changement de l'échéance.
  prefs->SetBoolean(kSawtunaaTempRevertTo, !enabled);
  prefs->SetTime(kSawtunaaTempRevertAt, base::Time::Now() + kDuration);
  Arm();
  if (auto* analytics =
          browther_analytics::BrowtherAnalyticsService::GetInstance()) {
    base::DictValue props;
    props.Set("feature", "sawtunaa");
    props.Set("enabled", enabled);
    props.Set("minutes", static_cast<int>(kDuration.InMinutes()));
    analytics->Track("feature_temporary", std::move(props));
  }
}

void SawtunaaTemporarySwitch::Keep() {
  if (!IsActive()) {
    return;
  }
  Clear();
  Track("feature_temporary_end", "keep");
}

void SawtunaaTemporarySwitch::OnEnabledChanged() {
  PrefService* prefs = profile_->GetPrefs();
  if (!IsActive() ||
      prefs->GetBoolean(kSawtunaaEnabled) !=
          prefs->GetBoolean(kSawtunaaTempRevertTo)) {
    return;
  }
  // Quelqu'un est revenu à l'état d'avant : plus rien à rétablir.
  Clear();
  Track("feature_temporary_end", "toggle");
}

void SawtunaaTemporarySwitch::Finish(std::string_view reason) {
  PrefService* prefs = profile_->GetPrefs();
  const bool target = prefs->GetBoolean(kSawtunaaTempRevertTo);
  Clear();
  // ⛔ Pas de rallumage pendant la pause du parrainage : elle garde Sawtunaa
  // éteint (`BrowtherReferralHandler::EnforcePause`), le rallumer ici la
  // contournerait.
  if (target && browther_referral::IsMusicRemovalPaused(
                    g_browser_process->local_state())) {
    Track("feature_temporary_end", "referral_paused");
    return;
  }
  prefs->SetBoolean(kSawtunaaEnabled, target);
  Track("feature_temporary_end", reason);
}

void SawtunaaTemporarySwitch::Clear() {
  timer_.Stop();
  profile_->GetPrefs()->SetTime(kSawtunaaTempRevertAt, base::Time());
}

void SawtunaaTemporarySwitch::Arm() {
  timer_.Start(FROM_HERE, Remaining(),
               base::BindOnce(&SawtunaaTemporarySwitch::Finish,
                              base::Unretained(this), std::string("timer")));
}

void SawtunaaTemporarySwitch::Track(std::string_view event,
                                    std::string_view reason) {
  auto* analytics = browther_analytics::BrowtherAnalyticsService::GetInstance();
  if (!analytics) {
    return;
  }
  base::DictValue props;
  props.Set("feature", "sawtunaa");
  props.Set("reason", reason);
  analytics->Track(std::string(event), std::move(props));
}
