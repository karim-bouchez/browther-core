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
#include "brave/browser/browther/browther_protected_content_tab_helper.h"
#include "brave/components/constants/pref_names.h"
#include "chrome/browser/ui/singleton_tabs.h"
#include "ui/views/controls/button/md_text_button.h"
#include "brave/grit/brave_generated_resources.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser.h"
#include "chrome/browser/ui/browser_commands.h"
#include "chrome/browser/ui/recently_audible_helper.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "components/grit/brave_components_resources.h"
#include "components/vector_icons/vector_icons.h"
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
#include "ui/views/controls/button/button.h"
#include "ui/views/controls/image_view.h"
#include "ui/views/controls/label.h"
#include "ui/views/layout/box_layout.h"
#include "ui/base/cursor/cursor.h"
#include "ui/base/cursor/mojom/cursor_type.mojom-shared.h"
#include "ui/base/window_open_disposition.h"
#include "ui/views/animation/ink_drop.h"
#include "ui/views/background.h"
#include "ui/views/border.h"
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

// Browther: encadré CLIQUABLE du hint « recharge l'onglet ». Bouton plutôt
// que simple étiquette : le message dit à l'utilisateur ce qu'il doit faire,
// autant lui permettre de le faire d'un clic (et on hérite du focus clavier +
// du rôle d'accessibilité). Le rendu reste custom (ink drop coupé, comme
// BrowtherBigToggle) : fond ambre translucide qui s'intensifie au survol.
class ReloadHintButton : public views::Button {
  METADATA_HEADER(ReloadHintButton, views::Button)

 public:
  static constexpr SkColor kAccent = SkColorSetRGB(0xF5, 0x9E, 0x0B);

  explicit ReloadHintButton(PressedCallback callback)
      : views::Button(std::move(callback)) {
    views::InkDrop::Get(this)->SetMode(views::InkDropHost::InkDropMode::OFF);
    SetHasInkDropActionOnClick(false);
    auto* layout = SetLayoutManager(std::make_unique<views::BoxLayout>(
        views::BoxLayout::Orientation::kHorizontal,
        gfx::Insets::TLBR(10, 14, 10, 14), /*between_child_spacing=*/8));
    layout->set_cross_axis_alignment(
        views::BoxLayout::CrossAxisAlignment::kCenter);
    SetBorder(
        views::CreateRoundedRectBorder(1, 8, SkColorSetA(kAccent, 0x66)));
    UpdateBackground();
  }
  ReloadHintButton(const ReloadHintButton&) = delete;
  ReloadHintButton& operator=(const ReloadHintButton&) = delete;
  ~ReloadHintButton() override = default;

  // views::Button:
  void StateChanged(ButtonState old_state) override {
    views::Button::StateChanged(old_state);
    UpdateBackground();
  }

  // views::View:
  ui::Cursor GetCursor(const ui::MouseEvent& event) override {
    return GetEnabled() ? ui::Cursor(ui::mojom::CursorType::kHand)
                        : views::Button::GetCursor(event);
  }

 private:
  void UpdateBackground() {
    const bool hot =
        GetState() == STATE_HOVERED || GetState() == STATE_PRESSED;
    SetBackground(views::CreateRoundedRectBackground(
        SkColorSetA(kAccent, hot ? 0x3D : 0x24), 8));
  }
};

BEGIN_METADATA(ReloadHintButton)
END_METADATA

}  // namespace browther

