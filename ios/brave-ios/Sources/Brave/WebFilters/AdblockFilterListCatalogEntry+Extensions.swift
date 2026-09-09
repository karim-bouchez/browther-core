// Copyright 2024 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BraveCore
import Foundation

extension AdblockFilterListCatalogEntry {
  /// The component ID of the "Default list"
  /// This is a special filter list that is enabled by default
  public static let defaultListComponentID = "iodkpdagapdfkphljnddpjlldadblomo"
  /// The component ID of the "Fanboy's Mobile Notifications List"
  /// This is a special filter list that is enabled by default
  public static let mobileAnnoyancesComponentID = "bfpgedeaaibpoidldhjcknekahbikncb"
  /// The component id of the YouTube mobile recommendations filter list.
  /// This is a special filter list that has more accessible UI to control it
  public static let youtubeMobileRecommendationsComponentID = "phdmgpanpejkbmbljlhcehpadabljfbk"
  /// The component id of the YouTube distracting elements filter list.
  /// This is a special filter list that has more accessible UI to control it
  public static let youtubeDistractingElementsComponentID = "cpapfkpkeaajehipopnaiihfmbfbnkdp"
  /// The component id of the YouTube shorts filter list.
  /// This is a special filter list that has more accessible UI to control it
  public static let youtubeShortsComponentID = "almolcgbkikkhliiibfjkohebgklegam"

  public static let disabledContentBlockersComponentIDs = [
    // Browther : la liste anti-porn (`lbnibkdpkdjnookgfeogjdanfenekmpe`) était
    // exclue ici par Brave avec la raison « 500251 rules » contre une limite de
    // 150 000 pour le rule store WebKit. Ce chiffre est périmé : sa source
    // (hagezi `nsfw.txt`) en compte 97 065 au 2026-09-09, toutes des règles
    // réseau, zéro cosmétique. On la laisse donc compiler — sur iOS le content
    // blocker est le SEUL chemin de blocage réseau (WebKit n'expose pas
    // d'interception de requêtes), donc la garder ici en ferait un interrupteur
    // mort : visible et activable dans les réglages, sans aucun effet.
    // ⚠️ Si WebKit refuse la compilation (dépassement de limite, mémoire), le
    // symptôme est une liste qui ne bloque rien, pas un crash — vérifier les
    // logs de `WKContentRuleListStore` avant de conclure à autre chose.
    // For now we don't compile this into content blockers because we use the one coming from slim list
    // We might change this in the future as it ends up with 95k items whereas the limit is 150k.
    // So there is really no reason to use slim list except perhaps for performance which we need to test out.
    defaultListComponentID,
  ]

  /// Lets us know if this filter list is always aggressive.
  /// This value comes from `list_catalog.json` in brave core
  var engineType: GroupedAdBlockEngine.EngineType {
    return firstPartyProtections ? .standard : .aggressive
  }
}
