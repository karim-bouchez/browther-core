// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Strings

// MARK: - Browther : panels Basarunaa & Sawtunaa
//
// Ces textes étaient EN DUR (et en français) dans BrowtherFeaturePanels.swift,
// donc identiques pour tout le monde : un utilisateur arabophone lisait
// « Suppression de la musique ACTIVÉE ». Extraits ici pour être localisables.
//
// ⚠️ Le texte anglais de `value:` est COPIÉ à l'identique de la string
// équivalente du panel desktop (`app/brave_generated_resources.grd`). Ce n'est
// pas cosmétique : les `.strings` des 39 langues ont été générés en cherchant
// la traduction desktop par HASH DU TEXTE ANGLAIS. Retoucher un `value:` ici
// sans retoucher le desktop détache la string de sa traduction et la fait
// retomber en anglais. Cf. private/docs/TODO.md § panels mobiles.
extension Strings {
  public enum Browther {
    public static let sawtunaaStatusOn = NSLocalizedString(
      "sawtunaaStatusOn",
      tableName: "Browther",
      bundle: .module,
      value: "Music removal ENABLED",
      comment: "Status line, Sawtunaa panel"
    )
    public static let sawtunaaStatusOff = NSLocalizedString(
      "sawtunaaStatusOff",
      tableName: "Browther",
      bundle: .module,
      value: "Music removal DISABLED",
      comment: "Status line, Sawtunaa panel"
    )
    public static let sawtunaaDescription = NSLocalizedString(
      "sawtunaaDescription",
      tableName: "Browther",
      bundle: .module,
      value: "For now, this only works on YouTube.",
      comment: "Mobile-only limitation"
    )
    public static let sawtunaaLearnMore = NSLocalizedString(
      "sawtunaaLearnMore",
      tableName: "Browther",
      bundle: .module,
      value: "(learn more)",
      comment: "Clickable suffix opening the limitations dialog"
    )
    public static let sawtunaaLimitationsTitle = NSLocalizedString(
      "sawtunaaLimitationsTitle",
      tableName: "Browther",
      bundle: .module,
      value: "Why only YouTube?",
      comment: "Title of the limitations dialog"
    )
    public static let sawtunaaLimitationsMessage = NSLocalizedString(
      "sawtunaaLimitationsMessage",
      tableName: "Browther",
      bundle: .module,
      value: "Mobile browsers impose technical restrictions that make this kind of audio filtering harder than on Mac, Windows or Android. We are working on extending it to other sites, in shaa Allah.",
      comment: "Body of the limitations dialog"
    )
    public static let basarunaaStatusOn = NSLocalizedString(
      "basarunaaStatusOn",
      tableName: "Browther",
      bundle: .module,
      value: "Person blurring ENABLED",
      comment: "Status line, Basarunaa panel"
    )
    public static let basarunaaStatusOff = NSLocalizedString(
      "basarunaaStatusOff",
      tableName: "Browther",
      bundle: .module,
      value: "Person blurring DISABLED",
      comment: "Status line, Basarunaa panel"
    )
    public static let basarunaaModeLabel = NSLocalizedString(
      "basarunaaModeLabel",
      tableName: "Browther",
      bundle: .module,
      value: "Mode",
      comment: "Section label"
    )
    public static let basarunaaModeFemale = NSLocalizedString(
      "basarunaaModeFemale",
      tableName: "Browther",
      bundle: .module,
      value: "Blur women",
      comment: "Blur mode option"
    )
    public static let basarunaaModeMale = NSLocalizedString(
      "basarunaaModeMale",
      tableName: "Browther",
      bundle: .module,
      value: "Blur men",
      comment: "Blur mode option"
    )
    public static let basarunaaModeAll = NSLocalizedString(
      "basarunaaModeAll",
      tableName: "Browther",
      bundle: .module,
      value: "Blur everyone",
      comment: "Blur mode option"
    )
    public static let basarunaaDetectionLabel = NSLocalizedString(
      "basarunaaDetectionLabel",
      tableName: "Browther",
      bundle: .module,
      value: "Detection",
      comment: "Section label"
    )
    public static let basarunaaHandFilter = NSLocalizedString(
      "basarunaaHandFilter",
      tableName: "Browther",
      bundle: .module,
      value: "Ignore lone hands",
      comment: "Toggle"
    )
    public static let basarunaaHandFilterDesc = NSLocalizedString(
      "basarunaaHandFilterDesc",
      tableName: "Browther",
      bundle: .module,
      value: "Does not blur when only a hand is visible (e.g. video tutorials). As soon as more shows — face, arm with elbow, leg, body — the blur applies.",
      comment: "Toggle description"
    )
    public static let basarunaaGenderCertainty = NSLocalizedString(
      "basarunaaGenderCertainty",
      tableName: "Browther",
      bundle: .module,
      value: "Blur caution level",
      comment: "Slider label"
    )
    public static let basarunaaGenderCertaintyDesc = NSLocalizedString(
      "basarunaaGenderCertaintyDesc",
      tableName: "Browther",
      bundle: .module,
      value: "Every detected person gets a certainty score (the % shown on their debug label). Below this threshold they are blurred as a precaution. Above it, their class decides (woman → blurred, man/child → not).",
      comment: "Slider description"
    )
    public static let basarunaaScaleLessBlur = NSLocalizedString(
      "basarunaaScaleLessBlur",
      tableName: "Browther",
      bundle: .module,
      value: "Less blur",
      comment: "Slider scale, left end"
    )
    public static let basarunaaScaleSafer = NSLocalizedString(
      "basarunaaScaleSafer",
      tableName: "Browther",
      bundle: .module,
      value: "More cautious",
      comment: "Slider scale, right end"
    )
    public static let basarunaaNsfwToggle = NSLocalizedString(
      "basarunaaNsfwToggle",
      tableName: "Browther",
      bundle: .module,
      value: "NSFW detection",
      comment: "Toggle"
    )
    public static let basarunaaNsfwToggleDesc = NSLocalizedString(
      "basarunaaNsfwToggleDesc",
      tableName: "Browther",
      bundle: .module,
      value: "Blurs the whole image when explicit content is detected (nudity, intimate parts). Off by default for better responsiveness.",
      comment: "Toggle description"
    )
    public static let basarunaaNsfwConf = NSLocalizedString(
      "basarunaaNsfwConf",
      tableName: "Browther",
      bundle: .module,
      value: "NSFW (Marqo)",
      comment: "Slider label"
    )
    public static let basarunaaNsfwConfDesc = NSLocalizedString(
      "basarunaaNsfwConfDesc",
      tableName: "Browther",
      bundle: .module,
      value: "Threshold of the global NSFW classifier. Above it, the whole image is blurred.",
      comment: "Slider description"
    )
    public static let basarunaaNudenetConf = NSLocalizedString(
      "basarunaaNudenetConf",
      tableName: "Browther",
      bundle: .module,
      value: "NudeNet",
      comment: "Slider label"
    )
    public static let basarunaaNudenetConfDesc = NSLocalizedString(
      "basarunaaNudenetConfDesc",
      tableName: "Browther",
      bundle: .module,
      value: "Detection threshold for explicit body parts. Lower means more sensitive.",
      comment: "Slider description"
    )
    public static let basarunaaConfBody = NSLocalizedString(
      "basarunaaConfBody",
      tableName: "Browther",
      bundle: .module,
      value: "Detection floor (advanced)",
      comment: "Slider label"
    )
    public static let basarunaaDebugNone = NSLocalizedString(
      "basarunaaDebugNone",
      tableName: "Browther",
      bundle: .module,
      value: "Off",
      comment: "Debug overlay mode"
    )
    public static let basarunaaDebugBoxes = NSLocalizedString(
      "basarunaaDebugBoxes",
      tableName: "Browther",
      bundle: .module,
      value: "Detection boxes",
      comment: "Debug overlay mode"
    )
    public static let basarunaaDebugFull = NSLocalizedString(
      "basarunaaDebugFull",
      tableName: "Browther",
      bundle: .module,
      value: "Full overlay (boxes + skeleton)",
      comment: "Debug overlay mode"
    )
    public static let reportSiteQuestion = NSLocalizedString(
      "reportSiteQuestion",
      tableName: "Browther",
      bundle: .module,
      value: "Not working on this site?",
      comment: "Report row"
    )
    public static let reportSiteButton = NSLocalizedString(
      "reportSiteButton",
      tableName: "Browther",
      bundle: .module,
      value: "Report this site",
      comment: "Report button"
    )
    public static let reportSiteDone = NSLocalizedString(
      "reportSiteDone",
      tableName: "Browther",
      bundle: .module,
      value: "Thanks — site reported.",
      comment: "Report confirmation"
    )
    public static let reportSiteAnalyticsOff = NSLocalizedString(
      "reportSiteAnalyticsOff",
      tableName: "Browther",
      bundle: .module,
      value: "Reporting needs usage statistics, which are turned off.",
      comment: "Shown when analytics are disabled"
    )

