// Copyright (c) 2026 The Browther Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_COMPONENTS_BROWTHER_ANALYTICS_STATS_CLIENT_H_
#define BRAVE_COMPONENTS_BROWTHER_ANALYTICS_STATS_CLIENT_H_

#include <memory>
#include <optional>
#include <string>

#include "base/memory/raw_ptr.h"
#include "base/memory/scoped_refptr.h"
#include "base/memory/weak_ptr.h"
#include "base/timer/timer.h"

class PrefService;
class PrefRegistrySimple;

namespace network {
class SharedURLLoaderFactory;
class SimpleURLLoader;
}  // namespace network

namespace browther_analytics {

// Client HTTP pour `/api/stats/ingest` (browther-api).
//
// Accumule en mémoire et persiste dans des prefs locales (kStats*Pending),
// puis flush par batch toutes les `kFlushInterval`. Les prefs survivent aux
// crashs / shutdowns brutaux : un compteur partiellement comptabilisé n'est
// jamais perdu (au pire renvoyé en double si le serveur n'a pas eu le 200,
// mais l'API étant idempotente sur le delta, le risque est limité).
//
// L'UUID est partagé avec PostHog (le même `distinct_id` injecté dans
// `BrowtherAnalyticsService`).
class StatsClient {
 public:
  StatsClient(scoped_refptr<network::SharedURLLoaderFactory> url_loader_factory,
              PrefService* local_state,
              std::string anon_uuid);
  ~StatsClient();

  StatsClient(const StatsClient&) = delete;
  StatsClient& operator=(const StatsClient&) = delete;

  // API publique — appelable depuis n'importe quel chemin C++ Browther.
  // delta doit être >= 0. Les valeurs sont accumulées dans une pref locale
  // jusqu'au prochain flush. Pas de batching côté caller : on peut appeler
  // 1000 fois/sec sans souci.
  void IncrementMusicSeconds(int delta);
  void IncrementPersonsBlurred(int delta);
  void IncrementAdsBlocked(int delta);

  // Flush immédiat (best effort, fire-and-forget).
  void FlushNow();

  // True si l'endpoint est configuré (pas de no-op à la compilation).
  static bool IsConfigured();

  static void RegisterLocalStatePrefs(PrefRegistrySimple* registry);

 private:
  void IncrementPref(const char* pref_name, int delta);
  void OnFlushComplete(std::unique_ptr<network::SimpleURLLoader> loader,
                       int sent_music,
                       int sent_persons,
                       int sent_ads,
                       std::optional<std::string> response_body);

  scoped_refptr<network::SharedURLLoaderFactory> url_loader_factory_;
  raw_ptr<PrefService> local_state_;
  std::string anon_uuid_;
  base::RepeatingTimer flush_timer_;
  bool flush_in_flight_ = false;

  base::WeakPtrFactory<StatsClient> weak_factory_{this};
};

}  // namespace browther_analytics

#endif  // BRAVE_COMPONENTS_BROWTHER_ANALYTICS_STATS_CLIENT_H_
