// Copyright (c) 2026 The Browther Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

import BrowtherAnalytics
import Strings
import SwiftUI

/// Dernière étape de l'onboarding : proposer de suivre les deux canaux
/// broadcast publics dev&din (cf. `devndin/docs/BROADCASTS.md` §0).
///
/// Parité avec l'étape desktop (`brave_welcome_ui/components/follow-channels/`),
/// **à un arbitrage près** : là-bas le QR est le chemin principal parce que
/// presque personne n'a WhatsApp ou Telegram installé sur son ordinateur. Ici
/// c'est l'inverse — les deux apps sont sur le téléphone, un QR n'aurait aucun
/// sens (il faudrait un second appareil pour le scanner). Donc **ouverture
/// directe**, et pas de QR du tout.
///
/// L'écran ne collecte rien et n'attend rien : un canal public ne renvoie aucun
/// signal d'abonnement, il n'y a donc rien à valider. On avance sur l'action de
/// l'utilisateur, quelle qu'elle soit.
struct FollowChannelsGraphicView: View {
  /// Chaîne WhatsApp dev&din. `whatsapp.com/channel/...` ouvre l'app native si
  /// elle est installée, et bascule sur le navigateur sinon — pas besoin de
  /// tester `canOpenURL`, qui exigerait en plus une entrée `LSApplicationQueriesSchemes`.
  private static let whatsAppURL = URL(
    string: "https://whatsapp.com/channel/0029Vb8ydkv5vKABH78PVX32"
  )!
  private static let telegramURL = URL(string: "https://t.me/devndin_nouveautes")!

  @Environment(\.openURL) private var openURL

  // ⚠️ Cette vue occupe la zone ILLUSTRATION du conteneur d'onboarding, que
  // `OnboardingStepView` force en pleine hauteur avec un fond en carte
  // arrondie. La v1 y mettait les deux boutons de canal entourés de `Spacer()` :
  // deux contrôles de taille normale flottant au milieu d'une grande carte
  // noire, avec un vide au-dessus et en dessous — constaté à l'écran le
  // 2026-08-28. Les contrôles vont dans la zone ACTIONS (`makeActions`), pas
  // ici ; cette zone-là attend une illustration qui REMPLIT.
  var body: some View {
    GeometryReader { proxy in
      let side = min(proxy.size.width * 0.34, proxy.size.height * 0.42)
      VStack(spacing: 20) {
        Spacer(minLength: 0)
        HStack(spacing: 24) {
          // Couleurs officielles des deux services, identiques au desktop et au
          // panneau QR de Sawtunaa : c'est ce qui fait reconnaître le canal
          // avant même d'en lire l'intitulé.
          glyph(
            systemName: "message.fill",
            accent: Color(red: 0.145, green: 0.827, blue: 0.4),
            side: side
          )
          glyph(
            systemName: "paperplane.fill",
            accent: Color(red: 0.133, green: 0.62, blue: 0.851),
            side: side
          )
        }
        // Répond à « pourquoi l'un plutôt que l'autre ? » — les deux canaux
        // portent la même chose, seule compte l'app déjà installée.
        Text(Strings.FocusOnboarding.followChannelsSameContent)
          .font(.footnote)
          .multilineTextAlignment(.center)
          .foregroundStyle(Color(braveSystemName: .textSecondary))
          .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 0)
      }
      .frame(width: proxy.size.width, height: proxy.size.height)
      .padding(.horizontal, 24)
    }
  }

  @ViewBuilder
  private func glyph(systemName: String, accent: Color, side: CGFloat) -> some View {
    Image(systemName: systemName)
      .font(.system(size: side * 0.42, weight: .semibold))
      .foregroundStyle(.white)
      .frame(width: side, height: side)
      .background(accent.gradient, in: RoundedRectangle(cornerRadius: side * 0.28, style: .continuous))
  }

  @ViewBuilder
  private func channelButton(
    title: String,
    accent: Color,
    icon: String,
    url: URL,
    event: String
  ) -> some View {
    Button {
      BrowtherAnalyticsService.shared.track(event: event, properties: ["source": "onboarding"])
      openURL(url)
    } label: {
      HStack(spacing: 12) {
        // Pastille blanche autour du logo, comme sur desktop : le symbole garde
        // sa couleur de marque quel que soit le fond de l'écran.
        Image(systemName: icon)
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(accent)
          .frame(width: 32, height: 32)
          .background(Color.white, in: Circle())
        Text(title)
          .font(.callout.weight(.semibold))
          .foregroundStyle(Color(braveSystemName: .textPrimary))
        Spacer()
      }
      .padding(12)
      .frame(maxWidth: .infinity)
      .background(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(accent.opacity(0.12))
          .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
              .strokeBorder(accent.opacity(0.45), lineWidth: 1)
          )
      )
    }
    .buttonStyle(.plain)
  }
}

