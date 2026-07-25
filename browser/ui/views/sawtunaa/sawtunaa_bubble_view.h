// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_BROWSER_UI_VIEWS_SAWTUNAA_SAWTUNAA_BUBBLE_VIEW_H_
#define BRAVE_BROWSER_UI_VIEWS_SAWTUNAA_SAWTUNAA_BUBBLE_VIEW_H_

#include "base/memory/raw_ptr.h"
#include "components/prefs/pref_change_registrar.h"
#include "ui/base/metadata/metadata_header_macros.h"
#include "ui/views/bubble/bubble_dialog_delegate_view.h"

namespace views {
class Label;
}  // namespace views

namespace browther {
class BrowtherBigToggle;
}  // namespace browther

class Browser;
class PrefService;

// Browther: native popup anchored to the Sawtunaa toolbar button.
// Contains the on/off toggle for the Sawtunaa feature plus a short
// explanation of why it currently only targets YouTube.
class SawtunaaBubbleView : public views::BubbleDialogDelegateView {
  METADATA_HEADER(SawtunaaBubbleView, views::BubbleDialogDelegateView)

 public:
  // Creates and shows the bubble. If a bubble is already shown, closes it
  // (toggle behavior, mirrors BraveVPN/Basarunaa panel pattern).
  static void Show(views::View* anchor, Browser* browser);

  // Whether a bubble is currently shown anywhere (used by the toolbar
  // button's MenuButtonController to ignore the activation that occurs when
  // re-clicking the anchor).
  static bool IsShowing();

  SawtunaaBubbleView(views::View* anchor, Browser* browser);
  SawtunaaBubbleView(const SawtunaaBubbleView&) = delete;
  SawtunaaBubbleView& operator=(const SawtunaaBubbleView&) = delete;
  ~SawtunaaBubbleView() override;

  // views::BubbleDialogDelegate:
  void OnWidgetDestroying(views::Widget* widget) override;

 private:
  void BuildContents();
  void OnTogglePressed();
  void OnPrefChanged();

  raw_ptr<Browser> browser_ = nullptr;
  raw_ptr<PrefService> profile_prefs_ = nullptr;
  raw_ptr<browther::BrowtherBigToggle> toggle_ = nullptr;
  raw_ptr<views::Label> status_label_ = nullptr;
  raw_ptr<views::Label> reload_hint_ = nullptr;
  PrefChangeRegistrar pref_change_registrar_;

  void UpdateStatusLabel();

  // Browther/Sawtunaa V2 : le tap audio natif décide PAR PLAYER, à la
  // création du WebMediaPlayer. Activer Sawtunaa pendant qu'un média joue ne
  // change donc rien pour ce média-là tant que l'onglet n'est pas rechargé
  // (OFF, lui, est quasi-live). On affiche un hint plutôt que de recharger
  // d'autorité (décision UX 2026-07-25).
  bool ShouldShowReloadHint() const;
  void UpdateReloadHint(bool enabled);
};

#endif  // BRAVE_BROWSER_UI_VIEWS_SAWTUNAA_SAWTUNAA_BUBBLE_VIEW_H_
