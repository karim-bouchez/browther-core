// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/browser/ui/views/browther/shields_internal_bubble.h"

#include <memory>
#include <utility>

#include "base/check.h"
#include "base/functional/bind.h"
#include "base/task/single_thread_task_runner.h"
#include "base/time/time.h"
#include "brave/browser/ui/views/browther/browther_big_toggle.h"
#include "brave/grit/brave_generated_resources.h"
#include "chrome/browser/ui/browser.h"
#include "components/grit/brave_components_resources.h"
#include "skia/ext/image_operations.h"
#include "third_party/skia/include/core/SkBitmap.h"
#include "third_party/skia/include/core/SkColor.h"
#include "ui/base/l10n/l10n_util.h"
#include "ui/base/metadata/metadata_impl_macros.h"
#include "ui/base/mojom/dialog_button.mojom.h"
#include "ui/base/resource/resource_bundle.h"
#include "ui/gfx/font.h"
#include "ui/gfx/font_list.h"
#include "ui/gfx/geometry/insets.h"
#include "ui/gfx/geometry/size.h"
#include "ui/gfx/image/image_skia.h"
#include "ui/gfx/image/image_skia_operations.h"
#include "ui/views/controls/button/button.h"
#include "ui/views/controls/image_view.h"
#include "ui/views/controls/label.h"
#include "ui/views/layout/box_layout.h"
#include "ui/views/layout/box_layout_view.h"
#include "ui/views/widget/widget.h"

