// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/browser/ui/views/brave_actions/basarunaa_action_view.h"

#include <memory>

#include "base/check.h"
#include "brave/app/brave_command_ids.h"
#include "chrome/browser/ui/browser.h"
#include "chrome/browser/ui/browser_commands.h"
#include "chrome/browser/ui/layout_constants.h"
#include "chrome/browser/ui/views/chrome_layout_provider.h"
#include "components/grit/brave_components_resources.h"
#include "ui/base/metadata/metadata_impl_macros.h"
#include "ui/base/models/image_model.h"
#include "ui/base/resource/resource_bundle.h"
#include "ui/gfx/image/image_skia.h"
#include "ui/gfx/image/image_skia_rep.h"
#include "ui/views/controls/button/menu_button_controller.h"

BasarunaaActionView::BasarunaaActionView(Browser* browser)
    : ToolbarButton(base::BindRepeating(&BasarunaaActionView::OnButtonPressed,
                                        base::Unretained(this)),
                    /*menu_model=*/nullptr,
                    /*tab_strip_model=*/nullptr,
                    /*trigger_menu_on_long_press=*/false),
      browser_(browser) {
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
  SetTooltipText(u"Basarunaa");
}

BasarunaaActionView::~BasarunaaActionView() = default;

void BasarunaaActionView::Init() {
  UpdateColorsAndInsets();
}

void BasarunaaActionView::UpdateColorsAndInsets() {
  // Minimal placeholder icon — bisect rebuild only cares about lifecycle.
  ui::ResourceBundle& rb = ui::ResourceBundle::GetSharedInstance();
  const SkBitmap bitmap = rb.GetImageNamed(IDR_BASARUNAA_ICON_64).AsBitmap();
  if (bitmap.isNull()) {
    return;
  }
  const int icon_size =
      GetLayoutConstant(LayoutConstant::kLocationBarTrailingIconSize);
  const float scale =
      static_cast<float>(bitmap.width()) / static_cast<float>(icon_size);
  gfx::ImageSkia image;
  image.AddRepresentation(gfx::ImageSkiaRep(bitmap, scale));
  SetImageModel(views::Button::STATE_NORMAL,
                ui::ImageModel::FromImageSkia(image));
}

void BasarunaaActionView::OnButtonPressed(const ui::Event& event) {
  chrome::ExecuteCommand(browser_, IDC_SHOW_BASARUNAA_PANEL);
}

BEGIN_METADATA(BasarunaaActionView)
END_METADATA
