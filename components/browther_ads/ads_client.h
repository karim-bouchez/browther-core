// Copyright (c) 2026 The Browther Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_COMPONENTS_BROWTHER_ADS_ADS_CLIENT_H_
#define BRAVE_COMPONENTS_BROWTHER_ADS_ADS_CLIENT_H_

#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "base/containers/flat_map.h"
#include "base/functional/callback.h"
#include "base/memory/scoped_refptr.h"
#include "base/memory/weak_ptr.h"
#include "base/timer/timer.h"

class GURL;

namespace network {
class SharedURLLoaderFactory;
class SimpleURLLoader;
}  // namespace network

namespace browther_ads {

// Une pub servie par la régie devndin-ads. Seuls `id` + `image_url` sont
// exposés au renderer (cf. mojom BrowtherAd) ; `impression_token` et
// `click_url` restent côté navigateur (jamais dans le JS).
struct ServedAd {
  ServedAd();
  ServedAd(const ServedAd&);
  ServedAd& operator=(const ServedAd&);
  ServedAd(ServedAd&&) noexcept;
  ServedAd& operator=(ServedAd&&) noexcept;
  ~ServedAd();

  std::string id;
  std::string image_url;
  std::string click_url;
  std::string impression_token;
  // Format du placement renvoyé par le serve (ex "3.2:1") — pilote
  // l'aspect-ratio côté UI (jamais de valeur en dur, cf. INTEGRATION.md § 3).
  std::string ratio;
  // true = annonceur externe → le label « Pub » DOIT être affiché sur cette
  // créa ; false/absent = house ad dev&din, pas de label. Décision par pub
  // (un carousel peut mélanger), pilotée par le dashboard de la régie.
  bool show_ad_label = false;
};

// Client HTTP minimal pour la régie pub dev&din (https://ads-api.devndin.com).
//
// - `Serve()` : POST /v1/serve en mode publisher PUBLIC (X-Publisher-Id seul,
//   AUCUN secret embarqué — un binaire distribué ne peut pas en détenir un ;
//   l'anti-fraude vit côté serveur : serve tokens signés serveur, TTL, dédup,
//   rate limiting). Met en cache les pubs servies par `id`.
// - `MarkVisible()` : batch les impression tokens et flush /v1/track/impressions.
// - `GetClickURL()` : résout l'URL de click (302 → targetUrl) d'une pub servie.
//
// L'url/publisher sont embarqués via ads_config.h (généré depuis
// private/configs/analytics.env). Une config vide → IsConfigured() false →
// aucune requête réseau, bannière masquée proprement.
//
// Pas de SDK : de simples POST JSON, calqués sur INTEGRATION.md.
class AdsClient {
 public:
  explicit AdsClient(
      scoped_refptr<network::SharedURLLoaderFactory> url_loader_factory);
  ~AdsClient();

  AdsClient(const AdsClient&) = delete;
  AdsClient& operator=(const AdsClient&) = delete;

  // True si publisher id + url sont configurés (analytics.env).
  static bool IsConfigured();

  using ServeCallback = base::OnceCallback<void(std::vector<ServedAd>)>;

  // Récupère jusqu'à `count` pubs pour `placement`. Best effort : sur erreur
  // réseau / 4xx / config absente, renvoie un vecteur vide (jamais d'échec dur
  // — l'UI masque simplement la bannière).
  //
  // Re-serve throttlé à ~10 min par placement (définition officielle de
  // l'impression, INTEGRATION.md § 4) : le lot servi est mis en cache
  // process-wide ; entre deux, on ressert les mêmes pubs sans requête réseau
  // et sans re-tracker (les tokens déjà consommés le restent, dédup globale).
  void Serve(const std::string& placement, int count, ServeCallback callback);

  // Signale qu'une pub (par `id`) est devenue réellement visible. Batch +
  // flush différé des impression tokens. Idempotent par `id`.
  void MarkVisible(const std::string& id);

  // URL de click d'une pub servie (vide si `id` inconnu).
  GURL GetClickURL(const std::string& id) const;

 private:
  void OnServeComplete(const std::string& placement,
                       ServeCallback callback,
                       std::unique_ptr<network::SimpleURLLoader> loader,
                       std::optional<std::string> response_body);
  void ScheduleImpressionFlush();
  void FlushImpressions();
  void OnImpressionFlushComplete(
      std::unique_ptr<network::SimpleURLLoader> loader,
      std::vector<std::string> sent_tokens,
      std::optional<std::string> response_body);

  scoped_refptr<network::SharedURLLoaderFactory> url_loader_factory_;

  // Pubs servies dans cet onglet, indexées par id (résout impression/click).
  base::flat_map<std::string, ServedAd> served_;

  // Impression tokens en attente de flush. L'anti-double vit dans un set
  // process-wide de tokens consommés (cf. .cc) : une pub resservie depuis le
  // cache 10 min par un autre onglet ne re-tracke pas.
  std::vector<std::string> pending_impressions_;
  base::OneShotTimer flush_timer_;

  base::WeakPtrFactory<AdsClient> weak_factory_{this};
};

}  // namespace browther_ads

#endif  // BRAVE_COMPONENTS_BROWTHER_ADS_ADS_CLIENT_H_