namespace browther {

namespace {

views::Widget* g_active_widget = nullptr;

gfx::FontList DeriveFont(int font_size, gfx::Font::Weight weight) {
  gfx::FontList list;
  return list.DeriveWithSizeDelta(font_size - list.GetFontSize())
      .DeriveWithWeight(weight);
}

}  // namespace

// static
void ShieldsInternalBubble::Show(views::View* anchor, Browser* browser) {
  CHECK(anchor);
  CHECK(browser);
  if (g_active_widget) {
    g_active_widget->Close();
    return;
  }

  auto bubble = std::make_unique<ShieldsInternalBubble>(anchor, browser);
  ShieldsInternalBubble* bubble_ptr = bubble.get();
  views::Widget* widget =
      views::BubbleDialogDelegateView::CreateBubble(std::move(bubble));
  g_active_widget = widget;
  if (auto* anchor_button = views::Button::AsButton(anchor)) {
    bubble_ptr->SetHighlightedButton(anchor_button);
  }
  widget->Show();
}

ShieldsInternalBubble::ShieldsInternalBubble(views::View* anchor,
                                             Browser* browser)
    : BubbleDialogDelegateView(anchor,
                               views::BubbleBorder::TOP_RIGHT,
                               views::BubbleBorder::STANDARD_SHADOW,
                               /*autosize=*/true),
      browser_(browser) {
  SetShowCloseButton(false);
  SetShowTitle(false);
  SetButtons(static_cast<int>(ui::mojom::DialogButton::kNone));
  SetTitle(l10n_util::GetStringUTF16(IDS_BROWTHER_SHIELDS_INTERNAL_TITLE));
  set_fixed_width(320);
  set_margins(gfx::Insets::TLBR(20, 20, 22, 20));

  BuildContents();
}

ShieldsInternalBubble::~ShieldsInternalBubble() = default;

void ShieldsInternalBubble::OnWidgetDestroying(views::Widget* widget) {
  if (g_active_widget == widget) {
    g_active_widget = nullptr;
  }
  BubbleDialogDelegateView::OnWidgetDestroying(widget);
}

void ShieldsInternalBubble::BuildContents() {
  auto* layout = SetLayoutManager(std::make_unique<views::BoxLayout>(
      views::BoxLayout::Orientation::kVertical, gfx::Insets(),
      /*between_child_spacing=*/14));
  layout->set_cross_axis_alignment(
      views::BoxLayout::CrossAxisAlignment::kCenter);

  // ----- Header lockup : Shield icon + "Boucliers Browther" label -----
  ui::ResourceBundle& rb = ui::ResourceBundle::GetSharedInstance();
  auto* header = AddChildView(std::make_unique<views::BoxLayoutView>());
  header->SetOrientation(views::BoxLayout::Orientation::kHorizontal);
  header->SetCrossAxisAlignment(
      views::BoxLayout::CrossAxisAlignment::kCenter);
  header->SetBetweenChildSpacing(10);

  const SkBitmap shield_bm =
      rb.GetImageNamed(IDR_BRAVE_SHIELDS_ICON_64).AsBitmap();
  if (!shield_bm.isNull()) {
    constexpr int kIconSize = 40;
    gfx::ImageSkia raw = gfx::ImageSkia::CreateFrom1xBitmap(shield_bm);
    gfx::ImageSkia resized = gfx::ImageSkiaOperations::CreateResizedImage(
        raw, skia::ImageOperations::RESIZE_BEST,
        gfx::Size(kIconSize * 2, kIconSize * 2));
    auto* icon_view = header->AddChildView(std::make_unique<views::ImageView>(
        ui::ImageModel::FromImageSkia(resized)));
    icon_view->SetImageSize(gfx::Size(kIconSize, kIconSize));
  }

  auto* title = header->AddChildView(std::make_unique<views::Label>(
      l10n_util::GetStringUTF16(IDS_BROWTHER_SHIELDS_INTERNAL_TITLE)));
  title->SetFontList(DeriveFont(18, gfx::Font::Weight::SEMIBOLD));
  title->SetAutoColorReadabilityEnabled(false);
  title->SetEnabledColor(SK_ColorWHITE);

  // ----- Big toggle : visuel uniquement, ON par défaut. -----
  // Browther: Brave gère Shields strictement par-site (TOP_ORIGIN_ONLY_SCOPE).
  // Pas d'API publique pour off-globally → si user toggle OFF, on revient à
  // ON et on affiche un message inline expliquant la sémantique par-site.
  auto big = std::make_unique<BrowtherBigToggle>(base::BindRepeating(
      &ShieldsInternalBubble::OnTogglePressed, base::Unretained(this)));
  big->SetIsOn(true);
  toggle_ = AddChildView(std::move(big));
  toggle_->SetAccessibleName(
      l10n_util::GetStringUTF16(IDS_BROWTHER_SHIELDS_INTERNAL_TITLE));

  // ----- Status label (suit l'état visuel du toggle) -----
  status_label_ = AddChildView(std::make_unique<views::Label>());
  status_label_->SetFontList(DeriveFont(13, gfx::Font::Weight::SEMIBOLD));
  status_label_->SetHorizontalAlignment(gfx::ALIGN_CENTER);
  status_label_->SetAutoColorReadabilityEnabled(false);
  status_label_->SetEnabledColor(SkColorSetA(SK_ColorWHITE, 0xB3));
  UpdateStatusLabel(true);

  // ----- Description (toujours visible) -----
  auto* desc = AddChildView(std::make_unique<views::Label>(
      l10n_util::GetStringUTF16(IDS_BROWTHER_SHIELDS_INTERNAL_DESCRIPTION)));
  desc->SetFontList(DeriveFont(12, gfx::Font::Weight::NORMAL));
  desc->SetHorizontalAlignment(gfx::ALIGN_CENTER);
  desc->SetMultiLine(true);
  desc->SetMaximumWidth(280);
  desc->SetAutoColorReadabilityEnabled(false);
  desc->SetEnabledColor(SkColorSetA(SK_ColorWHITE, 0xB3));

  // ----- Info label (visible uniquement après tentative de toggle OFF) -----
  info_label_ = AddChildView(std::make_unique<views::Label>(
      l10n_util::GetStringUTF16(
          IDS_BROWTHER_SHIELDS_INTERNAL_PER_SITE_INFO)));
  info_label_->SetFontList(DeriveFont(12, gfx::Font::Weight::NORMAL));
  info_label_->SetHorizontalAlignment(gfx::ALIGN_CENTER);
  info_label_->SetMultiLine(true);
  info_label_->SetMaximumWidth(280);
  info_label_->SetAutoColorReadabilityEnabled(false);
  // Browther: jaune doux (warning) — explique sans alarmer.
  info_label_->SetEnabledColor(SkColorSetRGB(0xF5, 0x9E, 0x0B));
  info_label_->SetVisible(false);
}

void ShieldsInternalBubble::OnTogglePressed(bool on) {
  if (on) {
    return;  // Browther: rien à faire si l'utilisateur (re)met ON.
  }
  // Browther: laisse le toggle visuellement OFF + status DISABLED + message
  // inline pendant ~500ms pour que l'utilisateur voie l'animation, puis
  // revient à ON automatiquement (Shields ne se désactive que par-site).
  UpdateStatusLabel(false);
  if (info_label_) {
    info_label_->SetVisible(true);
    SizeToContents();
  }
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostDelayedTask(
      FROM_HERE,
      base::BindOnce(&ShieldsInternalBubble::RestoreToggleOn,
                     weak_factory_.GetWeakPtr()),
      base::Milliseconds(500));
}

void ShieldsInternalBubble::RestoreToggleOn() {
  if (toggle_) {
    toggle_->SetIsOn(true);
  }
  UpdateStatusLabel(true);
}

void ShieldsInternalBubble::UpdateStatusLabel(bool on) {
  if (!status_label_) {
    return;
  }
  status_label_->SetText(l10n_util::GetStringUTF16(
      on ? IDS_BROWTHER_SHIELDS_INTERNAL_STATUS_ON
         : IDS_BROWTHER_SHIELDS_INTERNAL_STATUS_OFF));
}

BEGIN_METADATA(ShieldsInternalBubble)
END_METADATA

}  // namespace browther
