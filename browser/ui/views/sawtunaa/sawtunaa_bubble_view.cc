// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/browser/ui/views/sawtunaa/sawtunaa_bubble_view.h"

#include <memory>
#include <utility>

#include "base/check.h"
#include "base/functional/bind.h"
#include "base/values.h"
#include "brave/browser/ui/views/browther/browther_big_toggle.h"
#include "brave/components/browther_analytics/browther_analytics_service.h"
#include "brave/components/constants/pref_names.h"
#include "brave/grit/brave_generated_resources.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser.h"
#include "chrome/browser/ui/recently_audible_helper.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "components/grit/brave_components_resources.h"
#include "components/prefs/pref_service.h"
#include "content/public/browser/web_contents.h"
#include "third_party/skia/include/core/SkBitmap.h"
#include "third_party/skia/include/core/SkColor.h"
#include "ui/base/l10n/l10n_util.h"
#include "ui/base/metadata/metadata_impl_macros.h"
#include "ui/base/mojom/dialog_button.mojom.h"
#include "ui/base/resource/resource_bundle.h"
#include "ui/gfx/geometry/insets.h"
#include "ui/gfx/geometry/size.h"
#include "skia/ext/image_operations.h"
#include "ui/gfx/image/image_skia.h"
#include "ui/gfx/image/image_skia_operations.h"
#include "ui/views/controls/image_view.h"
#include "ui/views/controls/label.h"
#include "ui/views/layout/box_layout.h"
#include "ui/views/layout/box_layout_view.h"
#include "ui/views/widget/widget.h"

namespace browther {

// Track the active widget to mirror the BraveVPN/Basarunaa toggle-on-reclick
// behavior without owning a controller object.
views::Widget* g_active_widget = nullptr;

gfx::FontList DeriveFont(int font_size, gfx::Font::Weight weight) {
  gfx::FontList list;
  return list.DeriveWithSizeDelta(font_size - list.GetFontSize())
      .DeriveWithWeight(weight);
}

}  // namespace browther

using browther::BrowtherBigToggle;
using browther::g_active_widget;
using browther::DeriveFont;

// static
void SawtunaaBubbleView::Show(views::View* anchor, Browser* browser) {
  CHECK(anchor);
  CHECK(browser);
  // If already open, treat the call as a close request (anchor re-click).
  if (g_active_widget) {
    g_active_widget->Close();
    return;
  }

  auto bubble = std::make_unique<SawtunaaBubbleView>(anchor, browser);
  SawtunaaBubbleView* bubble_ptr = bubble.get();
  views::Widget* widget =
      views::BubbleDialogDelegateView::CreateBubble(std::move(bubble));
  g_active_widget = widget;
  // Browther: highlight the anchor button while the bubble is open so that
  // re-clicking the toolbar button closes (rather than re-opens) the bubble.
  if (auto* anchor_button = views::Button::AsButton(anchor)) {
    bubble_ptr->SetHighlightedButton(anchor_button);
  }
  widget->Show();
}

// static
bool SawtunaaBubbleView::IsShowing() {
  return g_active_widget != nullptr;
}

SawtunaaBubbleView::SawtunaaBubbleView(views::View* anchor, Browser* browser)
    : BubbleDialogDelegateView(anchor,
                               views::BubbleBorder::TOP_RIGHT,
                               views::BubbleBorder::STANDARD_SHADOW,
                               /*autosize=*/true),
      browser_(browser),
      profile_prefs_(browser->profile()->GetPrefs()) {
  CHECK(profile_prefs_);
  SetShowCloseButton(false);
  SetShowTitle(false);
  SetButtons(static_cast<int>(ui::mojom::DialogButton::kNone));
  SetTitle(u"Sawtunaa");  // accessibility only — frame title hidden
  set_fixed_width(320);
  set_margins(gfx::Insets::TLBR(20, 20, 22, 20));

  BuildContents();

  pref_change_registrar_.Init(profile_prefs_);
  pref_change_registrar_.Add(
      kSawtunaaEnabled,
      base::BindRepeating(&SawtunaaBubbleView::OnPrefChanged,
                          base::Unretained(this)));
}

