// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// La **vidéo** du statut WhatsApp — `private/docs/PARRAINAGE.md` § 11, porté de
/// la référence `fajrunaa/lib/referral/statusVideo.ts` (recettée sur iPhone par
/// Karim le 2026-10-08). Jumeaux : `core/ReferralStatusVideo.java` (Android),
/// `website/lib/statusVideo.ts` (page `/share`).
///
/// La feuille « Partager mon code » propose DEUX statuts : la vidéo de
/// présentation de Browther (la même pour tout le monde) et l'image qui porte
/// le code de la personne. Elle coche ce qu'elle veut publier.
///
/// ## Un envoi par statut
///
/// WhatsApp ne donne le texte partagé qu'au PREMIER média d'un envoi, et range
/// les médias à sa façon (constat iPhone du 2026-10-07, cinq arrangements
/// essayés). Le seul qui garde le lien sous CHAQUE statut, dans l'ordre voulu :
/// **un envoi par statut**, chacun avec son lien. ⛔ Ne pas revenir à un envoi
/// groupé « pour gagner un geste » : le second statut partirait sans lien.
/// ⭐ Le second envoi part tout seul après un court décompte ANNONCÉ par la
/// jauge du bouton (`nextAutoSeconds`) — un tap le devance. ⛔ Jamais sans la
/// jauge : rouvrir WhatsApp sans prévenir se lit comme un défaut.
///
/// ## La vidéo n'est pas dans l'app
///
/// ~5 Mo par langue : elle est téléchargée depuis le site, qui publie un
/// **manifeste** (une vidéo par langue). Chacun n'a besoin que de SA langue, la
/// plupart ne partagent jamais, et la vidéo se change — ou se COUPE — sans
/// release (`{"v": 1, "videos": {}}`).
///
/// 🔴 **Tout ce fichier est fail-open** : pas de manifeste, entrée malformée,
/// langue absente ⇒ `nil`, et la feuille ne propose que l'image — le geste
/// d'avant, à l'identique. ⛔ Rien ici ne doit pouvoir empêcher de publier.
///
/// Pur (Foundation seul) : testé dans `private/scripts/ios-referral-tests/`.
public enum ReferralStatusSegment: String, CaseIterable, Sendable {
  case video, image
}

/// Un oui ou un non par statut : ce qui est coché, ce qui est déjà parti.
public struct ReferralStatusFlags: Equatable, Sendable {
  public var video: Bool
  public var image: Bool

  public init(video: Bool, image: Bool) {
    self.video = video
    self.image = image
  }

  public static let both = ReferralStatusFlags(video: true, image: true)
  public static let none = ReferralStatusFlags(video: false, image: false)
  /// Sans vidéo, une seule chose à publier : l'image, d'office.
  public static let imageOnly = ReferralStatusFlags(video: false, image: true)

  public subscript(segment: ReferralStatusSegment) -> Bool {
    get { segment == .video ? video : image }
    set {
      if segment == .video { video = newValue } else { image = newValue }
    }
  }
}

/// Ce que dit le bouton — UN bouton, qui publie toujours le prochain statut de
/// la file.
public enum ReferralStatusCta: Equatable, Sendable {
  /// Les deux sont cochés, rien n'est parti.
  case both
  /// Un seul est coché, rien n'est parti.
  case one(ReferralStatusSegment)
  /// Un statut est parti, il reste celui-ci (« 2 sur 2 »).
  case next(ReferralStatusSegment)
  /// Rien n'est coché : le bouton est éteint.
  case none
  /// Tout ce qui était coché est parti : la feuille se referme.
  case done
}

public struct ReferralStatusVideoEntry: Equatable, Sendable {
  public let url: String
  public let bytes: Int

  public init(url: String, bytes: Int) {
    self.url = url
    self.bytes = bytes
  }
}

public enum ReferralStatusVideo {
  /// Le manifeste, sur le site du produit (un hôte que l'app appelle déjà).
  public static let manifestURL = "\(ReferralProduct.siteURL)/share-status/manifest.json"

