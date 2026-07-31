// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/browser/browther/browther_protected_content_tab_helper.h"

#include <utility>

#include "base/functional/bind.h"
#include "base/logging.h"
#include "base/memory/ref_counted.h"
#include "base/memory/scoped_refptr.h"
#include "brave/browser/infobars/browther_protected_content_infobar_delegate.h"
#include "brave/components/constants/pref_names.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/shell_integration.h"
#include "components/infobars/content/content_infobar_manager.h"
#include "components/infobars/core/infobar.h"
#include "components/infobars/core/infobar_delegate.h"
#include "components/prefs/pref_service.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/web_contents.h"

namespace {

// Délai entre le départ du challenge de licence et le constat d'échec.
//
// 2 s (9 s à l'origine, ramené le 2026-07-31). Un serveur de licence qui
// FONCTIONNE répond en quelques centaines de ms — c'est un aller-retour HTTP,
// pas un calcul. Passé ~2 s, l'utilisateur a déjà vu l'erreur du site et il est
// reparti : un message qui arrive après n'aide plus personne.
//
// La décision est RÉVERSIBLE (cf. OnKeyUsable) : une clé qui arrive en retard
// retire la barre. La justesse ne dépend donc PAS de ce délai — ce qu'il borne,
// c'est le CLIGNOTEMENT. Trop court et on affiche puis on retire une barre sur
// des lectures qui marchaient : elle pousse le contenu de la page vers le bas,
// donc un aller-retour se voit et se paie en saccade. Sur une lecture protégée
// qui aboutit normalement (< 1 s), 2 s ne clignote pas ; descendre à 1 s
// commencerait à clignoter dès qu'un serveur est un peu lent, pour ne gagner
// qu'une seconde là où l'échec est de toute façon définitif.
constexpr base::TimeDelta kLicenseGracePeriod = base::Seconds(2);

}  // namespace

BrowtherProtectedContentTabHelper::BrowtherProtectedContentTabHelper(
    content::WebContents* contents)
    : WebContentsObserver(contents),
      content::WebContentsUserData<BrowtherProtectedContentTabHelper>(
          *contents),
      receivers_(contents, this) {}

BrowtherProtectedContentTabHelper::~BrowtherProtectedContentTabHelper() =
    default;

// static
void BrowtherProtectedContentTabHelper::BindBrowtherDrmStatus(
    mojo::PendingAssociatedReceiver<browther_drm::mojom::BrowtherDrmStatus>
        receiver,
    content::RenderFrameHost* rfh) {
  auto* web_contents = content::WebContents::FromRenderFrameHost(rfh);
  if (!web_contents) {
    return;
  }
  auto* tab_helper =
      BrowtherProtectedContentTabHelper::FromWebContents(web_contents);
  if (!tab_helper) {
    return;
  }
  tab_helper->receivers_.Bind(rfh, std::move(receiver));
}

void BrowtherProtectedContentTabHelper::DidStartNavigation(
    content::NavigationHandle* navigation_handle) {
  if (!navigation_handle->IsInPrimaryMainFrame() ||
      navigation_handle->IsSameDocument()) {
    return;
  }
  // Nouvelle page = nouvel état. Volontairement PAS réinitialisé sur une
  // navigation same-document : les lecteurs vidéo (Netflix, YouTube…) sont des
  // SPA qui changent d'URL sans recharger, et ré-afficher la barre à chaque
  // changement de titre serait pénible.
  license_timer_.Stop();
  notified_this_navigation_ = false;
  notified_blocked_ = false;
  license_request_seen_ = false;
}

void BrowtherProtectedContentTabHelper::OnLicenseRequestSent() {
  if (notified_this_navigation_ || license_timer_.IsRunning()) {
    return;
  }
  license_request_seen_ = true;
  license_timer_.Start(
      FROM_HERE, kLicenseGracePeriod,
      base::BindOnce(&BrowtherProtectedContentTabHelper::OnLicenseTimeout,
                     weak_factory_.GetWeakPtr()));
}

void BrowtherProtectedContentTabHelper::OnKeyUsable() {
  license_timer_.Stop();

  // Correction a posteriori : on a pu conclure trop tôt à un échec (serveur de
  // licence lent, renégociation). La clé prouve le contraire → on retire la
  // barre « impossible à lire » avant d'afficher la bonne. C'est ce filet qui
  // autorise un délai court (cf. kLicenseGracePeriod).
  if (notified_blocked_) {
    RemoveOurInfoBar();
    notified_blocked_ = false;
    notified_this_navigation_ = false;
  }
  if (notified_this_navigation_) {
    return;
  }
  // La lecture protégée fonctionne. On ne le signale que si l'utilisateur se
  // sert d'une feature qui, elle, ne s'appliquera pas — sinon c'est du bruit.
  auto* profile =
      Profile::FromBrowserContext(web_contents()->GetBrowserContext());
  if (!profile) {
    return;
  }
  auto* prefs = profile->GetPrefs();
  if (!prefs || (!prefs->GetBoolean(kBasarunaaEnabled) &&
                 !prefs->GetBoolean(kSawtunaaEnabled))) {
    return;
  }
  ShowInfoBar(/*blocked=*/false);
}