struct FollowChannelsActionsView: View {
  var continueHandler: () -> Void

  private static let whatsAppURL = URL(
    string: "https://whatsapp.com/channel/0029Vb8ydkv5vKABH78PVX32"
  )!
  private static let telegramURL = URL(string: "https://t.me/devndin_nouveautes")!

  @Environment(\.openURL) private var openURL

  var body: some View {
    VStack(spacing: 12) {
      // Les deux liens de canal vivent ICI, pas dans l'illustration : c'est la
      // zone que le conteneur réserve aux contrôles, et elle épouse leur
      // hauteur au lieu de les noyer dans une carte pleine hauteur.
      channelButton(
        title: Strings.FocusOnboarding.followChannelsWhatsApp,
        accent: Color(red: 0.145, green: 0.827, blue: 0.4),
        icon: "message.fill",
        url: Self.whatsAppURL,
        event: "marketing_whatsapp_channel_clicked"
      )
      channelButton(
        title: Strings.FocusOnboarding.followChannelsTelegram,
        accent: Color(red: 0.133, green: 0.62, blue: 0.851),
        icon: "paperplane.fill",
        url: Self.telegramURL,
        event: "marketing_telegram_channel_clicked"
      )

      // Un seul bouton de sortie : l'écran ne demande rien, « Passer » et
      // « Terminer » mèneraient exactement au même endroit.
      Button {
        continueHandler()
      } label: {
        Text(Strings.FocusOnboarding.startBrowseActionButtonTitle)
          .frame(maxWidth: .infinity)
      }
      .primaryContinueAction()
      .padding(.top, 4)
    }
  }

  @ViewBuilder
  private func channelButton(
    title: String,
    accent: Color,
    icon: String,
    url: URL,
    event: String
  ) -> some View {
    Button {
      BrowtherAnalyticsService.shared.track(event: event, properties: [:])
      openURL(url)
    } label: {
      HStack(spacing: 12) {
        Image(systemName: icon)
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(accent)
          .frame(width: 28, height: 28)
          .background(Color.white, in: Circle())
        Text(title)
          .font(.callout.weight(.semibold))
          .foregroundStyle(Color(braveSystemName: .textPrimary))
        Spacer()
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 12)
      .frame(maxWidth: .infinity)
      .background(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(accent.opacity(0.12))
          .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
              .stroke(accent.opacity(0.5), lineWidth: 1)
          )
      )
    }
    .buttonStyle(.plain)
  }
}

public struct FollowChannelsOnboardingStep: OnboardingStep {
  public var id: String = "follow-channels"

  public func makeTitle() -> some View {
    OnboardingTitleView(
      // L'invocation est ajoutée ici, sur sa propre ligne, et **pas** dans la
      // chaîne traduite : en fin de titre elle se fait couper par le retour à la
      // ligne (un fragment RTL en bout de ligne LTR ne se césure pas). Même
      // traitement que sur desktop — et elle n'a pas à être retraduite, la
      // formule étant identique dans toutes les langues.
      title: "\(Strings.FocusOnboarding.followChannelsScreenTitle)\nإن شاء الله",
      subtitle: Strings.FocusOnboarding.followChannelsScreenDescription
    )
  }

  public func makeGraphic() -> some View {
    FollowChannelsGraphicView()
  }

  public func makeActions(continueHandler: @escaping () -> Void) -> some View {
    FollowChannelsActionsView(continueHandler: continueHandler)
  }
}

extension OnboardingStep where Self == FollowChannelsOnboardingStep {
  public static var followChannels: Self { .init() }
}

#if DEBUG
#Preview {
  OnboardingStepView(step: .followChannels)
}
#endif
