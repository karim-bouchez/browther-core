// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BraveStrings
import BraveUI
import Onboarding
import Shared
import SwiftUI
import UIKit

// MARK: - 1 · Accueil

/// L'accueil s'ouvre sur un fond du Nouvel Onglet — celui qu'on retrouve en
/// arrivant — et sur le verset qui résume les deux moteurs : l'ouïe (Sawtunaa)
/// et la vue (Basarunaa).
struct BrowtherIntroWelcomeStep: View {
  @ObservedObject var model: BrowtherIntroModel

  /// Un des fonds déjà embarqués pour le Nouvel Onglet : aucun asset de plus,
  /// et la continuité visuelle est gratuite.
  private static let background: UIImage? = {
    guard
      let url = Bundle.module.url(
        forResource: "david-billings-KCEwOduK8ck-unsplash",
        withExtension: "jpg"
      )
    else { return nil }
    return UIImage(contentsOfFile: url.path)
  }()

  var body: some View {
    ZStack(alignment: .bottom) {
      backgroundLayer
      VStack(spacing: 0) {
        Image("browther.shield.bar", bundle: .module)
          .resizable()
          .renderingMode(.template)
          .aspectRatio(contentMode: .fit)
          .frame(width: 54, height: 54)
          .foregroundStyle(.white)
          .padding(.top, 66)
        verse
          .padding(.top, 26)
        Spacer(minLength: 20)
        Text(Strings.BrowtherIntro.welcomeTitle)
          .font(.system(size: 30, weight: .semibold))
          .multilineTextAlignment(.center)
          .foregroundStyle(.white)
          .padding(.horizontal, 20)
        protections
          .padding(.horizontal, 20)
          .padding(.top, 18)
        Button(Strings.BrowtherIntro.startButton) {
          model.advance()
        }
        .buttonStyle(BrowtherIntroLightButtonStyle())
        .padding(.horizontal, 20)
        .padding(.top, 18)
        signature
          .padding(.top, 14)
          .padding(.bottom, 10)
      }
    }
    .ignoresSafeArea(edges: .top)
  }

  @ViewBuilder
  private var backgroundLayer: some View {
    ZStack {
      if let image = Self.background {
        Image(uiImage: image)
          .resizable()
          .aspectRatio(contentMode: .fill)
      } else {
        Color(UIColor(rgb: 0x0F100E))
      }
      LinearGradient(
        stops: [
          .init(color: Color.black.opacity(0.2), location: 0),
          .init(color: Color.black.opacity(0.35), location: 0.34),
          .init(color: Color.black.opacity(0.88), location: 0.64),
          .init(color: Color(UIColor(rgb: 0x0F100E)), location: 1),
        ],
        startPoint: .top,
        endPoint: .bottom
      )
    }
    .ignoresSafeArea()
  }

  private var verse: some View {
    VStack(spacing: 10) {
      // Texte uthmani exact (Coran 17:36, seconde moitié) — ⛔ ne jamais le
      // ressaisir à la main : il vient d'une source unique, cf.
      // `private/design/intro-iphone/verse.txt`.
      Text(verbatim: "إِنَّ ٱلسَّمْعَ وَٱلْبَصَرَ وَٱلْفُؤَادَ كُلُّ أُو۟لَٰٓئِكَ كَانَ عَنْهُ مَسْـُٔولًۭا")
        .font(.system(size: 23))
        .lineSpacing(10)
        .multilineTextAlignment(.center)
        .environment(\.layoutDirection, .rightToLeft)
        .foregroundStyle(.white)
      Text(Strings.BrowtherIntro.verseTranslation)
        .font(.system(size: 15.5, design: .serif))
        .italic()
        .multilineTextAlignment(.center)
        .foregroundStyle(.white.opacity(0.84))
      Text(Strings.BrowtherIntro.verseReference)
        .font(.system(size: 10.5, weight: .semibold))
        .tracking(1.6)
        .textCase(.uppercase)
        .foregroundStyle(BrowtherIntroPalette.sage)
    }
    .padding(.horizontal, 26)
  }

