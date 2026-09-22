// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/browser/browther/referral/browther_referral_prefs.h"

#include "components/prefs/pref_registry_simple.h"

namespace browther_referral::prefs {

void RegisterLocalStatePrefs(PrefRegistrySimple* registry) {
  registry->RegisterStringPref(kDeviceId, "");
  registry->RegisterDictionaryPref(kStore);
  registry->RegisterDictionaryPref(kUsage);
  registry->RegisterDictionaryPref(kAccess);
  registry->RegisterDictionaryPref(kDayLock);
  registry->RegisterDictionaryPref(kAccount);
}

}  // namespace browther_referral::prefs
