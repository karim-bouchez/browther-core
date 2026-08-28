// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Basarunaa — politique d'échantillonnage du corpus de navigation (opt-in).
///
/// Port FIDÈLE de `private/extensions/basarunaa/src/collect/policy.js` — mêmes
/// strates, mêmes bornes, mêmes taux, même formule de charge. Les deux corpus
/// (desktop + iOS) sont destinés à être fusionnés : un seuil qui diverge ici
/// biaiserait la moitié mobile du corpus sans que rien ne le signale.
///
/// Module PUR : aucun I/O, aucun UIKit, aucune préférence lue. C'est la pièce
/// qu'on doit pouvoir relire et discuter sans lire le reste, parce que c'est
/// elle qui décide ce qui entre dans le corpus — donc ce que le prochain
/// gender-v2n apprendra. Testé par `private/scripts/ios-collect-tests/`, qui
/// rejoue les assertions de `scripts/test_collect_policy.mjs`.
///
/// ── L'idée centrale ────────────────────────────────────────────────────────
/// On ne cherche PAS un échantillon uniforme : on ne peut pas tout garder, et
/// un échantillon uniforme du web serait à ~78 % des images sans humain —
/// inexploitable pour réapprendre le genre. On fait donc un échantillonnage
/// STRATIFIÉ, et on écrit dans le manifeste la probabilité d'inclusion RÉELLE
/// de chaque image gardée (`p`) et son poids `1/p`. Tout biais introduit ici
/// devient alors corrigeable hors-ligne par pondération inverse.

// MARK: - Strates

/// Strates, dans l'ordre de priorité de `classify` (première qui matche gagne).
public enum CollectStratum: String, CaseIterable, Sendable {
  /// gender-v2n voit quelqu'un, le vérificateur non → faux positif probable.
  /// ⚠️ Ne se déclenche JAMAIS sur iOS : voir `classify`.
  case fpSuspect = "fp-suspect"
  /// Le vérificateur voit quelqu'un, gender-v2n non → fuite (personne ratée).
  /// ⚠️ Ne se déclenche JAMAIS sur iOS : voir `classify`.
  case leakSuspect = "leak-suspect"
  /// Détection dont la confiance tombe dans la zone du curseur utilisateur.
  case borderline
  /// Cas nominal : une personne détectée.
  case person
  /// Aucune figure — la majorité du web, indispensable au taux de faux positifs.
  case empty
  /// Frame d'ouverture de scène vidéo (quota strictement séparé).
  case videoScene = "video-scene"
}

/// Bornes de la zone « le curseur utilisateur tranche » (`gender_certainty` =
/// 0,70 par défaut). Une détection dont la confiance tombe là-dedans est
/// exactement celle qui bascule quand l'utilisateur bouge le slider d'un cran.
private let borderlineLo = 0.45
private let borderlineHi = 0.78

/// Verdicts des modèles pour une image, tels que le pipeline les connaît déjà.
///
/// - `pf`  : nb de boîtes `person` du pré-filtre généraliste (NanoDet).
///           **Toujours `nil` sur iOS** — le sentinel a été retiré le
///           2026-08-04 (vidéo one-tier, −4,8 Mo). Le champ est conservé parce
///           que le manifeste est partagé avec desktop : `null` s'y lit comme
///           « pas d'information », pas comme « zéro personne ».
/// - `raw` : nb de détections gender-v2n AVANT vérification.
/// - `ok`  : nb de détections retenues APRÈS vérification (= `raw` sur iOS,
///           faute de vérificateur).
/// - `confs` : confiances des détections retenues.
public struct CollectDetection: Sendable, Equatable {
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
}

