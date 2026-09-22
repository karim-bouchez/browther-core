// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Ce que Browther met dans le dispositif — `docs/PARRAINAGE.md` § 9 (ligne
/// Browther, tranchée le 2026-09-11 puis le 2026-09-22 avec Karim).
///
/// ⭐ **C'est le SEUL endroit où la liste vit.** Les écrans 0, 1, 2 et 7
/// affichent le même composant « fonctionnalités » avec l'état qui va ; la
/// garde de l'app lit `ExtraFeature`. ⛔ Ne jamais recopier un libellé ou une
/// icône dans un écran.
///
/// 🔴 **Basarunaa (le floutage) ne se met JAMAIS en pause** (§ 11.2, arbitré le
/// 2026-09-11) : il est « disponible, pour toujours ». Seul Sawtunaa (le
/// retrait de la musique) est supplémentaire — et il tourne en local, à coût
/// marginal nul : « à vie » tient (§ 5.1).
public enum ReferralProduct {
  /// La clé du produit côté service (⛔ jamais affichée).
  public static let key = "browther"

  /// L'adresse du service — ⛔ jamais une adresse de beta en dur ici : il
  /// n'y a qu'un service, et la recette y pose ses états par un jeton.
  public static let serviceURL = URL(string: "https://referral.devndin.com")!

  /// Le site : repli du message partagé quand le lien traqué manque encore.
  public static let siteURL = "https://browther.devndin.com"

  // MARK: - Le critère de validation (§ 5.2, § 9)

  /// 🔴 **Doublon commenté du service** (`referral/src/domain/products.ts`) —
  /// à garder identique. Tranché le 2026-09-22 (Karim : « validé quand le
  /// filleul a passé Browther en navigateur par défaut ») : **3 journées
  /// distinctes où Browther, navigateur par défaut, a chargé une vraie page**.
  /// ⛔ Le défaut SEUL se ferait en dix secondes (installer, cocher, revenir en
  /// arrière) : § 5.2, il faut un geste ET une durée.
  public static let validationEvent = "default_browser_day"
  /// Ne sert qu'aux TEXTES (« 3 jours ») : la progression affichée est celle
  /// que le service renvoie.
  public static let validationTargetDays = 3
}

/// Les fonctionnalités, par identifiant — ⚠️ la liste AFFICHÉE et les GARDES
/// ne se confondent pas (§ 9.0) : la liste dit ce que la personne gagne, les
/// gardes suivent les gestes.
public enum EssentialFeature: String, CaseIterable, Sendable {
  /// Basarunaa — ⛔ jamais en pause (§ 9).
  case blur
  case shields
  case browsing

  /// SF Symbol — chaque écran le résout, ⛔ aucun ne le recopie.
  public var symbol: String {
    switch self {
    case .blur: return "eye.slash"
    case .shields: return "shield.lefthalf.filled"
    case .browsing: return "safari"
    }
  }
}

public enum ExtraFeature: String, CaseIterable, Sendable {
  /// Sawtunaa, le retrait de la musique. ⚠️ **L'annonce attend qu'il sorte
  /// de « encore en développement »** (`ReferralLaunch.extrasReleased`) :
  /// d'ici là, rien n'est en pause.
  case musicRemoval = "music_removal"

  public var symbol: String {
    switch self {
    case .musicRemoval: return "music.note"
    }
  }
}

/// Les prix — ⚠️ ce ne sont pas des textes traduisibles, et ⚠️ **sur iOS ce
/// n'est qu'un REPLI** : dès que l'offre est chargée, l'écran affiche le prix
/// que l'App Store renvoie (localisé, dans la devise de la personne).
///
/// 🔴 **UN seul prix, partout : 2,99 € / 29,99 €** (§ 2.1 n° 4). Changer un
/// prix ici suppose de changer les stores ET Polar le même jour.
public enum ReferralPricing {
  /// ⚠️ Espace INSÉCABLE entre le montant et « € » : ils ne se coupent jamais
  /// en fin de ligne (§ 12.26).
  public static let monthly = "2,99\u{00A0}€"
  public static let yearly = "29,99\u{00A0}€"
  /// Douze mois au tarif mensuel — le prix barré.
  public static let yearlyStruck = "35,88\u{00A0}€"
  /// Ce que l'annuel revient par mois — « soit 2,50 € par mois ».
  public static let yearlyPerMonth = "2,50\u{00A0}€"
  /// Le badge « 2 mois offerts ».
  public static let yearlyFreeMonths = 2
}

public enum BillingPeriod: String, Sendable, CaseIterable {
  case monthly, yearly
}

/// Ce que l'abonnement s'appelle **dans le code** (RevenueCat, App Store) — le
/// même patron que Darsunaa et Fajrunaa. ⚠️ Des identifiants, ⛔ pas un
/// vocabulaire : partout où la personne lit quelque chose, c'est
/// « fonctionnalités supplémentaires » (§ 2.2).
public enum ReferralBilling {
  public static let entitlement = "premium"
  public static func productID(_ period: BillingPeriod) -> String {
    switch period {
    case .monthly: return "browther_premium_monthly"
    case .yearly: return "browther_premium_yearly"
    }
  }
}
