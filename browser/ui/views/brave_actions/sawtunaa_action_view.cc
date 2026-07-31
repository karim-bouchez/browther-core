// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/browser/ui/views/brave_actions/sawtunaa_action_view.h"

#include <memory>
#include <utility>

#include "base/check_deref.h"
#include "base/functional/bind.h"
#include "brave/browser/browther/browther_protected_content_tab_helper.h"
#include "brave/browser/ui/brave_icon_with_badge_image_source.h"
#include "brave/browser/ui/browther_status_dot_image_source.h"
#include "brave/browser/ui/views/sawtunaa/sawtunaa_bubble_view.h"
#include "brave/components/constants/pref_names.h"
#include "brave/grit/brave_generated_resources.h"
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
#include "ui/base/l10n/l10n_util.h"
#include "ui/base/metadata/metadata_impl_macros.h"
#include "ui/base/models/image_model.h"
#include "ui/base/resource/resource_bundle.h"
#include "ui/color/color_provider_manager.h"
#include "ui/gfx/image/image_skia_operations.h"
#include "ui/gfx/image/image_skia_rep.h"
#include "ui/views/animation/ink_drop_impl.h"
#include "ui/views/controls/button/label_button_border.h"
#include "ui/views/controls/button/menu_button_controller.h"
#include "ui/views/controls/highlight_path_generator.h"
#include "chrome/browser/ui/browser.h"
#include "extensions/common/constants.h"

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

SawtunaaActionView::SawtunaaActionView(
    BrowserWindowInterface* browser_window_interface)
    : LabelButton(base::BindRepeating(&SawtunaaActionView::OnButtonPressed,
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

  // Browther: MenuButtonController so re-clicking the toolbar button while
  // the bubble is open closes it (mirror of BraveVPNButton/Basarunaa pattern).
  auto menu_button_controller = std::make_unique<views::MenuButtonController>(
      this,
      base::BindRepeating(&SawtunaaActionView::OnButtonPressed,
                          base::Unretained(this)),
      std::make_unique<views::Button::DefaultButtonControllerDelegate>(this));
  menu_button_controller_ = menu_button_controller.get();
  SetButtonController(std::move(menu_button_controller));

  pref_change_registrar_.Init(&*profile_prefs_);
  pref_change_registrar_.Add(
      kSawtunaaEnabled,
      base::BindRepeating(&SawtunaaActionView::UpdateIconState,
                          base::Unretained(this)));
}

void SawtunaaActionView::OnButtonPressed(const ui::Event& event) {
  // Browther: open the popup; SawtunaaBubbleView::Show closes the active
  // bubble itself if one is already shown (toggle behavior).
  Browser* browser = browser_window_interface_
                         ? browser_window_interface_->GetBrowserForMigrationOnly()
                         : nullptr;
  if (!browser) {
    return;
  }
  SawtunaaBubbleView::Show(this, browser);
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

  // Browther: petit dot 8pt à cheval sur le coin bas-droite de l'icône (style
  // iOS), au lieu du gros badge rectangulaire Brave.
  const int icon_size =
      GetLayoutConstant(LayoutConstant::kLocationBarTrailingIconSize);
  auto image_source = std::make_unique<browther::BrowtherStatusDotImageSource>(
      preferred_size, std::move(get_color_provider_callback), icon_size);
  // Browther: l'icône PNG est un template blanc + alpha. On la tinte avec la
  // couleur système toolbar pour matcher les autres boutons.
  gfx::ImageSkia base_icon = GetIconImage(active);
  if (auto* cp = GetColorProvider()) {
    base_icon = gfx::ImageSkiaOperations::CreateColorMask(
        base_icon, cp->GetColor(kColorOmniboxText));
  }
  image_source->SetIcon(gfx::Image(base_icon));
  // Ambre = ON mais sans effet sur CET onglet (contenu protégé).
  // ⚠️ Gaté sur kSawtunaaNativeTapActive : quand le tap natif n'est PAS actif
  // (cas Windows aujourd'hui), c'est l'extension bundlée qui capture via
  // chrome.tabCapture — et tabCapture, lui, fonctionne sur du DRM. Annoncer
  // une panne là-bas serait faux.
  const bool protected_here =
      active && profile_prefs_->GetBoolean(kSawtunaaNativeTapActive) &&
      BrowtherProtectedContentTabHelper::StateFor(web_contents) !=
          BrowtherProtectedContentTabHelper::ProtectedState::kUnknown;
  image_source->SetDotColor(protected_here ? kBadgeAmber
                                           : (active ? kBadgeGreen : kBadgeRed));

  const gfx::ImageSkia icon(std::move(image_source), preferred_size);
  SetImageModel(views::Button::STATE_NORMAL,
                ui::ImageModel::FromImageSkia(icon));

  SetTooltipText(l10n_util::GetStringUTF16(
      active ? IDS_SAWTUNAA_TOGGLE_TOOLTIP_ON
             : IDS_SAWTUNAA_TOGGLE_TOOLTIP_OFF));
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

void SawtunaaActionView::OnTabChangedAt(tabs::TabInterface* tab,
                                        int index,
                                        TabChangeType change_type) {
  // Le verdict « contenu protégé » tombe ~2 s après la demande de licence,
  // donc APRÈS le chargement : sans ce rafraîchissement le badge ne
  // passerait à l'ambre qu'au prochain changement d'onglet.
  UpdateIconState();
}

BEGIN_METADATA(SawtunaaActionView)
END_METADATA
