// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Basarunaa — persistance de la collecte sur iOS.
///
/// Équivalent de `src/collect/store.js`, qui utilise IndexedDB. iOS n'en a pas,
/// et n'en a pas besoin : **le hash EST le nom du fichier**, donc un simple
/// dossier de spool donne la déduplication par contenu à l'œil nu, sans index.
///
///     Application Support/BasarunaaCollect/     (invisible de l'utilisateur)
///       spool/<hash>.jpg      image en attente d'archivage
///       spool/<hash>.json     sa ligne de manifeste
///       seen.idx              hashes déjà collectés — SURVIT au flush
///       seenurl.idx           hashes d'URL déjà tentées (évite le re-fetch)
///       stats.json            compteurs
///
///     Documents/basarunaa-corpus/               (visible dans Files.app)
///       <appareil>-<horodatage>-<n>img.zip
///
/// Les deux index sont des fichiers **append-only** relus en mémoire au
/// démarrage : à 33 octets par ligne, 10 000 images pèsent 330 Ko. Une base
/// serait plus élégante et strictement moins fiable — un fichier tronqué se
/// répare en ignorant sa dernière ligne, ce que fait `loadIndex`.
///
/// ⚠️ `seenurl.idx` stocke un HASH TRONQUÉ de l'URL, jamais l'URL : sans ça le
/// fichier deviendrait un historique de navigation en clair, ce qui n'est pas
/// ce qu'on a demandé à l'utilisateur d'accepter.

// MARK: - Manifeste

/// Une ligne de `manifest.jsonl`. **Le format est partagé avec desktop** : les
/// archives des deux plateformes seront fusionnées d'un `unzip -n`, et les clés
/// courtes (`h`, `ht`, `sw`…) sont celles de `collector.js`. Ne pas les
/// renommer « pour la lisibilité » — ça couperait le corpus en deux.
public struct ManifestRow: Codable, Sendable {
  public struct Det: Codable, Sendable {
    /// Boîtes `person` du vérificateur. `nil` quand le vérificateur n'a pas
    /// tourné — se sérialise en `null`, ce qui se lit « pas d'information » et
    /// non « zéro personne ».
    public let pf: Int?
    public let raw: Int
    public let ok: Int
    public let confs: [Double]

    public init(pf: Int?, raw: Int, ok: Int, confs: [Double]) {
      self.pf = pf
      self.raw = raw
      self.ok = ok
      self.confs = confs
    }

    /// ⚠️ Encodage explicite pour que `pf == nil` produise `"pf": null` et
    /// **non** une clé absente — ce que ferait l'encodeur synthétisé de Swift
    /// (`encodeIfPresent` sur les Optional). L'écart n'est pas cosmétique :
    /// une clé manquante se lit « champ oublié à l'écriture », un `null` se lit
    /// « le vérificateur n'a pas tourné ». Desktop écrit `null`, le corpus est
    /// fusionné, l'analyse hors-ligne doit pouvoir compter les deux cas.
    public func encode(to encoder: Encoder) throws {
      var c = encoder.container(keyedBy: CodingKeys.self)
      if let pf {
        try c.encode(pf, forKey: .pf)
      } else {
        try c.encodeNil(forKey: .pf)
      }
      try c.encode(raw, forKey: .raw)
      try c.encode(ok, forKey: .ok)
      try c.encode(confs, forKey: .confs)
    }
  }

  public let h: String        // SHA-256 (128 bits) des octets stockés = nom du fichier
  public let dhash: String    // empreinte perceptuelle 64 bits
  public let w: Int           // largeur d'origine
  public let ht: Int          // hauteur d'origine
  public let sw: Int          // largeur stockée
  public let sh: Int          // hauteur stockée
  public let bytes: Int
  public let src: String      // DOMAINE de l'image, jamais l'URL
  public let page: String     // DOMAINE de la page, jamais l'URL
  public let kind: String     // "image" | "video-scene"
  public let ev: String       // comment le caractère public a été établi
  public let stratum: String
  public let p: Double
  public let wgt: Double
  public let det: Det
  public let dev: String      // nom d'appareil ("karim", "epouse")
  /// Plateforme d'origine — ajouté le 2026-08-28 avec le port iOS. Permet de
  /// mesurer plus tard ce que la navigation mobile apporte par rapport au
  /// desktop, une fois les deux archives fusionnées.
  public let platform: String
  public let ts: String       // ISO 8601

