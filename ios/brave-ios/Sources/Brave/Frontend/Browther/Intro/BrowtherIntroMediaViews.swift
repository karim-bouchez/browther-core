// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AVFoundation
import AVKit
import BraveStrings
import CoreImage
import SwiftUI
import UIKit

// MARK: - Photo

/// La vignette « image » : la photo nette, et par-dessus **la même photo
/// floutée**, découpée par le contour du corps.
///
/// C'est la composition du moteur (`blur-compositor.ts`) : le flou est un vrai
/// gaussien posé dans les pixels de la photo, pas une matière translucide. La
/// version floutée est calculée une seule fois ; seul le masque bouge quand on
/// change de cible, ce qui rend la bascule instantanée et animable.
struct BrowtherIntroPhotoTile: View {
  let mode: BrowtherIntroVeilMode

  var body: some View {
    ZStack {
      if let sharp = BrowtherIntroMedia.photoImage {
        Image(uiImage: sharp)
          .resizable()
          .aspectRatio(contentMode: .fill)
        if let blurred = BrowtherIntroMedia.photoBlurredImage {
          GeometryReader { proxy in
            Image(uiImage: blurred)
              .resizable()
              .aspectRatio(contentMode: .fill)
              .frame(width: proxy.size.width, height: proxy.size.height)
              .mask {
                BrowtherIntroVeilMask(
                  persons: BrowtherIntroMedia.photoPersons,
                  mode: mode,
                  sourceWidth: 1200
                )
              }
          }
        }
      } else {
        Color(UIColor.secondarySystemGroupedBackground)
      }
    }
    .aspectRatio(16.0 / 9.0, contentMode: .fit)
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(alignment: .topLeading) {
      BrowtherIntroTileTag(symbol: "photo", label: Strings.BrowtherIntro.tileImage)
    }
  }
}

/// Le masque du voile : les contours pré-calculés, adoucis de 10 px du média.
struct BrowtherIntroVeilMask: View {
  let persons: [BrowtherIntroMedia.Person]
  let mode: BrowtherIntroVeilMode
  /// Largeur du média d'origine, pour mettre l'adoucissement à l'échelle.
  let sourceWidth: Double

  var body: some View {
    GeometryReader { proxy in
      if mode == .nothing {
        Color.clear
      } else if mode == .everything {
        Color.white
      } else {
        let visible = persons.filter { $0.isBlurred(for: mode.target) }
        Canvas { context, size in
          for person in visible {
            context.fill(person.path(in: size), with: .color(.white))
          }
        }
        .blur(radius: CGFloat(max(2, 10 * Double(proxy.size.width) / sourceWidth)))
      }
    }
    .animation(.easeOut(duration: 0.3), value: mode)
  }
}

// MARK: - Vidéo

/// La vignette « vidéo » : le voile suit les personnes, image par image.
///
/// Ici le flou ne peut pas être posé par-dessus — on ne peut pas afficher deux
/// fois la même couche vidéo. Il est donc calculé **dans le flux**, par une
/// `AVVideoComposition` qui rejoue le compositeur sur chaque image. La cible
/// vit dans un objet partagé : la changer ne recrée pas la composition, elle
/// est relue à l'image suivante.
struct BrowtherIntroVideoTile: View {
  let mode: BrowtherIntroVeilMode

  var body: some View {
    BrowtherIntroVeiledVideo(mode: mode)
      .aspectRatio(16.0 / 9.0, contentMode: .fit)
      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      .overlay(alignment: .topLeading) {
        BrowtherIntroTileTag(symbol: "play.fill", label: Strings.BrowtherIntro.tileVideo)
      }
  }
}

struct BrowtherIntroTileTag: View {
  let symbol: String
  let label: String

  var body: some View {
    HStack(spacing: 5) {
      Image(systemName: symbol)
        .font(.system(size: 10, weight: .semibold))
      Text(label)
        .font(.system(size: 11.5, weight: .semibold))
    }
    .foregroundStyle(.white)
    .padding(.horizontal, 9)
    .padding(.vertical, 5)
    .background(.ultraThinMaterial.opacity(0.9), in: Capsule())
    .environment(\.colorScheme, .dark)
    .padding(10)
  }
}