SawtunaaBubbleView::~SawtunaaBubbleView() = default;

void SawtunaaBubbleView::OnWidgetDestroying(views::Widget* widget) {
  if (g_active_widget == widget) {
    g_active_widget = nullptr;
  }
  BubbleDialogDelegateView::OnWidgetDestroying(widget);
}

void SawtunaaBubbleView::BuildContents() {
  auto* layout = SetLayoutManager(std::make_unique<views::BoxLayout>(
      views::BoxLayout::Orientation::kVertical, gfx::Insets(),
      /*between_child_spacing=*/14));
  layout->set_cross_axis_alignment(
      views::BoxLayout::CrossAxisAlignment::kCenter);

  // ----- Header : brand icon (with bg) + wordmark white, on one line -----
  ui::ResourceBundle& rb = ui::ResourceBundle::GetSharedInstance();
  auto* header = AddChildView(std::make_unique<views::BoxLayoutView>());
  header->SetOrientation(views::BoxLayout::Orientation::kHorizontal);
  header->SetCrossAxisAlignment(
      views::BoxLayout::CrossAxisAlignment::kCenter);
  header->SetBetweenChildSpacing(10);

  // Browther: les sources PNG sont énormes (~2100×2100). Pré-resize en
  // RESIZE_BEST (Lanczos) à la taille d'affichage exacte. Pas de hack 2x —
  // sous Windows avec DPI scaling != 100%, le 2x produit des artefacts
  // (dotted edges + clipping) car ImageSkia décide à l'affichage entre la
  // rep "1x" demandée par SetImageSize et la rep "2x" stockée.
  auto resize_exact = [](const SkBitmap& src, int dst_w, int dst_h) {
    gfx::ImageSkia raw = gfx::ImageSkia::CreateFrom1xBitmap(src);
    return gfx::ImageSkiaOperations::CreateResizedImage(
        raw, skia::ImageOperations::RESIZE_BEST,
        gfx::Size(dst_w, dst_h));
  };

  const SkBitmap brand_bm =
      rb.GetImageNamed(IDR_SAWTUNAA_BRAND_ICON).AsBitmap();
  if (!brand_bm.isNull()) {
    header->AddChildView(std::make_unique<views::ImageView>(
        ui::ImageModel::FromImageSkia(resize_exact(brand_bm, 40, 40))));
  }
  const SkBitmap wm_bm =
      rb.GetImageNamed(IDR_SAWTUNAA_WORDMARK_WHITE).AsBitmap();
  if (!wm_bm.isNull()) {
    constexpr int kWmHeight = 26;
    const int wm_w = static_cast<int>(static_cast<float>(kWmHeight) *
                                      wm_bm.width() / wm_bm.height());
    header->AddChildView(std::make_unique<views::ImageView>(
        ui::ImageModel::FromImageSkia(resize_exact(wm_bm, wm_w, kWmHeight))));
  }

  // ----- Big toggle (custom paint, no native hover/violet glitch) -----
  auto big = std::make_unique<BrowtherBigToggle>(base::BindRepeating(
      [](SawtunaaBubbleView* self, bool on) {
        self->profile_prefs_->SetBoolean(kSawtunaaEnabled, on);
        if (auto* analytics = browther_analytics::BrowtherAnalyticsService::
                GetInstance()) {
          base::DictValue props;
          props.Set("feature", "sawtunaa");
          props.Set("enabled", on);
          analytics->Track("feature_toggled", std::move(props));
        }
      },
      base::Unretained(this)));
  big->SetIsOn(profile_prefs_->GetBoolean(kSawtunaaEnabled));
  toggle_ = AddChildView(std::move(big));
  toggle_->SetAccessibleName(u"Sawtunaa");

  // ----- Status label (color-coded ON / OFF) -----
  status_label_ = AddChildView(std::make_unique<views::Label>());
  status_label_->SetFontList(DeriveFont(13, gfx::Font::Weight::SEMIBOLD));
  status_label_->SetHorizontalAlignment(gfx::ALIGN_CENTER);
  status_label_->SetAutoColorReadabilityEnabled(false);
  UpdateStatusLabel();

  // ----- Description user-friendly -----
  auto* desc = AddChildView(std::make_unique<views::Label>(
      l10n_util::GetStringUTF16(IDS_SAWTUNAA_POPUP_DESCRIPTION)));
  desc->SetFontList(DeriveFont(12, gfx::Font::Weight::NORMAL));
  desc->SetHorizontalAlignment(gfx::ALIGN_CENTER);
  desc->SetMultiLine(true);
  desc->SetMaximumWidth(280);

  // ----- Hint « recharge l'onglet » (masqué tant que non pertinent) -----
  reload_hint_ = AddChildView(std::make_unique<views::Label>(
      l10n_util::GetStringUTF16(IDS_SAWTUNAA_POPUP_RELOAD_HINT)));
  reload_hint_->SetFontList(DeriveFont(12, gfx::Font::Weight::SEMIBOLD));
  reload_hint_->SetHorizontalAlignment(gfx::ALIGN_CENTER);
  reload_hint_->SetMultiLine(true);
  reload_hint_->SetMaximumWidth(280);
  reload_hint_->SetAutoColorReadabilityEnabled(false);
  // Browther: jaune doux (warning), même code couleur que le message inline
  // du bouclier — informe sans alarmer.
  reload_hint_->SetEnabledColor(SkColorSetRGB(0xF5, 0x9E, 0x0B));
  reload_hint_->SetVisible(false);
}