using browther::BrowtherBigToggle;
using browther::g_active_widget;
using browther::DeriveFont;
using browther::ReloadHintButton;

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
  // Encadré CLIQUABLE : le message est une conséquence de l'action qu'on vient
  // de faire, il se détache de la description permanente — et un clic dessus
  // recharge l'onglet (pas de reload automatique : c'est l'utilisateur qui
  // décide quand, décision UX 2026-07-25).
  const std::u16string hint_text =
      l10n_util::GetStringUTF16(IDS_SAWTUNAA_POPUP_RELOAD_HINT);
  auto hint_button = std::make_unique<ReloadHintButton>(base::BindRepeating(
      &SawtunaaBubbleView::OnReloadHintPressed, base::Unretained(this)));
  hint_button->SetAccessibleName(hint_text);

  auto* hint_icon =
      hint_button->AddChildView(std::make_unique<views::ImageView>(
          ui::ImageModel::FromVectorIcon(vector_icons::kReloadChromeRefreshIcon,
                                         ReloadHintButton::kAccent, 16)));
  hint_icon->SetVerticalAlignment(views::ImageView::Alignment::kCenter);
  hint_icon->SetCanProcessEventsWithinSubtree(false);

  reload_hint_ =
      hint_button->AddChildView(std::make_unique<views::Label>(hint_text));
  reload_hint_->SetFontList(DeriveFont(12, gfx::Font::Weight::SEMIBOLD));
  reload_hint_->SetHorizontalAlignment(gfx::ALIGN_LEFT);
  reload_hint_->SetMultiLine(true);
  reload_hint_->SetMaximumWidth(224);  // 280 - icône - espacements - insets
  reload_hint_->SetAutoColorReadabilityEnabled(false);
  // Browther: jaune doux (warning), même code couleur que le message inline
  // du bouclier — informe sans alarmer.
  reload_hint_->SetEnabledColor(ReloadHintButton::kAccent);
  reload_hint_->SetCanProcessEventsWithinSubtree(false);

  hint_container_ = AddChildView(std::move(hint_button));
  hint_container_->SetVisible(false);

  // ----- Encadré « contenu protégé (DRM) » (masqué tant que non pertinent) --
  // Répond à la question que l'utilisateur se pose en ouvrant la popup après
  // avoir vu le badge AMBRE : pourquoi c'est ambre, pourquoi ça ne marche pas
  // ici, et comment faire malgré tout.
  //
  // ⚠️ PAS un encadré cliquable comme le hint reload : personne ne devine
  // qu'on peut cliquer dessus (retour Karim, 2026-07-31 — il l'avait trouvé
  // par hasard). L'action est portée par un VRAI bouton, sous le texte.
  auto protected_box = std::make_unique<views::View>();
  auto* protected_layout =
      protected_box->SetLayoutManager(std::make_unique<views::BoxLayout>(
          views::BoxLayout::Orientation::kVertical,
          gfx::Insets::TLBR(10, 14, 10, 14), /*between_child_spacing=*/8));
  protected_layout->set_cross_axis_alignment(
      views::BoxLayout::CrossAxisAlignment::kStart);
  protected_box->SetBorder(views::CreateRoundedRectBorder(
      1, 8, SkColorSetA(ReloadHintButton::kAccent, 0x66)));
  protected_box->SetBackground(views::CreateRoundedRectBackground(
      SkColorSetA(ReloadHintButton::kAccent, 0x24), 8));

  auto* protected_row =
      protected_box->AddChildView(std::make_unique<views::View>());
  auto* protected_row_layout =
      protected_row->SetLayoutManager(std::make_unique<views::BoxLayout>(
          views::BoxLayout::Orientation::kHorizontal, gfx::Insets(),
          /*between_child_spacing=*/8));
  protected_row_layout->set_cross_axis_alignment(
      views::BoxLayout::CrossAxisAlignment::kStart);

  auto* protected_icon =
      protected_row->AddChildView(std::make_unique<views::ImageView>(
          ui::ImageModel::FromVectorIcon(vector_icons::kVideocamOffIcon,
                                         ReloadHintButton::kAccent, 16)));
  protected_icon->SetVerticalAlignment(views::ImageView::Alignment::kLeading);

  protected_hint_ =
      protected_row->AddChildView(std::make_unique<views::Label>());
  protected_hint_->SetFontList(DeriveFont(12, gfx::Font::Weight::SEMIBOLD));
  protected_hint_->SetHorizontalAlignment(gfx::ALIGN_LEFT);
  protected_hint_->SetMultiLine(true);
  protected_hint_->SetMaximumWidth(200);  // 280 - icône - espacements - insets
  protected_hint_->SetAutoColorReadabilityEnabled(false);
  protected_hint_->SetEnabledColor(ReloadHintButton::kAccent);

  auto* protected_action =
      protected_box->AddChildView(std::make_unique<views::MdTextButton>(
          base::BindRepeating(&SawtunaaBubbleView::OnProtectedHintPressed,
                              base::Unretained(this)),
          l10n_util::GetStringUTF16(
              IDS_BROWTHER_PROTECTED_CONTENT_GET_SAWTUNAA)));
  protected_action->SetStyle(ui::ButtonStyle::kProminent);

  protected_container_ = AddChildView(std::move(protected_box));
  UpdateProtectedHint();
}