  public init(
    h: String, dhash: String, w: Int, ht: Int, sw: Int, sh: Int, bytes: Int,
    src: String, page: String, kind: String, ev: String, stratum: String,
    p: Double, det: Det, dev: String, platform: String = "ios", ts: String
  ) {
    self.h = h
    self.dhash = dhash
    self.w = w
    self.ht = ht
    self.sw = sw
    self.sh = sh
    self.bytes = bytes
    self.src = src
    self.page = page
    self.kind = kind
    self.ev = ev
    self.stratum = stratum
    // `wgt` est dérivé du `p` ARRONDI, pas du `p` exact : sinon relire le
    // manifeste et recalculer 1/p ne redonne pas le poids écrit. Constaté sur
    // la première archive desktop réelle (p 0,0067 → wgt 150 alors que
    // 1/0,0067 = 149,25). Sur un petit `p` — donc un gros poids, donc une image
    // qui pèse lourd dans la pondération — l'écart n'est pas anecdotique.
    let rounded = (p * 1_000_000).rounded() / 1_000_000
    self.p = rounded
    self.wgt = rounded > 0 ? ((1 / rounded) * 1000).rounded() / 1000 : 0
    self.det = det
    self.dev = dev
    self.platform = platform
    self.ts = ts
  }
}

// MARK: - Compteurs

/// Compteurs de la collecte. Miroir d'`EMPTY_STATS()` côté desktop, aux champs
/// propres à MV3 près (`zips` y compte les téléchargements déclenchés).
public struct CollectStats: Codable, Sendable {
  public var day: String = ""          // 'YYYY-MM-DD' — bascule = remise à zéro
  public var imagesToday: Int = 0
  public var bytesToday: Int = 0
  public var videoFramesToday: Int = 0
  public var domains: [String: Int] = [:]   // eTLD+1 → nb collecté aujourd'hui
  public var totalStored: Int = 0
  public var totalBytes: Int = 0
  public var spoolBytes: Int = 0
  public var spoolSince: Double = 0    // ms epoch du 1er élément du spool courant
  public var zips: Int = 0
  public var offered: [String: Int] = [:]    // strate → candidats présentés
  public var attempted: [String: Int] = [:]  // strate → candidats tirés
  public var stored: [String: Int] = [:]     // strate → candidats stockés
  public var dropped: [String: Int] = [:]    // raison → compte
  public var budgetHitAt: String = ""  // heure à laquelle un plafond a coupé

  public init() {}

  /// Bascule de jour : remet à zéro le quotidien, garde les totaux.
  public mutating func rollDay(_ today: String) {
    guard day != today else { return }
    day = today
    imagesToday = 0
    bytesToday = 0
    videoFramesToday = 0
    domains = [:]
    budgetHitAt = ""
  }
}

public func bump(_ dict: inout [String: Int], _ key: String, _ n: Int = 1) {
  dict[key, default: 0] += n
}

// MARK: - Store

public enum CollectStoreError: Error {
  case noDirectory(String)
}

/// Accès disque de la collecte. Volontairement **sans état d'exécution** (pas
/// de file, pas de décision) : c'est `Collector` qui orchestre. Toutes les
/// méthodes sont synchrones et appelées depuis l'acteur, jamais depuis le
/// thread principal.
public final class CollectStore: @unchecked Sendable {
  public let baseDir: URL
  public let spoolDir: URL
  public let archivesDir: URL

  private let seenFile: URL
  private let seenUrlFile: URL
  private let statsFile: URL

  private var seen: Set<String> = []
  private var seenUrl: Set<String> = []

  /// - Parameter root: racine de test. `nil` = emplacements réels de l'app.
  public init(root: URL? = nil) throws {
    let fm = FileManager.default
    let support: URL
    let documents: URL
    if let root {
      support = root.appendingPathComponent("Support", isDirectory: true)
      documents = root.appendingPathComponent("Documents", isDirectory: true)
    } else {
      guard let s = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
        let d = fm.urls(for: .documentDirectory, in: .userDomainMask).first
      else { throw CollectStoreError.noDirectory("Application Support / Documents") }
      support = s
      documents = d
    }

    baseDir = support.appendingPathComponent("BasarunaaCollect", isDirectory: true)
    spoolDir = baseDir.appendingPathComponent("spool", isDirectory: true)
    // Les archives vont dans Documents/ parce que c'est le SEUL emplacement
    // exposé par Files.app (`UIFileSharingEnabled` + `LSSupportsOpeningDocuments
    // InPlace`, déjà dans l'Info.plist). Le reste n'a rien à y faire : un
    // dossier `spool` visible inviterait à le vider à la main.
    archivesDir = documents.appendingPathComponent("basarunaa-corpus", isDirectory: true)

    seenFile = baseDir.appendingPathComponent("seen.idx")
    seenUrlFile = baseDir.appendingPathComponent("seenurl.idx")
    statsFile = baseDir.appendingPathComponent("stats.json")

    try fm.createDirectory(at: spoolDir, withIntermediateDirectories: true)
    try fm.createDirectory(at: archivesDir, withIntermediateDirectories: true)

    // Le tampon n'a aucune raison de partir dans iCloud : c'est de la donnée
    // reconstructible, potentiellement 60 Mo, et l'utilisateur n'a pas demandé
    // que ses images de navigation quittent l'appareil — fût-ce vers sa propre
    // sauvegarde.
    excludeFromBackup(baseDir)

    seen = Self.loadIndex(seenFile)
    seenUrl = Self.loadIndex(seenUrlFile)
  }