void BrowtherProtectedContentTabHelper::OnLicenseTimeout() {
  if (notified_this_navigation_ || !license_request_seen_) {
    return;
  }
  ShowInfoBar(/*blocked=*/true);
}

void BrowtherProtectedContentTabHelper::ShowInfoBar(bool blocked) {
  if (!blocked) {
    // Rien à proposer d'autre que l'app Sawtunaa : pas besoin de savoir si on
    // est le navigateur par défaut.
    ShowInfoBarWithDefaultBrowserState(blocked, /*browther_is_default=*/false);
    return;
  }
  // « Ouvrir dans le navigateur par défaut » n'a de sens que si CE navigateur
  // n'est pas le défaut — sinon la page se rouvrirait ici même (cas courant :
  // l'utilisateur qui dogfoode Browther). La vérification est bloquante en
  // interne, d'où le worker asynchrone.
  scoped_refptr<shell_integration::DefaultBrowserWorker> worker =
      base::MakeRefCounted<shell_integration::DefaultBrowserWorker>();
  worker->StartCheckIsDefault(base::BindOnce(
      [](base::WeakPtr<BrowtherProtectedContentTabHelper> self, bool blocked,
         shell_integration::DefaultWebClientState state) {
        if (!self) {
          return;
        }
        self->ShowInfoBarWithDefaultBrowserState(
            blocked, state == shell_integration::IS_DEFAULT);
      },
      weak_factory_.GetWeakPtr(), blocked));
}

void BrowtherProtectedContentTabHelper::ShowInfoBarWithDefaultBrowserState(
    bool blocked,
    bool browther_is_default) {
  // Le worker est asynchrone : l'utilisateur a pu naviguer entre-temps.
  if (notified_this_navigation_) {
    return;
  }
  auto* infobar_manager =
      infobars::ContentInfoBarManager::FromWebContents(web_contents());
  if (!infobar_manager) {
    return;
  }
  auto* profile =
      Profile::FromBrowserContext(web_contents()->GetBrowserContext());
  auto* prefs = profile ? profile->GetPrefs() : nullptr;
  // L'app Sawtunaa n'est proposée qu'à qui se sert de Sawtunaa. Pour Basarunaa
  // il n'existe aucune alternative connue sur contenu protégé — on ne feint
  // pas d'en avoir une (cf. private/docs/WIDEVINE_VMP.md § 10.5).
  const bool offer_sawtunaa_app =
      prefs && prefs->GetBoolean(kSawtunaaEnabled);

  notified_this_navigation_ = true;
  notified_blocked_ = blocked;
  VLOG(1) << "[browtherDRM] infobar mode="
          << (blocked ? "blocked" : "unfiltered")
          << " default_browser=" << browther_is_default
          << " sawtunaa=" << offer_sawtunaa_app;
  BrowtherProtectedContentInfoBarDelegate::Create(
      infobar_manager,
      blocked ? BrowtherProtectedContentInfoBarDelegate::Mode::kBlocked
              : BrowtherProtectedContentInfoBarDelegate::Mode::kUnfiltered,
      web_contents()->GetLastCommittedURL(),
      /*can_open_in_default_browser=*/!browther_is_default,
      offer_sawtunaa_app);
}

void BrowtherProtectedContentTabHelper::RemoveOurInfoBar() {
  auto* infobar_manager =
      infobars::ContentInfoBarManager::FromWebContents(web_contents());
  if (!infobar_manager) {
    return;
  }
  // Recherche par identifiant plutôt que par pointeur gardé : la barre peut
  // avoir été fermée par l'utilisateur entre-temps, et un raw_ptr mémorisé
  // deviendrait pendouillant.
  for (infobars::InfoBar* bar : infobar_manager->infobars()) {
    if (bar->delegate()->GetIdentifier() ==
        infobars::InfoBarDelegate::BROWTHER_PROTECTED_CONTENT_INFOBAR_DELEGATE) {
      infobar_manager->RemoveInfoBar(bar);
      return;
    }
  }
}

WEB_CONTENTS_USER_DATA_KEY_IMPL(BrowtherProtectedContentTabHelper);
