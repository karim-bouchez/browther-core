// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_COMPONENTS_BROWTHER_ANALYTICS_SITE_REPORT_H_
#define BRAVE_COMPONENTS_BROWTHER_ANALYTICS_SITE_REPORT_H_

#include <string>

namespace content {
class WebContents;
}

namespace browther_analytics {

// « Ça ne marche pas sur ce site » — signalement déclenché par l'utilisateur
// depuis le panel d'une feature (Basarunaa, Sawtunaa).
//
// POURQUOI l'utilisateur et pas une détection automatique : la couverture
// réelle dépend de trop de choses pour être devinée depuis le code (player
// dans un iframe, flux DRM, vidéo jamais lue donc jamais décodée, site qui
// n'a tout simplement rien à flouter). Surtout, seul l'utilisateur sait ce
// qu'il s'ATTENDAIT à voir traité. Une heuristique produirait des faux
// positifs sur des pages parfaitement normales.
//
// VIE PRIVÉE — les trois règles, toutes appliquées ici :
//   1. seul le domaine enregistrable (eTLD+1) sort, jamais l'URL, le chemin
//      ni les paramètres : `dailymotion.com`, pas la vidéo regardée ;
//   2. rien ne part sans un clic — pas de télémétrie passive de navigation ;
//   3. le consentement statistiques est respecté (`IsTrackingEnabled`), et
//      quand il est coupé l'appelant doit griser son bouton plutôt que de
//      laisser croire à un envoi.
// C'est ce qui sépare ce signalement d'un historique de navigation : on
// n'apprend rien des sites que l'utilisateur visite, seulement de ceux où il
// nous dit que le produit échoue.
struct SiteReportState {
  // Y a-t-il un domaine signalable dans l'onglet actif ? Faux sur les pages
  // internes (browther://, NTP, about:blank) et les URL sans domaine.
  bool can_report = false;
  // Domaine enregistrable, à afficher pour que l'utilisateur voie exactement
  // ce qui sera transmis. Vide si `can_report` est faux.
  std::string domain;
  // Les statistiques d'usage sont coupées → `ReportSite` serait un no-op.
  bool analytics_off = false;
};

// Calcule l'état à afficher dans le panel pour l'onglet donné (peut être null).
SiteReportState GetSiteReportState(content::WebContents* web_contents);

// Envoie l'event `site_reported` avec {feature, domain}. Retourne false si
// rien n'est parti (pas de domaine, ou consentement coupé) — l'UI doit alors
// ne pas afficher de confirmation.
// `feature` : "basarunaa" | "sawtunaa".
bool ReportSite(content::WebContents* web_contents, const std::string& feature);

}  // namespace browther_analytics

#endif  // BRAVE_COMPONENTS_BROWTHER_ANALYTICS_SITE_REPORT_H_
