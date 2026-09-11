// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Shared
import UIKit

/// Contact par e-mail — la seule sortie qui permette une RÉPONSE (§3.3).
///
/// Convention systématique dev&din : `browther@devndin.com` pour les frères,
/// `browther-femme@devndin.com` pour les sœurs (Email Routing vérifié le
/// 2026-09-11 : les deux règles existent et forwardent). Browther n'a pas de
/// profil, donc la question se pose AU TAP — ⛔ jamais les deux adresses en
/// clair sous le formulaire : ça en ferait une page de support, alors que le
/// formulaire doit rester le chemin principal.
///
/// Le brouillon porte un diagnostic (version, iOS, modèle, langue) sous un
/// trait, comme Sawtunaa (`lib/support.ts`) : un navigateur a des pannes
/// reproductibles, et c'est la personne qui envoie — elle voit tout avant.
/// ⛔ Aucune URL visitée n'y est ajoutée : si elle veut citer un site, elle
/// l'écrit elle-même.
enum BrowtherContact {

  enum Recipient: String {
    case brother
    case sister

    var address: String {
      switch self {
      case .brother: return "browther@devndin.com"
      case .sister: return "browther-femme@devndin.com"
      }
    }
  }

  /// Le `mailto:` complet. Sujet non traduit : il sert au tri de la boîte.
  static func mailtoURL(for recipient: Recipient) -> URL? {
    var components = URLComponents()
    components.scheme = "mailto"
    components.path = recipient.address
    components.queryItems = [
      URLQueryItem(name: "subject", value: "Browther (iOS)"),
      URLQueryItem(name: "body", value: "\n\n\n—\n\(diagnostic)"),
    ]
    return components.url
  }

  /// Ce qu'il faut pour reproduire, et rien d'autre.
  static var diagnostic: String {
    let info = Bundle.main.infoDictionary
    let version = info?["CFBundleShortVersionString"] as? String ?? "?"
    let build = info?["CFBundleVersion"] as? String ?? "?"
    let device = UIDevice.current
    return
      "Browther \(version) (\(build)) · \(device.systemName) \(device.systemVersion) · \(device.modelName) · \(Locale.current.identifier)"
  }

  /// Ouvre l'app de mail. `completion(false)` = aucune app de mail : l'adresse
  /// est alors copiée, et l'appelant le dit (un lien qui ne fait rien serait pire
  /// que pas de lien du tout).
  static func open(
    _ recipient: Recipient,
    source: String,
    completion: @escaping (_ opened: Bool) -> Void
  ) {
    guard let url = mailtoURL(for: recipient) else {
      completion(false)
      return
    }
    UIApplication.shared.open(url) { opened in
      if !opened {
        UIPasteboard.general.string = recipient.address
      }
      // ⛔ Le genre choisi ne part PAS dans l'évènement : il ne sert qu'à router
      // le message, et n'apprendrait rien qu'on ait besoin de mesurer.
      BrowtherSurfaces.track("contact_opened", ["source": source, "mail_app": opened])
      completion(opened)
    }
  }
}
