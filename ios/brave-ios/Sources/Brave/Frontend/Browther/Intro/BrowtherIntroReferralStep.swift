// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BraveStrings
import Onboarding
import SwiftUI
import UIKit

// MARK: - Le code d'un proche (écran O du parrainage)

/// **Dans une introduction : le code SEUL** (`docs/PARRAINAGE.md` § 12.24) — ⛔
/// ni l'accroche « Débloquer… ça t'intéresse ? », ni « Tu veux en parler autour
/// de toi ? » : la personne ne connaît pas encore Browther, lui proposer d'en
/// parler est prématuré (l'annonce le fera). Ce qui a sa place ici, c'est ce
/// qu'elle ne pourra plus faire aussi simplement plus tard : **saisir le code
/// du proche qui l'a amenée** — sur iOS, c'est le SEUL chemin d'attribution.
///
/// La grammaire des autres écrans de l'introduction : titre, une phrase, un
/// visuel central, le champ, « Continuer » / « Plus tard ». ⭐ Une réussite se
/// fête (confettis, une fois). ⚠️ Clavier ouvert : le visuel s'efface, le champ
/// et son erreur restent visibles.
struct BrowtherIntroReferralStep: View {
  @ObservedObject var model: BrowtherIntroModel
  @State private var keyboardUp = false
  @State private var redeemed = false

  var body: some View {
    BrowtherIntroLayout(
      title: Strings.BrowtherReferral.redeemHead,
      subtitle: Strings.BrowtherReferral.redeemBody
    ) {
      VStack(spacing: 24) {
        if !keyboardUp {
          ReferralGiftBadge(done: redeemed || BrowtherReferralController.shared.known?.referredBy != nil)
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
        if redeemed || BrowtherReferralController.shared.known?.referredBy != nil {
          Label(Strings.BrowtherReferral.redeemValidatedLine, systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(ReferralPalette.green)
            .multilineTextAlignment(.center)
        } else {
          ReferralRedeemField(source: "onboarding") {
            redeemed = true
            model.celebrateReferralCode()
          }
        }
      }
      .frame(maxHeight: .infinity, alignment: .center)
      .animation(.smooth(duration: 0.25), value: keyboardUp)
    } actions: {
      Button(Strings.FocusOnboarding.continueButtonTitle) {
        dismissKeyboard()
        model.advance()
      }
      .buttonStyle(BrowtherIntroPrimaryButtonStyle())
      if !redeemed {
        Button(Strings.BrowtherIntro.laterButton) {
          dismissKeyboard()
          model.later("referral_code")
        }
        .buttonStyle(BrowtherIntroGhostButtonStyle())
      }
    }
    // ⚠️ Pas de « toucher à côté ferme le clavier » par un geste SwiftUI posé
    // sur l'écran : il se déclencherait aussi en touchant le champ pour y placer
    // le curseur (cf. `BrowtherFeedbackView`). Le clavier se ferme par sa touche
    // « OK » (qui valide), et par les deux boutons.
    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
      keyboardUp = true
    }
    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
      keyboardUp = false
    }
  }

  private func dismissKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
  }
}
