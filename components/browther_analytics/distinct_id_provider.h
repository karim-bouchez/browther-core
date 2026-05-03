// Copyright (c) 2026 The Browther Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_COMPONENTS_BROWTHER_ANALYTICS_DISTINCT_ID_PROVIDER_H_
#define BRAVE_COMPONENTS_BROWTHER_ANALYTICS_DISTINCT_ID_PROVIDER_H_

#include <string>

#include "base/memory/raw_ptr.h"

class PrefService;
class PrefRegistrySimple;

namespace browther_analytics {

// Fournit l'UUID anonyme persistant pour les events PostHog.
// Généré au premier appel, stocké dans local_state via la pref kBrowtherDistinctId.
class DistinctIdProvider {
 public:
  explicit DistinctIdProvider(PrefService* local_state);
  ~DistinctIdProvider();

  DistinctIdProvider(const DistinctIdProvider&) = delete;
  DistinctIdProvider& operator=(const DistinctIdProvider&) = delete;

  // Retourne l'UUID. Génère + persiste si absent.
  std::string GetOrCreate();

  static void RegisterLocalStatePrefs(PrefRegistrySimple* registry);

 private:
  raw_ptr<PrefService> local_state_;
};

}  // namespace browther_analytics

#endif  // BRAVE_COMPONENTS_BROWTHER_ANALYTICS_DISTINCT_ID_PROVIDER_H_