  private var protections: some View {
    HStack(spacing: 0) {
      protection(
        icon: "browther.shield.bar",
        name: Strings.BrowtherIntro.protectionAds,
        soon: false
      )
      Divider().frame(height: 58).overlay(Color.white.opacity(0.12))
      protection(
        icon: "sawtunaa.icon",
        name: Strings.BrowtherIntro.protectionMusic,
        soon: model.isEarlyAccess
      )
      Divider().frame(height: 58).overlay(Color.white.opacity(0.12))
      protection(
        icon: "basarunaa.icon",
        name: Strings.BrowtherIntro.protectionImages,
        soon: model.isEarlyAccess
      )
    }
    .padding(.vertical, 13)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
    }
  }

  /// Les icônes sont celles de la barre d'outils : la personne les reverra
  /// telles quelles en haut de son écran.
  private func protection(icon: String, name: String, soon: Bool) -> some View {
    VStack(spacing: 7) {
      Image(icon, bundle: .module)
        .resizable()
        .renderingMode(.template)
        .aspectRatio(contentMode: .fit)
        .frame(width: 26, height: 26)
        .foregroundStyle(.white)
      Text(name)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(.white)
      HStack(spacing: 5) {
        Circle()
          .fill(soon ? Color(UIColor(rgb: 0xF59E0B)) : Color(UIColor(rgb: 0x34C759)))
          .frame(width: 7, height: 7)
        Text(soon ? Strings.BrowtherIntro.statusSoon : Strings.BrowtherIntro.statusActive)
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(.white.opacity(0.72))
      }
      // Seconde ligne : l'invocation pour ce qui arrive, « dès maintenant »
      // pour ce qui marche déjà — sinon la colonne active paraît plus courte.
      Text(soon ? "إن شاء الله" : Strings.BrowtherIntro.statusActiveDetail)
        .font(.system(size: 11))
        .foregroundStyle(BrowtherIntroPalette.sage)
    }
    .frame(maxWidth: .infinity)
  }

  /// Signature de l'éditeur — ⛔ PAS tapable ici : ouvrir `devndin.com` ferait
  /// sortir de l'introduction. Donc pas de pastille bordée non plus, c'est elle
  /// qui porte l'affordance (`SURFACES-COMMUNES.md` §6). La version tapable
  /// reste au pied des Paramètres.
  private var signature: some View {
    HStack(spacing: 5) {
      Text(Strings.Browther.signatureLabel)
        .font(.footnote)
      Image("browther-devndin-logo", bundle: .module)
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(height: 15)
    }
    .foregroundStyle(.white.opacity(0.55))
    .accessibilityElement(children: .combine)
  }
}

/// Le bouton clair de l'accueil : sur la photo sombre, l'encre système
/// disparaîtrait.
struct BrowtherIntroLightButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.body.weight(.semibold))
      .foregroundStyle(Color(UIColor(rgb: 0x0F100E)))
      .frame(maxWidth: .infinity, minHeight: 52)
      .background(
        Color(UIColor(rgb: 0xF8F3EA)),
        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
      )
      .opacity(configuration.isPressed ? 0.9 : 1)
      .scaleEffect(configuration.isPressed ? 0.97 : 1)
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
  }
}

// MARK: - 2 · Pubs

struct BrowtherIntroAdsStep: View {
  @ObservedObject var model: BrowtherIntroModel

  var body: some View {
    BrowtherIntroLayout(
      pill: AnyView(
        BrowtherIntroPill(tone: .active, label: Strings.BrowtherIntro.adsPill)
      ),
      title: Strings.BrowtherIntro.adsTitle,
      subtitle: Strings.BrowtherIntro.adsSubtitle
    ) {
      ZStack(alignment: .bottom) {
        BrowtherIntroWebPage(blocked: model.adsDemoOn)
          .padding(.bottom, 34)
        BrowtherStampPair(isOn: model.adsDemoOn)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
          .offset(x: 10, y: -14)
        BrowtherIntroSwitchRow(
          title: "Browther",
          offLabel: Strings.BrowtherIntro.adsSwitchOff,
          onLabel: Strings.BrowtherIntro.adsSwitchOn,
          isOn: Binding(
            get: { model.adsDemoOn },
            set: { _ in model.toggleDemo(for: .ads) }
          )
        )
      }
      .sensoryFeedback(.impact(weight: .medium), trigger: model.adsDemoOn)
    } actions: {
      Button(Strings.FocusOnboarding.continueButtonTitle) {
        model.advance()
      }
      .buttonStyle(BrowtherIntroPrimaryButtonStyle())
    }
  }
}