/// Strate d'une image, à partir des verdicts DÉJÀ calculés par le pipeline.
///
/// ⚠️ **Sur iOS, `fpSuspect` et `leakSuspect` sont inatteignables** — et c'est
/// structurel, pas un oubli. Les deux mesurent un DÉSACCORD entre gender-v2n et
/// un détecteur généraliste ; iOS n'en a plus (`pf == nil`) et le natif est un
/// pur extracteur (`raw == ok`, la décision de flou vit dans `core/policy.ts`).
/// Le corpus iOS ne portera donc que `borderline` / `person` / `empty`, ce que
/// `det.pf == null` rend lisible hors-ligne au lieu de le laisser deviner.
/// La fonction est portée telle quelle malgré tout : elle est la même sur les
/// deux plateformes, et desktop a exactement ce comportement quand son
/// pré-filtre est en repli.
public func classify(_ det: CollectDetection) -> CollectStratum {
  // Désaccord descendant : le modèle a vu quelqu'un là où le généraliste voit
  // un chien / une peluche / un beignet.
  if det.raw > det.ok { return .fpSuspect }
  // Désaccord montant : le généraliste voit un humain que gender-v2n rate.
  // C'est le mode de défaillance le plus coûteux en usage (l'utilisateur voit
  // une personne non floutée, il ne signale pas, il désactive).
  if let pf = det.pf, pf > 0, det.ok == 0 { return .leakSuspect }
  if det.ok > 0, det.confs.contains(where: { $0 >= borderlineLo && $0 <= borderlineHi }) {
    return .borderline
  }
  if det.ok > 0 { return .person }
  return .empty
}

// MARK: - Configuration

/// Réglages de la collecte.
///
/// ── Écart assumé avec desktop : il n'y a PAS de configuration persistée ─────
/// Desktop stocke un objet de config dans `chrome.storage`, ce qui lui a coûté
/// trois pannes (`CONFIG_VERSION`, une config vide figée, une page de contrôle
/// qui rallumait la collecte en boucle). Ici les réglages fins sont des
/// **constantes de code**, et seuls les deux choix qui appartiennent vraiment à
/// l'utilisateur — l'activation et le nom d'appareil — sont des préférences.
/// Toute cette classe de bugs disparaît avec la config persistée.
public struct CollectConfig: Sendable {
  // Probabilité d'inclusion de BASE par strate, AVANT facteurs de charge/quota.
  //
  // Recalibré le 2026-08-23 sur une vraie journée de navigation : 979 images
  // vues, dont **207 seulement** portaient une figure. La ressource rare n'est
  // donc pas le disque — c'est l'image avec des gens dedans. Règle retenue :
  // **prendre presque tout ce qui porte une figure, échantillonner le reste**.
  //
  // ⚠️ `empty` à 0,25 et pas plus bas (objection Karim, décisive) : le bug qu'on
  // répare est un FAUX POSITIF. gender-v2n, dont les 3 classes sont toutes
  // humaines, appelle « personne » un vase ou un chien parce qu'il n'a jamais
  // appris à quoi ressemble une non-personne. Un corpus fait surtout de figures
  // referait l'erreur d'origine. Et on ne peut pas VISER les images vides
  // intéressantes (le pré-filtre ne remonte que la classe `person`), donc on
  // ratisse — la pondération `wgt` garde l'ensemble repondérable.
  public var rates: [CollectStratum: Double] = [
    .fpSuspect: 0.95,
    .leakSuspect: 0.95,
    .borderline: 0.95,
    .person: 0.85,
    .empty: 0.25,
    .videoScene: 0.60,
  ]

  /// < 128 px de côté max : icône/avatar, inannotable (`level`/`adult` ne sont
  /// pas établissables de façon fiable en dessous).
  public var minSide: Int = 128
  /// Redimension avant stockage — divise le volume par ~4, suffit au VLM
  /// d'annotation qui tourne de toute façon en 416/640.
  public var storeMaxSide: Int = 1024
  public var jpegQuality: Double = 0.82

  /// Au-delà, la proba décroît en `softCap/n` sur ce domaine.
  public var domainSoftCap: Int = 100
  /// Au-delà, plus rien de ce domaine aujourd'hui. Garde la diversité :
  /// « 5 000 images variées » l'emportent sur « 50 000 d'un même site ».
  public var domainHardCap: Int = 400

