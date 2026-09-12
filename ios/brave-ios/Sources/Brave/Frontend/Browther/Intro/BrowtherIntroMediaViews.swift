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
  let target: BrowtherBlurTarget?

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
                  target: target,
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
  let target: BrowtherBlurTarget?
  /// Largeur du média d'origine, pour mettre l'adoucissement à l'échelle.
  let sourceWidth: Double

  var body: some View {
    GeometryReader { proxy in
      let visible = persons.filter { $0.isBlurred(for: target) }
      Canvas { context, size in
        for person in visible {
          context.fill(person.path(in: size), with: .color(.white))
        }
      }
      .blur(radius: CGFloat(max(2, 10 * Double(proxy.size.width) / sourceWidth)))
    }
    .animation(.easeOut(duration: 0.26), value: target)
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
  let target: BrowtherBlurTarget?

  var body: some View {
    BrowtherIntroVeiledVideo(target: target)
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
  private var value: BrowtherBlurTarget?

  var current: BrowtherBlurTarget? {
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
  let target: BrowtherBlurTarget?

  func makeUIView(context: Context) -> PlayerView {
    let view = PlayerView()
    context.coordinator.attach(to: view)
    context.coordinator.veilTarget.current = target
    return view
  }

  func updateUIView(_ uiView: PlayerView, context: Context) {
    context.coordinator.veilTarget.current = target
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
          target: target.current,
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
@MainActor
final class BrowtherIntroAudio: ObservableObject {
  @Published private(set) var isPlaying = false
  @Published private(set) var progress: Double = 0
  @Published private(set) var duration: Double = 0
  /// Le volume de sortie de l'iPhone. À zéro, l'extrait joue sans qu'on
  /// l'entende : l'écran doit le dire plutôt que de laisser croire à une panne.
  @Published private(set) var systemVolume: Float = 1

  private var before: AVAudioPlayer?
  private var after: AVAudioPlayer?
  private var ticker: Timer?
  private var volumeObservation: NSKeyValueObservation?

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

  private func prepare() {
    guard before == nil else { return }
    // `.playback` : l'extrait est le sujet de l'écran, il doit s'entendre même
    // en mode silencieux. `.mixWithOthers` n'est pas demandé — on veut au
    // contraire que la musique de la personne se taise pendant la démonstration.
    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
    try? AVAudioSession.sharedInstance().setActive(true)
    guard
      let beforeURL = BrowtherIntroMedia.audioBeforeURL,
      let afterURL = BrowtherIntroMedia.audioAfterURL,
      let beforePlayer = try? AVAudioPlayer(contentsOf: beforeURL),
      let afterPlayer = try? AVAudioPlayer(contentsOf: afterURL)
    else { return }
    for player in [beforePlayer, afterPlayer] {
      player.numberOfLoops = -1
      player.prepareToPlay()
    }
    before = beforePlayer
    after = afterPlayer
    duration = beforePlayer.duration
    apply(musicRemoved: false)
  }

  /// Lecture et pause. Rien ne démarre tout seul : l'extrait part au geste de
  /// la personne — le bouton, ou l'interrupteur de l'écran.
  func play() {
    prepare()
    guard let before, let after, !isPlaying else { return }
    // Démarrage simultané sur une base commune : les lancer l'un après l'autre
    // les décalerait, et la bascule s'entendrait comme un saut.
    let start = before.deviceCurrentTime + 0.05
    before.play(atTime: start)
    after.play(atTime: start)
    isPlaying = true
    startTicker()
  }

  func pause() {
    before?.pause()
    after?.pause()
    isPlaying = false
    ticker?.invalidate()
    ticker = nil
  }

  func toggle() {
    isPlaying ? pause() : play()
  }

  /// Déplacer la tête de lecture — sur les **deux** pistes, sinon la
  /// comparaison perd son sens.
  func seek(to fraction: Double) {
    prepare()
    guard let before, let after, duration > 0 else { return }
    let time = min(max(0, fraction), 0.999) * duration
    before.currentTime = time
    after.currentTime = time
    progress = time / duration
  }

  func apply(musicRemoved: Bool) {
    before?.volume = musicRemoved ? 0 : 1
    after?.volume = musicRemoved ? 1 : 0
  }

  func stop() {
    before?.stop()
    after?.stop()
    isPlaying = false
    progress = 0
    ticker?.invalidate()
    ticker = nil
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  private func startTicker() {
    ticker?.invalidate()
    ticker = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
      Task { @MainActor in
        guard let self, let before = self.before, self.duration > 0 else { return }
        self.progress = before.currentTime / self.duration
      }
    }
  }
}
