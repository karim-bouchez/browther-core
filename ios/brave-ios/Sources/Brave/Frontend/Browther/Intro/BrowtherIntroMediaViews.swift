// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AVFoundation
import AVKit
import BraveStrings
import SwiftUI
import UIKit

// MARK: - Le voile

/// Le voile de Basarunaa, tel qu'il est rendu sur macOS : la matière dépolie
/// est découpée par le **contour du corps**, adouci sur les bords — pas un
/// rectangle. Les contours viennent du pré-calcul (`BrowtherIntroMedia`).
///
/// Un seul calque de matière pour toutes les personnes : deux voiles qui se
/// chevauchent doivent donner le même flou qu'un seul, pas le double.
struct BrowtherIntroVeilLayer: View {
  let persons: [BrowtherIntroMedia.Person]
  let target: BrowtherBlurTarget
  /// Rayon de l'adoucissement, en pixels du média (10 px chez le compositeur).
  var featherAtSourceWidth: (radius: Double, width: Double) = (10, 900)

  var body: some View {
    GeometryReader { proxy in
      let visible = persons.filter { $0.isBlurred(for: target) }
      let feather = featherAtSourceWidth.radius * proxy.size.width / featherAtSourceWidth.width
      Rectangle()
        .fill(.ultraThinMaterial)
        .mask {
          Canvas { context, size in
            for person in visible {
              context.fill(person.path(in: size), with: .color(.white))
            }
          }
          .blur(radius: max(2, feather))
        }
        .animation(.easeOut(duration: 0.26), value: target)
    }
    .allowsHitTesting(false)
  }
}

// MARK: - Photo

/// La vignette « image » : une vraie photo, avec le voile posé dessus.
struct BrowtherIntroPhotoTile: View {
  let target: BrowtherBlurTarget

  var body: some View {
    ZStack {
      if let image = BrowtherIntroMedia.photoImage {
        Image(uiImage: image)
          .resizable()
          .aspectRatio(contentMode: .fill)
      } else {
        Color(UIColor.secondarySystemGroupedBackground)
      }
      BrowtherIntroVeilLayer(
        persons: BrowtherIntroMedia.photoPersons,
        target: target,
        featherAtSourceWidth: (10, 1200)
      )
    }
    .aspectRatio(16.0 / 9.0, contentMode: .fit)
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(alignment: .topLeading) {
      BrowtherIntroTileTag(symbol: "photo", label: Strings.BrowtherIntro.tileImage)
    }
  }
}

// MARK: - Vidéo

/// La vignette « vidéo » : le voile suit les personnes, image par image. C'est
/// la seule chose qu'une photo ne peut pas montrer — et le mode de panne qu'on
/// veut exclure (un flou qui saute ou qui traîne).
struct BrowtherIntroVideoTile: View {
  let target: BrowtherBlurTarget
  @State private var time: Double = 0

  var body: some View {
    ZStack {
      BrowtherIntroLoopingVideo(time: $time)
      BrowtherIntroVeilLayer(
        persons: BrowtherIntroMedia.persons(at: time),
        target: target
      )
    }
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

/// Lecture en boucle, muette, sans commandes : c'est une illustration, pas un
/// lecteur. Le temps courant remonte pour que le voile suive.
struct BrowtherIntroLoopingVideo: UIViewRepresentable {
  @Binding var time: Double

  func makeUIView(context: Context) -> PlayerView {
    let view = PlayerView()
    context.coordinator.attach(to: view, onTime: { time = $0 })
    return view
  }

  func updateUIView(_ uiView: PlayerView, context: Context) {}

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
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var observer: Any?

    func attach(to view: PlayerView, onTime: @escaping (Double) -> Void) {
      guard let url = BrowtherIntroMedia.videoURL else { return }
      let item = AVPlayerItem(url: url)
      let player = AVQueuePlayer(playerItem: item)
      player.isMuted = true
      // Pas de son, donc aucune raison de couper la musique de l'utilisateur.
      player.actionAtItemEnd = .advance
      looper = AVPlayerLooper(player: player, templateItem: item)
      view.playerLayer.player = player
      view.playerLayer.videoGravity = .resizeAspectFill
      // 24 relevés par seconde : le voile ne doit jamais avoir une image de
      // retard sur la personne qu'il couvre.
      observer = player.addPeriodicTimeObserver(
        forInterval: CMTime(value: 1, timescale: 24),
        queue: .main
      ) { time in
        onTime(time.seconds)
      }
      player.play()
      self.player = player
    }

    func stop() {
      if let observer {
        player?.removeTimeObserver(observer)
      }
      observer = nil
      player?.pause()
      looper = nil
      player = nil
    }
  }
}

// MARK: - Son

/// Les deux versions du même extrait, jouées **en parallèle** et à la même
/// position : l'interrupteur ne relance rien, il change de canal. Sans ça, la
/// comparaison porterait sur deux instants différents du morceau, et ne
/// prouverait rien.
@MainActor
final class BrowtherIntroAudio: ObservableObject {
  @Published private(set) var isPlaying = false

  private var before: AVAudioPlayer?
  private var after: AVAudioPlayer?

  func prepare() {
    guard before == nil else { return }
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
    apply(musicRemoved: false)
  }

  func toggle() {
    prepare()
    guard let before, let after else { return }
    if isPlaying {
      before.pause()
      after.pause()
    } else {
      // Démarrage simultané : `play(atTime:)` sur une base commune évite le
      // décalage qu'on entendrait en les lançant l'un après l'autre.
      let start = before.deviceCurrentTime + 0.05
      before.play(atTime: start)
      after.play(atTime: start)
    }
    isPlaying.toggle()
  }

  func apply(musicRemoved: Bool) {
    before?.volume = musicRemoved ? 0 : 1
    after?.volume = musicRemoved ? 1 : 0
  }

  func stop() {
    before?.stop()
    after?.stop()
    isPlaying = false
  }
}