  public var maxImagesPerDay: Int = 2500
  public var maxBytesPerDay: Int = 400 * 1024 * 1024

  /// Seuil d'écriture d'une archive.
  ///
  /// **60 Mo et pas les 120 de desktop** : sur un téléphone c'est de l'espace
  /// immobilisé dans le conteneur de l'app, et une archive plus petite arrive
  /// plus tôt dans Files.app — donc se récupère plus tôt. Le format du ZIP est
  /// identique, seul le rythme change (`unzip -n` fusionne de toute façon).
  public var maxSpoolBytes: Int = 60 * 1024 * 1024
  /// ... ou 6 h, le premier des deux. Ces deux seuils sont les SEULS
  /// déclencheurs de l'archive automatique — « Exporter maintenant » reste le
  /// moyen de vérifier la chaîne sans attendre.
  public var maxSpoolAgeMs: Double = 6 * 3600 * 1000
  /// Plafond global. 2 Go et pas 4 : c'est un iPhone.
  public var maxTotalBytes: Int = 2 * 1024 * 1024 * 1024

  // Vidéo : quota STRICTEMENT séparé — sinon une seule vidéo (≈150 scènes,
  // 18 000 frames pour 10 minutes) noierait tout le corpus. Échantillonnage
  // par SCÈNE, jamais par frame.
  //
  // /!\ `videoScenes` coupe l'échantillonnage vidéo CÔTÉ PAGE. Capturer une
  // frame impose un readback GPU→CPU (`drawImage(video)`), précisément ce que
  // l'overlay vidéo évite à 60 fps. C'est borné (au plus une fois par scène,
  // plafonné par `maxFramesPerVideo`), mais si une saccade apparaît sur device,
  // c'est le PREMIER interrupteur à basculer.
  public var videoScenes: Bool = true
  public var maxVideoFramesPerDay: Int = 300
  public var maxFramesPerVideo: Int = 25
  public var minSceneIntervalMs: Double = 4000

  /// Nom d'appareil (`karim`, `epouse`) — préfixe les archives et marque chaque
  /// ligne du manifeste (`dev`). Sans lui, les appareils produisent des `anon-*`
  /// indistinguables et le découpage par personne est perdu SANS RECOURS pour
  /// les images déjà collectées.
  public var device: String = ""

  /// Hôtes dont on ne collecte RIEN, ni page ni image. Deux familles :
  ///  - contextes authentifiés (le GET anonyme les rejetterait de toute façon,
  ///    mais autant ne pas émettre la requête) ;
  ///  - CDN à URL SIGNÉE : le GET anonyme y RÉUSSIT (la signature voyage dans
  ///    l'URL, pas dans un cookie) — c'est le trou du test de caractère public,
  ///    et la seule parade est cette liste.
  ///
  /// ⚠️ Ce n'est PAS le garde-fou (cf. `CollectPublicityTest`) : c'est une
  /// préférence. Si la liste oublie un hôte on ne perd pas une garantie,
  /// seulement un choix — « je ne veux rien de ces sites, même techniquement
  /// public ».
  public var denyHosts: [String] = [
    "mail.google.com", "drive.google.com", "docs.google.com", "photos.google.com",
    "calendar.google.com", "contacts.google.com", "accounts.google.com",
    "outlook.com", "outlook.office.com", "outlook.live.com", "teams.microsoft.com",
    "onedrive.live.com", "sharepoint.com", "icloud.com",
    "facebook.com", "fbcdn.net", "instagram.com", "cdninstagram.com",
    "x.com", "twitter.com", "twimg.com", "snapchat.com", "linkedin.com",
    "licdn.com", "whatsapp.com", "whatsapp.net", "messenger.com",
    "slack.com", "slack-edge.com", "discord.com", "discordapp.net",
    "telegram.org", "web.telegram.org", "proton.me", "protonmail.com",
    "paypal.com", "stripe.com",
  ]

