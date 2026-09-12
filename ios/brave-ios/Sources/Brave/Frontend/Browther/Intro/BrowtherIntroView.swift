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
      if let celebratedAt = model.celebratedAt {
        BrowtherIntroConfetti(start: celebratedAt)
          .id(celebratedAt)
          .ignoresSafeArea()
      }
    }
    .overlay {
      if let feature = model.soonFeature {
        BrowtherIntroSoonSheet(feature: feature) {
          model.dismissSoonSheet()
          model.advance()
        } onDismiss: {
          model.dismissSoonSheet()
        }
      }
    }
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
          // Sans ça, le bloc du haut se fait rogner par la scène et le texte
          // finit en « … » (vu sur le dernier écran à la recette).
          .fixedSize(horizontal: false, vertical: true)
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

// MARK: - Feuille « ça arrive bientôt »

/// Ce que répond « Continuer » pendant l'accès anticipé.
///
/// ⚠️ Une vraie feuille, pas un panneau posé en fondu : elle monte au ressort,
/// la poignée **glisse** et la referme, et le fond s'assombrit progressivement.
/// La version précédente apparaissait d'un coup, avec une poignée décorative
/// qui ne répondait pas — on promettait un geste qui n'existait pas.
struct BrowtherIntroSoonSheet: View {
  let feature: BrowtherIntroFeature
  let onContinue: () -> Void
  let onDismiss: () -> Void

  @State private var offset: CGFloat = 0
  @State private var appeared = false

  private var icon: String {
    feature == .basarunaa ? "basarunaa.icon" : "sawtunaa.icon"
  }

  private var name: String {
    feature == .basarunaa ? "Basarunaa" : "Sawtunaa"
  }

  var body: some View {
    ZStack(alignment: .bottom) {
      Color.black
        .opacity(appeared ? 0.55 : 0)
        .ignoresSafeArea()
        .onTapGesture(perform: dismiss)
      card
        .offset(y: appeared ? offset : 700)
        .gesture(
          DragGesture()
            .onChanged { value in
              offset = max(0, value.translation.height)
            }
            .onEnded { value in
              // Un tiers de la feuille, ou un geste franc : on referme.
              if value.translation.height > 110 || value.predictedEndTranslation.height > 240 {
                dismiss()
              } else {
                withAnimation(.snappy(duration: 0.3)) { offset = 0 }
              }
            }
        )
    }
    .onAppear {
      withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { appeared = true }
    }
  }

  private func dismiss() {
    close(then: onDismiss)
  }

  /// La feuille redescend avant de rendre la main : sans ça, elle disparaît
  /// d'un coup et l'écran suivant arrive par-dessus.
  private func close(then action: @escaping () -> Void) {
    withAnimation(.smooth(duration: 0.25)) {
      appeared = false
      offset = 700
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: action)
  }

  private var card: some View {
    VStack(alignment: .leading, spacing: 14) {
      Capsule()
        .fill(Color.primary.opacity(0.28))
        .frame(width: 40, height: 5)
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .contentShape(Rectangle())
      HStack(spacing: 10) {
        Image(icon, bundle: .module)
          .resizable()
          .renderingMode(.template)
          .aspectRatio(contentMode: .fit)
          .frame(width: 22, height: 22)
          .foregroundStyle(BrowtherEarlyAccess.amber)
          .frame(width: 42, height: 42)
          .background(BrowtherEarlyAccess.amber.opacity(0.15), in: Circle())
        VStack(alignment: .leading, spacing: 2) {
          Text(name)
            .font(.callout.weight(.semibold))
            .foregroundStyle(BrowtherIntroPalette.ink)
          Text(Strings.BrowtherIntro.soonTitle)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(BrowtherEarlyAccess.amber)
        }
      }
      Text(
        feature == .basarunaa
          ? Strings.BrowtherIntro.soonBlurBody
          : Strings.BrowtherIntro.soonMusicBody
      )
      .font(.callout)
      .foregroundStyle(BrowtherIntroPalette.inkSoft)
      .fixedSize(horizontal: false, vertical: true)
      Text(Strings.BrowtherIntro.soonNote)
        .font(.footnote)
        .foregroundStyle(Color(UIColor.tertiaryLabel))
        .fixedSize(horizontal: false, vertical: true)
      Button(Strings.BrowtherIntro.soonPrimaryButton) {
        close(then: onContinue)
      }
      .buttonStyle(BrowtherIntroPrimaryButtonStyle())
      .padding(.top, 2)
    }
    .padding(.horizontal, 22)
    // La barre d'accueil est déjà sous la feuille : 14 pt suffisent, 30 pt
    // laissaient le bouton flotter trop haut.
    .padding(.bottom, 14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background {
      // ⚠️ C'est le FOND qui déborde sous la barre d'accueil, pas la feuille :
      // `ignoresSafeArea` posé sur la vue entière décale son contenu et laisse
      // une bande noire sous elle (même piège que sur l'accueil).
      UnevenRoundedRectangle(
        topLeadingRadius: 28,
        bottomLeadingRadius: 0,
        bottomTrailingRadius: 0,
        topTrailingRadius: 28,
        style: .continuous
      )
      .fill(Color(UIColor.secondarySystemGroupedBackground))
      .overlay(alignment: .top) {
        // Un liseré ambre : la feuille appartient à l'accès anticipé, comme le
        // badge de la barre d'outils. ⚠️ En HAUT seulement — le contour fermé
        // dessinait un trait sous la feuille, là où elle n'a pas de bord.
        UnevenRoundedRectangle(
          topLeadingRadius: 28,
          bottomLeadingRadius: 0,
          bottomTrailingRadius: 0,
          topTrailingRadius: 28,
          style: .continuous
        )
        .strokeBorder(BrowtherEarlyAccess.amber.opacity(0.35), lineWidth: 1)
        .padding(.bottom, -80)
      }
      .shadow(color: .black.opacity(0.4), radius: 24, y: -8)
      .ignoresSafeArea(edges: .bottom)
    }
  }
}