  /// Au-delà, WhatsApp REFUSE la vidéo en statut (16 Mo). Une entrée plus
  /// lourde est écartée : mieux vaut l'image seule qu'un statut rejeté.
  public static let maxBytes = 16_000_000

  /// Combien de temps la feuille attend la vidéo avant de s'en passer. Elle est
  /// lancée dès l'ouverture de l'écran Parrainage : ce délai ne se voit que sur
  /// une connexion lente, et il ne doit jamais retenir quelqu'un qui veut publier.
  public static let waitSeconds: TimeInterval = 8

  /// Le décompte avant que le second statut parte tout seul. Court, mais assez
  /// long pour LIRE « Publié » et voir la jauge avancer — donc pour refermer la
  /// feuille si on n'en veut pas.
  public static let nextAutoSeconds: TimeInterval = 3

  /// ⚠️ Un succès n'est mémorisé que dix minutes : le manifeste est aussi
  /// l'interrupteur qui COUPE la vidéo, et iOS garde l'app en mémoire des jours.
  public static let freshSeconds: TimeInterval = 600

  /// ⭐ **L'ordre des deux statuts — la SEULE source** : celui des vignettes ET
  /// celui des envois (verrouillé par test). La vidéo d'abord : elle accroche
  /// et explique ; l'image ensuite porte l'offre et l'appel au clic.
  public static let segments: [ReferralStatusSegment] = [.video, .image]

  /// Les langues dans lesquelles l'image du statut existe
  /// (`Strings.BrowtherReferral.StatusImage`).
  public static let imageLanguages = ["fr", "en", "ar"]

  /// ⭐ **La vidéo suit la langue de l'IMAGE** (Karim, 2026-10-08) : Browther a
  /// ~60 langues d'interface et l'image n'existe qu'en fr, en et ar — les autres
  /// la reçoivent en anglais, donc la vidéo aussi. ⛔ Aucun autre repli : la
  /// règle « pas de vidéo dans une autre langue que l'image » tient toujours.
  public static func statusLanguage(appLanguage: String) -> String {
    let base = base(of: appLanguage)
    return imageLanguages.contains(base) ? base : "en"
  }

  private static func base(of language: String) -> String {
    let lowered = language.lowercased()
    return lowered.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? lowered
  }

  /// ⛔ Rien d'autre qu'un `.mp4` en HTTPS servi par dev&din : le manifeste ne
  /// doit pas pouvoir faire télécharger n'importe quoi, de n'importe où.
  private static func entry(_ raw: Any?) -> ReferralStatusVideoEntry? {
    guard let object = raw as? [String: Any], let url = object["url"] as? String else { return nil }
    // ⚠️ `JSONSerialization` rend `true` comme un `NSNumber` : seul un nombre
    // ENTIER, écrit comme tel, est une taille.
    guard let number = object["bytes"] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else {
      return nil
    }
    let value = number.doubleValue
    guard value.isFinite, value == value.rounded(), value > 0, value <= Double(maxBytes) else { return nil }
    let pattern = #"^https://([a-z0-9-]+\.)+devndin\.com/[A-Za-z0-9/._-]+\.mp4$"#
    guard url.range(of: pattern, options: .regularExpression) != nil, !url.contains("..") else { return nil }
    return ReferralStatusVideoEntry(url: url, bytes: Int(value))
  }

  /// Lecture défensive : une entrée malformée est jetée, jamais tout le manifeste.
  public static func manifest(from data: Data?) -> [String: ReferralStatusVideoEntry] {
    guard let data, let raw = try? JSONSerialization.jsonObject(with: data) else { return [:] }
    return manifest(fromJSON: raw)
  }

