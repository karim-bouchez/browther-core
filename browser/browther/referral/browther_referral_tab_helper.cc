// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/browser/browther/referral/browther_referral_tab_helper.h"

#include "base/functional/bind.h"
#include "base/strings/strcat.h"
#include "base/task/single_thread_task_runner.h"
#include "brave/browser/browther/referral/browther_referral_files.h"
#include "brave/browser/browther/referral/browther_referral_launch.h"
#include "brave/browser/browther/referral/browther_referral_usage.h"
#include "chrome/browser/browser_process.h"
#include "chrome/browser/profiles/profile.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/web_contents.h"
#include "ui/base/page_transition_types.h"
#include "url/gurl.h"

namespace {

constexpr char kBillingReturnHost[] = "browther.devndin.com";

// `/billing/paid` ou `/<langue>/billing/paid` : le site est traduit
// (`app/[locale]/…`), l'adresse de retour ne l'est pas forcément.
bool IsBillingReturn(const GURL& url) {
  if (!url.SchemeIs("https") || url.host() != kBillingReturnHost) {
    return false;
  }
  const std::string_view path = url.path();
  constexpr std::string_view kSuffix = "/billing/paid";
  return path.ends_with(kSuffix) || path.ends_with("/billing/paid/");
}

}  // namespace

BrowtherReferralTabHelper::BrowtherReferralTabHelper(
    content::WebContents* contents)
    : content::WebContentsObserver(contents),
      content::WebContentsUserData<BrowtherReferralTabHelper>(*contents) {
  // Le libellé du menu ⋯ se lit dès le premier onglet : il est prêt bien avant
  // qu'on ouvre le menu (`browther_referral_files.h`).
  if (browther_referral::IsEnabled()) {
    browther_referral::PreloadMenuLabel();
  }
}

BrowtherReferralTabHelper::~BrowtherReferralTabHelper() = default;

void BrowtherReferralTabHelper::DocumentOnLoadCompletedInPrimaryMainFrame() {
  if (!browther_referral::IsEnabled()) {
    return;
  }
  // ⛔ Une fenêtre privée ne compte pas : rien de ce qu'on y fait ne se note.
  Profile* profile =
      Profile::FromBrowserContext(web_contents()->GetBrowserContext());
  if (!profile || profile->IsOffTheRecord()) {
    return;
  }
  const GURL& url = web_contents()->GetLastCommittedURL();
  if (!url.SchemeIsHTTPOrHTTPS()) {
    return;
  }
  browther_referral::RecordRealPageLoad(g_browser_process->local_state());
}

void BrowtherReferralTabHelper::DidFinishNavigation(
    content::NavigationHandle* navigation_handle) {
  if (!browther_referral::IsEnabled() ||
      !navigation_handle->IsInPrimaryMainFrame() ||
      !navigation_handle->HasCommitted() ||
      !IsBillingReturn(navigation_handle->GetURL())) {
    return;
  }
  // ⚠️ Pas de navigation depuis l'observateur lui-même : on la poste.
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(&BrowtherReferralTabHelper::ReplaceWithThanksPage,
                                weak_factory_.GetWeakPtr()));
}

void BrowtherReferralTabHelper::ReplaceWithThanksPage() {
  // Adresse CONSTRUITE (§ 12.17) : ⛔ jamais l'adresse de retour telle quelle,
  // qui porte les paramètres du prestataire.
  web_contents()->GetController().LoadURL(
      GURL(base::StrCat({browther_referral::kReferralURL, "?billing=paid"})),
      content::Referrer(), ui::PAGE_TRANSITION_AUTO_TOPLEVEL, std::string());
}

WEB_CONTENTS_USER_DATA_KEY_IMPL(BrowtherReferralTabHelper);