    // MARK: - Bandeau « accès anticipé » du Nouvel Onglet
    //
    // Textes anglais IDENTIQUES au desktop (`brave_new_tab_page_strings.grdp`,
    // IDS_NEW_TAB_BROWTHER_BETA_*) : c'est ce qui permet de réutiliser les
    // traductions déjà écrites côté .xtb, la correspondance se faisant par hash
    // du texte source. Toute retouche ici doit être répercutée là-bas.
    public static let betaNoticeTitle = NSLocalizedString(
      "betaNoticeTitle",
      tableName: "Browther",
      bundle: .module,
      value: "Browther is in early access",
      comment: "Title of the early-access notice on the new tab page"
    )
    public static let betaNoticeText = NSLocalizedString(
      "betaNoticeText",
      tableName: "Browther",
      bundle: .module,
      value:
        "Some things may not work yet — that is expected, and it gets better "
        + "with every update. The finished version is coming soon إن شاء الله.",
      comment: "Body of the early-access notice on the new tab page"
    )
    public static let betaNoticeFollow = NSLocalizedString(
      "betaNoticeFollow",
      tableName: "Browther",
      bundle: .module,
      value: "A problem, an idea? Talk to us on",
      comment: "Label introducing the WhatsApp and Telegram links"
    )
    public static let betaNoticeDismiss = NSLocalizedString(
      "betaNoticeDismiss",
      tableName: "Browther",
      bundle: .module,
      value: "Close this notice",
      comment: "Accessibility label of the notice's close button"
    )
  }
}
