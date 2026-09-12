// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BraveStrings
import BraveUI
import MediaPlayer
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
    // ⚠️ Le fond passe par `GeometryReader` + `.clipped()`, jamais par un
    // `ZStack` : une image en `.fill` sans taille imposée propose sa propre
    // largeur au conteneur, et tout l'écran s'élargit avec elle. C'est ce qui
    // faisait déborder le titre et les trois protections (recette 2026-09-12).
    GeometryReader { proxy in
      VStack(spacing: 0) {
        Image("browther.app.icon", bundle: .module)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(width: 66, height: 66)
          .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
          .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
          // La barre de progression occupe le haut : le logo commence en
          // dessous, sinon il passe derrière elle.
          .padding(.top, 96)
        verse
          .padding(.top, 22)
        Spacer(minLength: 16)
        Text(Strings.BrowtherIntro.welcomeTitle)
          .font(.system(size: 29, weight: .semibold))
          .multilineTextAlignment(.center)
          .foregroundStyle(.white)
          .fixedSize(horizontal: false, vertical: true)
        protections
          .padding(.top, 18)
        Button(Strings.BrowtherIntro.startButton) {
          model.advance()
        }
        .buttonStyle(BrowtherIntroLightButtonStyle())
        .padding(.top, 18)
        BrowtherIntroSignature()
          .padding(.top, 14)
          .padding(.bottom, 26)
      }
      .padding(.horizontal, 20)
      .frame(width: proxy.size.width, height: proxy.size.height)
      .background {
        backgroundLayer
          .frame(width: proxy.size.width, height: proxy.size.height)
          .clipped()
      }
    }
    // Haut ET bas : sans le bas, une bande noire restait sous la signature,
    // à l'endroit de la barre d'accueil.
    .ignoresSafeArea()
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
  }

  private var verse: some View {
    VStack(spacing: 10) {
      // Texte uthmani exact (Coran 17:36, seconde moitié) — ⛔ ne jamais le
      // ressaisir à la main : il vient d'une source unique, cf.
      // `private/design/intro-iphone/verse.txt`. La police est celle du
      // muṣḥaf : voir `BrowtherIntroFont`.
      //
      // ⚠️ Édition **quran-uthmani-quran-academy**, pas `quran-uthmani`
      // (Tanzil). Cette dernière accole un `U+06ED SMALL LOW MEEM` à chaque
      // tanwīn fatḥ suivi d'alif — 99 versets sur 111 rien que dans cette
      // sourate : une convention d'encodage, pas un signe d'iqlāb. Amiri le
      // dessine comme un vrai mīm sous la ligne, et il saute aux yeux hors
      // d'un muṣḥaf complet. L'édition académique écrit la fatḥatan ouverte
      // du muṣḥaf imprimé (U+08F0), que la police couvre entièrement.
      Text(verbatim: "إِنَّ ٱلسَّمۡعَ وَٱلۡبَصَرَ وَٱلۡفُؤَادَ كُلُّ أُو۟لَـٰۤىِٕكَ كَانَ عَنۡهُ مَسۡـُٔولࣰا")
        .font(BrowtherIntroFont.quran(size: 22))
        .lineSpacing(14)
        .multilineTextAlignment(.center)
        .environment(\.layoutDirection, .rightToLeft)
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.5), radius: 10)
        .fixedSize(horizontal: false, vertical: true)
      Text(Strings.BrowtherIntro.verseTranslation)
        .font(.system(size: 15.5, design: .serif))
        .italic()
        .multilineTextAlignment(.center)
        .foregroundStyle(.white.opacity(0.84))
        .fixedSize(horizontal: false, vertical: true)
      Text(Strings.BrowtherIntro.verseReference)
        .font(.system(size: 10.5, weight: .semibold))
        .tracking(1.6)
        .textCase(.uppercase)
        .foregroundStyle(BrowtherIntroPalette.sage)
    }
    .padding(.horizontal, 6)
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
        .lineLimit(1)
        .minimumScaleFactor(0.8)
      HStack(spacing: 5) {
        BrowtherIntroStatusDot(soon: soon)
        Text(soon ? Strings.BrowtherIntro.statusSoon : Strings.BrowtherIntro.statusActive)
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(.white.opacity(0.72))
      }
      // Seconde ligne : l'invocation pour ce qui arrive, « dès maintenant »
      // pour ce qui marche déjà — sinon la colonne active paraît plus courte.
      Text(soon ? "إن شاء الله" : Strings.BrowtherIntro.statusActiveDetail)
        .font(.system(size: 11))
        .foregroundStyle(BrowtherIntroPalette.sage)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, 4)
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

