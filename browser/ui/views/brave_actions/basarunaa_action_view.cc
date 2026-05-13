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
#include "brave/browser/ui/brave_icon_with_badge_image_source.h"
#include "brave/browser/ui/browther_status_dot_image_source.h"
#include "brave/components/constants/pref_names.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser.h"
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
}

BasarunaaActionView::~BasarunaaActionView() = default;

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
  image_source->SetDotColor(IsActive() ? kBadgeGreen : kBadgeRed);

  const gfx::ImageSkia composed(std::move(image_source), preferred_size);
  SetImageModel(views::Button::STATE_NORMAL,
                ui::ImageModel::FromImageSkia(composed));

  SetTooltipText(IsActive() ? u"Basarunaa — ON" : u"Basarunaa — OFF");
}

void BasarunaaActionView::OnButtonPressed(const ui::Event& event) {
  chrome::ExecuteCommand(browser_, IDC_SHOW_BASARUNAA_PANEL);
}

BEGIN_METADATA(BasarunaaActionView)
END_METADATA
