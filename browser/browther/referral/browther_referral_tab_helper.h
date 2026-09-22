// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_BROWSER_BROWTHER_REFERRAL_BROWTHER_REFERRAL_TAB_HELPER_H_
#define BRAVE_BROWSER_BROWTHER_REFERRAL_BROWTHER_REFERRAL_TAB_HELPER_H_

#include "base/memory/weak_ptr.h"
#include "content/public/browser/web_contents_observer.h"
#include "content/public/browser/web_contents_user_data.h"

// Ce que le parrainage apprend d'un onglet — desktop seulement :
//  - une **vraie page chargée** (cadre principal, `http(s)`, profil normal) :
//    l'unité d'usage de Browther (§ 9), le moment de mérite (« N-ième onglet du
//    jour », § 3.1) et la moitié « durée » de la validation du filleul ;
//  - le **retour du paiement** (§ 12.17) : Polar renvoie sur
//    `https://browther.devndin.com/billing/paid` — dans Browther, l'onglet est
//    aussitôt remplacé par l'écran « Merci » (7 bis). ⭐ C'est le « deep link »
//    de Sawtunaa, sans scheme à enregistrer : le navigateur voit passer
//    l'adresse. ⛔ Aucun code ni jeton n'y circule, seul le drapeau `paid`.
class BrowtherReferralTabHelper final
    : public content::WebContentsObserver,
      public content::WebContentsUserData<BrowtherReferralTabHelper> {
 public:
  explicit BrowtherReferralTabHelper(content::WebContents* contents);
  BrowtherReferralTabHelper(const BrowtherReferralTabHelper&) = delete;
  BrowtherReferralTabHelper& operator=(const BrowtherReferralTabHelper&) =
      delete;
  ~BrowtherReferralTabHelper() override;

  // content::WebContentsObserver:
  void DocumentOnLoadCompletedInPrimaryMainFrame() override;
  void DidFinishNavigation(
      content::NavigationHandle* navigation_handle) override;

  WEB_CONTENTS_USER_DATA_KEY_DECL();

 private:
  void ReplaceWithThanksPage();

  base::WeakPtrFactory<BrowtherReferralTabHelper> weak_factory_{this};
};

#endif  // BRAVE_BROWSER_BROWTHER_REFERRAL_BROWTHER_REFERRAL_TAB_HELPER_H_
