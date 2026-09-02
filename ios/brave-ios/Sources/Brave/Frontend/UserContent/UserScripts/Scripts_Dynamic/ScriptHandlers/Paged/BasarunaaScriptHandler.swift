// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Basarunaa
import BrowtherAnalytics
import Foundation
import OSLog
import Preferences
import Shared
import UIKit
import Web
import WebKit

protocol BasarunaaScriptHandlerDelegate: AnyObject {
  func basarunaaDidActivate(tab: (any TabState)?)
  func basarunaaDidApplyBlur(tab: (any TabState)?, imageCount: Int)
  func basarunaaDidEnterFakeFullscreen(tab: (any TabState)?)
  func basarunaaDidExitFakeFullscreen(tab: (any TabState)?)
}

/// V1 (étape A) : pas de ML. Le script JS injecté applique un `filter: blur()`
/// CSS sur toutes les `<img>` au pageload, et observe les images chargées
/// dynamiquement via `MutationObserver`. Ce handler gère uniquement le
/// lifecycle (page reset, métriques) en attendant le couplage ML de l'étape B.
///
/// Migration gender-v2n (2026-07-13) : le natif est désormais un **PUR
/// EXTRACTEUR** (cf. `private/docs/BASARUNAA_MOBILE_GENDER_V2N.md`). Il envoie
/// TOUTES les persons détectées (genre 3 classes + conf brute + keypoints) +
/// les prefs (mode/certitude) au JS. La **décision de flou vit dans
/// `core/policy.ts`**, appliquée côté bundle webkit — plus de `decide()` natif.
class BasarunaaScriptHandler: TabContentScript {

  weak var delegate: BasarunaaScriptHandlerDelegate?
  /// Métriques relevées en `notice` — celles qui servent à mesurer la cadence
  /// vidéo (cf. `case "metric"`). Tenir cette liste courte : chaque entrée
  /// ajoute ~4 lignes/seconde au syslog du device.
  private static let cadenceMetrics = [
    "yolo_send", "video_apply", "video_render", "sweep_step", "sweep_start", "caps",
  ]

  // ─── Thermique & batterie ───────────────────────────────────────────────
  //
  // Question de Karim (2026-08-29) : « il faut faire attention au fait que ça
  // chauffe de trop, c'est vraiment important — mais comment vérifier ? ».
  // Réponse : iOS l'expose lui-même. `ProcessInfo.thermalState` est l'état que
  // le système utilise pour décider de brider, et c'est la seule mesure qui
  // compte — la température en degrés n'est pas lisible sans API privée, et ne
  // dirait pas ce qu'on veut savoir (à partir de quand iOS nous ralentit).
  //
  //   nominal → fair → serious → critical
  //
  // `serious` = le système bride déjà. `critical` = l'app devient inutilisable,
  // exactement le scénario redouté. On relève l'état à chaque analyse mais on
  // ne journalise qu'aux CHANGEMENTS, plus un relevé toutes les 10 s — cadence
  // imposée par le %CPU, qui est un TAUX : sans relevés réguliers il n'existe
  // pas. L'état thermique seul se contenterait de bien moins.
  //
  // Lecture, en parallèle des métriques de cadence :
  //   idevicesyslog -u <udid> -m "THERMAL"
  // ─── Journal d'énergie — persistant, pour mesurer TÉLÉPHONE DÉBRANCHÉ ───
  //
  // Problème posé par Karim (2026-09-02) : « la diff est difficile à
  // quantifier ». Il a raison, et les deux sondes en place n'y répondent pas :
  // `app_cpu` ignore le GPU, et `thermalState` n'a que quatre crans qui mettent
  // des minutes à bouger. La seule grandeur qui intègre CPU + GPU + ANE, c'est
  // la **décharge de la batterie**.
  //
  // Mais elle ne bouge pas quand le téléphone charge — et c'est justement
  // branché qu'on lit le syslog. D'où ce journal : on relève un point toutes
  // les 30 s dans `UserDefaults`, et on le vide dans le log au démarrage
  // suivant. Karim teste débranché, rebranche, relance : la session précédente
  // se déverse d'un coup.
  //
  // Lecture : idevicesyslog -u <udid> -m "[ENERGY]"
  private static let energyKey = "basarunaa.energy.samples"
  private static let energyMaxSamples = 240  // 2 h à 30 s
  private var lastEnergyMs: Double = 0
  /// Palier de balayage actif, poussé par le JS — sans lui les points ne sont
  /// pas attribuables à une configuration.
  private var currentStep = "-"

  private func recordEnergyIfNeeded(_ nowMs: Double, thermal: String) {
    guard nowMs - lastEnergyMs >= 30_000 else { return }
    lastEnergyMs = nowMs
    let level = UIDevice.current.batteryLevel
    let charging = UIDevice.current.batteryState == .charging
      || UIDevice.current.batteryState == .full
    var samples = UserDefaults.standard.array(forKey: Self.energyKey) as? [String] ?? []
    samples.append(
      "\(Int(Date().timeIntervalSince1970));\(String(format: "%.2f", level));"
        + "\(charging ? 1 : 0);\(thermal);\(currentStep)"
    )
    if samples.count > Self.energyMaxSamples {
      samples.removeFirst(samples.count - Self.energyMaxSamples)
    }
    UserDefaults.standard.set(samples, forKey: Self.energyKey)
  }

