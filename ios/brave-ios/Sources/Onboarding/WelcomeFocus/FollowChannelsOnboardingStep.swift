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

  var body: some View {
    VStack(spacing: 16) {
      Spacer()

      channelButton(
        title: Strings.FocusOnboarding.followChannelsWhatsApp,
        // Couleurs officielles des deux services, identiques au desktop et au
        // panneau QR de Sawtunaa : c'est ce qui fait reconnaître le bouton
        // avant même d'en lire l'intitulé.
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

      // Répond à « pourquoi l'un plutôt que l'autre ? » — les deux canaux
      // portent la même chose, seule compte l'app déjà installée.
      Text(Strings.FocusOnboarding.followChannelsSameContent)
        .font(.footnote)
        .multilineTextAlignment(.center)
        .foregroundStyle(Color(braveSystemName: .textSecondary))
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 4)

      Spacer()
    }
    .padding(.horizontal, 24)
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

  var body: some View {
    // Un seul bouton : l'écran ne demande rien, « Passer » et « Terminer »
    // mèneraient exactement au même endroit.
    Button {
      continueHandler()
    } label: {
      Text(Strings.FocusOnboarding.startBrowseActionButtonTitle)
        .frame(maxWidth: .infinity)
    }
    .primaryContinueAction()
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
