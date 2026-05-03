// Copyright (c) 2026 The Browther Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_COMPONENTS_BROWTHER_ANALYTICS_PREF_NAMES_H_
#define BRAVE_COMPONENTS_BROWTHER_ANALYTICS_PREF_NAMES_H_

namespace browther_analytics::prefs {

// UUID v4 anonyme local persistant. Stocké dans local_state.
// Régénéré à chaque réinstall (par design — pas de tracking cross-install).
inline constexpr char kBrowtherDistinctId[] = "browther.analytics.distinct_id";

// True quand l'event onboarding_completed a déjà été envoyé pour ce profil.
// Évite les doublons si l'user retourne sur browther://welcome.
inline constexpr char kOnboardingEventSent[] =
    "browther.analytics.onboarding_event_sent";

}  // namespace browther_analytics::prefs

#endif  // BRAVE_COMPONENTS_BROWTHER_ANALYTICS_PREF_NAMES_H_
