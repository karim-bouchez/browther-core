// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/browser/ui/webui/browther_referral/browther_referral_dialog.h"

#include <memory>
#include <string>
#include <vector>

#include "base/logging.h"
#include "base/no_destructor.h"
#include "base/strings/escape.h"
#include "base/strings/strcat.h"
#include "brave/browser/browther/referral/browther_referral_launch.h"
#include "chrome/browser/ui/views/chrome_web_dialog_view.h"
#include "content/public/browser/web_contents.h"
#include "ui/base/mojom/ui_base_types.mojom.h"
#include "ui/gfx/geometry/size.h"
#include "ui/views/widget/widget.h"
#include "ui/web_dialogs/web_dialog_delegate.h"

namespace browther_referral {

namespace {

// ⚠️ Les cotes de la carte du flow (`private/webui/referral`), pas plus : la
// modale n'a ni titre ni bordure, c'est la carte elle-même qu'on voit.
constexpr int kDialogWidth = 460;
constexpr int kDialogHeight = 660;

// La modale ouverte, s'il y en a une — une seule à la fois par principe.
// ⚠️ `base::NoDestructor` : `gfx::NativeWindow` a un destructeur, et Chromium
// interdit les destructeurs de fin de programme sur les globales.
gfx::NativeWindow& ModalWindow() {
  static base::NoDestructor<gfx::NativeWindow> window;
  return *window;
}

class ReferralDialogDelegate : public ui::WebDialogDelegate {
 public:
  explicit ReferralDialogDelegate(const std::string& screen) {
    set_can_close(true);
    set_dialog_modal_type(ui::mojom::ModalType::kWindow);
    set_show_dialog_title(false);
    set_dialog_size(gfx::Size(kDialogWidth, kDialogHeight));
    // `host=modal` : l'app ne monte QUE le flow (⛔ pas l'écran Parrainage
    // derrière), et `screen` lui dit lequel ouvrir (`app.tsx`).
    set_dialog_content_url(
        GURL(base::StrCat({kReferralURL, "?host=modal&screen=",
                           base::EscapeQueryParamValue(screen, false)})));
  }

  ReferralDialogDelegate(const ReferralDialogDelegate&) = delete;
  ReferralDialogDelegate& operator=(const ReferralDialogDelegate&) = delete;
  ~ReferralDialogDelegate() override = default;
};

}  // namespace

bool ShowModal(content::WebContents* initiator, const std::string& screen) {
  if (!IsEnabled() || !initiator) {
    return false;
  }
  // Déjà ouverte : on la remet devant plutôt que d'en empiler une deuxième.
  if (ModalWindow()) {
    if (views::Widget* widget =
            views::Widget::GetWidgetForNativeWindow(ModalWindow())) {
      widget->Show();
      return true;
    }
    ModalWindow() = gfx::NativeWindow();
  }
  // ⚠️ La vue PARENTE fait la modalité : sans elle, la fenêtre s'ouvrirait
  // libre et l'on retomberait sur une fenêtre qu'on peut ignorer.
  views::Widget* parent_widget = views::Widget::GetWidgetForNativeWindow(
      initiator->GetTopLevelNativeWindow());
  if (!parent_widget) {
    LOG(ERROR) << "[browther] modale du parrainage : pas de fenêtre parente";
    return false;
  }
  ModalWindow() = chrome::ShowWebDialogWithParams(
      parent_widget->GetNativeView(), initiator->GetBrowserContext(),
      new ReferralDialogDelegate(screen), std::nullopt);
  return static_cast<bool>(ModalWindow());
}

void CloseModal() {
  if (!ModalWindow()) {
    return;
  }
  views::Widget* widget =
      views::Widget::GetWidgetForNativeWindow(ModalWindow());
  ModalWindow() = gfx::NativeWindow();
  if (widget) {
    widget->Close();
  }
}

}  // namespace browther_referral