/// La cible courante, lisible depuis le fil de rendu vidéo.
final class BrowtherIntroVeilTarget: @unchecked Sendable {
  private let lock = NSLock()
  private var value: BrowtherIntroVeilMode = .everything

  var current: BrowtherIntroVeilMode {
    get {
      lock.lock()
      defer { lock.unlock() }
      return value
    }
    set {
      lock.lock()
      value = newValue
      lock.unlock()
    }
  }
}

/// Lecture en boucle, muette, sans commandes : c'est une illustration, pas un
/// lecteur.
struct BrowtherIntroVeiledVideo: UIViewRepresentable {
  let mode: BrowtherIntroVeilMode

  func makeUIView(context: Context) -> PlayerView {
    let view = PlayerView()
    context.coordinator.attach(to: view)
    context.coordinator.veilTarget.current = mode
    return view
  }

  func updateUIView(_ uiView: PlayerView, context: Context) {
    context.coordinator.veilTarget.current = mode
  }

  static func dismantleUIView(_ uiView: PlayerView, coordinator: Coordinator) {
    coordinator.stop()
  }

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  final class PlayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
  }

  @MainActor
  final class Coordinator {
    let veilTarget = BrowtherIntroVeilTarget()
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?

    func attach(to view: PlayerView) {
      guard let url = BrowtherIntroMedia.videoURL else { return }
      let asset = AVURLAsset(url: url)
      let item = AVPlayerItem(asset: asset)
      item.videoComposition = Self.makeComposition(asset: asset, target: veilTarget)
      let player = AVQueuePlayer(playerItem: item)
      player.isMuted = true
      player.actionAtItemEnd = .advance
      looper = AVPlayerLooper(player: player, templateItem: item)
      view.playerLayer.player = player
      view.playerLayer.videoGravity = .resizeAspectFill
      player.play()
      self.player = player
    }

    /// Le compositeur, image par image. `compositionTime` donne l'instant :
    /// c'est lui qui choisit les contours, donc le voile ne peut pas prendre
    /// une image de retard sur la personne qu'il couvre.
    private static func makeComposition(
      asset: AVAsset,
      target: BrowtherIntroVeilTarget
    ) -> AVVideoComposition {
      AVMutableVideoComposition(asset: asset) { request in
        let source = request.sourceImage
        let persons = BrowtherIntroMedia.persons(at: request.compositionTime.seconds)
        let output = BrowtherIntroVeil.composite(
          source,
          persons: persons,
          mode: target.current,
          // 10 px du média : le clip est encodé à 900 px de large.
          feather: 10 * Double(source.extent.width) / 900
        )
        request.finish(with: output, context: nil)
      }
    }

    func stop() {
      player?.pause()
      looper = nil
      player = nil
    }
  }
}

// MARK: - Son

/// Les deux versions du même extrait, jouées **en parallèle** et à la même
/// position : l'interrupteur ne relance rien, il change de canal. Sans ça, la
/// comparaison porterait sur deux instants différents du morceau.
///
/// ⚠️ La catégorie de session est obligatoire : par défaut une app est en
/// `soloAmbient`, où le bouton silencieux de l'iPhone coupe tout — l'extrait se
/// jouait sans qu'on entende rien (recette du 2026-09-12).
///
/// ⚠️ **Rien de l'audio ne passe par le fil principal** : session, lecteurs et
/// lecture vivent dans `BrowtherIntroAudioEngine`, sur sa file ; cette classe ne
/// garde que ce que l'écran affiche. Faits dans le geste, ils figeaient
/// l'interrupteur et les confettis au premier ON — mesuré sur iPhone 13 :
/// ~450 ms pour créer et préparer les deux lecteurs, puis ~100 ms pour le
/// premier `play(atTime:)` (cf. `ONBOARDING-SPEC.md` § 11.3).
@MainActor
final class BrowtherIntroAudio: ObservableObject {
  /// Ce que la personne a demandé : vrai dès le geste, avant que le son parte,
  /// pour que le bouton réponde tout de suite.
  @Published private(set) var isPlaying = false
  @Published private(set) var progress: Double = 0
  @Published private(set) var duration: Double = 0
  /// Le volume de sortie de l'iPhone. À zéro, l'extrait joue sans qu'on
  /// l'entende : l'écran doit le dire plutôt que de laisser croire à une panne.
  @Published private(set) var systemVolume: Float = 1

