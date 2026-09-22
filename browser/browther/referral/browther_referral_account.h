// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_BROWSER_BROWTHER_REFERRAL_BROWTHER_REFERRAL_ACCOUNT_H_
#define BRAVE_BROWSER_BROWTHER_REFERRAL_BROWTHER_REFERRAL_ACCOUNT_H_

#include <optional>
#include <string>

#include "base/functional/callback_forward.h"
#include "base/memory/weak_ptr.h"
#include "base/no_destructor.h"
#include "base/values.h"

// Le compte dev&din FACULTATIF (`PARRAINAGE.md` § 7.1, arbitré par Karim le
// 2026-09-22) — ⛔ jamais exigé : le parrainage marche dès l'installation sur
// l'identité d'appareil. Il ne sert qu'à faire suivre le SOUTIEN (mois gagnés,
// code, abonnement) d'un Mac à un iPhone. 🔴 Il ne porte QUE ça : ⛔ ni
// historique, ni favoris, ni onglets — ce n'est pas un compte de
// synchronisation.
//
// ## La connexion : le Mac affiche, le téléphone approuve
//
// Autorisation par appareil (RFC 8628, plugin `device-authorization` de Better
// Auth dans `auth-service`) : Browther demande un code, affiche un QR vers
// `https://auth.devndin.com/device?user_code=…`, et attend. La personne le
// scanne avec son téléphone (ou ouvre le lien sur cet ordinateur), s'y
// connecte comme sur n'importe quel site dev&din, approuve — et Browther reçoit
// SA session. ⭐ Pas d'e-mail à retaper sur le Mac, et rien à changer dans l'app
// iOS pour que ça marche.
//
// 🔴 Le jeton de session est CHIFFRÉ (OSCrypt) dans le Local State et ⛔ ne sort
// jamais vers le JavaScript : les appels qui en ont besoin passent par
// `browther_referral::Fetch`, qui l'ajoute lui-même.
namespace browther_referral {

class BrowtherReferralAccount {
 public:
  static BrowtherReferralAccount* Get();

  BrowtherReferralAccount(const BrowtherReferralAccount&) = delete;
  BrowtherReferralAccount& operator=(const BrowtherReferralAccount&) = delete;

  // `{userId, email, name}`, ou `none` sans compte.
  base::Value Info() const;

  // Demande un code : `{ok, userCode, verificationUri,
  // verificationUriComplete, expiresIn, interval}` ou `{ok:false, error}`.
  void StartLogin(base::OnceCallback<void(base::Value)> done);

  // Une tentative d'échange (à l'intervalle rendu par `StartLogin`) :
  // `{state: pending|slow_down|expired|denied|connected|error, account?}`.
  void PollLogin(base::OnceCallback<void(base::Value)> done);

  void CancelLogin();

  // Déconnecte CET appareil (session révoquée côté serveur, puis oubliée ici).
  // ⚠️ La couverture de l'appareil n'est pas perdue : la fusion lui en laisse
  // une copie (`referral`, brief B ter).
  void SignOut(base::OnceClosure done);

  // Le jeton déchiffré, pour les appels qui l'exigent — `nullopt` sans compte.
  void WithToken(base::OnceCallback<void(std::optional<std::string>)> done);

 private:
  friend class base::NoDestructor<BrowtherReferralAccount>;
  BrowtherReferralAccount();
  ~BrowtherReferralAccount();

  void OnToken(base::OnceCallback<void(base::Value)> done,
               std::string token);
  void OnSession(base::OnceCallback<void(base::Value)> done,
                 std::string token,
                 int status,
                 std::string body);

  std::string device_code_;

  base::WeakPtrFactory<BrowtherReferralAccount> weak_factory_{this};
};

}  // namespace browther_referral

#endif  // BRAVE_BROWSER_BROWTHER_REFERRAL_BROWTHER_REFERRAL_ACCOUNT_H_