  public static func manifest(fromJSON raw: Any?) -> [String: ReferralStatusVideoEntry] {
    guard let root = raw as? [String: Any], let videos = root["videos"] as? [String: Any] else { return [:] }
    var out: [String: ReferralStatusVideoEntry] = [:]
    for (language, value) in videos {
      if let entry = entry(value) { out[language.lowercased()] = entry }
    }
    return out
  }

  /// La vidéo d'une langue. ⛔ Pas de repli ICI : l'appelant passe la langue de
  /// l'image (`statusLanguage`), et sans vidéo dans cette langue l'image part seule.
  public static func pick(
    _ manifest: [String: ReferralStatusVideoEntry],
    language: String
  ) -> ReferralStatusVideoEntry? {
    manifest[base(of: language)]
  }

  /// Le nom du fichier en cache = le dernier segment de l'URL. Une vidéo changée
  /// porte un autre nom (`…-2.mp4`) : l'ancienne n'est jamais relue par erreur.
  public static func fileName(_ entry: ReferralStatusVideoEntry) -> String {
    let last = entry.url.split(separator: "/").last.map(String.init) ?? entry.url
    return String(
      last.unicodeScalars.map { scalar -> Character in
        let keep =
          scalar.isASCII
          && (CharacterSet.alphanumerics.contains(scalar) || scalar == "." || scalar == "_" || scalar == "-")
        return keep ? Character(scalar) : "_"
      }
    )
  }

  /// Le fichier en cache est-il LA vidéo ? ⚠️ Un transfert interrompu laisse un
  /// fichier court que le système déclare présent : seule la taille exacte du
  /// manifeste fait foi.
  public static func isComplete(_ entry: ReferralStatusVideoEntry, size: Int?) -> Bool {
    size == entry.bytes
  }

  /// Les statuts que la feuille propose : les deux, ou l'image seule faute de vidéo.
  public static func segments(hasVideo: Bool) -> [ReferralStatusSegment] {
    hasVideo ? segments : [.image]
  }

  /// Ce qui reste à publier, dans l'ordre des statuts : coché, et pas encore parti.
  public static func queue(picked: ReferralStatusFlags, sent: ReferralStatusFlags) -> [ReferralStatusSegment] {
    segments.filter { picked[$0] && !sent[$0] }
  }

  public static func cta(picked: ReferralStatusFlags, sent: ReferralStatusFlags) -> ReferralStatusCta {
    let queue = queue(picked: picked, sent: sent)
    let sentAny = segments.contains { sent[$0] }
    guard let first = queue.first else { return sentAny ? .done : .none }
    if queue.count > 1 { return .both }
    return sentAny ? .next(first) : .one(first)
  }
}

// MARK: - Le message qui accompagne un fichier (onglet « Message »)

extension ReferralShare {
  /// Retire les marques de surlignage de l'image du statut (`[[…]]`, `{{…}}`).
  public static func stripStatusMarks(_ text: String) -> String {
    ["[[", "]]", "{{", "}}"].reduce(text) { $0.replacingOccurrences(of: $1, with: "") }
  }

  /// Le message qui accompagne la **VIDÉO** (Karim, 2026-10-08) : le texte de
  /// l'IMAGE du statut, en clair — une seule source pour ce qu'on dit du
  /// produit —, puis le code VISIBLE (sur l'image il est sur la carte ; ici il
  /// n'y a pas de carte), et le lien seul sur la dernière ligne.
  public static func videoMessage(paragraphs: [String], codeLine: String, code: String, url: String?) -> String {
    let body = paragraphs.map(stripStatusMarks).joined(separator: "\n\n")
    return "\(body)\n\n\(codeLine)\n\(link(code: code, url: url))"
  }

  /// Le message qui accompagne l'**IMAGE** du statut, quand la vidéo est
  /// décochée. L'image dit déjà tout : il ne reste que le code, en texte qu'on
  /// peut copier, et le lien juste dessous.
  public static func imageMessage(codeLine: String, code: String, url: String?) -> String {
    "\(codeLine)\n\(link(code: code, url: url))"
  }
}
