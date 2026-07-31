// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_BROWSER_BROWTHER_BROWTHER_PROTECTED_CONTENT_TAB_HELPER_H_
#define BRAVE_BROWSER_BROWTHER_BROWTHER_PROTECTED_CONTENT_TAB_HELPER_H_

#include "base/memory/weak_ptr.h"
#include "base/timer/timer.h"
#include "brave/components/browther_drm/browther_drm.mojom.h"
#include "content/public/browser/render_frame_host_receiver_set.h"
#include "content/public/browser/web_contents_observer.h"
#include "content/public/browser/web_contents_user_data.h"

// [Browther] Dit à l'utilisateur ce qui se passe vraiment sur une page à
// contenu protégé (DRM). Deux cas, tous deux muets sans nous :
//
//  1. La lecture protégée ÉCHOUE (cas Netflix aujourd'hui, faute de signature
//     VMP). Chromium ne voit AUCUNE erreur : le CDM s'initialise, le challenge
//     de licence part, et c'est le serveur du service qui refuse. Le site
//     affiche un code opaque (« E100 »). On détecte donc l'ABSENCE DE SUCCÈS :
//     un challenge est parti, et N secondes plus tard aucune clé n'est devenue
//     utilisable.
//
//  2. La lecture protégée MARCHE (démo Bitmovin, et tout le catalogue si la
//     certification VMP arrive un jour). Là, c'est Basarunaa/Sawtunaa qui ne
//     s'appliquent pas, parce qu'on refuse délibérément de toucher au média
//     protégé (cf. private/docs/TODO.md § média DRM déchiffré). Sans message,
//     l'utilisateur conclut juste que « le floutage ne marche pas ».
//
// Spec : private/docs/WIDEVINE_VMP.md § 10.
class BrowtherProtectedContentTabHelper final
    : public content::WebContentsObserver,
      public content::WebContentsUserData<BrowtherProtectedContentTabHelper>,
      public browther_drm::mojom::BrowtherDrmStatus {
 public:
  explicit BrowtherProtectedContentTabHelper(content::WebContents* contents);

  BrowtherProtectedContentTabHelper(
      const BrowtherProtectedContentTabHelper&) = delete;
  BrowtherProtectedContentTabHelper& operator=(
      const BrowtherProtectedContentTabHelper&) = delete;

  ~BrowtherProtectedContentTabHelper() override;

  static void BindBrowtherDrmStatus(
      mojo::PendingAssociatedReceiver<browther_drm::mojom::BrowtherDrmStatus>
          receiver,
      content::RenderFrameHost* rfh);

  // content::WebContentsObserver:
  void DidStartNavigation(
      content::NavigationHandle* navigation_handle) override;

  // browther_drm::mojom::BrowtherDrmStatus:
  void OnLicenseRequestSent() override;
  void OnKeyUsable() override;

  WEB_CONTENTS_USER_DATA_KEY_DECL();

 private:
  // Échéance atteinte sans clé utilisable → lecture protégée impossible.
  void OnLicenseTimeout();
  // Point d'entrée unique de l'affichage : résout d'abord, en asynchrone, si
  // Browther est le navigateur par défaut (auquel cas « ouvrir dans le
  // navigateur par défaut » rouvrirait la page ici même).
  void ShowInfoBar(bool blocked);
  void ShowInfoBarWithDefaultBrowserState(bool blocked, bool browther_is_default);
  // Retire notre barre si elle est encore affichée (correction d'un verdict
  // « impossible à lire » démenti par l'arrivée d'une clé).
  void RemoveOurInfoBar();

  content::RenderFrameHostReceiverSet<browther_drm::mojom::BrowtherDrmStatus>
      receivers_;

  // Une seule barre par navigation, quelle que soit la situation : un lecteur
  // DRM crée plusieurs sessions (audio + vidéo, plus les retries).
  bool notified_this_navigation_ = false;
  // La barre affichée est-elle celle du mode « bloqué » ? Sert à la corriger
  // si une clé finit par arriver.
  bool notified_blocked_ = false;
  bool license_request_seen_ = false;

  base::OneShotTimer license_timer_;
  base::WeakPtrFactory<BrowtherProtectedContentTabHelper> weak_factory_{this};
};

#endif  // BRAVE_BROWSER_BROWTHER_BROWTHER_PROTECTED_CONTENT_TAB_HELPER_H_
