// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/browser/ui/views/brave_actions/sawtunaa_action_view.h"

#include <memory>

#include "base/check_deref.h"
#include "base/values.h"
#include "brave/browser/ui/brave_icon_with_badge_image_source.h"
#include "brave/components/browther_analytics/browther_analytics_service.h"
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
#include "ui/color/color_provider_manager.h"
#include "ui/gfx/image/image_skia_rep.h"
#include "ui/views/animation/ink_drop_impl.h"
#include "ui/views/controls/button/label_button_border.h"
#include "ui/views/controls/highlight_path_generator.h"
#include "extensions/common/constants.h"

namespace {
constexpr SkColor kBadgeGreen = SkColorSetRGB(0x22, 0xC5, 0x5E);
constexpr SkColor kBadgeRed = SkColorSetRGB(0xEF, 0x44, 0x44);
}  // namespace

SawtunaaActionView::SawtunaaActionView(
    BrowserWindowInterface* browser_window_interface)
    : LabelButton(base::BindRepeating(
                      [](SawtunaaActionView* self) {
                        bool current = self->profile_prefs_->GetBoolean(
                            kSawtunaaEnabled);
                        self->profile_prefs_->SetBoolean(kSawtunaaEnabled,
                                                         !current);
                        // Browther: track user-initiated toggle.
                        if (auto* analytics = browther_analytics::
                                BrowtherAnalyticsService::GetInstance()) {
                          base::DictValue props;
                          props.Set("feature", "sawtunaa");
                          props.Set("enabled", !current);
                          analytics->Track("feature_toggled",
                                           std::move(props));
                        }
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
  // Always use the same base icon — badge shows state
  const SkBitmap bitmap =
      rb.GetImageNamed(IDR_SAWTUNAA_ICON_64).AsBitmap();
  float scale = static_cast<float>(bitmap.width()) /
                GetLayoutConstant(LayoutConstant::kLocationBarTrailingIconSize);
  gfx::ImageSkia image;
  image.AddRepresentation(gfx::ImageSkiaRep(bitmap, scale));
  return image;
}

void SawtunaaActionView::UpdateIconState() {
  bool active = IsActive();
  auto preferred_size = GetPreferredSize();

  auto* web_contents = tab_strip_model_->GetActiveWebContents();
  auto get_color_provider_callback = base::BindRepeating(
      [](base::WeakPtr<content::WebContents> weak_web_contents) {
        const auto* const color_provider =
            weak_web_contents
                ? &weak_web_contents->GetColorProvider()
                : ui::ColorProviderManager::Get().GetColorProviderFor(
                      ui::NativeTheme::GetInstanceForNativeUi()
                          ->GetColorProviderKey(nullptr));
        return color_provider;
      },
      web_contents ? web_contents->GetWeakPtr()
                   : base::WeakPtr<content::WebContents>());

  std::unique_ptr<IconWithBadgeImageSource> image_source(
      new brave::BraveIconWithBadgeImageSource(
          preferred_size, std::move(get_color_provider_callback),
          GetLayoutConstant(LayoutConstant::kLocationBarTrailingIconSize),
          kBraveActionLeftMarginExtra));

  image_source->SetIcon(gfx::Image(GetIconImage(active)));

  // Badge: green dot when ON, red dot when OFF
  SkColor badge_bg = active ? kBadgeGreen : kBadgeRed;
  auto badge = std::make_unique<IconWithBadgeImageSource::Badge>(
      " ", SK_ColorWHITE, badge_bg);
  image_source->SetBadge(std::move(badge));

  const gfx::ImageSkia icon(std::move(image_source), preferred_size);
  SetImageModel(views::Button::STATE_NORMAL,
                ui::ImageModel::FromImageSkia(icon));

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
