// Copyright (c) 2026 The Browther Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/components/browther_ads/ads_client.h"

#include <algorithm>
#include <string_view>
#include <utility>

#include "base/containers/span.h"
#include "base/functional/bind.h"
#include "base/json/json_reader.h"
#include "base/json/json_writer.h"
#include "base/logging.h"
#include "base/no_destructor.h"
#include "base/strings/strcat.h"
#include "base/strings/string_number_conversions.h"
#include "base/strings/string_util.h"
#include "base/time/time.h"
#include "base/values.h"
#include "brave/components/browther_ads/ads_config.h"
#include "build/build_config.h"
#include "net/base/load_flags.h"
#include "net/http/http_request_headers.h"
#include "net/http/http_response_headers.h"
#include "net/traffic_annotation/network_traffic_annotation.h"
#include "services/network/public/cpp/resource_request.h"
#include "services/network/public/cpp/shared_url_loader_factory.h"
#include "services/network/public/cpp/simple_url_loader.h"
#include "services/network/public/mojom/url_response_head.mojom.h"
#include "url/gurl.h"

namespace browther_ads {

namespace {

// Délai de batch des impressions : on accumule les tokens des pubs réellement
// vues puis on flush par paquet. 10 s = compromis entre fraîcheur et bruit
// réseau (cf. INTEGRATION.md § 4). Les tokens expirent en 30 min côté serveur.
constexpr base::TimeDelta kImpressionFlushDelay = base::Seconds(10);

// Cap serveur : 50 tokens par POST /v1/track/impressions.
constexpr size_t kMaxImpressionBatch = 50;

// Délai avant de retenter un click non confirmé (réseau KO / 5xx). Le serveur
// dédup par serve_id : un doublon est sans effet, le retry est donc toujours
// sûr. Court, parce qu'un click sert à relier une conversion qui peut arriver
// dans la minute (installation depuis le store).
constexpr base::TimeDelta kClickRetryDelay = base::Seconds(15);

// Nombre total d'envois pour un click (1 direct + 3 retries ≈ 45 s). Au-delà,
// on abandonne : un navigateur reste ouvert des jours, une file qui se retente
// indéfiniment hors ligne coûte plus qu'elle ne rapporte.
constexpr int kMaxClickAttempts = 4;

// Throttle de re-serve par placement (INTEGRATION.md § 4 : « 1 impression =
// un affichage réellement vu, max ~1 par tranche de 10 min par appareil et
// par placement »). Entre deux serves, on ressert le même lot depuis un cache
// process-wide, sans requête réseau. Les tokens expirent en 30 min > TTL.
constexpr base::TimeDelta kServeCacheTtl = base::Minutes(10);

// Lot servi mis en cache pour le throttle ci-dessus.
struct CachedServe {
  base::TimeTicks served_at;
  std::vector<ServedAd> ads;
};

// Caches process-wide (UI thread uniquement — desktop instancie un AdsClient
// par NTP, Android un singleton ; les deux appellent depuis le UI thread) :
// - lot servi par placement (throttle 10 min) ;
// - tokens d'impression déjà consommés (une pub resservie depuis le cache par
//   un autre onglet ne re-tracke pas — le serveur dédupliquerait de toute
//   façon par serve_id, on évite juste le trafic inutile).
base::flat_map<std::string, CachedServe>& GetServeCache() {
  static base::NoDestructor<base::flat_map<std::string, CachedServe>> cache;
  return *cache;
}

base::flat_map<std::string, bool>& GetConsumedTokens() {
  static base::NoDestructor<base::flat_map<std::string, bool>> tokens;
  return *tokens;
}

// Tokens dont le click est déjà compté : « un seul click par pub servie »
// (INTEGRATION.md § 5). Process-wide comme les impressions, pour qu'une pub
// resservie depuis le cache 10 min dans un autre onglet ne recompte pas.
base::flat_map<std::string, bool>& GetClickedTokens() {
  static base::NoDestructor<base::flat_map<std::string, bool>> tokens;
  return *tokens;
}

// Plateforme envoyée au serve (alimente le breakdown dashboard). Le même code
// C++ build pour macOS, Windows desktop et Android ; on reporte la vraie
// plateforme. (iOS n'utilise pas ce client : port Swift `BrowtherAdsClient`.)
constexpr char kPlatform[] =
#if BUILDFLAG(IS_ANDROID)
    "android";
#elif BUILDFLAG(IS_MAC)
    "macos";
#elif BUILDFLAG(IS_WIN)
    "windows";
#elif BUILDFLAG(IS_LINUX)
    "linux";
#else
    "desktop";
#endif

// Suffixe des builds de dev (ads/docs/INTEGRATION.md § 8) : la régie le garde
// après normalisation (`macos-dev` → `desktop-dev`), donc les stats de test
// restent isolables et purgeables au lieu de se mêler aux vraies. Component =
// `is_official_build=false` ⇒ suffixé ; tout build `Release` est officiel
// (`config.js` `isOfficialBuild()`), et c'est le seul qu'on distribue (DMG,
// AAB, EXE) ⇒ plateforme nue.
constexpr char kPlatformSuffix[] =
#if defined(OFFICIAL_BUILD)
    "";
#else
    "-dev";
#endif

// Réduit une langue d'affichage (ex "fr-FR", "en_US", "ar") à son sous-tag
// primaire minuscule ("fr"/"en"/"ar"). La régie n'accepte que la langue
// demandée + neutres et ne garde de toute façon que le sous-tag primaire d'un
// BCP-47 ; on le réduit ici pour un body propre et surtout une clé de cache
// stable (fr-FR et fr-CA partagent le même lot).
std::string PrimaryLanguageSubtag(std::string_view locale) {
  return base::ToLowerASCII(locale.substr(0, locale.find_first_of("-_")));
}

// Clé du cache de re-serve : (placement, langue). Une langue différente
// invalide le lot mis en cache et déclenche un nouveau serve (INTEGRATION.md
// § Langue). '|' n'apparaît ni dans un id de placement ni dans un sous-tag.
std::string ServeCacheKey(const std::string& placement,
                          const std::string& lang) {
  return base::StrCat({placement, "|", lang});
}

// Champ `store` du serve → AdStoreTarget. `nullopt` dès que la destination est
// un site (champ `null`/absent, cas desktop systématique) ou que la fiche est
// inexploitable (kind inconnu, id vide) : l'appelant retombe alors sur
// l'onglet, jamais sur un tap qui ne fait rien.
std::optional<AdStoreTarget> ParseStoreTarget(const base::DictValue* store) {
  if (!store) {
    return std::nullopt;
  }
  const std::string* kind = store->FindString("kind");
  const std::string* id = store->FindString("id");
  if (!kind || !id || id->empty()) {
    return std::nullopt;
  }

  AdStoreTarget target;
  if (*kind == "app_store") {
    target.kind = AdStoreTarget::Kind::kAppStore;
  } else if (*kind == "play") {
    target.kind = AdStoreTarget::Kind::kPlay;
  } else {
    // Nouveau store côté régie que ce binaire ne connaît pas : on ouvre la page
    // web plutôt que d'inventer un comportement.
    return std::nullopt;
  }
  target.id = *id;
  if (const std::string* campaign_token = store->FindString("campaignToken")) {
    target.campaign_token = *campaign_token;
  }
  if (const std::string* provider_token = store->FindString("providerToken")) {
    target.provider_token = *provider_token;
  }
  return target;
}

constexpr net::NetworkTrafficAnnotationTag kServeTrafficAnnotation =
    net::DefineNetworkTrafficAnnotation("browther_ads_serve", R"ANNOT(
        semantics {
          sender: "Browther Ads"
          description:
            "Fetches house/community banner ads from the dev&din ad network "
            "to display in a banner below the favorites on the Browther new "
            "tab page. Sends only the placement name, platform, requested "
            "count and the browser's display language (so the network can "
            "return ads in a language the user reads). No URLs visited, no "
            "page content, no PII."
          trigger:
            "Opening a new tab page."
          data:
            "Placement identifier, platform name, requested ad count, the "
            "browser display language (primary subtag, e.g. \"fr\"), and the "
            "public publisher id (no secret is embedded in the binary)."
          destination: OTHER
          destination_other: "ads-api.devndin.com (self-hosted on OVH)"
        }
        policy {
          cookies_allowed: NO
          setting:
            "There is no dedicated setting; the banner is only shown when ads "
            "are eligible. Disabling background images does not affect it."
          policy_exception_justification:
            "Not implemented, consumer-facing browser."
        })ANNOT");

constexpr net::NetworkTrafficAnnotationTag kTrackTrafficAnnotation =
    net::DefineNetworkTrafficAnnotation("browther_ads_track", R"ANNOT(
        semantics {
          sender: "Browther Ads"
          description:
            "Reports that a Browther new tab page banner ad was actually "
            "displayed to the user, so the ad network can count impressions. "
            "Sends only opaque single-use impression tokens previously "
            "returned by the serve endpoint. No PII."
          trigger:
            "A served banner ad scrolled into view on the new tab page."
          data:
            "A batch of opaque impression tokens."
          destination: OTHER
          destination_other: "ads-api.devndin.com (self-hosted on OVH)"
        }
        policy {
          cookies_allowed: NO
          setting:
            "There is no dedicated setting; impressions are only sent for ads "
            "that were actually shown."
          policy_exception_justification:
            "Not implemented, consumer-facing browser."
        })ANNOT");

constexpr net::NetworkTrafficAnnotationTag kClickTrafficAnnotation =
    net::DefineNetworkTrafficAnnotation("browther_ads_click", R"ANNOT(
        semantics {
          sender: "Browther Ads"
          description:
            "Reports that the user tapped a Browther new tab page banner ad, "
            "so the ad network can count the click. Used only when the browser "
            "opens the ad's destination itself (a device app store listing) "
            "instead of following the network's redirect. Sends only the "
            "opaque single-use serve token previously returned by the serve "
            "endpoint. No PII."
          trigger:
            "The user taps a served banner ad whose destination is an app "
            "store listing."
          data:
            "A single opaque serve token."
          destination: OTHER
          destination_other: "ads-api.devndin.com (self-hosted on OVH)"
        }
        policy {
          cookies_allowed: NO
          setting:
            "There is no dedicated setting; a click is only reported when the "
            "user actually taps an ad."
          policy_exception_justification:
            "Not implemented, consumer-facing browser."
        })ANNOT");

}  // namespace

AdStoreTarget::AdStoreTarget() = default;
AdStoreTarget::AdStoreTarget(const AdStoreTarget&) = default;
AdStoreTarget& AdStoreTarget::operator=(const AdStoreTarget&) = default;
AdStoreTarget::AdStoreTarget(AdStoreTarget&&) noexcept = default;
AdStoreTarget& AdStoreTarget::operator=(AdStoreTarget&&) noexcept = default;
AdStoreTarget::~AdStoreTarget() = default;

ServedAd::ServedAd() = default;
ServedAd::ServedAd(const ServedAd&) = default;
ServedAd& ServedAd::operator=(const ServedAd&) = default;
ServedAd::ServedAd(ServedAd&&) noexcept = default;
ServedAd& ServedAd::operator=(ServedAd&&) noexcept = default;
ServedAd::~ServedAd() = default;

AdsClient::AdsClient(
    scoped_refptr<network::SharedURLLoaderFactory> url_loader_factory)
    : url_loader_factory_(std::move(url_loader_factory)) {}

AdsClient::~AdsClient() {
  // Best effort : flush les impressions restantes au teardown de l'onglet.
  FlushImpressions();
}

// static
bool AdsClient::IsConfigured() {
  return !std::string_view(kAdsApiUrl).empty() &&
         !std::string_view(kAdsPublisherId).empty();
}

void AdsClient::Serve(const std::string& placement,
                      const std::string& lang,
                      int count,
                      ServeCallback callback) {
  if (!IsConfigured() || !url_loader_factory_) {
    std::move(callback).Run({});
    return;
  }

  // Langue d'affichage réduite au sous-tag primaire ; entre dans le body ET la
  // clé de cache (un changement de langue repart sur un serve neuf).
  const std::string primary_lang = PrimaryLanguageSubtag(lang);
  const std::string cache_key = ServeCacheKey(placement, primary_lang);

  // Throttle 10 min : lot encore frais (même placement ET même langue) →
  // resservi sans requête réseau. On réindexe les pubs dans cette instance pour
  // que MarkVisible/GetClickURL fonctionnent aussi dans un onglet qui n'a pas
  // fait le serve d'origine.
  auto cached = GetServeCache().find(cache_key);
  if (cached != GetServeCache().end() &&
      base::TimeTicks::Now() - cached->second.served_at < kServeCacheTtl) {
    for (const ServedAd& ad : cached->second.ads) {
      served_[ad.id] = ad;
    }
    std::move(callback).Run(cached->second.ads);
    return;
  }

  base::DictValue payload;
  payload.Set("placement", placement);
  payload.Set("platform", base::StrCat({kPlatform, kPlatformSuffix}));
  payload.Set("count", count);
  // Langue ciblée par la régie : le serveur ne renvoie que les créas de cette
  // langue (+ neutres) et EXIGE ce champ — un `lang` absent, vide ou non
  // supporté ⇒ 400 (masqué par OnServeComplete, cf. gestion ci-dessous).
  // GetApplicationLocale (desktop/Android) et preferredLocalizations (iOS)
  // renvoient toujours une locale valide, donc primary_lang n'est jamais vide
  // ici. ⚠️ Contrat serveur : un client déployé AVANT le ciblage langue
  // (2026-07-13) n'envoie pas ce champ → 400 → bannière masquée tant qu'il
  // n'est pas rebuild/réinstallé (cf. STATUS.md).
  payload.Set("lang", primary_lang);

  std::string body;
  if (!base::JSONWriter::Write(payload, &body)) {
    std::move(callback).Run({});
    return;
  }

  // Publisher en mode PUBLIC : aucun secret embarqué (un binaire distribué ne
  // peut pas en détenir un — extractible = signatures forgeables, cf. bascule
  // 2026-07-07). L'anti-fraude vit côté serveur : serve tokens signés serveur
  // (TTL + dédup par serve_id sur impressions/clics) + rate limiting.
  auto request = std::make_unique<network::ResourceRequest>();
  request->url = GURL(base::StrCat({kAdsApiUrl, "/v1/serve"}));
  request->method = "POST";
  request->credentials_mode = network::mojom::CredentialsMode::kOmit;
  request->load_flags = net::LOAD_DO_NOT_SAVE_COOKIES;
  request->headers.SetHeader("X-Publisher-Id", kAdsPublisherId);

  auto loader = network::SimpleURLLoader::Create(std::move(request),
                                                 kServeTrafficAnnotation);
  loader->AttachStringForUpload(body, "application/json");

  auto* loader_ptr = loader.get();
  loader_ptr->DownloadToString(
      url_loader_factory_.get(),
      base::BindOnce(&AdsClient::OnServeComplete, weak_factory_.GetWeakPtr(),
                     cache_key, std::move(callback), std::move(loader)),
      /*max_body_size=*/64 * 1024);
}

void AdsClient::OnServeComplete(
    const std::string& cache_key,
    ServeCallback callback,
    std::unique_ptr<network::SimpleURLLoader> loader,
    std::optional<std::string> response_body) {
  const int net_error = loader->NetError();
  const int response_code =
      loader->ResponseInfo() && loader->ResponseInfo()->headers
          ? loader->ResponseInfo()->headers->response_code()
          : 0;

  if (net_error != net::OK || response_code < 200 || response_code >= 300 ||
      !response_body) {
    // Un 400 avec corps vient de NOTRE serve : on a envoyé quelque chose que la
    // régie refuse (ex. `{"error":"Langue \"xx\" non supportée …"}` si la langue
    // n'est pas gérée). Ce n'est PAS le cas normal `ads: []` (200) : c'est un
    // bug de config à REMONTER, pas à absorber en silence → LOG(ERROR) (console
    // d'erreur ; Sentry via crashpad n'a pas d'API message non-fatal). On masque
    // quand même la bannière (best effort, jamais d'échec dur ni de boucle).
    if (response_code == 400 && response_body) {
      std::string detail;
      if (std::optional<base::DictValue> err = base::JSONReader::ReadDict(
              *response_body, base::JSON_PARSE_RFC)) {
        if (const std::string* msg = err->FindString("error")) {
          detail = *msg;
        }
      }
      LOG(ERROR) << "[BrowtherAds] serve rejected (400, bug de config régie): "
                 << detail;
    } else {
      VLOG(1) << "[BrowtherAds] serve failed: net_error=" << net_error
              << " http=" << response_code;
    }
    std::move(callback).Run({});
    return;
  }

  std::optional<base::DictValue> root =
      base::JSONReader::ReadDict(*response_body, base::JSON_PARSE_RFC);
  if (!root) {
    std::move(callback).Run({});
    return;
  }

  const base::ListValue* ads = root->FindList("ads");
  if (!ads) {
    std::move(callback).Run({});
    return;
  }

  std::vector<ServedAd> result;
  for (const base::Value& entry : *ads) {
    const base::DictValue* ad = entry.GetIfDict();
    if (!ad) {
      continue;
    }
    const std::string* id = ad->FindString("id");
    const std::string* image_url = ad->FindString("imageUrl");
    const std::string* click_url = ad->FindString("clickUrl");
    const std::string* target_url = ad->FindString("targetUrl");
    const std::string* impression_token = ad->FindString("impressionToken");
    const std::string* ratio = ad->FindString("ratio");
    const std::string* locale = ad->FindString("locale");
    if (!id || !image_url || id->empty() || image_url->empty()) {
      continue;
    }

    ServedAd served;
    served.id = *id;
    served.image_url = *image_url;
    served.click_url = click_url ? *click_url : std::string();
    // Destination déjà résolue par la régie ; absente d'un serveur antérieur au
    // 2026-09-09 → les clients retombent sur `click_url` (chemin web).
    served.target_url = target_url ? *target_url : std::string();
    served.impression_token =
        impression_token ? *impression_token : std::string();
    served.store = ParseStoreTarget(ad->FindDict("store"));
    served.ratio = ratio ? *ratio : std::string();
    // Langue de la créa ("fr"/"en"/"ar") — absente/null pour une créa neutre.
    served.locale = locale ? *locale : std::string();
    // Champ absent (vieux cache serveur) → house ad, pas de label.
    served.show_ad_label = ad->FindBool("showAdLabel").value_or(false);
    served_[served.id] = served;
    result.push_back(std::move(served));
  }

  // Alimente le throttle 10 min : le prochain serve de ce (placement, langue)
  // (autre onglet, même onglet) resservira ce lot sans requête réseau.
  GetServeCache()[cache_key] = {base::TimeTicks::Now(), result};

  std::move(callback).Run(std::move(result));
}

void AdsClient::MarkVisible(const std::string& id) {
  auto it = served_.find(id);
  if (it == served_.end() || it->second.impression_token.empty()) {
    return;
  }
  // Idempotent process-wide par token : une impression par pub SERVIE (pas
  // par affichage) — une pub resservie depuis le cache 10 min garde le même
  // token, déjà consommé si elle a déjà été vue dans un autre onglet.
  const std::string& token = it->second.impression_token;
  if (GetConsumedTokens().contains(token)) {
    return;
  }
  GetConsumedTokens()[token] = true;
  pending_impressions_.push_back(token);
  ScheduleImpressionFlush();
}

GURL AdsClient::GetClickURL(const std::string& id) const {
  auto it = served_.find(id);
  if (it == served_.end() || it->second.click_url.empty()) {
    return GURL();
  }
  return GURL(it->second.click_url);
}

GURL AdsClient::GetTargetURL(const std::string& id) const {
  auto it = served_.find(id);
  if (it == served_.end() || it->second.target_url.empty()) {
    return GURL();
  }
  return GURL(it->second.target_url);
}

std::optional<AdStoreTarget> AdsClient::GetStoreTarget(
    const std::string& id) const {
  auto it = served_.find(id);
  if (it == served_.end()) {
    return std::nullopt;
  }
  return it->second.store;
}

void AdsClient::TrackClick(const std::string& id) {
  auto it = served_.find(id);
  if (it == served_.end() || it->second.impression_token.empty()) {
    return;
  }
  // Un seul click par pub SERVIE (INTEGRATION.md § 5) : pas besoin de débouncer
  // côté UI, un double-tap ne compte qu'une fois.
  const std::string& token = it->second.impression_token;
  if (GetClickedTokens().contains(token)) {
    return;
  }
  GetClickedTokens()[token] = true;
  // Le token entre en file AVANT l'envoi : ouvrir un store bascule Browther en
  // arrière-plan, et rien ne garantit que le callback d'échec s'exécutera.
  pending_clicks_.push_back({token, /*attempts=*/0});
  SendClick(token);
}

void AdsClient::SendClick(const std::string& token) {
  if (!IsConfigured() || !url_loader_factory_) {
    return;
  }

  base::DictValue payload;
  payload.Set("token", token);

  std::string body;
  if (!base::JSONWriter::Write(payload, &body)) {
    return;
  }

  auto request = std::make_unique<network::ResourceRequest>();
  request->url = GURL(base::StrCat({kAdsApiUrl, "/v1/track/click"}));
  request->method = "POST";
  request->credentials_mode = network::mojom::CredentialsMode::kOmit;
  request->load_flags = net::LOAD_DO_NOT_SAVE_COOKIES;

  auto loader = network::SimpleURLLoader::Create(std::move(request),
                                                 kClickTrafficAnnotation);
  loader->AttachStringForUpload(body, "application/json");

  auto* loader_ptr = loader.get();
  loader_ptr->DownloadToString(
      url_loader_factory_.get(),
      base::BindOnce(&AdsClient::OnClickComplete, weak_factory_.GetWeakPtr(),
                     std::move(loader), token),
      /*max_body_size=*/4 * 1024);
}

void AdsClient::OnClickComplete(
    std::unique_ptr<network::SimpleURLLoader> loader,
    std::string token,
    std::optional<std::string> response_body) {
  const int net_error = loader->NetError();
  const int response_code =
      loader->ResponseInfo() && loader->ResponseInfo()->headers
          ? loader->ResponseInfo()->headers->response_code()
          : 0;

  auto it = std::ranges::find(pending_clicks_, token, &PendingClick::token);
  if (it == pending_clicks_.end()) {
    return;  // déjà soldé par un autre essai
  }

  // 4xx = token expiré ou pub disparue : retenter n'y changerait rien. Réseau
  // KO / 5xx → on garde le token et on retente, dans la limite du budget.
  const bool retriable = net_error != net::OK || response_code >= 500;
  if (retriable && ++it->attempts < kMaxClickAttempts) {
    VLOG(1) << "[BrowtherAds] click failed: net_error=" << net_error
            << " http=" << response_code << " (requeued, essai "
            << it->attempts << "/" << kMaxClickAttempts << ")";
    ScheduleClickRetry();
    return;
  }

  pending_clicks_.erase(it);
  VLOG(1) << "[BrowtherAds] click settled (http=" << response_code
          << " net_error=" << net_error << ")";
}

void AdsClient::ScheduleClickRetry() {
  if (click_retry_timer_.IsRunning() || pending_clicks_.empty()) {
    return;
  }
  click_retry_timer_.Start(FROM_HERE, kClickRetryDelay,
                           base::BindOnce(&AdsClient::RetryPendingClicks,
                                          weak_factory_.GetWeakPtr()));
}

void AdsClient::RetryPendingClicks() {
  // Copie des tokens : `SendClick` peut faire muter la file dans son callback.
  std::vector<std::string> tokens;
  tokens.reserve(pending_clicks_.size());
  for (const PendingClick& click : pending_clicks_) {
    tokens.push_back(click.token);
  }
  for (const std::string& token : tokens) {
    SendClick(token);
  }
}

void AdsClient::ScheduleImpressionFlush() {
  if (flush_timer_.IsRunning() || pending_impressions_.empty()) {
    return;
  }
  flush_timer_.Start(FROM_HERE, kImpressionFlushDelay,
                     base::BindOnce(&AdsClient::FlushImpressions,
                                    weak_factory_.GetWeakPtr()));
}

void AdsClient::FlushImpressions() {
  if (!IsConfigured() || !url_loader_factory_ || pending_impressions_.empty()) {
    return;
  }

  // Prend jusqu'à 50 tokens ; reschedule s'il en reste.
  const size_t take =
      std::min(pending_impressions_.size(), kMaxImpressionBatch);
  std::vector<std::string> tokens(
      pending_impressions_.begin(),
      pending_impressions_.begin() + static_cast<ptrdiff_t>(take));
  pending_impressions_.erase(
      pending_impressions_.begin(),
      pending_impressions_.begin() + static_cast<ptrdiff_t>(take));

  base::ListValue token_list;
  for (const std::string& token : tokens) {
    token_list.Append(token);
  }
  base::DictValue payload;
  payload.Set("tokens", std::move(token_list));

  std::string body;
  if (!base::JSONWriter::Write(payload, &body)) {
    return;
  }

  auto request = std::make_unique<network::ResourceRequest>();
  request->url = GURL(base::StrCat({kAdsApiUrl, "/v1/track/impressions"}));
  request->method = "POST";
  request->credentials_mode = network::mojom::CredentialsMode::kOmit;
  request->load_flags = net::LOAD_DO_NOT_SAVE_COOKIES;

  auto loader = network::SimpleURLLoader::Create(std::move(request),
                                                 kTrackTrafficAnnotation);
  loader->AttachStringForUpload(body, "application/json");

  auto* loader_ptr = loader.get();
  loader_ptr->DownloadToString(
      url_loader_factory_.get(),
      base::BindOnce(&AdsClient::OnImpressionFlushComplete,
                     weak_factory_.GetWeakPtr(), std::move(loader),
                     std::move(tokens)),
      /*max_body_size=*/4 * 1024);

  if (!pending_impressions_.empty()) {
    ScheduleImpressionFlush();
  }
}

void AdsClient::OnImpressionFlushComplete(
    std::unique_ptr<network::SimpleURLLoader> loader,
    std::vector<std::string> sent_tokens,
    std::optional<std::string> response_body) {
  const int net_error = loader->NetError();
  const int response_code =
      loader->ResponseInfo() && loader->ResponseInfo()->headers
          ? loader->ResponseInfo()->headers->response_code()
          : 0;

  if (net_error != net::OK || response_code < 200 || response_code >= 300) {
    // Réseau KO → requeue pour retry (idempotent : un token consommé 2× =
    // `duplicates` côté serveur, sans erreur).
    VLOG(1) << "[BrowtherAds] impressions flush failed: net_error=" << net_error
            << " http=" << response_code << " (requeued)";
    pending_impressions_.insert(pending_impressions_.end(),
                                std::make_move_iterator(sent_tokens.begin()),
                                std::make_move_iterator(sent_tokens.end()));
    ScheduleImpressionFlush();
    return;
  }

  VLOG(1) << "[BrowtherAds] impressions flushed (" << sent_tokens.size() << ")";
}

}  // namespace browther_ads