// MARK: - 3 · Floutage

struct BrowtherIntroBlurStep: View {
  @ObservedObject var model: BrowtherIntroModel

  var body: some View {
    BrowtherIntroLayout(
      title: Strings.BrowtherIntro.blurTitle,
      subtitle: Strings.BrowtherIntro.blurSubtitle
    ) {
      // Une vidéo ET une photo : elles ne prouvent pas la même chose. La photo
      // montre que le voile est propre, la vidéo qu'il suit.
      VStack(spacing: 10) {
        BrowtherIntroVideoTile(target: model.blurTarget)
        BrowtherIntroPhotoTile(target: model.blurTarget)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .sensoryFeedback(.selection, trigger: model.blurTarget)
    } actions: {
      HStack(spacing: 10) {
        choice(.women, label: Strings.BrowtherIntro.blurWomen, symbol: "figure.stand.dress")
        choice(.men, label: Strings.BrowtherIntro.blurMen, symbol: "figure.stand")
        choice(.both, label: Strings.BrowtherIntro.blurBoth, symbol: "figure.2")
      }
      .padding(.bottom, 6)
      Button(Strings.BrowtherIntro.activateBlur) {
        model.activate(.basarunaa)
      }
      .buttonStyle(BrowtherIntroPrimaryButtonStyle())
      Button(Strings.BrowtherIntro.laterButton) {
        model.later(BrowtherIntroFeature.basarunaa.rawValue)
      }
      .buttonStyle(BrowtherIntroGhostButtonStyle())
    }
  }

  private func choice(_ target: BrowtherBlurTarget, label: String, symbol: String) -> some View {
    let selected = model.blurTarget == target
    return Button {
      model.choose(target)
    } label: {
      VStack(spacing: 8) {
        Image(systemName: symbol)
          .font(.system(size: 22))
        Text(label)
          .font(.system(size: 14, weight: .semibold))
          .lineLimit(1)
          .minimumScaleFactor(0.8)
      }
      .foregroundStyle(selected ? BrowtherIntroPalette.sage : BrowtherIntroPalette.inkSoft)
      .frame(maxWidth: .infinity, minHeight: 88)
      .background(
        selected
          ? BrowtherIntroPalette.sage.opacity(0.12)
          : Color(UIColor.secondarySystemGroupedBackground),
        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .strokeBorder(
            selected ? BrowtherIntroPalette.sage : Color.primary.opacity(0.08),
            lineWidth: selected ? 2 : 1
          )
      }
      .overlay(alignment: .topTrailing) {
        if selected {
          Image(systemName: "checkmark")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Color(UIColor.systemBackground))
            .frame(width: 20, height: 20)
            .background(BrowtherIntroPalette.sage, in: Circle())
            .padding(8)
            .transition(.scale.combined(with: .opacity))
        }
      }
    }
    .buttonStyle(.plain)
    .animation(.snappy(duration: 0.28), value: selected)
    .accessibilityAddTraits(selected ? [.isSelected] : [])
  }
}

// MARK: - 4 · Musique

struct BrowtherIntroMusicStep: View {
  @ObservedObject var model: BrowtherIntroModel
  /// L'extrait réel (voix + musique) et sa version passée dans Sawtunaa.
  @StateObject private var audio = BrowtherIntroAudio()

