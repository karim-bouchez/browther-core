// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/browser/ui/views/brave_actions/basarunaa_action_view.h"

#include <memory>
#include <utility>

#include "base/check.h"
#include "base/check_deref.h"
#include "base/functional/bind.h"
#include "brave/app/brave_command_ids.h"
#include "brave/browser/browther/browther_protected_content_tab_helper.h"
#include "brave/browser/ui/brave_icon_with_badge_image_source.h"
#include "brave/browser/ui/browther_status_dot_image_source.h"
#include "brave/components/constants/pref_names.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/browser_commands.h"
#include "chrome/browser/ui/layout_constants.h"
#include "chrome/browser/ui/views/chrome_layout_provider.h"
#include "components/grit/brave_components_resources.h"
#include "components/prefs/pref_service.h"
#include "extensions/common/constants.h"
#include "ui/base/metadata/metadata_impl_macros.h"
#include "ui/base/models/image_model.h"
#include "ui/base/resource/resource_bundle.h"
#include "chrome/browser/ui/omnibox/omnibox_theme.h"
#include "ui/color/color_provider_manager.h"
#include "ui/gfx/image/image.h"
#include "ui/gfx/image/image_skia.h"
#include "ui/gfx/image/image_skia_operations.h"
#include "ui/gfx/image/image_skia_rep.h"
#include "ui/views/controls/button/menu_button_controller.h"

namespace {
constexpr SkColor kBadgeGreen = SkColorSetRGB(0x22, 0xC5, 0x5E);
constexpr SkColor kBadgeRed = SkColorSetRGB(0xEF, 0x44, 0x44);
// Browther: badge AMBRE — la feature est ON, mais elle ne s'applique pas à
// l'onglet courant parce que c'est du contenu protégé (DRM). Le badge est la
// seule surface visible SANS ouvrir la popup : sans lui, l'utilisateur voit
// « vert = actif » sur une page où il ne se passe rien.
// Cf. private/docs/WIDEVINE_VMP.md § 10.
constexpr SkColor kBadgeAmber = SkColorSetRGB(0xF5, 0x9E, 0x0B);
}  // namespace

BasarunaaActionView::BasarunaaActionView(Browser* browser)
    : ToolbarButton(base::BindRepeating(&BasarunaaActionView::OnButtonPressed,
                                        base::Unretained(this)),
                    /*menu_model=*/nullptr,
                    /*tab_strip_model=*/nullptr,
                    /*trigger_menu_on_long_press=*/false),
      browser_(browser),
      profile_prefs_(CHECK_DEREF(browser->profile()->GetPrefs())) {
  CHECK(browser_);

  // The MenuButtonController makes sure the panel closes when clicked if the
  // panel is already open (mirror of BraveVPNButton).
  auto menu_button_controller = std::make_unique<views::MenuButtonController>(
      this,
      base::BindRepeating(&BasarunaaActionView::OnButtonPressed,
                          base::Unretained(this)),
      std::make_unique<views::Button::DefaultButtonControllerDelegate>(this));
  menu_button_controller_ = menu_button_controller.get();
  SetButtonController(std::move(menu_button_controller));
  SetAccessibleName(u"Basarunaa");

  pref_change_registrar_.Init(&*profile_prefs_);
  pref_change_registrar_.Add(
      kBasarunaaEnabled,
      base::BindRepeating(&BasarunaaActionView::OnPrefChanged,
                          base::Unretained(this)));

  // Browther: le badge dépend maintenant de l'onglet actif (contenu protégé).
  browser_->tab_strip_model()->AddObserver(this);
}

BasarunaaActionView::~BasarunaaActionView() {
  if (browser_) {
    browser_->tab_strip_model()->RemoveObserver(this);
  }
}

void BasarunaaActionView::Init() {
  UpdateColorsAndInsets();
}

bool BasarunaaActionView::IsActive() const {
  return profile_prefs_->GetBoolean(kBasarunaaEnabled);
}

void BasarunaaActionView::OnPrefChanged() {
  UpdateColorsAndInsets();
}

void BasarunaaActionView::UpdateColorsAndInsets() {
  ToolbarButton::UpdateColorsAndInsets();

  ui::ResourceBundle& rb = ui::ResourceBundle::GetSharedInstance();
  const SkBitmap bitmap = rb.GetImageNamed(IDR_BASARUNAA_ICON_64).AsBitmap();
  if (bitmap.isNull()) {
    return;
  }

  const auto preferred_size = GetPreferredSize();
  const int icon_size =
      GetLayoutConstant(LayoutConstant::kLocationBarTrailingIconSize);
  const float scale =
      static_cast<float>(bitmap.width()) / static_cast<float>(icon_size);
  gfx::ImageSkia icon_image;
  icon_image.AddRepresentation(gfx::ImageSkiaRep(bitmap, scale));

  auto get_color_provider_callback =
      base::BindRepeating([]() -> const ui::ColorProvider* {
        return ui::ColorProviderManager::Get().GetColorProviderFor(
            ui::NativeTheme::GetInstanceForNativeUi()->GetColorProviderKey(
                nullptr));
      });

  // Browther: petit dot 8pt à cheval sur le coin bas-droite de l'icône (style
  // iOS), cohérent avec Sawtunaa.
  auto image_source = std::make_unique<browther::BrowtherStatusDotImageSource>(
      preferred_size, std::move(get_color_provider_callback), icon_size);
  // Tinte l'icône template (blanc + alpha) avec la couleur système toolbar.
  if (auto* cp = GetColorProvider()) {
    icon_image = gfx::ImageSkiaOperations::CreateColorMask(
        icon_image, cp->GetColor(kColorOmniboxText));
  }
  image_source->SetIcon(gfx::Image(icon_image));
  // Ambre = ON mais sans effet sur CET onglet (contenu protégé). Contrairement
  // à Sawtunaa, pas de gate : le floutage vidéo est coupé sur du DRM quelle que
  // soit la plateforme, il n'existe aucune voie de repli.
  auto* const web_contents =
      browser_ ? browser_->tab_strip_model()->GetActiveWebContents() : nullptr;
  const bool protected_here =
      IsActive() &&
      BrowtherProtectedContentTabHelper::StateFor(web_contents) !=
          BrowtherProtectedContentTabHelper::ProtectedState::kUnknown;
  image_source->SetDotColor(
      protected_here ? kBadgeAmber : (IsActive() ? kBadgeGreen : kBadgeRed));

  const gfx::ImageSkia composed(std::move(image_source), preferred_size);
  SetImageModel(views::Button::STATE_NORMAL,
                ui::ImageModel::FromImageSkia(composed));

  SetTooltipText(IsActive() ? u"Basarunaa — ON" : u"Basarunaa — OFF");
}

void BasarunaaActionView::OnTabStripModelChanged(
    TabStripModel* tab_strip_model,
    const TabStripModelChange& change,
    const TabStripSelectionChange& selection) {
  if (selection.active_tab_changed()) {
    UpdateColorsAndInsets();
  }
}

void BasarunaaActionView::OnTabChangedAt(tabs::TabInterface* tab,
                                         int index,
                                         TabChangeType change_type) {
  // Le verdict « contenu protégé » tombe ~2 s après la demande de licence :
  // sans ce rafraîchissement, le badge resterait vert jusqu'au prochain
  // changement d'onglet.
  UpdateColorsAndInsets();
}

void BasarunaaActionView::OnButtonPressed(const ui::Event& event) {
  chrome::ExecuteCommand(browser_, IDC_SHOW_BASARUNAA_PANEL);
}

BEGIN_METADATA(BasarunaaActionView)
END_METADATA
