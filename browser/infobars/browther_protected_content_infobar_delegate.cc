// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/browser/infobars/browther_protected_content_infobar_delegate.h"

#include <memory>
#include <utility>

#include "base/notreached.h"
#include "base/strings/utf_string_conversions.h"
#include "brave/browser/infobars/brave_confirm_infobar_creator.h"
#include "brave/grit/brave_generated_resources.h"
#include "build/build_config.h"
#include "chrome/browser/platform_util.h"
#include "components/infobars/core/infobar.h"
#include "components/infobars/core/infobar_manager.h"
#include "ui/base/clipboard/clipboard_constants.h"
#include "ui/base/clipboard/scoped_clipboard_writer.h"
#include "ui/base/l10n/l10n_util.h"

namespace {

// App Sawtunaa autonome (hors navigateur) : c'est la seule voie qui reste pour
// supprimer la musique d'un flux protégé, puisque le navigateur, lui, ne doit
// pas y toucher. Cf. private/docs/WIDEVINE_VMP.md § 5.4.
constexpr char kSawtunaaAppUrl[] = "https://sawtunaa.devndin.com";

}  // namespace

// static
void BrowtherProtectedContentInfoBarDelegate::Create(
    infobars::InfoBarManager* infobar_manager,
    Mode mode,
    const GURL& page_url,
    bool can_open_in_default_browser,
    bool offer_sawtunaa_app) {
  if (!infobar_manager) {
    return;
  }
  infobar_manager->AddInfoBar(
      CreateBraveConfirmInfoBar(std::unique_ptr<BraveConfirmInfoBarDelegate>(
          new BrowtherProtectedContentInfoBarDelegate(
              mode, page_url, can_open_in_default_browser,
              offer_sawtunaa_app))));
}

BrowtherProtectedContentInfoBarDelegate::
    BrowtherProtectedContentInfoBarDelegate(Mode mode,
                                            const GURL& page_url,
                                            bool can_open_in_default_browser,
                                            bool offer_sawtunaa_app)
    : mode_(mode),
      page_url_(page_url),
      can_open_in_default_browser_(can_open_in_default_browser),
      offer_sawtunaa_app_(offer_sawtunaa_app) {}

BrowtherProtectedContentInfoBarDelegate::
    ~BrowtherProtectedContentInfoBarDelegate() = default;

infobars::InfoBarDelegate::InfoBarIdentifier
BrowtherProtectedContentInfoBarDelegate::GetIdentifier() const {
  return BROWTHER_PROTECTED_CONTENT_INFOBAR_DELEGATE;
}

std::u16string BrowtherProtectedContentInfoBarDelegate::GetMessageText() const {
  return l10n_util::GetStringUTF16(
      mode_ == Mode::kBlocked
          ? IDS_BROWTHER_PROTECTED_CONTENT_BLOCKED_MESSAGE
          : IDS_BROWTHER_PROTECTED_CONTENT_UNFILTERED_MESSAGE);
}

int BrowtherProtectedContentInfoBarDelegate::GetButtons() const {
  // kUnfiltered est purement informatif : la page marche, il n'y a rien à
  // faire. kBlocked propose une porte de sortie (autre navigateur / lien).
  return mode_ == Mode::kBlocked ? BUTTON_OK : BUTTON_NONE;
}

std::u16string BrowtherProtectedContentInfoBarDelegate::GetButtonLabel(
    InfoBarButton button) const {
  if (button != BUTTON_OK) {
    return std::u16string();
  }
  return l10n_util::GetStringUTF16(
      can_open_in_default_browser_
          ? IDS_BROWTHER_PROTECTED_CONTENT_OPEN_IN_DEFAULT_BROWSER
          : IDS_BROWTHER_PROTECTED_CONTENT_COPY_LINK);
}

std::vector<int> BrowtherProtectedContentInfoBarDelegate::GetButtonsOrder()
    const {
  return mode_ == Mode::kBlocked ? std::vector<int>{BUTTON_OK}
                                 : std::vector<int>{};
}

bool BrowtherProtectedContentInfoBarDelegate::ShouldSupportMultiLine() const {
  return true;
}

size_t BrowtherProtectedContentInfoBarDelegate::GetMaxLines() const {
  return 2;
}

bool BrowtherProtectedContentInfoBarDelegate::Accept() {
  if (can_open_in_default_browser_) {
#if BUILDFLAG(IS_CHROMEOS)
    // Browther ne cible pas ChromeOS ; la surcharge y prend un Profile.
    NOTREACHED();
#else
    platform_util::OpenExternal(page_url_);
#endif
  } else {
    ui::ScopedClipboardWriter(ui::ClipboardBuffer::kCopyPaste)
        .WriteText(base::UTF8ToUTF16(page_url_.spec()));
  }
  return true;  // ferme la barre
}

std::u16string BrowtherProtectedContentInfoBarDelegate::GetLinkText() const {
  // Pas de promesse pour Basarunaa : il n'existe aujourd'hui aucune façon de
  // flouter un flux protégé (ni dans le navigateur, ni depuis l'extérieur —
  // la capture système rend du noir). On ne propose donc que Sawtunaa, et
  // seulement si l'utilisateur s'en sert.
  return offer_sawtunaa_app_
             ? l10n_util::GetStringUTF16(
                   IDS_BROWTHER_PROTECTED_CONTENT_SAWTUNAA_APP)
             : std::u16string();
}

GURL BrowtherProtectedContentInfoBarDelegate::GetLinkURL() const {
  return offer_sawtunaa_app_ ? GURL(kSawtunaaAppUrl) : GURL();
}