  var body: some View {
    BrowtherIntroLayout(
      title: Strings.BrowtherIntro.musicTitle,
      subtitle: Strings.BrowtherIntro.musicSubtitle,
      footnote: AnyView(
        Text(Strings.BrowtherIntro.musicCompat)
          .font(.footnote)
          .foregroundStyle(Color(UIColor.tertiaryLabel))
      )
    ) {
      ZStack(alignment: .bottom) {
        VStack(spacing: 0) {
          ZStack {
            RadialGradient(
              colors: [Color(UIColor(rgb: 0x2F3C31)), Color(UIColor(rgb: 0x151916))],
              center: .init(x: 0.5, y: 0.2),
              startRadius: 10,
              endRadius: 260
            )
            VStack(spacing: 14) {
              Image(systemName: "mic.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color(UIColor(rgb: 0xE7E2D5)))
              Button {
                audio.toggle()
              } label: {
                HStack(spacing: 8) {
                  Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
                  Text(
                    audio.isPlaying
                      ? Strings.BrowtherIntro.musicPause
                      : Strings.BrowtherIntro.musicListen
                  )
                }
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(height: 40)
                .background(Color.white.opacity(0.16), in: Capsule())
              }
              .buttonStyle(.plain)
            }
          }
          .frame(maxHeight: .infinity)
          BrowtherIntroLanes(musicRemoved: model.musicDemoOn)
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 84)
            .background(Color(UIColor(rgb: 0x1B201C)))
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.bottom, 34)
        BrowtherStampPair(isOn: model.musicDemoOn)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
          .offset(x: 10, y: -14)
        BrowtherIntroSwitchRow(
          title: "Browther",
          offLabel: Strings.BrowtherIntro.musicSwitchOff,
          onLabel: Strings.BrowtherIntro.musicSwitchOn,
          isOn: Binding(
            get: { model.musicDemoOn },
            set: { _ in model.toggleDemo(for: .music) }
          )
        )
      }
      .sensoryFeedback(.impact(weight: .medium), trigger: model.musicDemoOn)
      .onChange(of: model.musicDemoOn) { _, removed in
        // L'interrupteur ne relance rien : il change de canal, à la même
        // position dans le morceau.
        audio.apply(musicRemoved: removed)
      }
      .onDisappear { audio.stop() }
    } actions: {
      Button(Strings.BrowtherIntro.activateMusic) {
        model.activate(.sawtunaa)
      }
      .buttonStyle(BrowtherIntroPrimaryButtonStyle())
      Button(Strings.BrowtherIntro.laterButton) {
        model.later(BrowtherIntroFeature.sawtunaa.rawValue)
      }
      .buttonStyle(BrowtherIntroGhostButtonStyle())
    }
  }
}

// MARK: - 5 · Navigateur par défaut

