// Copyright (c) 2026 The Browther Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/components/browther_analytics/distinct_id_provider.h"

#include "base/check.h"
#include "base/uuid.h"
#include "brave/components/browther_analytics/pref_names.h"
#include "components/prefs/pref_registry_simple.h"
#include "components/prefs/pref_service.h"

namespace browther_analytics {

DistinctIdProvider::DistinctIdProvider(PrefService* local_state)
    : local_state_(local_state) {
  CHECK(local_state_);
}

DistinctIdProvider::~DistinctIdProvider() = default;

std::string DistinctIdProvider::GetOrCreate() {
  std::string id = local_state_->GetString(prefs::kBrowtherDistinctId);
  if (id.empty()) {
    id = base::Uuid::GenerateRandomV4().AsLowercaseString();
    local_state_->SetString(prefs::kBrowtherDistinctId, id);
  }
  return id;
}

// static
void DistinctIdProvider::RegisterLocalStatePrefs(
    PrefRegistrySimple* registry) {
  registry->RegisterStringPref(prefs::kBrowtherDistinctId, std::string());
  registry->RegisterBooleanPref(prefs::kOnboardingEventSent, false);
}

}  // namespace browther_analytics
