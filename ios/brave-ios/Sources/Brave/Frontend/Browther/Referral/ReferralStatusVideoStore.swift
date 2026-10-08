// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AVFoundation
import BraveStrings
import BrowtherReferral
import Foundation
import SwiftUI
import UIKit

/// Télécharge et garde en cache la **vidéo du statut WhatsApp** — règle et
/// pourquoi : `BrowtherReferral/ReferralStatusVideo.swift`,
/// `private/docs/PARRAINAGE.md` § 11. Pendant de
/// `fajrunaa/services/referral/statusVideo.ts`.
///
/// ⭐ Lancé dès l'ouverture de l'écran Parrainage (`ReferralHomeView`) : la vidéo
/// est là avant le tap sur « Partager mon code ». Une fois en cache, plus aucun
/// transfert — seul le manifeste (quelques centaines d'octets) est relu, pour
/// suivre un changement ou une coupure de la vidéo.
///
/// 🔴 **Ne lève jamais** : `nil` = pas de vidéo, et le statut part avec l'image
/// seule. ⚠️ Un échec n'est PAS mémorisé (le réseau revient).
/// ⚠️ Un succès n'est mémorisé que `ReferralStatusVideo.freshSeconds` : le
/// manifeste est aussi l'interrupteur qui COUPE la vidéo.
@MainActor
final class ReferralStatusVideoStore {
  static let shared = ReferralStatusVideoStore()

  private var ready: [String: (file: URL, at: Date)] = [:]
  private var inflight: [String: Task<URL?, Never>] = [:]

  /// Le fichier local de la vidéo, ou `nil` s'il n'y en a pas. `language` est
  /// celle de l'IMAGE du statut (fr, en, ar) — ⛔ jamais un repli ici.
  func prepare(language: String) async -> URL? {
    if let known = fresh(language) { return known }
    if let pending = inflight[language] { return await pending.value }
    let task = Task<URL?, Never> { await ReferralStatusVideoLoader.load(language: language) }
    inflight[language] = task
    let file = await task.value
    inflight[language] = nil
    if let file {
      ready[language] = (file, Date())
    } else {
      ready[language] = nil
    }
    return file
  }

  /// ⭐ La langue de la vidéo = celle de l'IMAGE du statut (fr, en, ar, sinon
  /// l'anglais) : une langue sans image reçoit l'image ET la vidéo en anglais.
  static var language: String {
    ReferralStatusVideo.statusLanguage(
      appLanguage: Strings.BrowtherReferral.StatusImage.current(lifetimeAt: 1).language
    )
  }

  /// Demande la vidéo sans l'attendre — dès que « Partager mon code » est à
  /// l'écran, pour qu'elle soit là quand la feuille s'ouvre.
  static func warmUp() {
    Task { _ = await shared.prepare(language: language) }
  }

  /// La réponse encore fraîche, si son fichier est toujours là (le système vide
  /// le cache quand il veut).
  private func fresh(_ language: String) -> URL? {
    guard let known = ready[language], Date().timeIntervalSince(known.at) <= ReferralStatusVideo.freshSeconds
    else { return nil }
    return FileManager.default.fileExists(atPath: known.file.path) ? known.file : nil
  }
}

/// Le transfert lui-même — hors de l'acteur principal : il ne touche à rien de
/// l'écran. ⛔ Ne lève jamais (`nil` = pas de vidéo).
enum ReferralStatusVideoLoader {
  private static let manifestTimeout: TimeInterval = 4
  private static let cacheFolder = "browther-referral-status"