/// Le premier des trois écrans qui **demandent un geste** : l'interrupteur doit
/// passer sur ON pour que le bouton s'allume. On ne laisse pas franchir un
/// écran de démonstration sans avoir rien vu fonctionner.
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
          icon: "browther.shield.bar",
          title: Strings.BrowtherIntro.shieldsName,
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
      BrowtherIntroAdvanceButton(
        title: Strings.FocusOnboarding.continueButtonTitle,
        enabled: model.adsDemoOn
      ) {
        model.advance()
      }
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
      // ⛔ Tant que le floutage est éteint, les vignettes restent **entièrement
      // couvertes**. Montrer l'« avant » en clair, ce serait afficher
      // exactement ce que l'app existe pour ne plus montrer — et la personne
      // n'a encore rien demandé. Le geste lève le rideau sur le voile ciblé :
      // la démonstration y gagne, on passe de « tout caché » à « juste ce
      // qu'il faut ».
      let mode: BrowtherIntroVeilMode =
        model.blurDemoOn
        ? .target(model.blurTarget)
        : (model.blurDemoEverOn ? .nothing : .everything)
      VStack(spacing: 10) {
        BrowtherIntroVideoTile(mode: mode)
        BrowtherIntroPhotoTile(mode: mode)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .overlay {
        if !model.blurDemoOn, !model.blurDemoEverOn {
          VStack(spacing: 8) {
            Image("basarunaa.icon", bundle: .module)
              .resizable()
              .renderingMode(.template)
              .aspectRatio(contentMode: .fit)
              .frame(width: 26, height: 26)
            Text(Strings.BrowtherIntro.blurCurtain)
              .font(.footnote.weight(.semibold))
          }
          .foregroundStyle(.white)
          .padding(.horizontal, 16)
          .padding(.vertical, 12)
          .background(Color.black.opacity(0.45), in: Capsule())
          .transition(.opacity)
          .allowsHitTesting(false)
        }
      }
      .animation(.smooth(duration: 0.3), value: model.blurDemoOn)
      .sensoryFeedback(.selection, trigger: model.blurTarget)
    } actions: {
      HStack(spacing: 10) {
        choice(
          .women,
          label: Strings.BrowtherIntro.blurWomen,
          symbol: "figure.stand.dress",
          tint: BrowtherIntroPalette.feminine
        )
        choice(
          .men,
          label: Strings.BrowtherIntro.blurMen,
          symbol: "figure.stand",
          tint: BrowtherIntroPalette.masculine
        )
        choice(
          .both,
          label: Strings.BrowtherIntro.blurBoth,
          symbol: "figure.2",
          tint: BrowtherIntroPalette.sage
        )
      }
      BrowtherIntroSwitchRow(
        icon: "basarunaa.icon",
        title: "Basarunaa",
        offLabel: Strings.BrowtherIntro.blurSwitchOff,
        onLabel: Strings.BrowtherIntro.blurSwitchOn,
        isOn: Binding(
          get: { model.blurDemoOn },
          set: { _ in model.toggleDemo(for: .blur) }
        )
      )
      BrowtherIntroAdvanceButton(
        title: Strings.FocusOnboarding.continueButtonTitle,
        enabled: model.blurDemoOn
      ) {
        model.activate(.basarunaa)
      }
    }
  }

  /// Chaque cible a sa teinte — rose, bleu — pour que le choix se lise avant
  /// d'être lu. La case sélectionnée n'est plus un cadre vert de plus.
  private func choice(
    _ target: BrowtherBlurTarget,
    label: String,
    symbol: String,
    tint: Color
  ) -> some View {
    let selected = model.blurTarget == target
    return Button {
      model.choose(target)
    } label: {
      VStack(spacing: 7) {
        Image(systemName: symbol)
          .font(.system(size: 21))
        Text(label)
          .font(.system(size: 13.5, weight: .semibold))
          .lineLimit(1)
          .minimumScaleFactor(0.8)
      }
      .foregroundStyle(selected ? tint : BrowtherIntroPalette.inkSoft)
      .frame(maxWidth: .infinity, minHeight: 74)
      .background(
        selected ? tint.opacity(0.16) : Color(UIColor.secondarySystemGroupedBackground),
        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .strokeBorder(
            selected ? tint : Color.primary.opacity(0.08),
            lineWidth: selected ? 2 : 1
          )
      }
      .overlay(alignment: .topTrailing) {
        if selected {
          Image(systemName: "checkmark")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Color(UIColor.systemBackground))
            .frame(width: 20, height: 20)
            .background(tint, in: Circle())
            .padding(7)
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
      VStack(spacing: 10) {
        VStack(spacing: 0) {
          player
          BrowtherIntroLanes(musicRemoved: model.musicDemoOn)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(UIColor(rgb: 0x1B201C)))
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(alignment: .topTrailing) {
          BrowtherStampPair(isOn: model.musicDemoOn)
            .offset(x: 10, y: -14)
        }
        BrowtherIntroSwitchRow(
          icon: "sawtunaa.icon",
          title: "Sawtunaa",
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
        // position dans le morceau. S'il n'y a encore rien à entendre, il
        // lance l'extrait — c'est le geste qui décide, jamais l'écran.
        audio.apply(musicRemoved: removed)
        if removed { audio.play() }
      }
      .onDisappear { audio.stop() }
    } actions: {
      BrowtherIntroAdvanceButton(
        title: Strings.FocusOnboarding.continueButtonTitle,
        enabled: model.musicDemoOn
      ) {
        // ⛔ Le son s'arrête ici, pas seulement dans `onDisappear` : la feuille
        // de l'accès anticipé garde l'écran monté, et l'extrait continuerait à
        // jouer derrière elle.
        audio.stop()
        model.activate(.sawtunaa)
      }
    }
  }

  /// Le lecteur : un bouton, une barre qu'on peut déplacer, et l'état du son de
  /// l'appareil. ⚠️ Rien ne démarre tout seul — arriver sur un écran qui parle
  /// tout seul dans un lieu public est une trahison.
  private var player: some View {
    ZStack {
      RadialGradient(
        colors: [Color(UIColor(rgb: 0x2F3C31)), Color(UIColor(rgb: 0x151916))],
        center: .init(x: 0.5, y: 0.2),
        startRadius: 10,
        endRadius: 260
      )
      VStack(spacing: 12) {
        Button {
          audio.toggle()
        } label: {
          Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(Color(UIColor(rgb: 0x151916)))
            .frame(width: 62, height: 62)
            .background(Color(UIColor(rgb: 0xE7E2D5)), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
          audio.isPlaying
            ? Strings.BrowtherIntro.musicPause
            : Strings.BrowtherIntro.musicListen
        )
        BrowtherIntroScrubber(progress: audio.progress) { scrubbing in
          audio.setScrubbing(scrubbing)
        } onSeek: { fraction in
          audio.seek(to: fraction)
        }
        .frame(height: 26)
        .padding(.horizontal, 24)
        volumeControl
      }
      .padding(.vertical, 18)
    }
    .frame(maxHeight: .infinity)
    .animation(.smooth(duration: 0.3), value: audio.systemVolume)
  }
}

extension BrowtherIntroMusicStep {
  /// Le son de l'**appareil** : son niveau, et de quoi le régler sans quitter
  /// l'écran. ⚠️ Le curseur est celui du système (`MPVolumeView`) : régler
  /// `outputVolume` par code est interdit, et les touches physiques resteraient
  /// la seule voie.
  @ViewBuilder
  fileprivate var volumeControl: some View {
    let muted = audio.systemVolume <= 0.001
    VStack(spacing: 5) {
      HStack(spacing: 10) {
        Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(muted ? BrowtherEarlyAccess.amber : Color.white.opacity(0.72))
        BrowtherIntroSystemVolumeSlider()
          .frame(height: 22)
        Text(verbatim: "\(Int((Double(audio.systemVolume) * 100).rounded())) %")
          .font(.caption.weight(.semibold))
          .monospacedDigit()
          .lineLimit(1)
          .fixedSize()
          .foregroundStyle(Color.white.opacity(0.72))
          // 100 % est le cas le plus large : sans place pour lui, il passait
          // sur deux lignes alors que 40 % tenait sur une.
          .frame(width: 46, alignment: .trailing)
      }
      if muted {
        Text(Strings.BrowtherIntro.volumeMuted)
          .font(.caption.weight(.medium))
          .multilineTextAlignment(.center)
          .foregroundStyle(BrowtherEarlyAccess.amber)
          .fixedSize(horizontal: false, vertical: true)
          .transition(.opacity)
      }
    }
    .padding(.horizontal, 22)
  }
}

/// Le curseur du volume **système**.
///
/// ⚠️ `AVAudioSession.outputVolume` est en lecture seule : le seul moyen
/// officiel de le régler depuis une app est `MPVolumeView`, qui héberge le
/// curseur du système. On lui retire son bouton de sortie audio et on le
/// repeint aux couleurs de l'écran ; il reste le curseur d'iOS.
struct BrowtherIntroSystemVolumeSlider: UIViewRepresentable {
  func makeUIView(context: Context) -> MPVolumeView {
    let view = MPVolumeView(frame: .zero)
    view.showsRouteButton = false
    view.tintColor = UIColor(rgb: 0xE7E2D5)
    for case let slider as UISlider in view.subviews {
      slider.minimumTrackTintColor = UIColor(rgb: 0xE7E2D5)
      slider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.18)
    }
    return view
  }

  func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

/// La barre de lecture, déplaçable au doigt. Les deux pistes bougent ensemble —
/// c'est ce qui fait que l'interrupteur compare bien le même instant.
struct BrowtherIntroScrubber: View {
  let progress: Double
  /// Appelé **une seule fois**, quand le doigt se lève.
  ///
  /// ⛔ Ne pas déplacer la tête de lecture à chaque mouvement : écrire
  /// `currentTime` sur deux `AVAudioPlayer` soixante fois par seconde les fait
  /// re-tamponner, et la barre saccade — c'est ce qu'on a vu à la recette. Le
  /// curseur suit le doigt **en local**, le son ne bouge qu'au relâcher.
  let onScrub: (Bool) -> Void
  let onSeek: (Double) -> Void

  @State private var dragged: Double?

  var body: some View {
    GeometryReader { proxy in
      let width = proxy.size.width
      let shown = dragged ?? progress
      ZStack(alignment: .leading) {
        Capsule()
          .fill(Color.white.opacity(0.18))
          .frame(height: 5)
        Capsule()
          .fill(Color(UIColor(rgb: 0xE7E2D5)))
          .frame(width: max(5, width * shown), height: 5)
        Circle()
          .fill(Color(UIColor(rgb: 0xE7E2D5)))
          .frame(width: dragged == nil ? 14 : 18, height: dragged == nil ? 14 : 18)
          .offset(x: max(0, width * shown - (dragged == nil ? 7 : 9)))
          .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
          .animation(.smooth(duration: 0.15), value: dragged == nil)
      }
      .frame(maxHeight: .infinity)
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            if dragged == nil { onScrub(true) }
            dragged = min(max(0, value.location.x / width), 1)
          }
          .onEnded { value in
            let target = min(max(0, value.location.x / width), 1)
            dragged = nil
            onScrub(false)
            onSeek(target)
          }
      )
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
        conversation
        browserSheet
          .offset(y: sheetUp ? 0 : 340)
      }
      .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
      .onAppear {
        withAnimation(.smooth(duration: 0.65).delay(0.6)) {
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

  /// Une conversation, reconnaissable comme telle : barre de contact, fond
  /// propre à la messagerie, bulles vertes et blanches, horodatage. Sans ces
  /// repères, deux rectangles gris ne disent pas « message reçu ».
  private var conversation: some View {
    VStack(spacing: 0) {
      HStack(spacing: 9) {
        Image(systemName: "chevron.left")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(Color(UIColor(rgb: 0x25D366)))
        Circle()
          .fill(Color(UIColor(rgb: 0xCFD6CB)))
          .frame(width: 30, height: 30)
          .overlay {
            Image(systemName: "person.2.fill")
              .font(.system(size: 13))
              .foregroundStyle(Color(UIColor(rgb: 0x6B7A68)))
          }
        VStack(alignment: .leading, spacing: 1) {
          Text(Strings.BrowtherIntro.demoContactName)
            .font(.system(size: 14, weight: .semibold))
          Text(Strings.BrowtherIntro.demoMessagingApp)
            .font(.system(size: 11))
            .foregroundStyle(BrowtherIntroPalette.inkSoft)
        }
        Spacer()
        Image(systemName: "video.fill")
          .font(.system(size: 13))
          .foregroundStyle(BrowtherIntroPalette.inkSoft)
        Image(systemName: "phone.fill")
          .font(.system(size: 13))
          .foregroundStyle(BrowtherIntroPalette.inkSoft)
      }
      .padding(.horizontal, 12)
      .frame(height: 46)
      .background(Color(UIColor.secondarySystemGroupedBackground))
      VStack(alignment: .leading, spacing: 6) {
        bubble(Strings.BrowtherIntro.demoMessageIncoming)
        linkBubble
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .padding(12)
      .background {
        BrowtherIntroChatWallpaper()
      }
    }
  }

  private func bubble(_ text: String) -> some View {
    Text(text)
      .font(.system(size: 14.5))
      .foregroundStyle(BrowtherIntroPalette.ink)
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(
        Color(UIColor.systemBackground),
        in: UnevenRoundedRectangle(
          topLeadingRadius: 14,
          bottomLeadingRadius: 3,
          bottomTrailingRadius: 14,
          topTrailingRadius: 14,
          style: .continuous
        )
      )
      .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// La bulle qui porte le lien : c'est elle qu'on tape, et c'est de là que
  /// part la feuille du navigateur.
  private var linkBubble: some View {
    VStack(alignment: .leading, spacing: 0) {
      LinearGradient(
        colors: [Color(UIColor(rgb: 0xE7C9A0)), Color(UIColor(rgb: 0xC98F5B))],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      .frame(height: 58)
      VStack(alignment: .leading, spacing: 2) {
        Text(Strings.BrowtherIntro.demoArticleTitle)
          .font(.system(size: 13.5, weight: .semibold))
          .foregroundStyle(BrowtherIntroPalette.ink)
        Text(Strings.BrowtherIntro.demoSiteName)
          .font(.system(size: 12))
          .foregroundStyle(BrowtherIntroPalette.inkSoft)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 7)
    }
    .background(Color(UIColor.systemBackground))
    .clipShape(
      UnevenRoundedRectangle(
        topLeadingRadius: 14,
        bottomLeadingRadius: 3,
        bottomTrailingRadius: 14,
        topTrailingRadius: 14,
        style: .continuous
      )
    )
    .frame(maxWidth: 230, alignment: .leading)
  }

  /// Ce que devient le lien : Browther qui monte par-dessus la conversation,
  /// nommé, avec son icône et son compteur — c'est le « ouvert dans Browther »
  /// qu'on veut faire comprendre.
  /// Ce que devient le lien. ⚠️ Ça doit ressembler à un **navigateur** :
  /// en-tête nommé, barre d'adresse avec son cadenas, page en dessous, et le
  /// détail de ce que Browther vient de retirer. La version précédente était
  /// de la même couleur que la conversation — on ne voyait même pas la limite
  /// entre les deux.
  private var browserSheet: some View {
    VStack(spacing: 0) {
      Capsule()
        .fill(Color.primary.opacity(0.22))
        .frame(width: 34, height: 4)
        .padding(.top, 7)
      HStack(spacing: 8) {
        Image("browther.app.icon", bundle: .module)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(width: 19, height: 19)
          .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        Text(Strings.BrowtherIntro.demoOpenedIn)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(BrowtherIntroPalette.ink)
        Spacer()
        Image(systemName: "xmark")
          .font(.system(size: 11, weight: .bold))
          .foregroundStyle(BrowtherIntroPalette.inkSoft)
      }
      .padding(.horizontal, 14)
      .padding(.top, 8)
      .padding(.bottom, 8)
      // La barre d'adresse : le repère qui dit « navigateur » sans un mot.
      HStack(spacing: 6) {
        Image(systemName: "lock.fill")
          .font(.system(size: 9))
          .foregroundStyle(BrowtherIntroPalette.inkSoft)
        Text(Strings.BrowtherIntro.demoSiteName)
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(BrowtherIntroPalette.ink)
        Spacer()
        Image("browther.shield.bar", bundle: .module)
          .resizable()
          .renderingMode(.template)
          .aspectRatio(contentMode: .fit)
          .frame(width: 13, height: 13)
          .foregroundStyle(BrowtherIntroPalette.halalText)
      }
      .padding(.horizontal, 10)
      .frame(height: 32)
      .background(
        Color(UIColor.systemBackground),
        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
      )
      .padding(.horizontal, 12)
      // Ce que Browther vient de faire, nommé : sinon « 3 bloqués » ne dit pas
      // ce qui a été bloqué, et les deux autres moteurs n'existent pas.
      HStack(spacing: 6) {
        stat("browther.shield.bar", Strings.BrowtherIntro.demoStatAds)
        stat("sawtunaa.icon", Strings.BrowtherIntro.demoStatMusic)
        stat("basarunaa.icon", Strings.BrowtherIntro.demoStatImages)
      }
      .padding(.horizontal, 12)
      .padding(.top, 9)
      VStack(alignment: .leading, spacing: 8) {
        LinearGradient(
          colors: [Color(UIColor(rgb: 0xE7C9A0)), Color(UIColor(rgb: 0xC98F5B))],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
        .frame(height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        ForEach([0.7, 1.0, 0.85], id: \.self) { ratio in
          Capsule()
            .fill(Color.primary.opacity(0.1))
            .frame(height: 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .scaleEffect(x: ratio, anchor: .leading)
        }
      }
      .padding(.horizontal, 12)
      .padding(.top, 10)
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity)
    .frame(height: 240)
    // ⚠️ Le panneau doit se DÉTACHER de la conversation : même teinte des deux
    // côtés et on ne voyait plus la limite. Une surface élevée, un liseré net
    // et une ombre portée — les trois repères d'une feuille posée par-dessus.
    .background(
      Color(UIColor.secondarySystemGroupedBackground),
      in: UnevenRoundedRectangle(
        topLeadingRadius: 20,
        bottomLeadingRadius: 0,
        bottomTrailingRadius: 0,
        topTrailingRadius: 20,
        style: .continuous
      )
    )
    .overlay(alignment: .top) {
      UnevenRoundedRectangle(
        topLeadingRadius: 20,
        bottomLeadingRadius: 0,
        bottomTrailingRadius: 0,
        topTrailingRadius: 20,
        style: .continuous
      )
      .strokeBorder(Color.primary.opacity(0.22), lineWidth: 1)
    }
    .shadow(color: .black.opacity(0.55), radius: 20, y: -10)
  }

  private func stat(_ icon: String, _ label: String) -> some View {
    VStack(spacing: 4) {
      Image(icon, bundle: .module)
        .resizable()
        .renderingMode(.template)
        .aspectRatio(contentMode: .fit)
        .frame(width: 14, height: 14)
      Text(label)
        .font(.system(size: 9.5, weight: .semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
    .foregroundStyle(BrowtherIntroPalette.halalText)
    .frame(maxWidth: .infinity)
    .padding(.vertical, 7)
    .background(
      BrowtherIntroPalette.halalText.opacity(0.12),
      in: RoundedRectangle(cornerRadius: 10, style: .continuous)
    )
  }
}

// MARK: - 6 · Canaux dev&din

/// Dernière étape : Browther replacé dans l'écosystème, et les deux canaux où
/// l'on annonce ce qui sort.
struct BrowtherIntroChannelsStep: View {
  @ObservedObject var model: BrowtherIntroModel

  var body: some View {
    BrowtherIntroLayout(
      title: model.isEarlyAccess
        ? Strings.BrowtherIntro.channelsSoonTitle
        : Strings.FocusOnboarding.followChannelsScreenTitle,
      subtitle: model.isEarlyAccess
        ? Strings.BrowtherIntro.channelsSoonDescription
        : Strings.FocusOnboarding.followChannelsScreenDescription
    ) {
      // Le visuel de l'écosystème, celui de l'étape historique : il montre
      // d'un coup d'œil que Browther a des voisins.
      Image(devndinImageName, bundle: BrowtherOnboardingAssets.bundle)
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .frame(maxHeight: .infinity, alignment: .center)
    } actions: {
      channelButton(
        .whatsApp,
        label: Strings.FocusOnboarding.followChannelsWhatsApp,
        color: Color(UIColor(rgb: 0x25D366)),
        image: "channel-whatsapp"
      )
      channelButton(
        .telegram,
        label: Strings.FocusOnboarding.followChannelsTelegram,
        color: Color(UIColor(rgb: 0x229ED9)),
        image: "channel-telegram"
      )
      Text(Strings.BrowtherIntro.channelsSameContent)
        .font(.footnote)
        .multilineTextAlignment(.center)
        .foregroundStyle(Color(UIColor.tertiaryLabel))
        .padding(.top, 2)
        // Cette mention appartient aux deux boutons du dessus : l'espace
        // au-dessous le dit.
        .padding(.bottom, 14)
      Button(Strings.FocusOnboarding.startBrowseActionButtonTitle) {
        model.finish()
      }
      .buttonStyle(BrowtherIntroOutlineButtonStyle())
    }
  }

  /// Le visuel existe en français, en anglais et en arabe — on prend celui de
  /// la langue de l'appareil, comme l'étape historique.
  private var devndinImageName: String {
    switch Locale.current.language.languageCode?.identifier {
    case "fr": return "devndin-channels-fr"
    case "ar": return "devndin-channels-ar"
    default: return "devndin-channels-en"
    }
  }

  private func channelButton(
    _ channel: BrowtherIntroChannel,
    label: String,
    color: Color,
    image: String
  ) -> some View {
    Button {
      model.openChannel(channel)
    } label: {
      HStack(spacing: 12) {
        Image(image, bundle: BrowtherOnboardingAssets.bundle)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(width: 22, height: 22)
          .frame(width: 30, height: 30)
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

/// Le fond de la conversation.
///
/// C'est le fond de WhatsApp, **choix de Karim (2026-09-12)** : la scène n'agit
/// pas sur le service, elle illustre un lien reçu dans une messagerie, et le
/// repère visuel fait tout le travail. ⚠️ Ça reste un motif qui ne nous
/// appartient pas : s'il fallait un jour le retirer, la version dessinée à la
/// main est dans l'historique de ce fichier (commit « Introduction iOS : vrai
/// flou CoreImage… »).
struct BrowtherIntroChatWallpaper: View {
  var body: some View {
    ZStack {
      BrowtherIntroPalette.canvas
      Image("browther-chat-wallpaper", bundle: .module)
        .resizable(resizingMode: .tile)
    }
    .allowsHitTesting(false)
  }
}
