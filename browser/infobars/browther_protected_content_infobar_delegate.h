// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_BROWSER_INFOBARS_BROWTHER_PROTECTED_CONTENT_INFOBAR_DELEGATE_H_
#define BRAVE_BROWSER_INFOBARS_BROWTHER_PROTECTED_CONTENT_INFOBAR_DELEGATE_H_

#include <string>
#include <vector>

#include "brave/components/infobars/core/brave_confirm_infobar_delegate.h"
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
// Dans les deux cas on propose l'app Sawtunaa (hors navigateur, donc non
// concernée par le DRM) quand l'utilisateur se sert de Sawtunaa. Pour
// Basarunaa il n'existe aujourd'hui aucune alternative — on ne fait donc
// aucune promesse.
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
  // sinon le lien est hors sujet.
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
  std::u16string GetMessageText() const override;
  int GetButtons() const override;
  std::u16string GetButtonLabel(InfoBarButton button) const override;
  std::vector<int> GetButtonsOrder() const override;
  bool ShouldSupportMultiLine() const override;
  size_t GetMaxLines() const override;
  bool Accept() override;
  std::u16string GetLinkText() const override;
  GURL GetLinkURL() const override;

  const Mode mode_;
  const GURL page_url_;
  const bool can_open_in_default_browser_;
  const bool offer_sawtunaa_app_;
};

#endif  // BRAVE_BROWSER_INFOBARS_BROWTHER_PROTECTED_CONTENT_INFOBAR_DELEGATE_H_