  /// ⚠️ Éphémère, comme le client du parrainage : ni cookies ni cache du
  /// navigateur dans une requête de l'app.
  private static let session: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    return URLSession(configuration: configuration)
  }()

  private static func size(of file: URL) -> Int? {
    (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
  }

  private static func isOK(_ response: URLResponse) -> Bool {
    (response as? HTTPURLResponse)?.statusCode == 200
  }

  static func load(language: String) async -> URL? {
    guard let manifestURL = URL(string: ReferralStatusVideo.manifestURL) else { return nil }
    let request = URLRequest(
      url: manifestURL,
      cachePolicy: .reloadIgnoringLocalCacheData,
      timeoutInterval: manifestTimeout
    )
    guard let (data, response) = try? await session.data(for: request), isOK(response) else { return nil }
    guard
      let entry = ReferralStatusVideo.pick(ReferralStatusVideo.manifest(from: data), language: language),
      let remote = URL(string: entry.url),
      let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    else { return nil }

    let manager = FileManager.default
    let folder = caches.appendingPathComponent(cacheFolder, isDirectory: true)
    try? manager.createDirectory(at: folder, withIntermediateDirectories: true)
    let file = folder.appendingPathComponent(ReferralStatusVideo.fileName(entry))

    if !ReferralStatusVideo.isComplete(entry, size: size(of: file)) {
      try? manager.removeItem(at: file)
      guard let (downloaded, reply) = try? await session.download(from: remote), isOK(reply) else { return nil }
      try? manager.removeItem(at: file)
      guard (try? manager.moveItem(at: downloaded, to: file)) != nil else { return nil }
      // ⚠️ Un transfert interrompu laisse un fichier court : seule la taille
      // exacte du manifeste fait foi.
      guard ReferralStatusVideo.isComplete(entry, size: size(of: file)) else {
        try? manager.removeItem(at: file)
        return nil
      }
    }

    // Les vidéos d'avant (autre version, autre langue) ne serviront plus.
    // Ménage seulement : un fichier qui résiste ne gêne personne.
    for other in (try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
    where other.lastPathComponent != file.lastPathComponent {
      try? manager.removeItem(at: other)
    }
    return file
  }
}

/// Où en est la vidéo, telle que la feuille « Partager mon code » s'en sert —
/// pendant de `useStatusVideo` (Fajrunaa). Déjà là si l'écran Parrainage a eu le
/// temps de la télécharger, sinon on l'attend `waitSeconds`, puis on s'en passe
/// pour cette fois. 🔴 `.none` ne retire rien : chaque onglet garde son geste
/// d'avant (l'image seule).
@MainActor
final class ReferralStatusVideoWatch: ObservableObject {
  enum Phase: Equatable {
    case loading
    case ready(URL)
    case none
  }

  @Published private(set) var state: Phase = .loading
  private var started = false

  var file: URL? {
    if case .ready(let file) = state { return file }
    return nil
  }

  /// La feuille propose-t-elle la vidéo (deux vignettes, la case « Joindre la
  /// vidéo ») ? Oui tant qu'on l'attend encore.
  var offered: Bool { state != .none }

  func start(language: String) {
    guard !started else { return }
    started = true
    Task {
      let file = await ReferralStatusVideoStore.shared.prepare(language: language)
      settle(file.map(Phase.ready) ?? .none)
    }
    Task {
      try? await Task.sleep(nanoseconds: UInt64(ReferralStatusVideo.waitSeconds * 1_000_000_000))
      settle(.none)
    }
  }

  /// Le premier qui répond l'emporte : une vidéo arrivée après le délai ne
  /// réorganise pas une feuille déjà lue.
  private func settle(_ next: Phase) {
    if state == .loading { state = next }
  }
}

/// L'aperçu de la vidéo : elle joue, muette, en boucle.
///
/// 🔴 **Sans piste son, exprès** : dans Browther un lecteur audio créé sous la
/// catégorie par défaut met en pause la musique ou le PiP des AUTRES apps (vécu
/// avec Sawtunaa le 2026-09-21). `isMuted` ne suffit pas à l'éviter ; une
/// composition qui ne garde que la piste vidéo ne touche jamais à la session
/// audio. ⛔ Ne pas jouer le fichier tel quel, ⛔ ne pas toucher à `AVAudioSession`.
struct ReferralStatusVideoPreview: UIViewRepresentable {
  let file: URL
  var onDuration: (Double) -> Void = { _ in }

  func makeUIView(context: Context) -> PlayerView {
    let view = PlayerView()
    view.load(file: file, onDuration: onDuration)
    return view
  }

  func updateUIView(_ view: PlayerView, context: Context) {
    view.load(file: file, onDuration: onDuration)
  }

  static func dismantleUIView(_ view: PlayerView, coordinator: ()) {
    view.stop()
  }

  final class PlayerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }

    private var loaded: URL?
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var loading: Task<Void, Never>?

    private var playerLayer: AVPlayerLayer? { layer as? AVPlayerLayer }

    func load(file: URL, onDuration: @escaping (Double) -> Void) {
      guard loaded != file else { return }
      stop()
      loaded = file
      backgroundColor = .black
      playerLayer?.videoGravity = .resizeAspectFill
      loading = Task { @MainActor [weak self] in
        let asset = AVURLAsset(url: file)
        guard
          let track = try? await asset.loadTracks(withMediaType: .video).first,
          let duration = try? await asset.load(.duration),
          let transform = try? await track.load(.preferredTransform)
        else { return }
        let composition = AVMutableComposition()
        guard
          let silent = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
          ),
          (try? silent.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: track, at: .zero)) != nil
        else { return }
        silent.preferredTransform = transform
        guard let self, !Task.isCancelled, self.loaded == file else { return }
        let player = AVQueuePlayer()
        player.isMuted = true
        player.allowsExternalPlayback = false
        player.preventsDisplaySleepDuringVideoPlayback = false
        self.looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(asset: composition))
        self.player = player
        self.playerLayer?.player = player
        player.play()
        onDuration(duration.seconds)
      }
    }

    func stop() {
      loading?.cancel()
      loading = nil
      player?.pause()
      looper?.disableLooping()
      looper = nil
      player = nil
      playerLayer?.player = nil
      loaded = nil
    }
  }
}

/// `41` → `0:41`.
func referralVideoClock(_ seconds: Double) -> String {
  let total = Int(seconds.rounded())
  return "\(total / 60):" + String(format: "%02d", total % 60)
}
