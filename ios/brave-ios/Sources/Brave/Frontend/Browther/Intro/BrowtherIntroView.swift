// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BraveStrings
import BraveUI
import Onboarding
import Shared
import SwiftUI

/// L'introduction Browther : six écrans qui montrent ce que fait le navigateur
/// et laissent la personne régler ce qui la concerne.
///
/// ⚠️ Elle REMPLACE le parcours Focus de Brave (`OnboardingController`), qui ne
/// présentait que ce que Browther hérite : navigateur par défaut, argument
/// anti-pub, canaux. Le parcours Brave reste dans le dépôt (menu de debug), il
/// n'est simplement plus présenté au premier lancement.
struct BrowtherIntroView: View {
  @ObservedObject var model: BrowtherIntroModel
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    ZStack(alignment: .top) {
      Color(UIColor.systemBackground)
        .ignoresSafeArea()
      content
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      header
    }
    .overlay {
      if let feature = model.soonFeature {
        BrowtherIntroSoonSheet(feature: feature) {
          model.dismissSoonSheet()
          model.advance()
        } onDismiss: {
          model.dismissSoonSheet()
        }
        .transition(.opacity)
      }
    }
    .animation(.smooth(duration: 0.3), value: model.soonFeature)
    // Sans ça, `\.windowScene` reste nil et la vidéo en incrustation de
    // l'écran « navigateur par défaut » ne démarre jamais.
    .prepareWindowSceneEnvironment()
  }

  // MARK: Barre du haut

  private var header: some View {
    HStack(spacing: 6) {
      Button {
        model.back()
      } label: {
        Image(systemName: "chevron.left")
          .font(.system(size: 17, weight: .semibold))
          .frame(width: 44, height: 44)
          .contentShape(Rectangle())
      }
      .opacity(model.isFirstStep ? 0 : 1)
      .disabled(model.isFirstStep)
      .accessibilityLabel(Strings.tabToolbarBackButtonAccessibilityLabel)
      HStack(spacing: 5) {
        ForEach(Array(model.steps.enumerated()), id: \.offset) { index, _ in
          Capsule()
            .fill(Color.primary.opacity(index <= model.index ? 0.85 : 0.18))
            .frame(height: 3)
        }
      }
      .padding(.trailing, 20)
      .animation(.smooth(duration: 0.4), value: model.index)
    }
    .foregroundStyle(model.step == .welcome ? Color.white : Color.primary)
    .padding(.leading, 10)
  }

  // MARK: Contenu

  @ViewBuilder
  private var content: some View {
    switch model.step {
    case .welcome:
      BrowtherIntroWelcomeStep(model: model)
        .transition(pushTransition)
    case .ads:
      BrowtherIntroAdsStep(model: model)
        .transition(pushTransition)
    case .blur:
      BrowtherIntroBlurStep(model: model)
        .transition(pushTransition)
    case .music:
      BrowtherIntroMusicStep(model: model)
        .transition(pushTransition)
    case .defaultBrowser:
      BrowtherIntroDefaultBrowserStep(model: model)
        .transition(pushTransition)
    case .channels:
      BrowtherIntroChannelsStep(model: model)
        .transition(pushTransition)
    }
  }

  /// Les écrans entrent par la droite et sortent par la gauche : le parcours a
  /// un sens, et le retour le rembobine.
  private var pushTransition: AnyTransition {
    .asymmetric(
      insertion: .push(from: .trailing),
      removal: .push(from: .leading)
    )
  }
}

// MARK: - Gabarit commun

/// Titre, sous-titre, scène, boutons : la structure que partagent cinq des six
/// écrans (l'accueil a la sienne, pleine image).
struct BrowtherIntroLayout<Scene: View, Actions: View>: View {
  var pill: AnyView?
  let title: String
  let subtitle: String
  var footnote: AnyView?
  @ViewBuilder var scene: () -> Scene
  @ViewBuilder var actions: () -> Actions

  var body: some View {
    VStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 9) {
        if let pill {
          pill
        }
        Text(title)
          .font(.system(size: 28, weight: .semibold))
          .foregroundStyle(BrowtherIntroPalette.ink)
        Text(subtitle)
          .font(.body)
          .foregroundStyle(BrowtherIntroPalette.inkSoft)
        if let footnote {
          footnote
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 20)
      .padding(.top, 8)
      scene()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, 18)
      VStack(spacing: 6) {
        actions()
      }
      .padding(.horizontal, 20)
      .padding(.top, 14)
    }
    .padding(.top, 52)
    .padding(.bottom, 8)
  }
}

// MARK: - Feuille « ça arrive très bientôt »

/// Ce que répond « Activer » pendant l'accès anticipé. L'écran, lui, montre la
/// fonctionnalité finie : c'est le geste qui apprend qu'elle arrive, pas une
/// pastille posée d'avance sur toute la page.
struct BrowtherIntroSoonSheet: View {
  let feature: BrowtherIntroFeature
  let onContinue: () -> Void
  let onDismiss: () -> Void

  var body: some View {
    ZStack(alignment: .bottom) {
      Color.black.opacity(0.45)
        .ignoresSafeArea()
        .onTapGesture(perform: onDismiss)
      VStack(alignment: .leading, spacing: 12) {
        Capsule()
          .fill(Color.primary.opacity(0.18))
          .frame(width: 38, height: 5)
          .frame(maxWidth: .infinity)
          .padding(.bottom, 4)
        // L'invocation n'est plus ici : elle est portée par le bouton
        // (« qu'Allah facilite »), une seule fois et au bon endroit.
        Text(Strings.BrowtherIntro.soonTitle)
          .font(.system(size: 21, weight: .semibold))
        Text(
          feature == .basarunaa
            ? Strings.BrowtherIntro.soonBlurBody
            : Strings.BrowtherIntro.soonMusicBody
        )
        .font(.callout)
        .foregroundStyle(BrowtherIntroPalette.inkSoft)
        Text(Strings.BrowtherIntro.soonNote)
          .font(.footnote)
          .foregroundStyle(Color(UIColor.tertiaryLabel))
        Button(Strings.BrowtherIntro.soonPrimaryButton, action: onContinue)
          .buttonStyle(BrowtherIntroPrimaryButtonStyle())
          .padding(.top, 4)
      }
      .padding(.horizontal, 22)
      .padding(.top, 10)
      .padding(.bottom, 28)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        Color(UIColor.systemBackground),
        in: UnevenRoundedRectangle(
          topLeadingRadius: 26,
          bottomLeadingRadius: 0,
          bottomTrailingRadius: 0,
          topTrailingRadius: 26,
          style: .continuous
        )
      )
      .transition(.move(edge: .bottom))
    }
  }
}