  private let engine = BrowtherIntroAudioEngine()
  private var ticker: Timer?
  private var volumeObservation: NSKeyValueObservation?
  /// Vrai pendant qu'on déplace la tête de lecture : le rafraîchissement
  /// automatique doit se taire, sinon il repousse le curseur sous le doigt et
  /// la barre saccade.
  private var isScrubbing = false

  init() {
    let session = AVAudioSession.sharedInstance()
    systemVolume = session.outputVolume
    volumeObservation = session.observe(\.outputVolume, options: [.new]) { [weak self] _, change in
      guard let volume = change.newValue else { return }
      Task { @MainActor in self?.systemVolume = volume }
    }
  }

  deinit {
    volumeObservation?.invalidate()
  }

  /// À l'arrivée sur l'écran : ouvre les deux fichiers, sans rien activer.
  func load() {
    engine.load()
  }

  /// Lecture et pause. Rien ne démarre tout seul : l'extrait part au geste de
  /// la personne — le bouton, ou l'interrupteur de l'écran.
  func play() {
    guard !isPlaying else { return }
    isPlaying = true
    engine.play { [weak self] duration in
      guard let self else { return }
      guard let duration else {
        self.isPlaying = false
        return
      }
      self.duration = duration
      // Une pause arrivée pendant le démarrage est passée derrière lui dans la
      // file : le son est déjà arrêté, la barre ne doit pas repartir.
      if self.isPlaying { self.startTicker() }
    }
  }

  func pause() {
    engine.pause()
    isPlaying = false
    stopTicker()
  }

  func toggle() {
    isPlaying ? pause() : play()
  }

  /// Le doigt est posé sur la barre : le rafraîchissement se tait, mais on ne
  /// touche pas encore au son.
  func setScrubbing(_ scrubbing: Bool) {
    isScrubbing = scrubbing
  }

  /// Déplacer la tête de lecture — sur les **deux** pistes, sinon la
  /// comparaison perd son sens. Appelé une seule fois, au relâcher.
  func seek(to fraction: Double) {
    let fraction = min(max(0, fraction), 0.999)
    engine.seek(to: fraction)
    progress = fraction
  }

  /// L'état de l'interrupteur. ⚠️ Il doit valoir aussi pour des lecteurs pas
  /// encore prêts : c'est le bug de la recette, la préparation remettait
  /// « avec musique » juste après que l'interrupteur eut demandé « sans ».
  func apply(musicRemoved: Bool) {
    engine.setMusicRemoved(musicRemoved)
  }

  func stop() {
    engine.stop()
    isPlaying = false
    progress = 0
    stopTicker()
  }

  private func startTicker() {
    ticker?.invalidate()
    ticker = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
      Task { @MainActor in
        guard let self, !self.isScrubbing else { return }
        self.engine.readProgress { [weak self] fraction in
          guard let self, self.isPlaying, !self.isScrubbing else { return }
          self.progress = fraction
        }
      }
    }
  }

  private func stopTicker() {
    ticker?.invalidate()
    ticker = nil
  }
}

