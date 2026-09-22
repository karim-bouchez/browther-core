// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/browser/browther/referral/browther_referral_account.h"

#include <utility>

#include "base/base64.h"
#include "base/functional/bind.h"
#include "base/functional/callback.h"
#include "base/functional/callback_helpers.h"
#include "base/json/json_reader.h"
#include "base/json/json_writer.h"
#include "base/strings/strcat.h"
#include "brave/browser/browther/referral/browther_referral_net.h"
#include "brave/browser/browther/referral/browther_referral_prefs.h"
#include "chrome/browser/browser_process.h"
#include "components/os_crypt/async/browser/os_crypt_async.h"
#include "components/os_crypt/async/common/encryptor.h"
#include "components/prefs/pref_service.h"
#include "components/prefs/scoped_user_pref_update.h"

namespace browther_referral {

namespace {

// L'identifiant de client du flux par appareil, côté `auth-service` (liste
// fermée `validateClient`). ⚠️ Un par PLATEFORME, pas par produit : la page
// d'approbation dit « Connecter Browther sur un ordinateur ».
constexpr char kClientId[] = "browther-desktop";
constexpr char kDeviceGrant[] = "urn:ietf:params:oauth:grant-type:device_code";

constexpr char kUserId[] = "userId";
constexpr char kEmail[] = "email";
constexpr char kName[] = "name";
constexpr char kToken[] = "token";

PrefService* LocalState() {
  return g_browser_process ? g_browser_process->local_state() : nullptr;
}

std::optional<base::DictValue> ParseDict(const std::string& body) {
  return base::JSONReader::ReadDict(body, base::JSON_PARSE_RFC);
}

std::string ToJson(const base::DictValue& dict) {
  std::string out;
  base::JSONWriter::Write(dict, &out);
  return out;
}

base::Value Failure(const std::string& error) {
  base::DictValue dict;
  dict.Set("ok", false);
  dict.Set("error", error);
  return base::Value(std::move(dict));
}

base::Value State(const std::string& state) {
  base::DictValue dict;
  dict.Set("state", state);
  return base::Value(std::move(dict));
}

}  // namespace

// static
BrowtherReferralAccount* BrowtherReferralAccount::Get() {
  static base::NoDestructor<BrowtherReferralAccount> instance;
  return instance.get();
}

BrowtherReferralAccount::BrowtherReferralAccount() = default;
BrowtherReferralAccount::~BrowtherReferralAccount() = default;

base::Value BrowtherReferralAccount::Info() const {
  PrefService* local_state = LocalState();
  if (!local_state) {
    return base::Value();
  }
  const base::DictValue& account = local_state->GetDict(prefs::kAccount);
  const std::string* user_id = account.FindString(kUserId);
  const std::string* token = account.FindString(kToken);
  if (!user_id || user_id->empty() || !token || token->empty()) {
    return base::Value();
  }
  base::DictValue info;
  info.Set(kUserId, *user_id);
  if (const std::string* email = account.FindString(kEmail)) {
    info.Set(kEmail, *email);
  }
  if (const std::string* name = account.FindString(kName)) {
    info.Set(kName, *name);
  }
  return base::Value(std::move(info));
}

void BrowtherReferralAccount::StartLogin(
    base::OnceCallback<void(base::Value)> done) {
  base::DictValue body;
  body.Set("client_id", kClientId);
  Fetch(ServiceURL(Service::kAuth, "/api/auth/device/code"), "POST",
        ToJson(body), {},
        base::BindOnce(
            [](base::WeakPtr<BrowtherReferralAccount> self,
               base::OnceCallback<void(base::Value)> done,
               FetchResult result) {
              if (!self) {
                return;
              }
              std::optional<base::DictValue> dict = ParseDict(result.body);
              const std::string* device_code =
                  dict ? dict->FindString("device_code") : nullptr;
              const std::string* user_code =
                  dict ? dict->FindString("user_code") : nullptr;
              if (result.status != 200 || !device_code || !user_code) {
                std::move(done).Run(Failure(
                    result.status == 0 ? "unreachable" : "refused"));
                return;
              }
              self->device_code_ = *device_code;
              base::DictValue out;
              out.Set("ok", true);
              out.Set("userCode", *user_code);
              if (const std::string* uri = dict->FindString("verification_uri")) {
                out.Set("verificationUri", *uri);
              }
              if (const std::string* uri =
                      dict->FindString("verification_uri_complete")) {
                out.Set("verificationUriComplete", *uri);
              }
              out.Set("expiresIn", dict->FindInt("expires_in").value_or(1800));
              out.Set("interval", dict->FindInt("interval").value_or(5));
              std::move(done).Run(base::Value(std::move(out)));
            },
            weak_factory_.GetWeakPtr(), std::move(done)));
}

void BrowtherReferralAccount::PollLogin(
    base::OnceCallback<void(base::Value)> done) {
  if (device_code_.empty()) {
    std::move(done).Run(State("expired"));
    return;
  }
  base::DictValue body;
  body.Set("grant_type", kDeviceGrant);
  body.Set("device_code", device_code_);
  body.Set("client_id", kClientId);
  Fetch(ServiceURL(Service::kAuth, "/api/auth/device/token"), "POST",
        ToJson(body), {},
        base::BindOnce(
            [](base::WeakPtr<BrowtherReferralAccount> self,
               base::OnceCallback<void(base::Value)> done,
               FetchResult result) {
              if (!self) {
                return;
              }
              std::optional<base::DictValue> dict = ParseDict(result.body);
              if (result.status == 200 && dict) {
                const std::string* token = dict->FindString("access_token");
                if (!token || token->empty()) {
                  std::move(done).Run(State("error"));
                  return;
                }
                self->device_code_.clear();
                self->OnToken(std::move(done), *token);
                return;
              }
              const std::string* error = dict ? dict->FindString("error")
                                               : nullptr;
              if (result.status == 0) {
                // Réseau coupé : on réessaiera au prochain tour.
                std::move(done).Run(State("pending"));
              } else if (error && *error == "authorization_pending") {
                std::move(done).Run(State("pending"));
              } else if (error && *error == "slow_down") {
                std::move(done).Run(State("slow_down"));
              } else if (error && *error == "access_denied") {
                self->device_code_.clear();
                std::move(done).Run(State("denied"));
              } else if (error && (*error == "expired_token" ||
                                   *error == "invalid_grant")) {
                self->device_code_.clear();
                std::move(done).Run(State("expired"));
              } else {
                std::move(done).Run(State("error"));
              }
            },
            weak_factory_.GetWeakPtr(), std::move(done)));
}

void BrowtherReferralAccount::OnToken(
    base::OnceCallback<void(base::Value)> done,
    std::string token) {
  // Qui est-ce ? `get-session` avec le jeton tout neuf (plugin `bearer` côté
  // `auth-service`) — l'identifiant du compte devient le sujet du parrainage.
  Fetch(ServiceURL(Service::kAuth, "/api/auth/get-session"), "GET", "",
        {{"Authorization", base::StrCat({"Bearer ", token})}},
        base::BindOnce(
            [](base::WeakPtr<BrowtherReferralAccount> self,
               base::OnceCallback<void(base::Value)> done, std::string token,
               FetchResult result) {
              if (self) {
                self->OnSession(std::move(done), std::move(token),
                                result.status, std::move(result.body));
              }
            },
            weak_factory_.GetWeakPtr(), std::move(done), std::move(token)));
}

void BrowtherReferralAccount::OnSession(
    base::OnceCallback<void(base::Value)> done,
    std::string token,
    int status,
    std::string body) {
  std::optional<base::DictValue> dict = ParseDict(body);
  const base::DictValue* user = dict ? dict->FindDict("user") : nullptr;
  const std::string* user_id = user ? user->FindString("id") : nullptr;
  if (status != 200 || !user_id || user_id->empty()) {
    std::move(done).Run(State("error"));
    return;
  }
  base::DictValue account;
  account.Set(kUserId, *user_id);
  if (const std::string* email = user->FindString("email")) {
    account.Set(kEmail, *email);
  }
  if (const std::string* name = user->FindString("name")) {
    account.Set(kName, *name);
  }
  g_browser_process->os_crypt_async()->GetInstance(base::BindOnce(
      [](base::DictValue account, std::string token,
         base::OnceCallback<void(base::Value)> done,
         os_crypt_async::Encryptor encryptor) {
        std::string ciphertext;
        PrefService* local_state = LocalState();
        if (!local_state || !encryptor.EncryptString(token, &ciphertext)) {
          std::move(done).Run(State("error"));
          return;
        }
        base::DictValue stored = account.Clone();
        stored.Set(kToken, base::Base64Encode(ciphertext));
        local_state->SetDict(prefs::kAccount, std::move(stored));
        base::DictValue out;
        out.Set("state", "connected");
        out.Set("account", std::move(account));
        std::move(done).Run(base::Value(std::move(out)));
      },
      std::move(account), std::move(token), std::move(done)));
}

void BrowtherReferralAccount::CancelLogin() {
  device_code_.clear();
}

void BrowtherReferralAccount::SignOut(base::OnceClosure done) {
  WithToken(base::BindOnce(
      [](base::OnceClosure done, std::optional<std::string> token) {
        // Oublié ici QUOI QU'IL ARRIVE côté serveur : se déconnecter ne doit
        // jamais dépendre du réseau.
        if (PrefService* local_state = LocalState()) {
          local_state->ClearPref(prefs::kAccount);
        }
        if (token) {
          Fetch(ServiceURL(Service::kAuth, "/api/auth/sign-out"), "POST", "{}",
                {{"Authorization", base::StrCat({"Bearer ", *token})}},
                base::DoNothing());
        }
        std::move(done).Run();
      },
      std::move(done)));
}

void BrowtherReferralAccount::WithToken(
    base::OnceCallback<void(std::optional<std::string>)> done) {
  PrefService* local_state = LocalState();
  const std::string* stored =
      local_state ? local_state->GetDict(prefs::kAccount).FindString(kToken)
                  : nullptr;
  std::string ciphertext;
  if (!stored || stored->empty() || !base::Base64Decode(*stored, &ciphertext)) {
    std::move(done).Run(std::nullopt);
    return;
  }
  g_browser_process->os_crypt_async()->GetInstance(base::BindOnce(
      [](std::string ciphertext,
         base::OnceCallback<void(std::optional<std::string>)> done,
         os_crypt_async::Encryptor encryptor) {
        std::string token;
        if (!encryptor.DecryptString(ciphertext, &token)) {
          std::move(done).Run(std::nullopt);
          return;
        }
        std::move(done).Run(std::move(token));
      },
      std::move(ciphertext), std::move(done)));
}

}  // namespace browther_referral
