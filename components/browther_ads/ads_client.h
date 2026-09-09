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

// Ce vers quoi le `target_url` d'une pub mène QUAND c'est une fiche store —
// absent dès que la destination est un site (cas desktop systématique). Permet
// au client natif d'ouvrir le store de l'appareil au lieu de sa page web.
// ⛔ Jamais d'app id en dur : il descend du serve à chaque fois, c'est ce qui
// fait qu'une nouvelle app dev&din annoncée n'oblige pas à republier Browther
// (ads/docs/INTEGRATION.md § 5).
struct AdStoreTarget {
  enum class Kind {
    kAppStore,  // fiche App Store  → id numérique
    kPlay,      // fiche Play Store → package
  };

  AdStoreTarget();
  AdStoreTarget(const AdStoreTarget&);
  AdStoreTarget& operator=(const AdStoreTarget&);
  AdStoreTarget(AdStoreTarget&&) noexcept;
  AdStoreTarget& operator=(AdStoreTarget&&) noexcept;
  ~AdStoreTarget();

  Kind kind = Kind::kPlay;
  std::string id;
  // Jetons de campagne Apple (`ct`/`pt`), déjà posés sur `target_url` : à
  // repasser tels quels à SKOverlay pour attribuer l'install à l'identique.
  std::string campaign_token;
  std::string provider_token;
};

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
  // Destination FINALE déjà résolue par la régie selon la plateforme envoyée
  // (fiche store sur mobile quand la campagne le demande, site sinon), UTM et
  // click ID `dnd_cid` compris. Vide si le serveur est antérieur au 2026-09-09.
  std::string target_url;
  std::string impression_token;
  std::optional<AdStoreTarget> store;
  // Format du placement renvoyé par le serve (ex "3.2:1") — pilote
  // l'aspect-ratio côté UI (jamais de valeur en dur, cf. INTEGRATION.md § 3).
  std::string ratio;
  // true = annonceur externe → le label « Pub » DOIT être affiché sur cette
  // créa ; false/absent = house ad dev&din, pas de label. Décision par pub
  // (un carousel peut mélanger), pilotée par le dashboard de la régie.
  bool show_ad_label = false;
  // Langue de la créa renvoyée par le serve ("fr"/"en"/"ar") — vide si créa
  // neutre / champ absent. Pilote le sens de lecture (ar → RTL) et l'attribut
  // a11y `lang` côté UI. La régie ne sert QUE la langue demandée (+ neutres),
  // donc en usage normal `locale` == la langue envoyée ou vide.
  std::string locale;
};

