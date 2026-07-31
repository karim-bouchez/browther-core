// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_BROWSER_INFOBARS_BROWTHER_PROTECTED_CONTENT_INFOBAR_DELEGATE_H_
#define BRAVE_BROWSER_INFOBARS_BROWTHER_PROTECTED_CONTENT_INFOBAR_DELEGATE_H_

#include <cstddef>
#include <string>
#include <vector>

#include "brave/components/infobars/core/brave_confirm_infobar_delegate.h"
#include "ui/base/models/image_model.h"
#include "url/gurl.h"

namespace infobars {
class InfoBarManager;
}

// [Browther] Barre d'information affichée sur une page à contenu protégé (DRM).
// Deux situations distinctes, cf. private/docs/WIDEVINE_VMP.md § 10 :
//
//  - kBlocked    : le challenge de licence est parti, aucune clé n'est devenue
//                  utilisable. La lecture ne démarrera pas (nous n'avons pas de
//                  signature VMP). Le site, lui, n'affiche souvent qu'un code
//                  opaque — d'où l'intérêt de dire les choses.
//  - kUnfiltered  : la lecture protégée FONCTIONNE, mais nos features ne s'y
//                  appliquent pas (on refuse de lire du média protégé, cf.
//                  private/docs/TODO.md § média DRM déchiffré). Sans message,
//                  ça ressemble à « Basarunaa ne marche pas ».
//
// Règles de rédaction (retour Karim, 2026-07-31) — le message doit répondre
// à « POURQUOI ça ne marche pas » et « QU'EST-CE QUE JE FAIS maintenant » :
//  1. la cause est explicite (pas de certification / interdiction de toucher
//     au flux), pas seulement le constat ;
//  2. l'alternative Sawtunaa est **rattachée au problème** dans la phrase, et
//     portée par un BOUTON — pas par le lien de l'infobar, qui est rendu à
//     l'extrême droite (`GetEndX() - link_->width()`, brave_confirm_infobar.cc)
//     et se lit alors comme un élément sans rapport ;
//  3. on dit que l'app Sawtunaa ne suffit pas seule : il faut **aussi son
//     extension** (c'est `chrome.tabCapture` qui contourne la protection de
//     capture, la capture système rendrait du silence/noir — cf.
//     WIDEVINE_VMP.md § 5.4).
class BrowtherProtectedContentInfoBarDelegate
    : public BraveConfirmInfoBarDelegate {
 public:
  enum class Mode {
    kBlocked,     // lecture protégée impossible
    kUnfiltered,  // lecture protégée OK, mais non filtrée par Browther
  };

  // |can_open_in_default_browser| : faux quand Browther EST déjà le navigateur
  // par défaut — proposer « ouvrir dans le navigateur par défaut » rouvrirait
  // alors la page dans Browther. On propose « copier le lien » à la place.
  // |offer_sawtunaa_app| : seulement si l'utilisateur a Sawtunaa activé,
  // sinon l'app est hors sujet et le message n'en parle pas.
  static void Create(infobars::InfoBarManager* infobar_manager,
                     Mode mode,
                     const GURL& page_url,
                     bool can_open_in_default_browser,
                     bool offer_sawtunaa_app);

  BrowtherProtectedContentInfoBarDelegate(
      const BrowtherProtectedContentInfoBarDelegate&) = delete;
  BrowtherProtectedContentInfoBarDelegate& operator=(
      const BrowtherProtectedContentInfoBarDelegate&) = delete;

  ~BrowtherProtectedContentInfoBarDelegate() override;

 private:
  BrowtherProtectedContentInfoBarDelegate(Mode mode,
                                          const GURL& page_url,
                                          bool can_open_in_default_browser,
                                          bool offer_sawtunaa_app);

  // BraveConfirmInfoBarDelegate:
  infobars::InfoBarDelegate::InfoBarIdentifier GetIdentifier() const override;
  ui::ImageModel GetIcon() const override;
  std::u16string GetMessageText() const override;
  int GetButtons() const override;
  std::u16string GetButtonLabel(InfoBarButton button) const override;
  std::vector<int> GetButtonsOrder() const override;
  bool IsProminent(int id) const override;
  bool ShouldSupportMultiLine() const override;
  size_t GetMaxLines() const override;
  bool Accept() override;
  bool Cancel() override;

  // Ouvre la page de l'app Sawtunaa dans un nouvel onglet Browther (c'est une
  // page web ordinaire : pas de raison de sortir du navigateur pour ça).
  void OpenSawtunaaPage();
  // kBlocked : sortir la page vers un navigateur capable de la lire, ou à
  // défaut mettre le lien dans le presse-papiers.
  void OpenElsewhereOrCopyLink();

  const Mode mode_;
  const GURL page_url_;
  const bool can_open_in_default_browser_;
  const bool offer_sawtunaa_app_;
};

#endif  // BRAVE_BROWSER_INFOBARS_BROWTHER_PROTECTED_CONTENT_INFOBAR_DELEGATE_H_