  private func excludeFromBackup(_ url: URL) {
    var u = url
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try? u.setResourceValues(values)
  }

  /// Relit un index append-only. Une dernière ligne tronquée (arrêt brutal en
  /// pleine écriture) est **ignorée sans bruit** : perdre un hash coûte au pire
  /// un doublon dans le corpus, que `unzip -n` recouvre de toute façon.
  private static func loadIndex(_ url: URL) -> Set<String> {
    guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
    var out = Set<String>()
    for line in text.split(separator: "\n") {
      let t = line.trimmingCharacters(in: .whitespaces)
      if !t.isEmpty { out.insert(t) }
    }
    return out
  }

  private func append(_ line: String, to url: URL) {
    guard let data = (line + "\n").data(using: .utf8) else { return }
    if let h = try? FileHandle(forWritingTo: url) {
      defer { try? h.close() }
      _ = try? h.seekToEnd()
      try? h.write(contentsOf: data)
    } else {
      try? data.write(to: url, options: .atomic)
    }
  }

  // MARK: Déduplication

  public func hasSeen(_ hash: String) -> Bool { seen.contains(hash) }

  public func markSeen(_ hash: String) {
    guard seen.insert(hash).inserted else { return }
    append(hash, to: seenFile)
  }

  public func hasSeenUrl(_ key: String) -> Bool { seenUrl.contains(key) }

  public func markSeenUrl(_ key: String) {
    guard seenUrl.insert(key).inserted else { return }
    append(key, to: seenUrlFile)
  }

  // MARK: Spool

  /// Écrit l'image et sa ligne de manifeste. L'image d'abord : si l'app meurt
  /// entre les deux, `spoolEntries` ignorera un `.jpg` sans `.json` — alors
  /// qu'une ligne de manifeste sans image produirait une archive incohérente.
  public func addToSpool(hash: String, jpeg: Data, row: ManifestRow) throws {
    try jpeg.write(to: spoolDir.appendingPathComponent("\(hash).jpg"), options: .atomic)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let json = try encoder.encode(row)
    try json.write(to: spoolDir.appendingPathComponent("\(hash).json"), options: .atomic)
  }

  /// Couples (image, ligne) prêts à archiver, triés pour que deux exécutions
  /// produisent le même ordre — sinon deux archives d'un même spool diffèrent
  /// sans raison et deviennent pénibles à comparer.
  public func spoolEntries() -> [(hash: String, jpeg: URL, row: Data)] {
    let fm = FileManager.default
    guard let names = try? fm.contentsOfDirectory(atPath: spoolDir.path) else { return [] }
    var out: [(hash: String, jpeg: URL, row: Data)] = []
    for name in names.sorted() where name.hasSuffix(".jpg") {
      let hash = String(name.dropLast(4))
      let jpeg = spoolDir.appendingPathComponent(name)
      let jsonURL = spoolDir.appendingPathComponent("\(hash).json")
      guard let row = try? Data(contentsOf: jsonURL) else { continue }
      out.append((hash: hash, jpeg: jpeg, row: row))
    }
    return out
  }

  public func removeFromSpool(_ hashes: [String]) {
    let fm = FileManager.default
    for h in hashes {
      try? fm.removeItem(at: spoolDir.appendingPathComponent("\(h).jpg"))
      try? fm.removeItem(at: spoolDir.appendingPathComponent("\(h).json"))
    }
  }

  // MARK: Compteurs

  public func loadStats() -> CollectStats {
    guard let data = try? Data(contentsOf: statsFile),
      let s = try? JSONDecoder().decode(CollectStats.self, from: data)
    else { return CollectStats() }
    return s
  }

  public func saveStats(_ s: CollectStats) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
    guard let data = try? encoder.encode(s) else { return }
    try? data.write(to: statsFile, options: .atomic)
  }

  // MARK: Purge

  /// Vide le tampon ET les index. Les archives déjà écrites ne sont pas
  /// touchées — elles sont dans Documents/, c'est à l'utilisateur d'en
  /// disposer.
  public func purge() {
    let fm = FileManager.default
    try? fm.removeItem(at: spoolDir)
    try? fm.createDirectory(at: spoolDir, withIntermediateDirectories: true)
    try? fm.removeItem(at: seenFile)
    try? fm.removeItem(at: seenUrlFile)
    try? fm.removeItem(at: statsFile)
    seen.removeAll()
    seenUrl.removeAll()
  }
}