void SawtunaaBubbleView::OnPrefChanged() {
  const bool value = profile_prefs_->GetBoolean(kSawtunaaEnabled);
  if (toggle_) {
    if (toggle_->GetIsOn() != value) {
      toggle_->SetIsOn(value);
    }
  }
  UpdateStatusLabel();
  UpdateReloadHint(value);
}

bool SawtunaaBubbleView::ShouldShowReloadHint() const {
  // Uniquement pour le tap natif : ailleurs (Windows / anciens builds), c'est
  // l'extension MV3 qui traite l'audio et elle prend le toggle en compte sans
  // reload.
  if (!profile_prefs_->GetBoolean(kSawtunaaNativeTapActive)) {
    return false;
  }
  content::WebContents* web_contents =
      browser_->tab_strip_model()->GetActiveWebContents();
  if (!web_contents) {
    return false;
  }
  // « Un média joue dans l'onglet » : le helper de la tab strip retient aussi
  // le média mis en pause (WasEverAudible) — son WebMediaPlayer existe déjà,
  // donc lui aussi restera non tappé jusqu'au reload.
  auto* audible = RecentlyAudibleHelper::FromWebContents(web_contents);
  return audible ? audible->WasEverAudible()
                 : web_contents->IsCurrentlyAudible();
}

void SawtunaaBubbleView::UpdateReloadHint(bool enabled) {
  if (!reload_hint_) {
    return;
  }
  const bool visible = enabled && ShouldShowReloadHint();
  if (reload_hint_->GetVisible() == visible) {
    return;
  }
  reload_hint_->SetVisible(visible);
  SizeToContents();
}

void SawtunaaBubbleView::UpdateStatusLabel() {
  if (!status_label_) {
    return;
  }
  const bool active = profile_prefs_->GetBoolean(kSawtunaaEnabled);
  status_label_->SetText(l10n_util::GetStringUTF16(
      active ? IDS_SAWTUNAA_POPUP_STATUS_ON
             : IDS_SAWTUNAA_POPUP_STATUS_OFF));
  // Browther: gris neutre (~70% blanc) pour matcher le rendu iOS — pas de
  // sémantique chromatique sur ce label, le toggle porte déjà l'état.
  status_label_->SetEnabledColor(SkColorSetA(SK_ColorWHITE, 0xB3));
}

BEGIN_METADATA(SawtunaaBubbleView)
END_METADATA
