// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/browser/ui/views/brave_actions/sawtunaa_action_view.h"

#include <memory>

#include "base/check_deref.h"
#include "brave/components/constants/pref_names.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/layout_constants.h"
#include "chrome/browser/ui/omnibox/omnibox_theme.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/views/chrome_layout_provider.h"
#include "chrome/browser/ui/views/toolbar/toolbar_ink_drop_util.h"
#include "components/grit/brave_components_resources.h"
#include "components/prefs/pref_service.h"
#include "content/public/browser/web_contents.h"
#include "ui/base/metadata/metadata_impl_macros.h"
#include "ui/base/models/image_model.h"
#include "ui/base/resource/resource_bundle.h"
#include "ui/gfx/image/image_skia_rep.h"
#include "ui/views/animation/ink_drop_impl.h"
#include "ui/views/controls/button/label_button_border.h"
#include "ui/views/controls/highlight_path_generator.h"

SawtunaaActionView::SawtunaaActionView(
    BrowserWindowInterface* browser_window_interface)
    : LabelButton(base::BindRepeating(
                      [](SawtunaaActionView* self) {
                        bool current = self->profile_prefs_->GetBoolean(
                            kSawtunaaEnabled);
                        self->profile_prefs_->SetBoolean(kSawtunaaEnabled,
                                                         !current);
                      },
                      base::Unretained(this)),
                  std::u16string()),
      browser_window_interface_(browser_window_interface),
      profile_prefs_(
          CHECK_DEREF(browser_window_interface->GetProfile()->GetPrefs())),
      tab_strip_model_(
          CHECK_DEREF(browser_window_interface->GetTabStripModel())) {
  SetAccessibleName(u"Sawtunaa");
  SetHorizontalAlignment(gfx::ALIGN_CENTER);
  tab_strip_model_->AddObserver(this);

  // Watch the enabled pref to update icon state
  pref_change_registrar_.Init(&*profile_prefs_);
  pref_change_registrar_.Add(
      kSawtunaaEnabled,
      base::BindRepeating(&SawtunaaActionView::UpdateIconState,
                          base::Unretained(this)));
}

SawtunaaActionView::~SawtunaaActionView() = default;

void SawtunaaActionView::Init() {
  UpdateIconState();
}

bool SawtunaaActionView::IsActive() const {
  return profile_prefs_->GetBoolean(kSawtunaaEnabled);
}

gfx::ImageSkia SawtunaaActionView::GetIconImage(bool active) {
  ui::ResourceBundle& rb = ui::ResourceBundle::GetSharedInstance();
  const SkBitmap bitmap =
      rb.GetImageNamed(active ? IDR_SAWTUNAA_ICON_64
                              : IDR_SAWTUNAA_ICON_64_DISABLED)
          .AsBitmap();
  float scale = static_cast<float>(bitmap.width()) /
                GetLayoutConstant(LayoutConstant::kLocationBarTrailingIconSize);
  gfx::ImageSkia image;
  image.AddRepresentation(gfx::ImageSkiaRep(bitmap, scale));
  return image;
}

void SawtunaaActionView::UpdateIconState() {
  bool active = IsActive();
  SetImageModel(views::Button::STATE_NORMAL,
                ui::ImageModel::FromImageSkia(GetIconImage(active)));

  SetTooltipText(active ? u"Sawtunaa — ON" : u"Sawtunaa — OFF");
}

void SawtunaaActionView::Update() {
  UpdateIconState();
}

std::unique_ptr<views::LabelButtonBorder>
SawtunaaActionView::CreateDefaultBorder() const {
  auto border = LabelButton::CreateDefaultBorder();
  border->set_insets(gfx::Insets::TLBR(0, 0, 0, 0));
  return border;
}

void SawtunaaActionView::OnThemeChanged() {
  LabelButton::OnThemeChanged();

  const auto* const color_provider = GetColorProvider();
  if (!color_provider) {
    return;
  }

  auto* ink_drop = views::InkDrop::Get(this);
  ink_drop->SetMode(views::InkDropHost::InkDropMode::ON);
  SetHasInkDropActionOnClick(true);
  views::InkDrop::Get(this)->SetVisibleOpacity(kOmniboxOpacitySelected);
  views::InkDrop::Get(this)->SetHighlightOpacity(kOmniboxOpacityHovered);
  ink_drop->SetBaseColor(color_provider->GetColor(kColorOmniboxText));
}

void SawtunaaActionView::OnTabStripModelChanged(
    TabStripModel* tab_strip_model,
    const TabStripModelChange& change,
    const TabStripSelectionChange& selection) {
  if (selection.active_tab_changed()) {
    UpdateIconState();
  }
}

BEGIN_METADATA(SawtunaaActionView)
END_METADATA