  /// Frames vidéo : le flux vient de MSE (`blob:`), impossible à re-fetcher
  /// anonymement. Le caractère public ne peut donc être établi que par la PAGE
  /// → allowlist explicite, seule règle défendable. Le choix est entre une
  /// liste et pas de vidéo du tout.
  public var videoHosts: [String] = [
    "youtube.com", "youtu.be", "vimeo.com", "dailymotion.com", "twitch.tv",
    "arte.tv", "france.tv",
  ]

  public init() {}
}

// MARK: - Domaines

/// eTLD+1 approximatif — suffisant pour un quota, pas pour de la sécurité.
public func baseDomain(_ host: String?) -> String {
  guard let host, !host.isEmpty else { return "" }
  var h = host.lowercased()
  if let range = h.range(of: ":[0-9]+$", options: .regularExpression) {
    h.removeSubrange(range)
  }
  if h.range(of: "^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$", options: .regularExpression) != nil {
    return h
  }
  let parts = h.split(separator: ".").map(String.init)
  if parts.count <= 2 { return h }
  // Suffixes composés courants (co.uk, com.br…) : on garde 3 labels.
  let last2 = parts.suffix(2).joined(separator: ".")
  let composite = last2.range(
    of: "^(co|com|net|org|gov|edu|ac|or|ne)\\.[a-z]{2}$", options: .regularExpression) != nil
  return composite ? parts.suffix(3).joined(separator: ".") : last2
}

/// L'hôte (ou l'un de ses parents) figure-t-il dans la liste ?
public func hostMatches(_ host: String?, _ list: [String]) -> Bool {
  guard let host, !host.isEmpty else { return false }
  var h = host.lowercased()
  if let range = h.range(of: ":[0-9]+$", options: .regularExpression) {
    h.removeSubrange(range)
  }
  return list.contains { h == $0 || h.hasSuffix("." + $0) }
}

// MARK: - Probabilités

/// Facteur de quota par domaine — décroît doucement puis coupe net. Garde la
/// diversité sans jeter brutalement le 101ᵉ élément d'un site légitimement riche.
public func domainFactor(_ count: Int, _ cfg: CollectConfig) -> Double {
  if count >= cfg.domainHardCap { return 0 }
  if count < cfg.domainSoftCap { return 1 }
  return Double(cfg.domainSoftCap) / Double(count)
}

/// Probabilité d'inclusion FINALE. C'est ce nombre exact qui part dans le
/// manifeste : il doit être calculé AVANT le tirage et ne plus bouger après.
public func inclusionProb(
  _ stratum: CollectStratum,
  _ cfg: CollectConfig,
  load: Double = 1,
  domainCount: Int = 0
) -> Double {
  let base = cfg.rates[stratum] ?? 0
  let p = base * load * domainFactor(domainCount, cfg)
  return max(0, min(1, p))
}

/// Facteur de charge — la réponse à « quand échantillonner sans dégrader
/// l'expérience ». On ne devine pas un pourcentage : on lit la profondeur de la
/// file d'analyse au moment de la décision.
///
///   file vide (l'utilisateur n'attend rien)      → 1,0   (on collecte à fond)
///   1 image en attente                           → ~0,74
///   3 images en attente (galerie qui se charge)  → ~0,49
///   collecteur saturé                            → 0     (on laisse passer)
///
/// Le point important n'est pas la formule mais le fait que le résultat parte
/// dans `p` : un ralentissement adaptatif ne biaise plus le corpus, il le pondère.
///
/// Pondérations abaissées le 2026-08-23 : la v1 (`1/(1+depth+inflight/2)`) était
/// une intuition, pas une mesure — elle ramenait le taux effectif à ~0,35 alors
/// qu'aucun ralentissement n'a jamais été constaté.
public func loadFactor(queueDepth: Int = 0, inflight: Int = 0, maxInflight: Int = 4) -> Double {
  if inflight >= maxInflight { return 0 }
  return 1 / (1 + 0.35 * Double(queueDepth) + 0.25 * Double(inflight))
}