/// Les deux lecteurs et la session audio, **confinés à une file** : tout ce qui
/// touche au son y passe, dans l'ordre des gestes. Une désactivation ne peut
/// donc jamais doubler l'activation qu'elle défait (la musique de la personne
/// resterait coupée), ni une pause le démarrage qu'elle interrompt.
private final class BrowtherIntroAudioEngine: @unchecked Sendable {
  /// Une seule file pour tous les écrans : revenir sur Musique recrée un
  /// moteur, qui ne doit pas activer la session avant que l'ancien l'ait rendue.
  private static let queue = DispatchQueue(
    label: "com.devndin.browther.intro-audio",
    qos: .userInitiated
  )

  // Ce qui suit n'est touché que depuis `queue`.
  private var before: AVAudioPlayer?
  private var after: AVAudioPlayer?
  private var isSessionActive = false
  private var musicRemoved = false

  /// ⛔ Ni `prepareToPlay` ni la session ici : on est à l'arrivée sur l'écran,
  /// et saisir le matériel audio couperait la musique de la personne avant tout
  /// geste.
  func load() {
    Self.queue.async { self.loadPlayers() }
  }

  /// Démarre l'extrait ; `completion` reçoit sa durée, ou `nil` si les fichiers
  /// manquent.
  func play(then completion: @escaping @Sendable @MainActor (Double?) -> Void) {
    Self.queue.async {
      let duration = self.start()
      Task { @MainActor in completion(duration) }
    }
  }

  func pause() {
    Self.queue.async {
      self.before?.pause()
      self.after?.pause()
    }
  }

  func stop() {
    Self.queue.async {
      for player in [self.before, self.after] {
        player?.stop()
        player?.currentTime = 0
      }
      guard self.isSessionActive else { return }
      self.isSessionActive = false
      try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
  }

  func seek(to fraction: Double) {
    Self.queue.async {
      guard let before = self.before, let after = self.after else { return }
      before.currentTime = fraction * before.duration
      after.currentTime = fraction * before.duration
    }
  }

  func setMusicRemoved(_ removed: Bool) {
    Self.queue.async {
      self.musicRemoved = removed
      self.applyVolumes()
    }
  }

  func readProgress(then completion: @escaping @Sendable @MainActor (Double) -> Void) {
    Self.queue.async {
      guard let before = self.before, before.duration > 0 else { return }
      let fraction = before.currentTime / before.duration
      Task { @MainActor in completion(fraction) }
    }
  }

  // MARK: Sur la file

  private func loadPlayers() {
    guard before == nil,
      let beforeURL = BrowtherIntroMedia.audioBeforeURL,
      let afterURL = BrowtherIntroMedia.audioAfterURL,
      let beforePlayer = try? AVAudioPlayer(contentsOf: beforeURL),
      let afterPlayer = try? AVAudioPlayer(contentsOf: afterURL)
    else { return }
    beforePlayer.numberOfLoops = -1
    afterPlayer.numberOfLoops = -1
    before = beforePlayer
    after = afterPlayer
    applyVolumes()
  }

  private func start() -> Double? {
    loadPlayers()
    guard let before, let after else { return nil }
    if !isSessionActive {
      // `.playback` : l'extrait est le sujet de l'écran, il doit s'entendre
      // même en mode silencieux. `.mixWithOthers` n'est pas demandé — on veut
      // au contraire que la musique de la personne se taise pendant la
      // démonstration.
      let session = AVAudioSession.sharedInstance()
      try? session.setCategory(.playback, mode: .default)
      try? session.setActive(true)
      isSessionActive = true
    }
    // Préparés AVANT de fixer l'instant de départ : un lecteur qui se prépare
    // dans `play(atTime:)` rate l'instant commun et part en décalé.
    before.prepareToPlay()
    after.prepareToPlay()
    // Démarrage simultané sur une base commune : les lancer l'un après l'autre
    // les décalerait, et la bascule s'entendrait comme un saut.
    let start = before.deviceCurrentTime + 0.05
    before.play(atTime: start)
    after.play(atTime: start)
    return before.duration
  }

  private func applyVolumes() {
    before?.volume = musicRemoved ? 0 : 1
    after?.volume = musicRemoved ? 1 : 0
  }
}