  /// Déverse le journal de la session précédente, puis l'efface. Appelé une
  /// fois à l'init — c'est le moment où le téléphone vient d'être rebranché.
  private func flushEnergyLog() {
    let samples = UserDefaults.standard.array(forKey: Self.energyKey) as? [String] ?? []
    guard !samples.isEmpty else { return }
    UserDefaults.standard.removeObject(forKey: Self.energyKey)
    log.notice("[ENERGY] début — \(samples.count, privacy: .public) points (t;batterie;charge;thermal;palier)")
    for line in samples {
      log.notice("[ENERGY] \(line, privacy: .public)")
    }
    log.notice("[ENERGY] fin")
  }

  private var lastThermalState: ProcessInfo.ThermalState?
  private var lastThermalLogMs: Double = 0
  private var lastCpuSeconds: Double = 0
  private var lastCpuWallMs: Double = 0

  /// Temps CPU cumulé du process, threads vivants ET terminés.
  ///
  /// ⚠️ **Ce process est celui de l'APP, pas celui de la page.** Le WKWebView
  /// tourne dans un process WebContent séparé : le JS, le canvas et le repeint
  /// du flou n'apparaissent PAS ici, et on ne peut pas les mesurer d'ici sans
  /// API privée. Ce chiffre couvre donc l'inférence CoreML et le décodage
  /// base64 — le côté page est couvert par `video_render.render_pct` et
  /// `encode_ms`, mesurés là où ils se produisent. Les deux ensemble font le
  /// tour ; l'un des deux seul induit en erreur.
  private static func cpuSeconds() -> Double {
    var live = task_thread_times_info()
    var liveCount = mach_msg_type_number_t(
      MemoryLayout<task_thread_times_info>.size / MemoryLayout<natural_t>.size)
    let liveOk = withUnsafeMutablePointer(to: &live) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(liveCount)) {
        task_info(mach_task_self_, task_flavor_t(TASK_THREAD_TIMES_INFO), $0, &liveCount)
      }
    } == KERN_SUCCESS

    var basic = mach_task_basic_info()
    var basicCount = mach_msg_type_number_t(
      MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
    let basicOk = withUnsafeMutablePointer(to: &basic) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(basicCount)) {
        task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &basicCount)
      }
    } == KERN_SUCCESS

    var total: Double = 0
    if liveOk {
      total += Double(live.user_time.seconds) + Double(live.user_time.microseconds) / 1e6
      total += Double(live.system_time.seconds) + Double(live.system_time.microseconds) / 1e6
    }
    if basicOk {
      total += Double(basic.user_time.seconds) + Double(basic.user_time.microseconds) / 1e6
      total += Double(basic.system_time.seconds) + Double(basic.system_time.microseconds) / 1e6
    }
    return total
  }

  /// Relève l'état thermique + la batterie. Appelé à chaque analyse vidéo :
  /// c'est le seul endroit qui suit le rythme réel du pipeline.
  private func logThermalIfNeeded() {
    let state = ProcessInfo.processInfo.thermalState
    let nowMs = Date().timeIntervalSince1970 * 1000
    let changed = state != lastThermalState
    guard changed || nowMs - lastThermalLogMs >= 10_000 else { return }
    lastThermalState = state
    lastThermalLogMs = nowMs

    let name: String
    switch state {
    case .nominal: name = "nominal"
    case .fair: name = "fair"
    case .serious: name = "serious"
    case .critical: name = "critical"
    @unknown default: name = "unknown"
    }
    // `isBatteryMonitoringEnabled` est activé à l'init ; sans lui le niveau
    // vaut -1 et on croirait la batterie vide.
    let level = UIDevice.current.batteryLevel
    let battery = level < 0 ? "n/a" : String(format: "%.0f%%", level * 100)

    // %CPU depuis le dernier relevé. C'est LA mesure qui manquait : continue,
    // numérique, et qui réagit en secondes — là où `thermalState` n'a que
    // quatre niveaux et met des minutes à bouger. On compare des %CPU entre
    // configurations sans attendre que le téléphone chauffe, ni redescende.
    let cpu = Self.cpuSeconds()
    var cpuPct = "n/a"
    if lastCpuWallMs > 0 {
      let dtWall = (nowMs - lastCpuWallMs) / 1000
      if dtWall > 0.5 {
        cpuPct = String(format: "%.0f%%", 100 * (cpu - lastCpuSeconds) / dtWall)
      }
    }
    lastCpuSeconds = cpu
    lastCpuWallMs = nowMs

    log.notice(
      "[THERMAL] state=\(name, privacy: .public) battery=\(battery, privacy: .public) app_cpu=\(cpuPct, privacy: .public) changed=\(changed, privacy: .public)"
    )
    recordEnergyIfNeeded(nowMs, thermal: name)
  }

  private let log = Logger(subsystem: "com.devndin.browther", category: "Basarunaa.Handler")
  private static let staticLog = Logger(subsystem: "com.devndin.browther", category: "Basarunaa.Handler")
  private var isActive = false

  /// Pivot V2 (2026-05-17) : VTDecompressionSession + VP9 est bloqué par un
  /// entitlement Apple privé ⇒ on récupère les pixels rendus côté JS via
  /// `canvas.drawImage(video)` puis on bridge en JPEG.
  ///
  /// V4 (2026-05-20) : retrait du throttle natif sur `analyzeIntervalMs`. Le
  /// JS implémente le scheduling (one-tier single-shot depuis 2026-08-03 :
  /// gender-v2n à 250 ms en tracking, 5 s en safe + trigger scene-change),
  /// le natif ne doit pas mordre par-dessus — sinon les sendings JS sont
  /// drop silencieusement et `yoloInFlightById` reste figé (= flou freezé).
  /// Pour la même raison, `processVideoFrame` notifie *toujours* le JS, même
  /// en cas d'erreur de décodage / d'analyse.

  static let scriptName = "BasarunaaScript"
  static let scriptId = UUID().uuidString
  static let messageHandlerName = "\(scriptName)_\(messageUUID)"
  static let scriptSandbox: WKContentWorld = .page

  static let userScript: WKUserScript? = {
    guard let script = loadUserScript(named: scriptName) else { return nil }
    return WKUserScript(
      source: secureScript(
        handlerName: messageHandlerName,
        securityToken: scriptId,
        script: script
      ),
      injectionTime: .atDocumentStart,
      // [Browther 2026-08-09] false : un player embarqué vit dans un IFRAME
      // (Dailymotion & tous les embeds) — s'en tenir au frame principal
      // revenait à n'y rien flouter. ⚠️ Corollaire OBLIGATOIRE : toute réponse
      // au JS doit cibler le frame ÉMETTEUR (`frame:` ci-dessous), sinon elle
      // part dans le frame principal et l'iframe attend un verdict qui
      // n'arrive jamais — ses images resteraient masquées par hide-first, donc
      // floutées à vie. La charge (un scanner par iframe de pub) est bornée
      // côté JS par la garde micro-frame (core/frame-guard.ts).
      // Même correctif que desktop (manifest `all_frames`) et Android
      // (retrait des gates `IsMainFrame()` du RFO).
      forMainFrameOnly: false,
      in: scriptSandbox
    )
  }()

  init() {
    // Sans ça, `batteryLevel` renvoie -1 en permanence — une mesure qui a
    // l'air d'une valeur mais n'en est pas.
    UIDevice.current.isBatteryMonitoringEnabled = true
    flushEnergyLog()
    log.info("handler_init")
  }

  func tab(
    _ tab: some TabState,
    receivedScriptMessage message: WKScriptMessage,
    replyHandler: @escaping (Any?, String?) -> Void
  ) {
    defer { replyHandler(nil, nil) }

    if !verifyMessage(message: message) { return }

    guard let body = message.body as? [String: Any],
      let action = body["action"] as? String
    else { return }

    let data = body["data"] as? String ?? ""

    switch action {
    case "metric":
      // ⚠️ `Logger.info` ne sort PAS du téléphone : `idevicesyslog` ne le voit
      // pas et `log collect --device-udid` exige root. Les métriques de
      // CADENCE vidéo doivent donc partir en `notice`, sinon on croit avoir
      // instrumenté alors qu'on ne peut rien lire.
      //
      // On ne relève pas tout : `yolo_send` / `video_apply` tombent ~4×/s et
      // suffisent à borner le tour complet. Le reste (scene_change,
      // yolo_skip_static, …) resterait utile mais noierait la lecture —
      // l'ajouter ici au cas par cas, pas en bloc.
      //   idevicesyslog -u <udid> -m "[METRIC]"
      if Self.cadenceMetrics.contains(where: { data.contains("\"event\":\"\($0)\"") }) {
        log.notice("[METRIC] \(data, privacy: .public)")
        if let r = data.range(of: "\"step\":\""),
          let end = data[r.upperBound...].firstIndex(of: "\"") {
          currentStep = String(data[r.upperBound..<end])
        }
        logThermalIfNeeded()
      } else {
        log.info("[METRIC] \(data, privacy: .public)")
      }

    case "log":
      log.info("[JS] \(data, privacy: .public)")

    case "scriptReady":
      // État D'ONGLET (badge toolbar, activation) : seul le frame principal
      // le pilote. Depuis `forMainFrameOnly: false`, chaque iframe exécute le
      // script et enverrait sinon sa propre activation.
      guard message.frameInfo.isMainFrame else { return }
      if !isActive {
        isActive = true
        delegate?.basarunaaDidActivate(tab: tab)
        // Précharge le détecteur CoreML en tâche de fond dès que Basarunaa est
        // actif sur une page → évite le cold-start ~5s à la 1re image analysée.
        // Idempotent (le détecteur est mis en cache dans l'actor).
        Task.detached { await BasarunaaPipeline.shared.warmup() }
      }
      log.info("script_ready url=\(data, privacy: .public)")

    case "blurApplied":
      // État d'onglet (compteur affiché) → frame principal seulement.
      guard message.frameInfo.isMainFrame else { return }
      // data = "<initialImageCount>"
      let count = Int(data) ?? 0
      delegate?.basarunaaDidApplyBlur(tab: tab, imageCount: count)
      log.info("blur_applied count=\(count, privacy: .public)")

    case "statsBlurred":
      // data = "<count>" — le JS a décidé (core/policy) et floute N persons.
      // Compteur cumulatif "personnes floutées" de la NTP (parité Sawtunaa).
      let count = Int(data) ?? 0
      if count > 0 {
        BrowtherStatsReporter.shared.addPersonsBlurred(count)
      }

    case "analyzeImage":
      // data = "<id>|<w>|<h>|<queueDepth>|<srcUrlB64>|<base64Jpeg>"
      //
      // ⚠️ Le format historique était "<id>|<base64Jpeg>". Le parsing accepte
      // les deux : le bundle JS et le binaire natif ne sont pas déployés
      // ensemble (le premier est un fichier copié, le second un build de 40
      // minutes), donc un natif neuf DOIT tolérer un bundle ancien. Sinon la
      // moindre désynchronisation ne floute plus rien du tout.
      guard let parsed = Self.parseAnalyzeImage(data) else { return }
      let typeErasedTab: any TabState = tab
      let sourceFrame = message.frameInfo
      // Contexte de collecte. Le drapeau de navigation privée vient de
      // l'ONGLET, jamais du script de page : un script peut être trompé, et
      // c'est la garantie qu'on ne collecte rien en navigation privée.
      let collectContext = CollectContext(
        srcUrl: parsed.srcUrl,
        pageUrl: tab.visibleURL?.absoluteString ?? tab.url?.absoluteString ?? "",
        width: parsed.width,
        height: parsed.height,
        queueDepth: parsed.queueDepth,
        incognito: tab.isPrivate)
      Task.detached { [weak self] in
        await self?.processImage(
          id: parsed.id, base64: parsed.jpegB64, tab: typeErasedTab,
          frame: sourceFrame, collect: collectContext)
      }

    case "pageReset":
      // ⚠️ Sans ce gate, un iframe de pub qui se recharge éteindrait le badge
      // de TOUT l'onglet alors que la page principale tourne toujours.
      guard message.frameInfo.isMainFrame else { return }
      isActive = false
      log.info("page_reset url=\(data, privacy: .public)")

    case "fullscreenEnter":
      delegate?.basarunaaDidEnterFakeFullscreen(tab: tab)
      log.info("fake_fullscreen_enter")

    case "fullscreenExit":
      delegate?.basarunaaDidExitFakeFullscreen(tab: tab)
      log.info("fake_fullscreen_exit")

    case "videoFrame":
      // data = "<videoId>|<ct_ms>|<w>|<h>|<sceneOpening>|<base64Jpeg>"
      // (format antérieur au 2026-08-28 : sans <sceneOpening> — toléré, cf.
      //  la même remarque que pour analyzeImage sur la désynchronisation
      //  bundle JS / binaire natif.)
      //
      // Le base64 peut être gros (10+ KB) → on évite toute opération inutile
      // sur le data string en main thread (split est O(N)). On récupère
      // l'en-tête en cherchant les pipes à la main, puis on extrait le b64
      // en slice de String.
      var pipePositions: [String.Index] = []
      pipePositions.reserveCapacity(5)
      var idx = data.startIndex
      while pipePositions.count < 5, let next = data[idx...].firstIndex(of: "|") {
        pipePositions.append(next)
        idx = data.index(after: next)
      }
      guard pipePositions.count >= 4 else {
        log.error("videoFrame parse failed (no 4 pipes)")
        return
      }
      let v1Start = data.startIndex
      let v1End = pipePositions[0]
      let v2Start = data.index(after: pipePositions[0])
      let v2End = pipePositions[1]
      let v3Start = data.index(after: pipePositions[1])
      let v3End = pipePositions[2]
      let v4Start = data.index(after: pipePositions[2])
      let v4End = pipePositions[3]
      guard let videoId = Int(data[v1Start..<v1End]),
        let ctMs = Int64(data[v2Start..<v2End]),
        let w = Int(data[v3Start..<v3End]),
        let h = Int(data[v4Start..<v4End])
      else {
        log.error("videoFrame header parse failed")
        return
      }
      var sceneOpening = false
      var payloadStart = data.index(after: pipePositions[3])
      if pipePositions.count == 5 {
        sceneOpening = data[payloadStart..<pipePositions[4]] == "1"
        payloadStart = data.index(after: pipePositions[4])
      }
      // V4 : pas de throttle natif — le JS pilote sa propre cadence (250 ms
      // en tracking, 5s en safe + trigger scene-change). Tout drop natif sans
      // callback fige `yoloInFlightById` côté JS (= flou freezé).
      let b64 = String(data[payloadStart...])
      let typeErasedTab: any TabState = tab
      let sourceFrame = message.frameInfo
      // ⚠️ La frame d'ANALYSE ne va plus au corpus (correction du 2026-08-28,
      // le soir même de sa livraison). Elle est encodée en 320 px q0,5 pour le
      // modèle ; à cette taille les labels `level`/`adult` de la rubrique ne
      // sont pas établissables, donc les images étaient collectées pour rien —
      // constaté en relisant le tampon réel du device. Le corpus reçoit
      // désormais une capture DÉDIÉE en pleine qualité, via `corpusFrame`.
      // `sceneOpening` reste dans le payload : il ne sert plus qu'au diagnostic.
      _ = sceneOpening
      Task.detached { [weak self] in
        await self?.processVideoFrame(
          videoId: videoId, ctMs: ctMs, width: w, height: h, b64: b64,
          tab: typeErasedTab, frame: sourceFrame
        )
      }

    case "corpusFrame":
      // data = "<videoId>|<w>|<h>|<base64Jpeg>" — ouverture de scène, capture
      // pleine qualité destinée UNIQUEMENT à la collecte de corpus. Aucune
      // analyse n'est lancée dessus : les verdicts viennent de la frame
      // d'analyse voisine, déjà traitée.
      var cPipes: [String.Index] = []
      var cIdx = data.startIndex
      while cPipes.count < 3, let next = data[cIdx...].firstIndex(of: "|") {
        cPipes.append(next)
        cIdx = data.index(after: next)
      }
      guard cPipes.count == 3,
        let cVideoId = Int(data[data.startIndex..<cPipes[0]]),
        let cw = Int(data[data.index(after: cPipes[0])..<cPipes[1]]),
        let ch = Int(data[data.index(after: cPipes[1])..<cPipes[2]]),
        let cJpeg = Data(base64Encoded: String(data[data.index(after: cPipes[2])...]))
      else {
        log.error("corpusFrame parse failed")
        return
      }
      let cPageUrl = tab.visibleURL?.absoluteString ?? tab.url?.absoluteString ?? ""
      let cPrivate = tab.isPrivate
      let cDet = Self.sharedVideoDet[cVideoId] ?? CollectDetection(pf: nil, raw: 0, ok: 0, confs: [])
      Task.detached {
        await Collector.shared.offerVideoFrame(
          videoKey: "\(cPageUrl)#\(cVideoId)", pageUrl: cPageUrl, det: cDet,
          width: cw, height: ch, jpeg: cJpeg, incognito: cPrivate, queueDepth: 0)
      }

    default:
      log.info("unknown_action=\(action, privacy: .public)")
    }
  }

  // MARK: - Verdicts vidéo récents (appariement avec la capture de corpus)

  /// Dernier verdict par vidéo, borné. Statique parce que le handler est
  /// instancié par onglet alors que la capture de corpus et l'analyse peuvent
  /// venir de frames différentes ; borné parce qu'un dictionnaire indexé par
  /// identifiant de vidéo grossirait sur une session de navigation longue.
  @MainActor private static var sharedVideoDet: [Int: CollectDetection] = [:]

  @MainActor
  static func rememberVideoDet(videoId: Int, det: CollectDetection) {
    if sharedVideoDet.count > 64 { sharedVideoDet.removeAll() }
    sharedVideoDet[videoId] = det
  }

  // MARK: - Parsing des payloads JS

  /// Contexte nécessaire à la collecte de corpus, assemblé côté handler parce
  /// que c'est le seul endroit qui voit à la fois le message du JS et l'onglet.
  struct CollectContext: Sendable {
    let srcUrl: String
    let pageUrl: String
    let width: Int
    let height: Int
    let queueDepth: Int
    let incognito: Bool
  }

  struct ParsedAnalyzeImage {
    let id: Int
    let width: Int
    let height: Int
    let queueDepth: Int
    let srcUrl: String
    let jpegB64: String
  }

  /// `<id>|<w>|<h>|<queueDepth>|<srcUrlB64>|<jpeg>` — ou l'ancien `<id>|<jpeg>`.
  ///
  /// Découpage à la main plutôt que `split(separator:)` : le base64 du JPEG
  /// pèse souvent plus de 100 Ko, et `split` construirait un tableau de sous-
  /// chaînes en parcourant TOUT le payload alors que les cinq séparateurs
  /// utiles sont dans les 200 premiers octets. C'est du travail sur le thread
  /// principal, à chaque image analysée.
  static func parseAnalyzeImage(_ data: String) -> ParsedAnalyzeImage? {
    var bounds: [String.Index] = []
    bounds.reserveCapacity(5)
    var cursor = data.startIndex
    while bounds.count < 5, let next = data[cursor...].firstIndex(of: "|") {
      bounds.append(next)
      cursor = data.index(after: next)
    }
    guard let first = bounds.first, let id = Int(data[data.startIndex..<first]) else {
      return nil
    }

    // Format historique : un seul séparateur, aucun contexte de collecte.
    guard bounds.count == 5 else {
      return ParsedAnalyzeImage(
        id: id, width: 0, height: 0, queueDepth: 0, srcUrl: "",
        jpegB64: String(data[data.index(after: first)...]))
    }

    func field(_ i: Int) -> Substring {
      data[data.index(after: bounds[i - 1])..<bounds[i]]
    }
    let width = Int(field(1)) ?? 0
    let height = Int(field(2)) ?? 0
    let queueDepth = Int(field(3)) ?? 0
    var srcUrl = ""
    if let decoded = Data(base64Encoded: String(field(4))),
      let text = String(data: decoded, encoding: .utf8)
    {
      srcUrl = text
    }
    return ParsedAnalyzeImage(
      id: id, width: width, height: height, queueDepth: queueDepth, srcUrl: srcUrl,
      jpegB64: String(data[data.index(after: bounds[4])...]))
  }

  // MARK: - Prefs envoyées au JS (la policy vit dans core/policy.ts)

  /// Payload prefs pour le JS : mode + seuil de certitude + filtre main-seule.
  /// `minSkeletonActive` = pref `min_skeleton` > 0 (toggle « Ignorer les mains
  /// seules » du panel, parité desktop).
  private func prefsPayload() -> [String: Any] {
    [
      "mode": Preferences.Basarunaa.effectiveMode,
      "genderCertainty": Preferences.Basarunaa.genderCertainty.value,
      "minSkeletonActive": Preferences.Basarunaa.minSkeleton.value > 0,
    ]
  }

  // MARK: - Video frame processing (pivot D)

  /// Décompresse un JPEG capturé par JS (`canvas.drawImage(video)`), invoque
  /// `BasarunaaPipeline.analyze` (single-shot gender-v2n) puis push TOUTES les
  /// persons + les prefs au JS overlay, qui applique la policy (core/policy).
  ///
  /// V4 (2026-05-20) : appelle TOUJOURS `__basarunaaApplyVideo` côté JS, même
  /// en cas d'erreur (persons vides). Sans ça, le JS reste figé sur
  /// `yoloInFlightById = true` et le scheduler arrête de fire des YOLO →
  /// flou freezé jusqu'au pageReset.
  private func processVideoFrame(
    videoId: Int, ctMs: Int64, width: Int, height: Int, b64: String,
    tab: any TabState, frame: WKFrameInfo
  ) async {
    let start = Date()
    var personsPayload: [[String: Any]] = []
    var isNsfw = false
    var personsCount = 0
    var poseLatencyMs: Double = 0
    var classifyLatencyMs: Double = 0
    var nudeClasses: [String] = []
    let debugMode = Preferences.Basarunaa.debugMode.value

    decode: do {
      guard let jpegData = Data(base64Encoded: b64) else {
        log.error("videoFrame base64 decode failed videoId=\(videoId, privacy: .public)")
        break decode
      }
      guard let uiImage = UIImage(data: jpegData), let cgImage = uiImage.cgImage else {
        log.error(
          "videoFrame jpeg decode failed videoId=\(videoId, privacy: .public) bytes=\(jpegData.count, privacy: .public)"
        )
        break decode
      }
      do {
        // Pipeline vidéo : `analyze` (persons + gender) + `checkNsfw` (Marqo +
        // NudeNet) en parallèle — sinon le branch `if isNsfw` côté JS ne fire
        // jamais (analyze() retourne toujours isNsfw=false par design). NSFW
        // gaté sur la pref (opt-in, OFF par défaut — Marqo CPU-bound ~120ms).
        let result: BasarunaaResult
        let nsfw: (isNsfw: Bool, score: Double?, latencyMs: Double, nudeClasses: [String])?
        if Preferences.Basarunaa.nsfwEnabled.value {
          async let nsfwAsync = BasarunaaPipeline.shared.checkNsfw(image: cgImage)
          result = try await BasarunaaPipeline.shared.analyze(image: cgImage)
          nsfw = try? await nsfwAsync
        } else {
          result = try await BasarunaaPipeline.shared.analyze(image: cgImage)
          nsfw = nil
        }
        // PUR EXTRACTEUR : on envoie TOUTES les persons ; le JS (core/policy)
        // décide lesquelles flouter et remonte le compte via "statsBlurred".
        personsPayload = serialize(persons: result.persons)
        isNsfw = nsfw?.isNsfw ?? false
        personsCount = result.persons.count
        poseLatencyMs = result.poseLatencyMs
        classifyLatencyMs = result.classifyLatencyMs
        nudeClasses = nsfw?.nudeClasses ?? []
        // Capture mode — sauvegarde la frame raw + metadata pour dataset ML.
        if Preferences.Basarunaa.captureMode.value {
          Self.saveCapture(
            jpegData: jpegData,
            videoId: videoId,
            width: width,
            height: height,
            ctMs: ctMs,
            mode: Preferences.Basarunaa.effectiveMode,
            isNsfw: isNsfw,
            persons: result.persons,
            poseLatencyMs: result.poseLatencyMs,
            classifyLatencyMs: result.classifyLatencyMs
          )
        }
      } catch {
        log.error(
          "videoFrame analyze failed videoId=\(videoId, privacy: .public): \(String(describing: error), privacy: .public)"
        )
      }
    }

    let elapsedMs = Date().timeIntervalSince(start) * 1000
    log.info(
      """
      video_analyzed videoId=\(videoId, privacy: .public) ct_ms=\(ctMs, privacy: .public) \
      w=\(width, privacy: .public) h=\(height, privacy: .public) \
      persons=\(personsCount, privacy: .public) \
      nsfw=\(isNsfw, privacy: .public) elapsed=\(String(format: "%.0f", elapsedMs), privacy: .public)ms
      """
    )

    // ALWAYS notify the JS — even on error — to release `yoloInFlightById`.
    // Nouveau contrat : on envoie `persons` (toutes) + `prefs` au lieu de
    // `bboxes` — le JS calcule les régions à flouter via core/policy.
    let prefs = prefsPayload()
    do {
      _ = try await tab.evaluateJavaScript(
        functionName: "window.__basarunaaApplyVideo",
        args: [
          videoId, ctMs, width, height, personsPayload, isNsfw, debugMode,
          prefs,
          [
            "poseLatencyMs": poseLatencyMs,
            "classifyLatencyMs": classifyLatencyMs,
            "mode": Preferences.Basarunaa.effectiveMode,
            "nudeClasses": nudeClasses,
          ] as [String: Any],
        ],
        frame: frame,
        contentWorld: Self.scriptSandbox
      )
    } catch {
      log.error(
        "videoFrame evaluateJS failed videoId=\(videoId, privacy: .public): \(String(describing: error), privacy: .public)"
      )
    }

    // Le verdict de CETTE frame est mémorisé pour la capture de corpus qui
    // arrive juste après (message `corpusFrame`) : c'est lui qui donne la
    // strate et la pondération. Les deux frames sont prises à quelques
    // millisecondes d'écart sur la même scène — l'appariement est bon, et il
    // évite de relancer une inférence sur l'image pleine qualité.
    await MainActor.run {
      Self.rememberVideoDet(
        videoId: videoId,
        det: CollectDetection(
          pf: nil, raw: personsCount, ok: personsCount,
          confs: personsPayload.compactMap { $0["genderConfidence"] as? Double }))
    }
  }

  // MARK: - ML coupling (image)

  private func processImage(
    id: Int, base64: String, tab: any TabState, frame: WKFrameInfo,
    collect: CollectContext? = nil
  ) async {
    let start = Date()
    guard let imageData = Data(base64Encoded: base64),
      let uiImage = UIImage(data: imageData),
      let cgImage = uiImage.cgImage
    else {
      log.error("analyze[\(id, privacy: .public)] failed to decode base64")
      await reply(
        tab: tab, id: id, persons: [], debugMode: "none", elapsedMs: 0,
        frame: frame)
      return
    }

    do {
      // `useVerifier: true` — pré-filtre + vérificateur NanoDet, sur les IMAGES
      // seulement (parité desktop : le pré-filtre vit dans l'offscreen, qui ne
      // voit que les images ; la vidéo passe par un autre chemin des deux côtés).
      let result = try await BasarunaaPipeline.shared.analyze(
        image: cgImage, useVerifier: true)
      let debugMode = Preferences.Basarunaa.debugMode.value
      // PUR EXTRACTEUR : on envoie TOUTES les persons + prefs. Le JS
      // (core/policy) décide keep/remove et lesquelles flouter.
      let personsPayload = serialize(persons: result.persons)
      let elapsedMs = Date().timeIntervalSince(start) * 1000
      log.info(
        """
        analyze[\(id, privacy: .public)] persons=\(result.persons.count, privacy: .public) \
        debug=\(debugMode, privacy: .public) (\(String(format: "%.0f", elapsedMs), privacy: .public)ms)
        """
      )
      await reply(
        tab: tab,
        id: id,
        persons: personsPayload,
        debugMode: debugMode,
        elapsedMs: elapsedMs,
        frame: frame
      )

      // Collecte de corpus (opt-in) — APRÈS que le verdict soit parti vers le
      // JS. L'ordre est la garantie « zéro coût sur le chemin critique » : le
      // flou est déjà appliqué quand la collecte commence à réfléchir, et tout
      // son travail réel (GET anonyme, décodage, hash) part dans une file
      // séparée à l'intérieur du collecteur.
      if let collect {
        await Collector.shared.offerImage(
          srcUrl: collect.srcUrl,
          pageUrl: collect.pageUrl,
          det: result.det,
          width: collect.width,
          height: collect.height,
          jpeg: imageData,
          incognito: collect.incognito,
          queueDepth: collect.queueDepth)
      }

      // Phase 2 (POC parity) — fire NSFW check in the background. Only
      // notify JS when the result is positive. Gaté sur la pref (opt-in, OFF
      // par défaut — Marqo CPU-bound). Quand OFF : pas de check du tout.
      if Preferences.Basarunaa.nsfwEnabled.value {
        let weakLog = self.log
        Task.detached { [weak tab] in
          do {
            let nsfwResult = try await BasarunaaPipeline.shared.checkNsfw(image: cgImage)
            if nsfwResult.isNsfw, let tab {
              await Self.applyNsfwOverlay(
                tab: tab,
                id: id,
                score: nsfwResult.score ?? 1.0,
                frame: frame,
                log: weakLog
              )
            }
          } catch {
            weakLog.error("checkNsfw[\(id, privacy: .public)] failed: \(String(describing: error), privacy: .public)")
          }
        }
      }
    } catch {
      log.error("analyze[\(id, privacy: .public)] failed: \(String(describing: error), privacy: .public)")
      await reply(
        tab: tab, id: id, persons: [], debugMode: "none", elapsedMs: 0,
        frame: frame)
    }
  }

  /// Phase 2 notification — fires `window.__basarunaaApplyNsfw(id, score)`
  /// on the page so the JS can replace the per-person blur with a full
  /// image blur. Called only when NSFW is positive.
  @MainActor
  private static func applyNsfwOverlay(
    tab: any TabState,
    id: Int,
    score: Double,
    frame: WKFrameInfo,
    log: Logger
  ) async {
    do {
      _ = try await tab.evaluateJavaScript(
        functionName: "window.__basarunaaApplyNsfw",
        args: [id, score],
        frame: frame,
        contentWorld: BasarunaaScriptHandler.scriptSandbox
      )
    } catch {
      log.error(
        "applyNsfwOverlay failed for id=\(id, privacy: .public): \(String(describing: error), privacy: .public)"
      )
    }
  }

  @MainActor
  private func reply(
    tab: any TabState,
    id: Int,
    persons: [[String: Any]],
    debugMode: String,
    elapsedMs: Double,
    frame: WKFrameInfo
  ) async {
    do {
      _ = try await tab.evaluateJavaScript(
        functionName: "window.__basarunaaApply",
        args: [id, persons, prefsPayload(), debugMode, elapsedMs],
        frame: frame,
        contentWorld: Self.scriptSandbox
      )
    } catch {
      log.error(
        "evaluateJavaScript failed for id=\(id, privacy: .public): \(String(describing: error), privacy: .public)"
      )
    }
  }

  /// Représentation compacte pour le JS (pur extracteur, single-shot gender-v2n).
  /// Envoie par personne :
  /// - `bbox` `[x1, y1, x2, y2]`
  /// - `keypoints` 17 COCO points `[x, y, conf]` (JS rebuild le body-polygon)
  /// - `gender` `'male' | 'female' | 'child'` (classe argmax brute)
  /// - `genderConfidence` (score de la classe = score de détection)
  private func serialize(persons: [DetectedPerson]) -> [[String: Any]] {
    persons.map { p in
      let kps = p.keypoints.map { kp -> [Double] in
        [kp.point.x, kp.point.y, kp.confidence]
      }
      return [
        "bbox": [p.bbox.minX, p.bbox.minY, p.bbox.maxX, p.bbox.maxY] as [Double],
        "keypoints": kps,
        "gender": p.gender.rawValue,
        "genderConfidence": p.genderConfidence,
      ]
    }
  }

  deinit {
    log.info("handler_deinit")
  }

  /// Capture mode — sauvegarde une frame analysée dans `Documents/Basarunaa-capture/`.
  /// Crée 2 fichiers par capture : `{ts}-v{videoId}-raw.jpg` + `-meta.json`
  /// (mode, NSFW, bboxes, gender 3-classes, keypoints, latency). Dataset ML.
  private static func saveCapture(
    jpegData: Data,
    videoId: Int,
    width: Int,
    height: Int,
    ctMs: Int64,
    mode: String,
    isNsfw: Bool,
    persons: [DetectedPerson],
    poseLatencyMs: Double,
    classifyLatencyMs: Double
  ) {
    let fm = FileManager.default
    guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
    let dir = docs.appendingPathComponent("Basarunaa-capture", isDirectory: true)
    do {
      if !fm.fileExists(atPath: dir.path) {
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
      }
    } catch {
      staticLog.error("captureMode mkdir failed: \(String(describing: error), privacy: .public)")
      return
    }
    let ts = Int(Date().timeIntervalSince1970 * 1000)  // ms epoch
    let base = "\(ts)-v\(videoId)"
    let rawUrl = dir.appendingPathComponent("\(base)-raw.jpg")
    let metaUrl = dir.appendingPathComponent("\(base)-meta.json")
    do {
      try jpegData.write(to: rawUrl, options: .atomic)
    } catch {
      staticLog.error("captureMode raw write failed: \(String(describing: error), privacy: .public)")
      return
    }
    let personsMeta: [[String: Any]] = persons.map { p in
      var dict: [String: Any] = [
        "bbox": [p.bbox.minX, p.bbox.minY, p.bbox.maxX, p.bbox.maxY] as [Double],
        "gender": p.gender.rawValue,
        "genderConfidence": p.genderConfidence,
      ]
      dict["keypoints"] = p.keypoints.map { [$0.point.x, $0.point.y, $0.confidence] }
      return dict
    }
    let meta: [String: Any] = [
      "videoId": videoId,
      "ctMs": ctMs,
      "width": width,
      "height": height,
      "mode": mode,
      "isNsfw": isNsfw,
      "personsCount": persons.count,
      "poseLatencyMs": poseLatencyMs,
      "classifyLatencyMs": classifyLatencyMs,
      "persons": personsMeta,
    ]
    do {
      let json = try JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted, .sortedKeys])
      try json.write(to: metaUrl, options: .atomic)
    } catch {
      staticLog.error("captureMode meta write failed: \(String(describing: error), privacy: .public)")
    }
    staticLog.info("captureMode saved \(base, privacy: .public)")
  }
}
