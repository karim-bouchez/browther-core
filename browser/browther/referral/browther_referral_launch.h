// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_BROWSER_BROWTHER_REFERRAL_BROWTHER_REFERRAL_LAUNCH_H_
#define BRAVE_BROWSER_BROWTHER_REFERRAL_BROWTHER_REFERRAL_LAUNCH_H_

// Le parrainage de Browther desktop — `docs/PARRAINAGE.md` (le flow commun) et
// `private/docs/PARRAINAGE.md` (ce que Browther en a fait). Jumeau de
// `ReferralLaunch` côté iOS (`BrowtherReferral/ReferralDefaultBrowserDays.swift`).
//
// 🔴 Le mot `referral` est DÉJÀ pris dans le fork (`components/brave_referrals`,
// le programme de codes promo d'installation de Brave) : tout ce qui est à nous
// vit sous `browther_referral` / `browther.referral.*`.

namespace browther_referral {

// L'écran « Parrainage » (`browther://referral`), page de confiance plein onglet
// — `brave/browser/ui/webui/browther_referral/`. ⚠️ Ici plutôt que dans
// `components/constants/webui_url_constants.h`, inclus partout : y toucher
// recompilerait une grande partie de Brave sur le Mac de 16 Go.
inline constexpr char kReferralHost[] = "referral";
inline constexpr char kReferralURL[] = "chrome://referral/";

// La commande « Parrainage » du menu ⋯ (§ 12.12 : l'entrée de l'écran 6 est le
// menu en haut à droite, le seul présent pour tout le monde). ⚠️ Déclarée ICI,
// pas dans `app/brave_command_ids.h` : celui-ci est inclus par
// `chrome_command_ids.h`, et un identifiant de plus y recompile ~400 fichiers ;
// il imposerait aussi un `IDS_IDC_*` (grit), donc ~300 de plus. 56130 est dans
// la plage Brave (56000-57000, routée par `BraveBrowserCommandController`), à
// côté de Basarunaa (56128) et Sawtunaa (56129).
inline constexpr int kReferralCommandId = 56130;

// Le parrainage existe-t-il dans les builds OFFICIELS (le DMG, le zip Windows) ?
// ⛔ Ne passer à `true` que le jour du lancement, sur décision de Karim — une
// ligne visible dans git. Les builds de dev (Component) l'ont toujours, pour la
// recette.
inline constexpr bool kInReleaseBuilds = false;

// ⚠️ Sawtunaa est-il sorti de « encore en développement » ? (`PARRAINAGE.md`
// § 9) L'annonce (écran 0), qui démarre le mois offert, attend ce jour-là ;
// d'ici là tout est ouvert et le reste du flow tourne (code, invitations,
// écran Parrainage, validation). 🔴 Bascule LE MÊME JOUR que
// `ReferralLaunch.extrasReleased` (iOS) et `announcementDeferred: false` côté
// service (`referral/src/domain/products.ts`) — le service est commun aux deux
// plateformes, un seul des trois qui bascule casse l'autre.
inline constexpr bool kExtrasReleased = false;

// Le parrainage est-il allumé dans CE binaire ?
constexpr bool IsEnabled() {
#if defined(OFFICIAL_BUILD)
  return kInReleaseBuilds;
#else
  return true;
#endif
}

constexpr bool IsDevBuild() {
#if defined(OFFICIAL_BUILD)
  return false;
#else
  return true;
#endif
}

}  // namespace browther_referral

#endif  // BRAVE_BROWSER_BROWTHER_REFERRAL_BROWTHER_REFERRAL_LAUNCH_H_