// Client HTTP minimal pour la régie pub dev&din (https://ads-api.devndin.com).
//
// - `Serve()` : POST /v1/serve en mode publisher PUBLIC (X-Publisher-Id seul,
//   AUCUN secret embarqué — un binaire distribué ne peut pas en détenir un ;
//   l'anti-fraude vit côté serveur : serve tokens signés serveur, TTL, dédup,
//   rate limiting). Met en cache les pubs servies par `id`.
// - `MarkVisible()` : batch les impression tokens et flush /v1/track/impressions.
// - `GetClickURL()` : résout l'URL de click (302 → targetUrl) d'une pub servie.
// - `GetTargetURL()` / `GetStoreTarget()` + `TrackClick()` : chemin NATIF, pour
//   un client qui ouvre la destination lui-même (store de l'appareil).
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

  // Récupère jusqu'à `count` pubs pour `placement` dans la langue d'affichage
  // `lang` (la régie cible les créas par langue et ne renvoie que celles de la
  // langue demandée + d'éventuelles créas neutres). `lang` = langue d'affichage
  // courante de l'app (BCP-47 accepté, ex "fr-FR" ; réduit ici à son sous-tag
  // primaire "fr"/"en"/"ar" pour le body et la clé de cache). Best effort : sur
  // erreur réseau / 4xx / config absente, renvoie un vecteur vide (jamais
  // d'échec dur — l'UI masque simplement la bannière).
  //
  // Re-serve throttlé à ~10 min par (placement, langue) (définition officielle
  // de l'impression, INTEGRATION.md § 4) : le lot servi est mis en cache
  // process-wide, clé = placement + langue ; entre deux, on ressert les mêmes
  // pubs sans requête réseau et sans re-tracker (les tokens déjà consommés le
  // restent, dédup globale). Un changement de langue repart donc sur un serve
  // neuf (clé de cache différente).
  void Serve(const std::string& placement,
             const std::string& lang,
             int count,
             ServeCallback callback);

  // Signale qu'une pub (par `id`) est devenue réellement visible. Batch +
  // flush différé des impression tokens. Idempotent par `id`.
  void MarkVisible(const std::string& id);

  // URL de click d'une pub servie (vide si `id` inconnu). Chemin WEB : l'API
  // log le click puis 302 vers la destination — le click est donc compté côté
  // serveur, ⛔ ne PAS appeler `TrackClick()` en plus.
  GURL GetClickURL(const std::string& id) const;

  // Destination finale déjà résolue par la régie (vide si `id` inconnu ou si le
  // serve ne l'a pas renvoyée). Chemin NATIF : l'ouvrir soi-même évite l'aller-
  // retour par le navigateur, mais impose d'appeler `TrackClick()` — sinon une
  // conversion qui reviendrait avec ce `dnd_cid` serait un « click inconnu ».
  GURL GetTargetURL(const std::string& id) const;

  // Fiche store visée par `GetTargetURL()`, ou `nullopt` si la destination est
  // un site (toujours le cas sur desktop) / `id` inconnu.
  std::optional<AdStoreTarget> GetStoreTarget(const std::string& id) const;

  // Compte un click (POST /v1/track/click { token }) — le token est celui du
  // serve, le même que pour les impressions. À appeler UNIQUEMENT sur le chemin
  // natif, AVANT d'ouvrir la destination. Idempotent par pub servie ; sur
  // erreur réseau / 5xx le token repart en file et est retenté (le serveur
  // dédup par serve_id, un doublon est sans effet).
  void TrackClick(const std::string& id);

 private:
  void OnServeComplete(const std::string& cache_key,
                       ServeCallback callback,
                       std::unique_ptr<network::SimpleURLLoader> loader,
                       std::optional<std::string> response_body);
  void ScheduleImpressionFlush();
  void FlushImpressions();
  void OnImpressionFlushComplete(
      std::unique_ptr<network::SimpleURLLoader> loader,
      std::vector<std::string> sent_tokens,
      std::optional<std::string> response_body);
  void SendClick(const std::string& token);
  void OnClickComplete(std::unique_ptr<network::SimpleURLLoader> loader,
                       std::string token,
                       std::optional<std::string> response_body);
  void ScheduleClickRetry();
  void RetryPendingClicks();

  scoped_refptr<network::SharedURLLoaderFactory> url_loader_factory_;

  // Pubs servies dans cet onglet, indexées par id (résout impression/click).
  base::flat_map<std::string, ServedAd> served_;

  // Impression tokens en attente de flush. L'anti-double vit dans un set
  // process-wide de tokens consommés (cf. .cc) : une pub resservie depuis le
  // cache 10 min par un autre onglet ne re-tracke pas.
  std::vector<std::string> pending_impressions_;
  base::OneShotTimer flush_timer_;

  // Un click dont on n'a pas eu l'accusé de réception (réseau KO / 5xx). Un tap
  // qui n'aboutit pas ne doit pas disparaître : il repart au prochain essai,
  // dans la limite d'un budget — un navigateur reste ouvert des jours, une file
  // qui se retente indéfiniment hors ligne ne rendrait service à personne.
  struct PendingClick {
    std::string token;
    int attempts = 0;
  };

  std::vector<PendingClick> pending_clicks_;
  base::OneShotTimer click_retry_timer_;

  base::WeakPtrFactory<AdsClient> weak_factory_{this};
};

}  // namespace browther_ads

#endif  // BRAVE_COMPONENTS_BROWTHER_ADS_ADS_CLIENT_H_
