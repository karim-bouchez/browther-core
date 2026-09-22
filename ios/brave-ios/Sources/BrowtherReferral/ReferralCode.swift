// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Le code de parrainage — `docs/PARRAINAGE.md` § 7.2 et § 12.6, pendant de
/// `darsunaa/packages/core/src/referral/code.ts` (`readReferralCodeInput`,
/// « à reprendre tel quel »).
///
/// Le code **dicté** fait 6 signes de l'alphabet du service
/// (`referral/src/domain/codes.ts`), qui n'a ni `s`, ni `0`/`o`, ni `1`/`l`/`i`,
/// ni `b`/`8`, `u`/`v`, `z`/`2`. Le lien porte le produit en clair :
/// `go.devndin.com/browther-pfxd3r`.
///
/// 🔴 **Toute évolution de la forme du code (préfixe, longueur, alphabet) doit
/// passer ICI dans le même chantier** : sinon un code tapé juste est refusé
/// « avant le service », sans aucune erreur côté serveur.
public enum ReferralCode {
  static let alphabet = Set("acdefghjkmnpqrtwxy34679")
  static let length = 6
  static let productPrefix = "\(ReferralProduct.key)-"

  public enum InputError: Error, Equatable, Sendable {
    case empty
    /// « Un code de parrainage fait 6 caractères. »
    case length
    /// Un signe qu'aucun code n'utilise (O, 0, I, 1…).
    case alphabet
  }

  /// Ce que quelqu'un a TAPÉ ou COLLÉ dans le champ du code d'un proche → le
  /// code à envoyer à `redeem`, ou pourquoi ce n'en est pas un.
  ///
  /// ⭐ **On sait ce qu'on attend** : une saisie impossible se dit TOUT DE
  /// SUITE, dans ses propres mots (« un code fait 6 caractères »), ⛔ sans
  /// aller demander au service — qui ne saurait répondre que « ce code ne
  /// correspond à personne » (recette du 2026-09-10).
  ///
  /// ⚠️ **Un LIEN collé est accepté en silence** : on en tire le code (`?ref=`,
  /// `utm_source`, ou le lien court), ⛔ mais l'interface ne l'annonce pas : le
  /// champ demande un code. Les espaces et tirets d'un code recopié à la main
  /// sont retirés.
  public static func readInput(_ raw: String) -> Result<String, InputError> {
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.isEmpty { return .failure(.empty) }
    if let linked = fromLink(text) { return .success(linked.uppercased()) }

    var bare = text.lowercased()
    if bare.hasPrefix(productPrefix) { bare.removeFirst(productPrefix.count) }
    bare.removeAll { $0 == " " || $0 == "." || $0 == "_" || $0 == "-" || $0.isNewline }
    if bare.count != length { return .failure(.length) }
    if !isBare(bare) { return .failure(.alphabet) }
    return .success(bare.uppercased())
  }

  /// Un code nu et EXACT (6 signes de l'alphabet), en minuscules ou majuscules.
  public static func isBare(_ value: String) -> Bool {
    let lower = value.lowercased()
    return lower.count == length && lower.allSatisfy { alphabet.contains($0) }
  }

  /// Le code porté par un lien, ou `nil`. ⚠️ Un segment de chemin n'est pris
  /// que s'il porte le préfixe du produit, ou s'il EST tout le chemin
  /// (`/pfxd3r`, `/l/pfxd3r`) : sinon la fin d'une adresse quelconque de six
  /// signes passerait pour un code.
  static func fromLink(_ text: String) -> String? {
    guard text.contains("/") || text.contains("?") || text.contains("=") else { return nil }
    let candidate = text.range(of: "://") == nil ? "https://\(text)" : text
    guard let components = URLComponents(string: candidate) else { return nil }

    for name in ["ref", "utm_source"] {
      if let value = components.queryItems?.first(where: { $0.name == name })?.value {
        var bare = value.trimmingCharacters(in: .whitespaces).lowercased()
        if bare.hasPrefix(productPrefix) { bare.removeFirst(productPrefix.count) }
        if isBare(bare) { return bare }
      }
    }

    let segments = components.path.split(separator: "/").map(String.init)
    guard let last = segments.last?.lowercased() else { return nil }
    let prefixed = last.hasPrefix(productPrefix)
    let bare = prefixed ? String(last.dropFirst(productPrefix.count)) : last
    let wholePath = segments.count == 1 || (segments.count == 2 && segments[0] == "l")
    return (prefixed || wholePath) && isBare(bare) ? bare : nil
  }
}

/// Le message d'invitation — `docs/PARRAINAGE.md` § 12.10.
///
/// ⭐ La forme retenue par Karim, dans cet ordre : ce qu'est l'app · le code et
/// ce qu'il apporte · **le lien, seul sur la dernière ligne**.
///
/// 🔴 **Le lien est DANS le texte, ⛔ pas un élément à part de la feuille de
/// partage** : chaque cible le placerait où elle veut (en tête, en aperçu
/// détaché, ou nulle part). 🔴 **⛔ Pas de sujet non plus** (§ 12.10) : il se
/// colle en tête du message dans certaines cibles.
/// ⚠️ **Le lien traqué peut manquer** le temps que la régie le crée : on
/// termine alors par le site, avec le code en `?ref=`. ⛔ Jamais un message
/// qui ne mène nulle part.
public enum ReferralShare {
  /// Le lien d'invitation : le lien traqué, sinon le site avec le code.
  public static func link(code: String, url: String?) -> String {
    if let url, !url.isEmpty { return url }
    let allowed = CharacterSet.alphanumerics
    let encoded = code.addingPercentEncoding(withAllowedCharacters: allowed) ?? code
    return "\(ReferralProduct.siteURL)/?ref=\(encoded)"
  }

  /// Le message complet : `text` (déjà dans la langue de la personne, avec le
  /// code), puis le lien seul sur la dernière ligne.
  public static func message(text: String, code: String, url: String?) -> String {
    "\(text)\n\(link(code: code, url: url))"
  }
}