/// L'écran montre le bénéfice — un lien reçu dans une conversation qui s'ouvre
/// protégé — plutôt que le chemin dans les Réglages : c'est ce qui décide, et
/// le chemin, iOS le montre lui-même juste après.
struct BrowtherIntroDefaultBrowserStep: View {
  @ObservedObject var model: BrowtherIntroModel
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.windowScene) private var windowScene
  @State private var sheetUp = false

  var body: some View {
    BrowtherIntroLayout(
      title: Strings.BrowtherIntro.defaultTitle,
      subtitle: Strings.BrowtherIntro.defaultSubtitle
    ) {
      ZStack(alignment: .bottom) {
        VStack(alignment: .leading, spacing: 8) {
          bubble(Strings.BrowtherIntro.demoArticleTitle, incoming: true)
          linkCard
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(14)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        browserSheet
          .offset(y: sheetUp ? 0 : 320)
      }
      .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
      .onAppear {
        withAnimation(.smooth(duration: 0.65).delay(0.5)) {
          sheetUp = true
        }
      }
    } actions: {
      Button(Strings.FocusOnboarding.systemSettingsButtonTitle) {
        Task {
          // La vidéo part AVANT les Réglages : elle doit déjà flotter quand
          // iOS bascule, sinon elle s'ouvre derrière et personne ne la voit.
          await BrowtherDefaultBrowserVideo.presentPictureInPicture(
            isDarkMode: colorScheme == .dark,
            windowScene: windowScene
          )
          model.setAsDefaultBrowser()
        }
      }
      .buttonStyle(BrowtherIntroPrimaryButtonStyle())
      Button(Strings.BrowtherIntro.laterButton) {
        model.later("default_browser")
      }
      .buttonStyle(BrowtherIntroGhostButtonStyle())
    }
  }

  private func bubble(_ text: String, incoming: Bool) -> some View {
    Text(text)
      .font(.system(size: 14.5))
      .padding(.horizontal, 13)
      .padding(.vertical, 9)
      .background(
        incoming ? Color(UIColor.tertiarySystemGroupedBackground) : BrowtherIntroPalette.sage,
        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
      )
      .foregroundStyle(incoming ? BrowtherIntroPalette.ink : Color.white)
      .frame(maxWidth: .infinity, alignment: incoming ? .leading : .trailing)
  }

  private var linkCard: some View {
    VStack(alignment: .leading, spacing: 0) {
      LinearGradient(
        colors: [Color(UIColor(rgb: 0xE7C9A0)), Color(UIColor(rgb: 0xC98F5B))],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      .frame(height: 62)
      VStack(alignment: .leading, spacing: 2) {
        Text(Strings.BrowtherIntro.demoArticleTitle)
          .font(.system(size: 13.5, weight: .semibold))
        Text(Strings.BrowtherIntro.demoSiteName)
          .font(.system(size: 12))
          .foregroundStyle(BrowtherIntroPalette.inkSoft)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
    }
    .background(Color(UIColor.tertiarySystemGroupedBackground))
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .frame(maxWidth: 220, alignment: .leading)
  }

  private var browserSheet: some View {
    VStack(spacing: 10) {
      HStack(spacing: 8) {
        Image("browther.shield.bar", bundle: .module)
          .resizable()
          .renderingMode(.template)
          .aspectRatio(contentMode: .fit)
          .frame(width: 18, height: 18)
          .foregroundStyle(BrowtherIntroPalette.sage)
        Text(Strings.BrowtherIntro.demoSiteName)
          .font(.system(size: 13, weight: .semibold))
        Spacer()
        HStack(spacing: 4) {
          Image(systemName: "shield.fill")
          Text(Strings.BrowtherIntro.demoBlockedCount)
        }
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(BrowtherIntroPalette.halal)
      }
      .padding(.horizontal, 12)
      .frame(height: 44)
      .background(Color(UIColor.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
      VStack(alignment: .leading, spacing: 9) {
        LinearGradient(
          colors: [Color(UIColor(rgb: 0xE7C9A0)), Color(UIColor(rgb: 0xC98F5B))],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
        .frame(height: 70)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        ForEach([0.7, 1.0, 0.85], id: \.self) { ratio in
          Capsule()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .scaleEffect(x: ratio, anchor: .leading)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(12)
    .frame(maxWidth: .infinity)
    .frame(height: 230)
    .background(
      Color(UIColor.systemBackground),
      in: UnevenRoundedRectangle(
        topLeadingRadius: 20,
        bottomLeadingRadius: 0,
        bottomTrailingRadius: 0,
        topTrailingRadius: 20,
        style: .continuous
      )
    )
    .shadow(color: .black.opacity(0.18), radius: 12, y: -6)
  }
}

// MARK: - 6 · Canaux dev&din

/// Dernière étape : ce qu'on recevra, montré comme on le recevra — deux
/// notifications. Pendant l'accès anticipé, elle annonce la sortie des deux
/// moteurs ; ensuite, elle reprend le texte de l'étape historique.
struct BrowtherIntroChannelsStep: View {
  @ObservedObject var model: BrowtherIntroModel
  @State private var appeared = false

  var body: some View {
    BrowtherIntroLayout(
      title: model.isEarlyAccess
        ? Strings.BrowtherIntro.channelsSoonTitle
        : Strings.FocusOnboarding.followChannelsScreenTitle,
      subtitle: model.isEarlyAccess
        ? Strings.BrowtherIntro.channelsSoonDescription
        : Strings.FocusOnboarding.followChannelsScreenDescription,
      footnote: AnyView(
        Text(verbatim: "إن شاء الله")
          .font(.system(size: 20, weight: .semibold))
          .foregroundStyle(BrowtherIntroPalette.sage)
      )
    ) {
      ZStack {
        LinearGradient(
          colors: [Color(UIColor(rgb: 0x0A1B24)), Color(UIColor(rgb: 0x08161E))],
          startPoint: .top,
          endPoint: .bottom
        )
        VStack(spacing: 8) {
          Spacer(minLength: 0)
          notification(
            title: "dev&din",
            body: Strings.BrowtherIntro.notifBlur,
            icon: "browther-devndin-logo",
            template: false,
            delay: 0.35
          )
          notification(
            title: "Browther",
            body: Strings.BrowtherIntro.notifMusic,
            icon: "browther.shield.bar",
            template: true,
            delay: 0.75
          )
        }
        .padding(12)
      }
      .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
      .onAppear { appeared = true }
    } actions: {
      channelButton(
        .whatsApp,
        label: Strings.FocusOnboarding.followChannelsWhatsApp,
        color: Color(UIColor(rgb: 0x25D366)),
        symbol: "bubble.left.fill"
      )
      channelButton(
        .telegram,
        label: Strings.FocusOnboarding.followChannelsTelegram,
        color: Color(UIColor(rgb: 0x229ED9)),
        symbol: "paperplane.fill"
      )
      Text(Strings.FocusOnboarding.followChannelsSameContent)
        .font(.footnote)
        .multilineTextAlignment(.center)
        .foregroundStyle(Color(UIColor.tertiaryLabel))
        .padding(.top, 2)
      Button(Strings.FocusOnboarding.startBrowseActionButtonTitle) {
        model.finish()
      }
      .buttonStyle(BrowtherIntroOutlineButtonStyle())
    }
  }

  private func notification(
    title: String,
    body: String,
    icon: String,
    template: Bool,
    delay: Double
  ) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(icon, bundle: .module)
        .resizable()
        .renderingMode(template ? .template : .original)
        .aspectRatio(contentMode: .fit)
        .frame(width: 26, height: 22)
        .foregroundStyle(BrowtherIntroPalette.sage)
        .frame(width: 38, height: 38)
        .background(Color(UIColor(rgb: 0x0F100E)), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.system(size: 13.5, weight: .semibold))
        Text(body)
          .font(.system(size: 13))
          .lineLimit(2)
          .foregroundStyle(BrowtherIntroPalette.inkSoft)
      }
      Spacer(minLength: 0)
    }
    .padding(11)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    .offset(y: appeared ? 0 : -18)
    .opacity(appeared ? 1 : 0)
    .animation(.snappy(duration: 0.55, extraBounce: 0.15).delay(delay), value: appeared)
  }

  private func channelButton(
    _ channel: BrowtherIntroChannel,
    label: String,
    color: Color,
    symbol: String
  ) -> some View {
    Button {
      model.openChannel(channel)
    } label: {
      HStack(spacing: 12) {
        Image(systemName: symbol)
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(color)
          .frame(width: 28, height: 28)
          .background(Color.white, in: Circle())
        Text(label)
          .font(.callout.weight(.semibold))
        Spacer()
        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .semibold))
          .opacity(0.8)
      }
      .foregroundStyle(.white)
      .padding(.horizontal, 14)
      .frame(height: 54)
      .background(color, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    .buttonStyle(.plain)
  }
}

/// Sortie de la dernière étape : un contour, pas un aplat — ce sont les canaux
/// l'action de l'écran (même hiérarchie que l'étape historique).
struct BrowtherIntroOutlineButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.callout.weight(.semibold))
      .foregroundStyle(BrowtherIntroPalette.inkSoft)
      .frame(maxWidth: .infinity, minHeight: 48)
      .background {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .strokeBorder(BrowtherIntroPalette.inkSoft.opacity(0.55), lineWidth: 1.5)
      }
      .opacity(configuration.isPressed ? 0.7 : 1)
  }
}