bool SawtunaaBubbleView::ShouldShowProtectedHint() const {
  // Même gate que le badge ambre : sans tap natif (Windows aujourd'hui), c'est
  // l'extension bundlée qui capture via chrome.tabCapture — et elle, elle
  // fonctionne sur du DRM. Annoncer une panne là-bas serait faux.
  if (!profile_prefs_->GetBoolean(kSawtunaaEnabled) ||
      !profile_prefs_->GetBoolean(kSawtunaaNativeTapActive)) {
    return false;
  }
  content::WebContents* web_contents =
      browser_ ? browser_->tab_strip_model()->GetActiveWebContents() : nullptr;
  return BrowtherProtectedContentTabHelper::StateFor(web_contents) !=
         BrowtherProtectedContentTabHelper::ProtectedState::kUnknown;
}

void SawtunaaBubbleView::UpdateProtectedHint() {
  if (!protected_container_ || !protected_hint_) {
    return;
  }
  content::WebContents* web_contents =
      browser_ ? browser_->tab_strip_model()->GetActiveWebContents() : nullptr;
  const auto state =
      BrowtherProtectedContentTabHelper::StateFor(web_contents);
  const bool visible = ShouldShowProtectedHint();
  if (visible) {
    // Le texte DIFFÈRE selon le cas, et la nuance est cruciale (retour Karim) :
    // quand la lecture est BLOQUÉE, installer l'app ne suffit pas — la page
    // elle-même ne joue pas ici, il faut d'abord l'ouvrir ailleurs.
    protected_hint_->SetText(l10n_util::GetStringUTF16(
        state == BrowtherProtectedContentTabHelper::ProtectedState::kBlocked
            ? IDS_SAWTUNAA_POPUP_PROTECTED_HINT_BLOCKED
            : IDS_SAWTUNAA_POPUP_PROTECTED_HINT));
  }
  if (protected_container_->GetVisible() == visible) {
    return;
  }
  protected_container_->SetVisible(visible);
  if (GetWidget()) {
    SizeToContents();
  }
}

void SawtunaaBubbleView::OnProtectedHintPressed() {
  // La seule voie qui reste pour du DRM : l'app autonome + son extension.
  if (browser_) {
    ShowSingletonTab(browser_, GURL("https://sawtunaa.devndin.com"));
  }
  if (views::Widget* widget = GetWidget()) {
    widget->Close();
  }
}

void SawtunaaBubbleView::OnReloadHintPressed() {
  // Recharge l'onglet actif : c'est ce qui rebranche le tap natif sur le média
  // en cours (la décision se prend à la création du WebMediaPlayer). La bulle
  // se ferme dans la foulée — son hint n'a plus lieu d'être.
  if (browser_) {
    chrome::Reload(browser_, WindowOpenDisposition::CURRENT_TAB);
  }
  if (views::Widget* widget = GetWidget()) {
    widget->Close();
  }
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
  UpdateProtectedHint();
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
  if (!hint_container_) {
    return;
  }
  const bool visible = enabled && ShouldShowReloadHint();
  if (hint_container_->GetVisible() == visible) {
    return;
  }
  hint_container_->SetVisible(visible);
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
