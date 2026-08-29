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
  // Cette vue occupe la zone ILLUSTRATION du conteneur d'onboarding, que
  // `OnboardingStepView` force en pleine hauteur avec un fond en carte
  // arrondie. Toutes les étapes en ont une, et on ne peut pas la faire
  // disparaître sans toucher au conteneur partagé : trois tentatives l'ont
  // montré le 2026-08-29 (boutons dedans → contrôles flottant dans le vide ;
  // grands glyphes → doublon avec les icônes des boutons ; fond repeint → la
  // carte reste visible, le jeton de couleur n'étant pas celui de la page).
  //
  // Donc on la REMPLIT, avec le visuel de marque dev&din — celui du site et des
  // réseaux. Il dit ce que les canaux annoncent (les autres produits du studio)
  // au lieu de décorer, et il est déjà traduit.
  //
  // `scaledToFit` et non `scaledToFill` : le visuel est en 1,9:1 alors que la
  // zone est portrait. Un remplissage rognerait les icônes de produits sur les
  // côtés et couperait le texte — c'est-à-dire tout ce qui fait son intérêt.
  //
  // Reste que « ajusté » laisse des bandes au-dessus et en dessous. Peintes en
  // noir (le fond de carte du conteneur), elles donnaient un effet d'écran de
  // télévision en letterbox. On peint donc TOUTE la zone avec le fond du visuel
  // lui-même — un bleu-vert très sombre, échantillonné sur ses bords — et les
  // bandes cessent d'être des bandes : la carte devient le visuel.
  var body: some View {
    Image(Self.assetName, bundle: .module)
      .resizable()
      .scaledToFit()
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Self.artworkBackground)
  }

  /// Fond des visuels dev&din, relevé sur les bords des trois PNG
  /// (≈ RGB 8/22/30). Codé en dur et non extrait à l'exécution : lire un pixel
  /// coûterait un décodage complet de l'image à chaque affichage, pour une
  /// couleur qui ne change que si les visuels sont refaits.
  ///
  /// ⚠️ Si `ads/creatives/out/devndin/og-*.png` est régénéré avec un autre fond,
  /// c'est ici qu'il faut le répercuter — sinon un liseré apparaîtra autour du
  /// visuel, et rien ne dira d'où il vient.
  private static let artworkBackground = Color(
    red: 8 / 255, green: 22 / 255, blue: 30 / 255
  )

  /// Le visuel existe en trois langues. On suit la langue de l'interface, pas
  /// la région : c'est le texte de l'image qu'il s'agit de rendre lisible.
  /// Repli sur l'anglais — jamais sur le français, qui ne serait un défaut
  /// raisonnable que pour nous.
  private static var assetName: String {
    switch Locale.current.language.languageCode?.identifier {
    case "fr": return "devndin-channels-fr"
    case "ar": return "devndin-channels-ar"
    default: return "devndin-channels-en"
    }
  }

}

struct FollowChannelsActionsView: View {
  var continueHandler: () -> Void

  /// Chaîne WhatsApp dev&din. `whatsapp.com/channel/...` ouvre l'app native si
  /// elle est installée, et bascule sur le navigateur sinon — pas besoin de
  /// tester `canOpenURL`, qui exigerait en plus une entrée
  /// `LSApplicationQueriesSchemes`.
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
        icon: "channel-whatsapp",
        url: Self.whatsAppURL,
        event: "marketing_whatsapp_channel_clicked"
      )
      channelButton(
        title: Strings.FocusOnboarding.followChannelsTelegram,
        accent: Color(red: 0.133, green: 0.62, blue: 0.851),
        icon: "channel-telegram",
        url: Self.telegramURL,
        event: "marketing_telegram_channel_clicked"
      )

      // Répond à « pourquoi l'un plutôt que l'autre ? » — les deux canaux
      // portent la même chose, seule compte l'app déjà installée. Ici et non
      // dans l'illustration : c'est une légende DES BOUTONS, elle doit les
      // toucher. (Dans l'illustration elle se faisait couper à droite, la zone
      // n'ayant pas les marges de la colonne de contenu.)
      Text(Strings.FocusOnboarding.followChannelsSameContent)
        .font(.footnote)
        .multilineTextAlignment(.center)
        .foregroundStyle(Color(braveSystemName: .textSecondary))
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .padding(.top, 2)

      // Sortie volontairement DISCRÈTE — mais jamais cachée ni déguisée.
      //
      // L'intention (Karim, 2026-08-29) : que l'écran ne se passe pas
      // machinalement. On y répond en corrigeant la hiérarchie — les canaux
      // deviennent l'action pleine, la sortie devient un lien — et non en
      // rendant la sortie difficile à trouver : elle garde son libellé complet,
      // sa taille de texte lisible, et toute la largeur comme zone tactile.
      // Un écran d'onboarding dont on ne sait pas sortir se paie en
      // désinstallations et en revue App Store.
      Button {
        continueHandler()
      } label: {
        Text(Strings.FocusOnboarding.startBrowseActionButtonTitle)
          .font(.callout.weight(.semibold))
          .foregroundStyle(Color(braveSystemName: .textSecondary))
          .frame(maxWidth: .infinity)
          .padding(.vertical, 14)
          // Contour et non aplat : il se lit comme un bouton — donc on le
          // trouve sans le chercher — tout en restant clairement second
          // derrière les deux canaux pleins. Le simple texte, essayé juste
          // avant, basculait dans l'excès inverse : plus rien ne disait que
          // c'était cliquable.
          .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
              // Dérivé de la couleur du LIBELLÉ plutôt qu'un jeton de
              // séparateur : `dividerStrong` est calibré pour des traits de
              // séparation, il disparaissait presque en contour de bouton.
              // Suit le thème clair comme sombre, contrairement à un blanc
              // semi-transparent qui s'évanouirait sur fond clair.
              .stroke(
                Color(braveSystemName: .textSecondary).opacity(0.55),
                lineWidth: 1.5
              )
          )
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .primaryContinueAction()
      .padding(.top, 4)
    }
  }

  @ViewBuilder
  private func channelButton(
    title: String,
    /// Teinte le CADRE du bouton uniquement — le logo porte ses propres
    /// couleurs officielles.
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
        // Les VRAIS logos des deux services, et non des symboles système
        // approchants (`message.fill` / `paperplane.fill`). Ceux-ci ne
        // ressemblaient pas aux icônes que l'utilisateur a sur son écran
        // d'accueil — or c'est précisément ce qu'on lui demande de reconnaître.
        // Tracés officiels repris de
        // `tranquileaty/apps/mobile/components/icons/`, déjà en production sur
        // un autre produit dev&din, rendus en PNG @1x/@2x/@3x.
        //
        // Pastille blanche autour du logo, comme sur desktop : il garde ses
        // couleurs de marque quel que soit le fond de l'écran.
        Image(icon, bundle: .module)
          .resizable()
          .scaledToFit()
          .frame(width: 18, height: 18)
          .frame(width: 28, height: 28)
          .background(Color.white, in: Circle())
        Text(title)
          .font(.callout.weight(.semibold))
          .foregroundStyle(.white)
        Spacer()
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 14)
      .frame(maxWidth: .infinity)
      // Remplissage PLEIN aux couleurs du service : ce sont ces deux boutons
      // l'action de l'écran, pas la sortie. Ils étaient auparavant en simple
      // contour teinté, sous un « Démarrer la navigation » plein — la
      // hiérarchie disait donc l'inverse de l'intention, et l'écran se passait
      // machinalement.
      .background(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(accent)
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
