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
#include "components/infobars/content/content_infobar_manager.h"
#include "components/infobars/core/infobar.h"
#include "components/infobars/core/infobar_manager.h"
#include "components/vector_icons/vector_icons.h"
#include "content/public/browser/web_contents.h"
#include "ui/base/clipboard/clipboard_constants.h"
#include "ui/base/clipboard/scoped_clipboard_writer.h"
#include "ui/base/l10n/l10n_util.h"
#include "ui/base/page_transition_types.h"
#include "ui/base/window_open_disposition.h"

namespace {

// App Sawtunaa autonome + son extension. Les DEUX sont nécessaires sur du
// contenu protégé : c'est l'extension (`chrome.tabCapture`) qui contourne la
// protection de capture — une capture système est détectée comme telle et le
// navigateur refuse alors de lire le DRM. L'app seule ne suffit donc pas.
// Cf. private/docs/WIDEVINE_VMP.md § 5.4.
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

ui::ImageModel BrowtherProtectedContentInfoBarDelegate::GetIcon() const {
  // Une barre de texte nu passe inaperçue (retour Karim). L'icône est le
  // premier élément posé par InfoBarView → c'est ce qui accroche l'œil.
  return ui::ImageModel::FromVectorIcon(vector_icons::kVideocamOffIcon);
}

std::u16string BrowtherProtectedContentInfoBarDelegate::GetMessageText() const {
  if (mode_ == Mode::kBlocked) {
    return l10n_util::GetStringUTF16(
        offer_sawtunaa_app_
            ? IDS_BROWTHER_PROTECTED_CONTENT_BLOCKED_MESSAGE_SAWTUNAA
            : IDS_BROWTHER_PROTECTED_CONTENT_BLOCKED_MESSAGE);
  }
  return l10n_util::GetStringUTF16(
      offer_sawtunaa_app_
          ? IDS_BROWTHER_PROTECTED_CONTENT_UNFILTERED_MESSAGE_SAWTUNAA
          : IDS_BROWTHER_PROTECTED_CONTENT_UNFILTERED_MESSAGE);
}

int BrowtherProtectedContentInfoBarDelegate::GetButtons() const {
  if (mode_ == Mode::kBlocked) {
    // Action principale = aller voir la vidéo là où elle marche. Action
    // secondaire = récupérer Sawtunaa pour y retirer la musique.
    return BUTTON_OK | (offer_sawtunaa_app_ ? BUTTON_CANCEL : 0);
  }
  // kUnfiltered : la page marche, la seule action utile est Sawtunaa. Sans
  // Sawtunaa activé, le message est purement informatif → aucun bouton.
  return offer_sawtunaa_app_ ? BUTTON_OK : BUTTON_NONE;
}

std::u16string BrowtherProtectedContentInfoBarDelegate::GetButtonLabel(
    InfoBarButton button) const {
  if (mode_ == Mode::kUnfiltered) {
    return button == BUTTON_OK
               ? l10n_util::GetStringUTF16(
                     IDS_BROWTHER_PROTECTED_CONTENT_GET_SAWTUNAA)
               : std::u16string();
  }
  switch (button) {
    case BUTTON_OK:
      return l10n_util::GetStringUTF16(
          can_open_in_default_browser_
              ? IDS_BROWTHER_PROTECTED_CONTENT_OPEN_IN_DEFAULT_BROWSER
              : IDS_BROWTHER_PROTECTED_CONTENT_COPY_LINK);
    case BUTTON_CANCEL:
      return l10n_util::GetStringUTF16(
          IDS_BROWTHER_PROTECTED_CONTENT_GET_SAWTUNAA);
    default:
      return std::u16string();
  }
}

std::vector<int> BrowtherProtectedContentInfoBarDelegate::GetButtonsOrder()
    const {
  if (mode_ == Mode::kUnfiltered) {
    return offer_sawtunaa_app_ ? std::vector<int>{BUTTON_OK}
                               : std::vector<int>{};
  }
  return offer_sawtunaa_app_ ? std::vector<int>{BUTTON_OK, BUTTON_CANCEL}
                             : std::vector<int>{BUTTON_OK};
}

bool BrowtherProtectedContentInfoBarDelegate::IsProminent(int id) const {
  // BUTTON_OK l'est déjà d'office (brave_confirm_infobar.cc) ; on laisse le
  // bouton Sawtunaa en secondaire pour garder une hiérarchie lisible.
  return false;
}

bool BrowtherProtectedContentInfoBarDelegate::ShouldSupportMultiLine() const {
  return true;
}

size_t BrowtherProtectedContentInfoBarDelegate::GetMaxLines() const {
  // 3 lignes : les messages expliquent la CAUSE puis la marche à suivre, ils
  // ne tiennent pas en 2.
  return 3;
}

void BrowtherProtectedContentInfoBarDelegate::OpenSawtunaaPage() {
  auto* web_contents =
      infobars::ContentInfoBarManager::WebContentsFromInfoBar(infobar());
  if (!web_contents) {
    return;
  }
  web_contents->OpenURL(
      content::OpenURLParams(GURL(kSawtunaaAppUrl), content::Referrer(),
                             WindowOpenDisposition::NEW_FOREGROUND_TAB,
                             ui::PAGE_TRANSITION_LINK,
                             /*is_renderer_initiated=*/false),
      /*navigation_handle_callback=*/{});
}

void BrowtherProtectedContentInfoBarDelegate::OpenElsewhereOrCopyLink() {
  if (can_open_in_default_browser_) {
#if BUILDFLAG(IS_CHROMEOS)
    // Browther ne cible pas ChromeOS ; la surcharge y prend un Profile.
    NOTREACHED();
#else
    platform_util::OpenExternal(page_url_);
#endif
    return;
  }
  ui::ScopedClipboardWriter(ui::ClipboardBuffer::kCopyPaste)
      .WriteText(base::UTF8ToUTF16(page_url_.spec()));
}

bool BrowtherProtectedContentInfoBarDelegate::Accept() {
  if (mode_ == Mode::kUnfiltered) {
    OpenSawtunaaPage();
  } else {
    OpenElsewhereOrCopyLink();
  }
  return true;  // ferme la barre
}

bool BrowtherProtectedContentInfoBarDelegate::Cancel() {
  // Uniquement câblé en kBlocked, où BUTTON_CANCEL porte « Sawtunaa ».
  if (mode_ == Mode::kBlocked && offer_sawtunaa_app_) {
    OpenSawtunaaPage();
  }
  return true;
}
