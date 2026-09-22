// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_BROWSER_BROWTHER_REFERRAL_BROWTHER_REFERRAL_NET_H_
#define BRAVE_BROWSER_BROWTHER_REFERRAL_BROWTHER_REFERRAL_NET_H_

#include <optional>
#include <string>
#include <vector>

#include "base/functional/callback_forward.h"
#include "url/gurl.h"

// Le seul chemin réseau du parrainage desktop. L'app web ne fait AUCUN appel
// elle-même : elle demande au navigateur, qui n'appelle que trois services
// dev&din (liste fermée ci-dessous) — ⭐ c'est ce qui garde le jeton du compte
// hors du JavaScript, et qui évite d'ouvrir le CSP des pages internes.
//
// ⛔ Aucun cookie envoyé ni gardé (`kOmit`) : le contexte réseau est celui du
// navigateur, pas celui d'un profil — rien de ce que la personne a ouvert dans
// ses onglets ne s'y mêle.
namespace browther_referral {

enum class Service {
  kReferral,  // https://referral.devndin.com — le programme (§ 7.2)
  kApi,       // https://browther-api.devndin.com — le paiement Polar (§ 7.4)
  kAuth,      // https://auth.devndin.com — le compte facultatif (§ 7.1)
};

std::optional<Service> ServiceFromName(const std::string& name);

// L'adresse d'un appel, ou une adresse vide si le chemin sort de ce que le
// service a le droit de recevoir (`/v1/…`, `/api/billing/…`, `/api/auth/…`).
GURL ServiceURL(Service service, const std::string& path);

struct FetchResult {
  // Code HTTP, ou 0 quand rien n'est revenu (réseau coupé, délai dépassé).
  int status = 0;
  std::string body;
};

using FetchCallback = base::OnceCallback<void(FetchResult)>;

// `method` : "GET" ou "POST". `body` : JSON déjà sérialisé (POST seulement).
// `headers` : paires nom / valeur ajoutées telles quelles.
void Fetch(const GURL& url,
           const std::string& method,
           const std::string& body,
           const std::vector<std::pair<std::string, std::string>>& headers,
           FetchCallback callback);

}  // namespace browther_referral

#endif  // BRAVE_BROWSER_BROWTHER_REFERRAL_BROWTHER_REFERRAL_NET_H_
