// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/browser/browther/referral/browther_referral_access.h"

#include <utility>

#include "base/time/time.h"
#include "brave/browser/browther/referral/browther_referral_launch.h"
#include "brave/browser/browther/referral/browther_referral_prefs.h"
#include "components/prefs/pref_service.h"

namespace browther_referral {

bool IsMusicRemovalPaused(PrefService* local_state) {
  if (!IsEnabled() || !kExtrasReleased || !local_state) {
    return false;
  }
  const base::DictValue& access = local_state->GetDict(prefs::kAccess);
  if (!access.FindBool("known").value_or(false) ||
      access.FindBool("lifetime").value_or(false) ||
      access.FindBool("beforeTrial").value_or(false) ||
      access.FindBool("subscriptionActive").value_or(false)) {
    return false;
  }
  // `untilMs` (millisecondes depuis l'époque) plutôt qu'une date ISO : le
  // parseur de dates de Chromium ne lit pas les millisecondes du service.
  const std::optional<double> until_ms = access.FindDouble("untilMs");
  if (!until_ms) {
    return !access.FindBool("unlocked").value_or(true);
  }
  return base::Time::FromMillisecondsSinceUnixEpoch(*until_ms) <=
         base::Time::Now();
}

void SetAccessSnapshot(PrefService* local_state, base::DictValue snapshot) {
  if (local_state) {
    local_state->SetDict(prefs::kAccess, std::move(snapshot));
  }
}

}  // namespace browther_referral
