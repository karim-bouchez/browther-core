// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/browser/browther/referral/browther_referral_net.h"

#include <memory>
#include <utility>

#include "base/functional/bind.h"
#include "base/functional/callback.h"
#include "base/strings/strcat.h"
#include "base/time/time.h"
#include "chrome/browser/browser_process.h"
#include "net/base/load_flags.h"
#include "net/http/http_response_headers.h"
#include "net/traffic_annotation/network_traffic_annotation.h"
#include "services/network/public/cpp/resource_request.h"
#include "services/network/public/cpp/shared_url_loader_factory.h"
#include "services/network/public/cpp/simple_url_loader.h"
#include "services/network/public/mojom/url_response_head.mojom.h"

namespace browther_referral {

namespace {

constexpr net::NetworkTrafficAnnotationTag kTrafficAnnotation =
    net::DefineNetworkTrafficAnnotation("browther_referral", R"(
      semantics {
        sender: "Browther referral"
        description:
          "Le programme de parrainage et de soutien de dev&din : statut de "
          "la couverture, code de parrainage, invitations, paiement, compte "
          "facultatif. Un identifiant d'appareil opaque (haché côté serveur), "
          "jamais une URL visitée ni un contenu."
        trigger:
          "Ouverture du Nouvel Onglet, de l'écran Parrainage ou de "
          "l'introduction ; gestes de la personne dans ces écrans."
        data: "Identifiant opaque, code saisi, faits d'usage anonymes."
        destination: OTHER
        destination_other: "Services dev&din (referral, browther-api, auth)."
      }
      policy {
        cookies_allowed: NO
        setting: "Aucun réglage : le parrainage ne fonctionne pas sans."
        policy_exception_justification: "Service propre à Browther."
      })");

constexpr base::TimeDelta kTimeout = base::Seconds(20);
// Le statut le plus lourd (écran 6, liste des invitations) tient en quelques
// kilo-octets : 512 Ko protège de toute réponse aberrante.
constexpr size_t kMaxBody = 512 * 1024;

void OnDone(std::unique_ptr<network::SimpleURLLoader> loader,
            FetchCallback callback,
            std::optional<std::string> body) {
  FetchResult result;
  if (loader->ResponseInfo() && loader->ResponseInfo()->headers) {
    result.status = loader->ResponseInfo()->headers->response_code();
  }
  result.body = body.value_or(std::string());
  std::move(callback).Run(std::move(result));
}

}  // namespace

std::optional<Service> ServiceFromName(const std::string& name) {
  if (name == "referral") {
    return Service::kReferral;
  }
  if (name == "api") {
    return Service::kApi;
  }
  if (name == "auth") {
    return Service::kAuth;
  }
  return std::nullopt;
}

GURL ServiceURL(Service service, const std::string& path) {
  // ⛔ Aucun `..`, aucun schéma, aucun hôte : le chemin se colle à une origine
  // fixée ici et nulle part ailleurs.
  if (path.empty() || path[0] != '/' || path.find("..") != std::string::npos ||
      path.find("//") != std::string::npos) {
    return GURL();
  }
  std::string_view origin;
  std::string_view prefix;
  switch (service) {
    case Service::kReferral:
      origin = "https://referral.devndin.com";
      prefix = "/v1/";
      break;
    case Service::kApi:
      origin = "https://browther-api.devndin.com";
      prefix = "/api/billing/";
      break;
    case Service::kAuth:
      origin = "https://auth.devndin.com";
      prefix = "/api/auth/";
      break;
  }
  if (!path.starts_with(prefix)) {
    return GURL();
  }
  return GURL(base::StrCat({origin, path}));
}

void Fetch(const GURL& url,
           const std::string& method,
           const std::string& body,
           const std::vector<std::pair<std::string, std::string>>& headers,
           FetchCallback callback) {
  if (!url.is_valid() || !g_browser_process ||
      !g_browser_process->shared_url_loader_factory()) {
    std::move(callback).Run(FetchResult());
    return;
  }
  auto request = std::make_unique<network::ResourceRequest>();
  request->url = url;
  request->method = method == "POST" ? "POST" : "GET";
  request->credentials_mode = network::mojom::CredentialsMode::kOmit;
  request->load_flags = net::LOAD_DO_NOT_SAVE_COOKIES | net::LOAD_BYPASS_CACHE;
  request->headers.SetHeader("Accept", "application/json");
  for (const auto& [name, value] : headers) {
    request->headers.SetHeader(name, value);
  }

  auto loader =
      network::SimpleURLLoader::Create(std::move(request), kTrafficAnnotation);
  loader->SetTimeoutDuration(kTimeout);
  // ⚠️ Sans ça, un 4xx arrive sans corps — or le service dit ses refus EN
  // CORPS (`{accepted:false, reason}`, erreurs RFC 8628 du compte).
  loader->SetAllowHttpErrorResults(true);
  if (method == "POST") {
    loader->AttachStringForUpload(body.empty() ? "{}" : body,
                                  "application/json");
  }
  auto* loader_ptr = loader.get();
  loader_ptr->DownloadToString(
      g_browser_process->shared_url_loader_factory().get(),
      base::BindOnce(&OnDone, std::move(loader), std::move(callback)),
      kMaxBody);
}

}  // namespace browther_referral
