// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import OSLog
import UniformTypeIdentifiers

/// Basarunaa — collecte d'un corpus d'images de navigation (OPT-IN, local).
///
/// Port de `private/extensions/basarunaa/src/collect/collector.js`. Vit là où
/// passent DÉJÀ toutes les images analysées et où sont DÉJÀ connus les verdicts
/// des modèles : le handler de script. **Aucune inférence, aucun décodage,
/// aucun fetch supplémentaire n'est ajouté au chemin critique** — `offer()` est
/// appelé APRÈS que la réponse soit partie vers le JS.
///
/// ── Ce que le module garantit ──────────────────────────────────────────────
/// 1. Rien ne part si la pref est fausse (défaut). **Rien en navigation
///    privée** — et le drapeau vient du `TabState`, jamais d'un script de page.
/// 2. Une image n'entre au corpus que si un visiteur ANONYME obtient les mêmes
///    octets à la même URL — ce sont ces octets-là qu'on stocke (`fetchPublic`).
/// 3. Déduplication par hash de contenu, obligatoire.
/// 4. La probabilité d'inclusion de chaque image gardée est écrite dans le
///    manifeste : tout biais d'échantillonnage reste corrigeable (`CollectPolicy`).
/// 5. Rien ne quitte l'appareil : les archives vont dans `Documents/`, aucune
///    requête sortante à part le GET anonyme qui établit le caractère public.
///
/// ── Ce que le port iOS SIMPLIFIE, et pourquoi c'est un gain ────────────────
/// La moitié des incidents desktop (§11 de COLLECTE.md) vient d'une seule
/// cause : la configuration voyageait par messages entre trois contextes MV3
/// (page de contrôle → service worker → offscreen), avec une version de schéma,
/// une migration, une voie redondante — et une divergence possible entre
/// « ce que le réglage dit » et « ce que le collecteur fait ». Ici il n'y a ni
/// message ni config persistée : les préférences sont lues à la source, et
/// l'écran de contrôle lit l'état DU COLLECTEUR. Toute cette classe de pannes
/// disparaît avec le mécanisme qui la produisait.
public actor Collector {
  public static let shared = Collector()

  private let log = Logger(subsystem: "com.devndin.browther", category: "Basarunaa.Collect")

  /// Candidats traités en parallèle. 3 comme desktop : le travail est surtout
  /// du réseau, mais chaque candidat décode et réencode une image.
  private static let maxInflight = 3
  /// Au-delà, `loadFactor` renvoie 0 et on ne tire même plus.
  private static let maxPending = 8
  private static let fetchTimeout: TimeInterval = 8
  private static let maxSourceBytes = 25 * 1024 * 1024

  private var cfg = CollectConfig()
  private var stats = CollectStats()
  private var store: CollectStore?
  private var enabled = false
  private var ready = false
  private var initError: String?

  /// Candidats présentés depuis le lancement, AVANT tout filtre. En mémoire
  /// seulement. C'est le compteur qui distingue « rien à collecter » de « le
  /// pipeline n'appelle même pas le collecteur » — sans lui, les deux cas
  /// affichent des zéros et se ressemblent trait pour trait.
  private var received = 0

  private var pending: [Candidate] = []
  private var inflight = 0
  private var flushing = false
  private var pagePublic: [String: Bool] = [:]
  /// Dernière frame retenue par vidéo (ms epoch) — fait respecter
  /// `minSceneIntervalMs` AVANT toute probabilité, comme côté page sur desktop.
  private var lastSceneAt: [String: Double] = [:]
  private var framesPerVideo: [String: Int] = [:]

  /// GET anonyme : session éphémère, **aucun cookie**, aucun cache partagé avec
  /// la navigation. C'est ce qui rend le test honnête — une session qui
  /// emporterait les cookies de l'utilisateur répondrait 200 sur des images
  /// privées, et le corpus se remplirait de ce qu'on cherche justement à
  /// exclure.
  private let anonSession: URLSession = {
    let c = URLSessionConfiguration.ephemeral
    c.httpCookieStorage = nil
    c.httpShouldSetCookies = false
    c.urlCache = nil
    c.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    // Cellulaire AUTORISÉ (décision Karim, 2026-08-28) : la collecte ne tourne
    // que sur les appareils de deux personnes qui l'ont explicitement activée,
    // et brider au Wi-Fi ralentirait le remplissage du corpus pour économiser
    // un forfait qu'ils acceptent de dépenser.
    c.allowsCellularAccess = true
    c.timeoutIntervalForRequest = 8
    return URLSession(configuration: c)
  }()

  private init() {}

  // MARK: - Cycle de vie

  /// À appeler au démarrage, puis à chaque changement de préférence.
  /// Idempotent.
  public func configure(enabled: Bool, device: String, videoScenes: Bool) {
    self.enabled = enabled
    cfg.device = device
    cfg.videoScenes = videoScenes
    guard enabled else { return }
    if store == nil {
      do {
        let s = try CollectStore()
        store = s
        stats = s.loadStats()
        stats.rollDay(Self.today())
        ready = true
        initError = nil
        log.info("collecte prête (\(self.stats.totalStored, privacy: .public) images au total)")
      } catch {
        // Une panne d'initialisation doit avoir une cause NOMMÉE et visible
        // dans l'écran de contrôle. Une panne qu'on voit mais qui ne dit rien
        // coûte plus cher qu'une panne franche : elle oriente le diagnostic
        // vers la mauvaise pièce (leçon du 2026-08-21 côté desktop).
        ready = false
        initError = String(describing: error)
        log.error("collecte impossible à initialiser : \(self.initError ?? "", privacy: .public)")
      }
    }
  }

  public struct Status: Sendable {
    public let ready: Bool
    public let enabled: Bool
    public let initError: String?
    public let received: Int
    public let pending: Int
    public let inflight: Int
    public let device: String
    public let stats: CollectStats
    public let archivesPath: String
  }

  public func status() -> Status {
    Status(
      ready: ready, enabled: enabled, initError: initError, received: received,
      pending: pending.count, inflight: inflight, device: cfg.device, stats: stats,
      archivesPath: store?.archivesDir.path ?? "")
  }

  public func purge() {
    store?.purge()
    stats = CollectStats()
    stats.day = Self.today()
    pagePublic.removeAll()
    lastSceneAt.removeAll()
    framesPerVideo.removeAll()
  }

  // MARK: - Candidat

  struct Candidate: Sendable {
    let srcUrl: String
    let pageUrl: String
    let det: CollectDetection
    let width: Int
    let height: Int
    /// Pixels déjà décodés — utilisés UNIQUEMENT quand l'URL n'est pas
    /// re-fetchable (`data:`, frame vidéo). Sur la voie http on ne les garde
    /// pas : les octets viendront du GET anonyme, et retenir un JPEG de 200 Ko
    /// par candidat en file coûterait de la mémoire pour rien.
    let jpeg: Data?
    let stratum: CollectStratum
    let p: Double
    let domain: String
    let kind: String
    let videoKey: String?
  }

  /// Entrée IMAGE. Décide immédiatement, met en file, et rend la main.
  ///
  /// - Parameters:
  ///   - incognito: **doit venir de l'onglet** (`TabState.isPrivate`), jamais
  ///     d'un script de page — un script peut être trompé.
  ///   - queueDepth: profondeur de la file d'analyse côté page, pour que le
  ///     taux suive la charge observée (et que `p` la note).
  public func offerImage(
    srcUrl: String, pageUrl: String, det: CollectDetection,
    width: Int, height: Int, jpeg: Data?, incognito: Bool, queueDepth: Int
  ) {
    received += 1
    // Sortie AVANT tout comptage : collecte inactive ou navigation privée ne
    // sont pas des « rejets » à mesurer.
    guard ready, enabled, !incognito else { return }
    stats.rollDay(Self.today())
    guard !budgetExhausted() else { return }

    if let why = hardReject(srcUrl: srcUrl, pageUrl: pageUrl, width: width, height: height) {
      note(&stats.dropped, why)
      return
    }

    let stratum = classify(det)
    bump(&stats.offered, stratum.rawValue)

    let domain = baseDomain(host(of: pageUrl))
    let p = inclusionProb(
      stratum, cfg,
      load: loadFactor(
        queueDepth: queueDepth, inflight: inflight + pending.count,
        maxInflight: Self.maxPending),
      domainCount: stats.domains[domain] ?? 0)
    guard p > 0, Double.random(in: 0..<1) < p else { return }

    bump(&stats.attempted, stratum.rawValue)
    let isHTTP = srcUrl.lowercased().hasPrefix("http")
    pending.append(
      Candidate(
        srcUrl: srcUrl, pageUrl: pageUrl, det: det, width: width, height: height,
        jpeg: isHTTP ? nil : jpeg, stratum: stratum, p: p, domain: domain,
        kind: "image", videoKey: nil))
    pump()
  }

  /// Entrée VIDÉO — une frame d'OUVERTURE DE SCÈNE, jamais une frame au fil de
  /// l'eau. Une vidéo de 10 minutes contient ~150 scènes et 18 000 frames :
  /// échantillonner par frame noierait le corpus sous un seul contenu.
  ///
  /// Les trois bornes (quota du jour, quota par vidéo, intervalle minimal)
  /// s'appliquent **avant** toute probabilité — d'où l'écart normal entre
  /// « cuts » et « scènes gardées ».
  public func offerVideoFrame(
    videoKey: String, pageUrl: String, det: CollectDetection,
    width: Int, height: Int, jpeg: Data, incognito: Bool, queueDepth: Int
  ) {
    received += 1
    guard ready, enabled, !incognito, cfg.videoScenes else { return }
    stats.rollDay(Self.today())
    guard !budgetExhausted() else { return }

    guard stats.videoFramesToday < cfg.maxVideoFramesPerDay else {
      note(&stats.dropped, "quota-video")
      return
    }
    guard (framesPerVideo[videoKey] ?? 0) < cfg.maxFramesPerVideo else {
      note(&stats.dropped, "quota-video-single")
      return
    }
    let now = Date().timeIntervalSince1970 * 1000
    if let last = lastSceneAt[videoKey], now - last < cfg.minSceneIntervalMs {
      note(&stats.dropped, "scene-too-close")
      return
    }

    let pageHost = host(of: pageUrl)
    // Un flux MSE arrive en `blob:` : impossible à re-fetcher anonymement, donc
    // aucun test structurel n'est possible. Le caractère public ne peut être
    // établi que par la PAGE — d'où l'allowlist, seule règle défendable ici.
    // Le choix est entre une liste explicite et pas de vidéo du tout.
    guard hostMatches(pageHost, cfg.videoHosts) else {
      note(&stats.dropped, "video-host")
      return
    }
    guard !hostMatches(pageHost, cfg.denyHosts) else {
      note(&stats.dropped, "deny-page")
      return
    }
    guard max(width, height) >= cfg.minSide else {
      note(&stats.dropped, "tiny")
      return
    }

    let stratum = CollectStratum.videoScene
    bump(&stats.offered, stratum.rawValue)
    let p = inclusionProb(
      stratum, cfg,
      load: loadFactor(
        queueDepth: queueDepth, inflight: inflight + pending.count,
        maxInflight: Self.maxPending),
      domainCount: 0)  // quota vidéo géré à part
    guard p > 0, Double.random(in: 0..<1) < p else { return }

    // Les deux dictionnaires sont indexés par (page, vidéo) : sur une session
    // de plusieurs heures de navigation ils grossiraient indéfiniment. On les
    // vide au-delà d'un seuil large — perdre le compteur d'une vidéo coûte au
    // pire quelques frames de plus sur une vidéo déjà quittée, alors qu'une
    // fuite mémoire dans un navigateur se paie en onglets tués.
    if framesPerVideo.count > 200 {
      framesPerVideo.removeAll()
      lastSceneAt.removeAll()
    }
    lastSceneAt[videoKey] = now
    framesPerVideo[videoKey, default: 0] += 1
    bump(&stats.attempted, stratum.rawValue)
    pending.append(
      Candidate(
        srcUrl: "", pageUrl: pageUrl, det: det, width: width, height: height,
        jpeg: jpeg, stratum: stratum, p: p, domain: baseDomain(pageHost),
        kind: "video-scene", videoKey: videoKey))
    pump()
  }

  // MARK: - Décision synchrone

  /// Exclusions DÉTERMINISTES : elles définissent la population échantillonnée,
  /// elles ne sont pas un tirage. Une image écartée ici n'existe pas pour le
  /// corpus — c'est assumé et documenté, pas un biais caché.
  private func hardReject(srcUrl: String, pageUrl: String, width: Int, height: Int) -> String? {
    if max(width, height) < cfg.minSide { return "tiny" }

    let pageHost = host(of: pageUrl)
    if pageHost.isEmpty { return "no-page" }
    if hostMatches(pageHost, cfg.denyHosts) { return "deny-page" }

    let srcHost = host(of: srcUrl)
    if !srcHost.isEmpty, hostMatches(srcHost, cfg.denyHosts) { return "deny-src" }

    // Voie A = URL http(s) re-fetchable anonymement. Voie B = `data:` sur une
    // page publique. `blob:` est exclu PAR PRINCIPE : c'est du contenu fabriqué
    // localement (typiquement un fichier que l'utilisateur est en train
    // d'envoyer) — risque maximal, valeur nulle pour le corpus.
    let lower = srcUrl.lowercased()
    if !lower.hasPrefix("http://"), !lower.hasPrefix("https://"), !lower.hasPrefix("data:") {
      return "scheme"
    }
    return nil
  }

  /// Plafonds atteints. Traité à part des autres rejets : une fois le quota du
  /// jour atteint, il le reste pour la journée entière — compter chaque image
  /// écrirait sur disque toutes les 5 s jusqu'à minuit pour une information
  /// déjà connue. On note l'heure UNE fois, et l'écran de contrôle l'affiche.
  private func budgetExhausted() -> Bool {
    if stats.imagesToday < cfg.maxImagesPerDay,
      stats.bytesToday < cfg.maxBytesPerDay,
      stats.totalBytes < cfg.maxTotalBytes
    {
      return false
    }
    if stats.budgetHitAt.isEmpty {
      let f = DateFormatter()
      f.dateFormat = "HH:mm"
      stats.budgetHitAt = f.string(from: Date())
      persistStats()
    }
    return true
  }

  // MARK: - Traitement

  private func pump() {
    while inflight < Self.maxInflight, !pending.isEmpty {
      let c = pending.removeFirst()
      inflight += 1
      Task { [weak self] in
        await self?.run(c)
      }
    }
  }

  private func run(_ c: Candidate) async {
    do {
      try await process(c)
    } catch {
      // La raison EXACTE, pas un `error` fourre-tout : sur une collecte de deux
      // semaines, savoir que ce sont 6 délais de fetch dépassés ou 6 disques
      // pleins ne mène pas au même geste.
      note(&stats.dropped, "error: \(type(of: error))")
      log.error("candidat en échec : \(String(describing: error), privacy: .public)")
    }
    inflight -= 1
    pump()
  }

  private func process(_ c: Candidate) async throws {
    guard let store else { return }
    stats.rollDay(Self.today())

    // Dédup par URL AVANT tout réseau : ré-émettre un GET pour une image qu'on
    // a déjà tentée est du trafic pur.
    var urlKey: String?
    if c.srcUrl.lowercased().hasPrefix("http") {
      let key = Self.shortHash(c.srcUrl)
      if store.hasSeenUrl(key) {
        note(&stats.dropped, "dup-url")
        return
      }
      urlKey = key
    }

    var source: Data
    var evidence: String
    switch c.kind {
    case "video-scene":
      guard let jpeg = c.jpeg else {
        note(&stats.dropped, "no-bytes")
        return
      }
      source = jpeg
      evidence = "video-host"
    default:
      if c.srcUrl.lowercased().hasPrefix("http") {
        let pub = await fetchPublic(c.srcUrl)
        guard let blob = pub.data else {
          note(&stats.dropped, pub.evidence)
          return
        }
        source = blob
        evidence = pub.evidence
      } else {
        guard await isPagePublic(c.pageUrl) else {
          note(&stats.dropped, "nonpublic-page")
          return
        }
        guard let jpeg = c.jpeg else {
          note(&stats.dropped, "no-bytes")
          return
        }
        source = jpeg
        evidence = "page"
      }
    }

    guard let made = Self.makeStored(source, cfg: cfg) else {
      note(&stats.dropped, "decode")
      return
    }
    guard max(made.sw, made.sh) >= cfg.minSide else {
      note(&stats.dropped, "tiny")
      return
    }

    let hash = Self.sha256Hex(made.jpeg)
    guard !store.hasSeen(hash) else {
      note(&stats.dropped, "dup")
      return
    }
    if let urlKey { store.markSeenUrl(urlKey) }

    let row = ManifestRow(
      h: hash, dhash: made.dhash,
      w: made.w, ht: made.h, sw: made.sw, sh: made.sh, bytes: made.jpeg.count,
      src: host(of: c.srcUrl), page: c.domain, kind: c.kind, ev: evidence,
      stratum: c.stratum.rawValue, p: c.p,
      det: ManifestRow.Det(
        pf: c.det.pf, raw: c.det.raw, ok: c.det.ok, confs: c.det.confs),
      dev: cfg.device.isEmpty ? "anon" : cfg.device,
      ts: Self.iso8601(Date()))

    try store.addToSpool(hash: hash, jpeg: made.jpeg, row: row)
    store.markSeen(hash)

    stats.imagesToday += 1
    stats.bytesToday += made.jpeg.count
    stats.totalStored += 1
    stats.totalBytes += made.jpeg.count
    stats.spoolBytes += made.jpeg.count
    if stats.spoolSince == 0 { stats.spoolSince = Date().timeIntervalSince1970 * 1000 }
    if c.kind == "video-scene" { stats.videoFramesToday += 1 }
    bump(&stats.domains, c.domain)
    bump(&stats.stored, c.stratum.rawValue)
    persistStats()

    let ageMs = Date().timeIntervalSince1970 * 1000 - stats.spoolSince
    if stats.spoolBytes >= cfg.maxSpoolBytes
      || (stats.spoolSince > 0 && ageMs > cfg.maxSpoolAgeMs)
    {
      await flush(reason: "auto")
    }
  }

  // MARK: - Caractère public

  /// Test du caractère public — **STRUCTUREL, pas par énumération**.
  ///
  /// La question à laquelle il faut répondre n'est pas « ce site est-il dans ma
  /// liste ? » (une liste oublie toujours quelque chose, et un CDN de plus la
  /// rend fausse) mais :
  ///
  ///   « cette image est-elle accessible à n'importe qui, par son seul CHEMIN ? »
  ///
  /// D'où le test : GET anonyme de l'URL **privée de sa query string**.
  ///
  ///  - 2xx + `image/*` → publique par son chemin. On stocke CES octets-là : le
  ///    corpus ne contient alors que ce qu'un visiteur non connecté obtient à
  ///    une URL sans aucun secret dedans.
  ///  - **401 / 403** → le chemin EST une ressource et la query en OUVRE
  ///    l'accès : signature `fbcdn`, S3 présigné, CloudFront signé, vignettes
  ///    Drive, fichiers Slack. On jette (`token-url`), **sans qu'aucun de ces
  ///    hôtes ait eu à être nommé**.
  ///  - **400 / 404** → le chemin n'est PAS une ressource : c'est un point
  ///    d'entrée, et la query IDENTIFIE ce qu'on demande (les vignettes de
  ///    Google Images). Aucune barrière d'accès là-dedans → on accepte, en le
  ///    traçant (`ev: query`).
  ///
  /// Cette nuance entre les deux cas du milieu est le cœur du test : elle
  /// sépare *autoriser* de *désigner*. La v1 desktop les confondait et jetait
  /// toutes les vignettes Google Images — 16 rejets sur 49 tirages en session
  /// réelle, soit la TOTALITÉ de l'attrition mesurée.
  ///
  /// Limite connue : un serveur qui répondrait 404 au lieu de 403 sur une URL
  /// signée passerait au travers. Le compteur `token-url` reste là pour le voir.
  private func fetchPublic(_ url: String) async -> (data: Data?, evidence: String) {
    let bare = Self.stripQuery(url)
    let nue = await anonGet(bare)
    if let data = nue.data { return (data, "path") }
    if bare == url { return (nil, "nonpublic") }

    if nue.status == 401 || nue.status == 403 {
      return (nil, "token-url")
    }
    let complete = await anonGet(url)
    if let data = complete.data { return (data, "query") }
    return (nil, "nonpublic")
  }

  private func anonGet(_ url: String) async -> (data: Data?, status: Int) {
    guard let u = URL(string: url) else { return (nil, 0) }
    var req = URLRequest(url: u)
    req.httpMethod = "GET"
    req.timeoutInterval = Self.fetchTimeout
    // Pas de `Referer` : certains serveurs servent une image à un référent et
    // la refusent sans. Un visiteur anonyme n'en a pas — c'est bien lui qu'on
    // simule. Les images hotlink-protégées sont donc perdues, comptées en
    // `nonpublic`, et c'est le bon sens du compromis.
    req.setValue(nil, forHTTPHeaderField: "Referer")
    do {
      let (data, response) = try await anonSession.data(for: req)
      guard let http = response as? HTTPURLResponse else { return (nil, 0) }
      guard (200..<300).contains(http.statusCode) else { return (nil, http.statusCode) }
      let type = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
      guard type.hasPrefix("image/") else { return (nil, http.statusCode) }
      guard !data.isEmpty, data.count <= Self.maxSourceBytes else {
        return (nil, http.statusCode)
      }
      return (data, http.statusCode)
    } catch {
      return (nil, 0)  // erreur réseau / délai dépassé
    }
  }

  /// Voie B (`data:`) : on ne peut pas re-fetcher l'image, on teste la PAGE.
  /// Le contrôle d'origine APRÈS redirection est l'essentiel — une page privée
  /// renvoie l'anonyme vers un autre hôte (`accounts.google.com`, `login.*`),
  /// et sans cette vérification on prendrait la page de connexion pour une
  /// preuve que la page est publique.
  private func isPagePublic(_ pageUrl: String) async -> Bool {
    if let cached = pagePublic[pageUrl] { return cached }
    var ok = false
    if let u = URL(string: pageUrl) {
      var req = URLRequest(url: u)
      req.timeoutInterval = Self.fetchTimeout
      if let (_, response) = try? await anonSession.data(for: req),
        let http = response as? HTTPURLResponse,
        (200..<300).contains(http.statusCode),
        (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
          .contains("text/html"),
        let final = http.url
      {
        ok = final.host?.lowercased() == u.host?.lowercased()
          && final.scheme == u.scheme
      }
    }
    if pagePublic.count > 500 { pagePublic.removeAll() }
    pagePublic[pageUrl] = ok
    return ok
  }

  // MARK: - Archive

  /// Écrit une archive et vide le tampon. Retourne le nom du fichier écrit.
  @discardableResult
  public func flush(reason: String = "manuel") async -> String? {
    guard !flushing, let store else { return nil }
    flushing = true
    defer { flushing = false }

    let entries = store.spoolEntries()
    guard !entries.isEmpty else { return nil }

    let now = Date()
    let f = DateFormatter()
    f.dateFormat = "yyyyMMdd-HHmmss"
    // 32 caractères et pas 16 : « karim-iphone-15-pro » tombait à
    // « karim-iphone-15 » dans le nom de fichier côté desktop, ce qui rend deux
    // appareils proches indistinguables à l'œil.
    let dev = String(
      cfg.device.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }.prefix(32))
    let name = "\(dev.isEmpty ? "anon" : dev)-\(f.string(from: now))-\(entries.count)img.zip"
    let url = store.archivesDir.appendingPathComponent(name)

    do {
      let writer = try ZipWriter(url: url, now: now)
      var lines: [String] = []
      for e in entries {
        try writer.add(name: "\(e.hash).jpg", fileURL: e.jpeg)
        if let line = String(data: e.row, encoding: .utf8) { lines.append(line) }
      }
      writer.add(
        name: "manifest.jsonl",
        data: Data((lines.joined(separator: "\n") + "\n").utf8))
      // `zips` compte CETTE archive comprise — sinon la première porte « 0 »,
      // ce qui se lit comme une anomalie.
      var snapshot = stats
      snapshot.zips += 1
      let enc = JSONEncoder()
      enc.outputFormatting = [.sortedKeys, .prettyPrinted]
      writer.add(name: "stats.json", data: (try? enc.encode(snapshot)) ?? Data("{}".utf8))
      try writer.finish()
    } catch {
      // Le tampon n'est PAS purgé : mieux vaut réécrire une archive en double
      // (les fichiers portent leur hash, `unzip -n` les fusionne) que perdre
      // des images. C'est la seule façon d'en perdre en silence.
      try? FileManager.default.removeItem(at: url)
      stats.spoolSince = Date().timeIntervalSince1970 * 1000
      persistStats()
      log.error("archive non écrite, tampon conservé : \(String(describing: error), privacy: .public)")
      return nil
    }

    store.removeFromSpool(entries.map(\.hash))
    stats.spoolBytes = 0
    stats.spoolSince = 0
    stats.zips += 1
    persistStats()
    log.info("\(name, privacy: .public) — \(entries.count, privacy: .public) images (\(reason, privacy: .public))")
    return name
  }

  // MARK: - Fabrication de l'image stockée

  struct Stored {
    let jpeg: Data
    let w: Int
    let h: Int
    let sw: Int
    let sh: Int
    let dhash: String
  }

  /// Décodage + redimension + réencodage, via **ImageIO** — pas UIKit, ce qui
  /// permet de tester tout ce fichier sur le Mac sans device ni simulateur.
  ///
  /// `CGImageSourceCreateThumbnailAtIndex` décode DIRECTEMENT à la taille
  /// voulue : sur une photo de 4000 px, décoder en pleine résolution pour
  /// réduire ensuite coûterait ~50 Mo de bitmap intermédiaire, sur un appareil
  /// où c'est précisément ce qu'on ne peut pas se permettre.
  ///
  /// On stocke en 1024 px de côté max, qualité 0,82 : le VLM d'annotation n'a
  /// pas besoin de plus (le ré-entraînement tourne en 416/640) et ça divise le
  /// volume du corpus par ~4.
  static func makeStored(_ data: Data, cfg: CollectConfig) -> Stored? {
    guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }

    // Dimensions d'ORIGINE : elles partent dans le manifeste, et servent à
    // l'analyse (une vignette de 200 px et une photo de 4000 px n'ont pas la
    // même valeur d'annotation même si elles sont stockées à la même taille).
    let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
    let originalW = (props?[kCGImagePropertyPixelWidth] as? Int) ?? 0
    let originalH = (props?[kCGImagePropertyPixelHeight] as? Int) ?? 0

    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: cfg.storeMaxSide,
      kCGImageSourceShouldCacheImmediately: true,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary)
    else { return nil }

    let out = NSMutableData()
    guard
      let dest = CGImageDestinationCreateWithData(
        out as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil)
    else { return nil }
    CGImageDestinationAddImage(
      dest, image,
      [kCGImageDestinationLossyCompressionQuality: cfg.jpegQuality] as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { return nil }

    return Stored(
      jpeg: out as Data,
      w: originalW > 0 ? originalW : image.width,
      h: originalH > 0 ? originalH : image.height,
      sw: image.width, sh: image.height,
      dhash: dHash(image))
  }

  /// dHash 64 bits (gradient horizontal sur 9×8 en niveaux de gris).
  ///
  /// Il n'est **PAS** utilisé pour rejeter en ligne : un quasi-doublon écarté à
  /// la collecte est perdu sans recours, alors qu'un dHash stocké laisse le
  /// regroupement au pipeline d'annotation, où le seuil se règle et se rejoue.
  static func dHash(_ image: CGImage) -> String {
    let w = 9, h = 8
    var pixels = [UInt8](repeating: 0, count: w * h)
    guard
      let ctx = CGContext(
        data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
        space: CGColorSpaceCreateDeviceGray(),
        bitmapInfo: CGImageAlphaInfo.none.rawValue)
    else { return String(repeating: "0", count: 16) }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

    var bits = ""
    for y in 0..<h {
      for x in 0..<(w - 1) {
        bits += pixels[y * w + x] > pixels[y * w + x + 1] ? "1" : "0"
      }
    }
    var hex = ""
    var index = bits.startIndex
    while index < bits.endIndex {
      let end = bits.index(index, offsetBy: 4, limitedBy: bits.endIndex) ?? bits.endIndex
      hex += String(Int(bits[index..<end], radix: 2) ?? 0, radix: 16)
      index = end
    }
    return hex
  }

  // MARK: - Utilitaires

  /// 128 bits : assez pour 10⁴ images (collision ~10⁻³⁰), et c'est la longueur
  /// que desktop écrit — les deux corpus se dédupliquent l'un l'autre par ce
  /// nom de fichier, il ne peut donc pas différer.
  static func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).prefix(16).map { String(format: "%02x", $0) }.joined()
  }

  static func shortHash(_ s: String) -> String {
    SHA256.hash(data: Data(s.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
  }

  /// URL sans query ni fragment — la partie qui DÉSIGNE la ressource, pas celle
  /// qui en ouvre l'accès.
  static func stripQuery(_ url: String) -> String {
    guard var c = URLComponents(string: url) else { return url }
    c.query = nil
    c.fragment = nil
    return c.string ?? url
  }

  static func today() -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.timeZone = .current
    return f.string(from: Date())
  }

  static func iso8601(_ d: Date) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    f.timeZone = TimeZone(secondsFromGMT: 0)
    return f.string(from: d)
  }

  private func host(of url: String) -> String {
    URL(string: url)?.host?.lowercased() ?? ""
  }

  private func note(_ dict: inout [String: Int], _ key: String) {
    guard ready else { return }
    bump(&dict, key)
    persistStats()
  }

  /// Écriture différée des compteurs : ils sont touchés à chaque image, et une
  /// écriture disque par image serait absurde pour quelques centaines d'octets.
  private var statsDirty = false
  private func persistStats() {
    guard !statsDirty else { return }
    statsDirty = true
    Task { [weak self] in
      try? await Task.sleep(nanoseconds: 5_000_000_000)
      await self?.writeStatsNow()
    }
  }

  private func writeStatsNow() {
    statsDirty = false
    store?.saveStats(stats)
  }

  /// À appeler quand l'app passe en arrière-plan : sans ça les compteurs des
  /// 5 dernières secondes sont perdus à chaque suspension, et sur téléphone une
  /// suspension arrive plusieurs fois par heure.
  public func persistNow() {
    writeStatsNow()
  }
}
