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
      value: "Follow dev&din to hear about it first:",
      comment: "Label introducing the two broadcast channel links"
    )
    // Canaux de DIFFUSION : on s'y abonne pour être prévenu des sorties, on n'y
    // écrit pas. Le libellé dit « chaîne / canal » pour lever l'ambiguïté que
    // le seul nom de l'app laissait planer. Textes source identiques à l'étape
    // d'onboarding et au desktop → traductions déjà écrites.
    public static let betaNoticeWhatsApp = NSLocalizedString(
      "betaNoticeWhatsApp",
      tableName: "Browther",
      bundle: .module,
      value: "WhatsApp channel",
      comment: "Name of the dev&din WhatsApp broadcast channel"
    )
    public static let betaNoticeTelegram = NSLocalizedString(
      "betaNoticeTelegram",
      tableName: "Browther",
      bundle: .module,
      value: "Telegram channel",
      comment: "Name of the dev&din Telegram broadcast channel"
    )
    public static let betaNoticeDismiss = NSLocalizedString(
      "betaNoticeDismiss",
      tableName: "Browther",
      bundle: .module,
      value: "Close this notice",
      comment: "Accessibility label of the notice's close button"
    )
    // Encadré « fonctionnalité en cours de développement » des panels
    // Sawtunaa/Basarunaa, affiché tant que la feature est ON. Anglais MOT POUR
    // MOT celui du desktop/Android (IDS_BROWTHER_FEATURE_BETA_*) : les
    // traductions viennent des mêmes .xtb. Les deux libellés de canaux
    // réutilisent betaNoticeWhatsApp / betaNoticeTelegram.
    public static let featureBetaTitle = NSLocalizedString(
      "featureBetaTitle",
      tableName: "Browther",
      bundle: .module,
      value: "This feature is still in development",
      comment: "Title of the notice in the Sawtunaa and Basarunaa panels while the feature is on"
    )
    public static let featureBetaText = NSLocalizedString(
      "featureBetaText",
      tableName: "Browther",
      bundle: .module,
      value: "It may not work well yet.",
      comment: "Body of the notice in the Sawtunaa and Basarunaa panels while the feature is on"
    )
    public static let featureBetaFollow = NSLocalizedString(
      "featureBetaFollow",
      tableName: "Browther",
      bundle: .module,
      value: "We will announce it here as soon as it is ready, إن شاء الله:",
      comment:
        "Label introducing the two broadcast channel links in the feature notice. "
        + "The Arabic phrase means 'God willing' — keep it as-is"
    )

    // MARK: Bouclier sur une page interne (NTP, about:…)
    //
    // Les 4 premières reprennent À L'OCTET PRÈS l'anglais des
    // `IDS_BROWTHER_SHIELDS_INTERNAL_*` du desktop : leurs traductions viennent
    // des .xtb par hash grit (`private/assets/gen-ios-browther-strings.py`).
    // La 5ᵉ diverge volontairement (voir son commentaire) et se traduit dans ce
    // même script, à la main.
    public static let shieldsInternalTitle = NSLocalizedString(
      "shieldsInternalTitle",
      tableName: "Browther",
      bundle: .module,
      value: "Browther Shields",
      comment: "Title of the Shields panel shown on internal pages (new tab page)"
    )
    public static let shieldsInternalStatusOn = NSLocalizedString(
      "shieldsInternalStatusOn",
      tableName: "Browther",
      bundle: .module,
      value: "Ad blocking ENABLED",
      comment: "Status line of the Shields panel on internal pages"
    )
    public static let shieldsInternalStatusOff = NSLocalizedString(
      "shieldsInternalStatusOff",
      tableName: "Browther",
      bundle: .module,
      value: "Ad blocking DISABLED",
      comment: "Status line of the Shields panel on internal pages"
    )
    public static let shieldsInternalDescription = NSLocalizedString(
      "shieldsInternalDescription",
      tableName: "Browther",
      bundle: .module,
      value:
        "Browther Shields block ads, trackers, fingerprinting and unwanted scripts on every site you visit.",
      comment: "Description of what Shields do, Shields panel on internal pages"
    )
    // Divergence VOULUE avec le desktop, qui dit « click the shield button at
    // the top right » : sur iPhone on touche, et la barre d'adresse est souvent
    // en bas. Ne pas l'« aligner » sur le desktop.
    public static let shieldsInternalPerSiteInfo = NSLocalizedString(
      "shieldsInternalPerSiteInfo",
      tableName: "Browther",
      bundle: .module,
      value:
        "Shields are managed per site. Open the website you want to exclude and tap the shield button in the address bar.",
      comment: "Shown when the user tries to turn Shields off from an internal page — Shields are per-site only"
    )

    // MARK: Surfaces communes dev&din (avis, contact, nouveautés, signature)
    //
    // Propres au mobile (le desktop ne les a pas encore) : traduites à la main
    // pour les 39 locales dans `private/assets/ios-browther-strings-surfaces.json`,
    // appliquées par `gen-ios-browther-strings.py`. Voix dev&din : tutoiement.
    // Doc : `private/docs/SURFACES_IOS.md`.

    public static let settingsFeedbackRow = NSLocalizedString(
      "settingsFeedbackRow",
      tableName: "Browther",
      bundle: .module,
      value: "Contact us",
      comment: "Settings row (Support section) opening the feedback form"
    )
    public static let signatureLabel = NSLocalizedString(
      "signatureLabel",
      tableName: "Browther",
      bundle: .module,
      value: "A project by",
      comment: "Footer of Settings, followed by the dev&din logo (the brand name is not translated)"
    )
    public static let feedbackTitle = NSLocalizedString(
      "feedbackTitle",
      tableName: "Browther",
      bundle: .module,
      value: "Your feedback",
      comment: "Title of the feedback form"
    )
    public static let feedbackIntroSpontaneous = NSLocalizedString(
      "feedbackIntroSpontaneous",
      tableName: "Browther",
      bundle: .module,
      value: "You've been browsing with Browther for a few days. What works, and what doesn't?",
      comment: "Intro of the feedback form when it opens on its own after a few days of use"
    )
    public static let feedbackIntroPermanent = NSLocalizedString(
      "feedbackIntroPermanent",
      tableName: "Browther",
      bundle: .module,
      value: "Tell us what's wrong, or what's missing. We read everything.",
      comment: "Intro of the feedback form opened from Settings"
    )
    public static let feedbackPlaceholder = NSLocalizedString(
      "feedbackPlaceholder",
      tableName: "Browther",
      bundle: .module,
      value: "What you want to tell us…",
      comment: "Placeholder of the feedback text field"
    )
    public static let feedbackPrivacy = NSLocalizedString(
      "feedbackPrivacy",
      tableName: "Browther",
      bundle: .module,
      value:
        "Only your message is sent — not your name, your address or the sites you visit. Browther asks for no account, so we can't reply.",
      comment: "Privacy note under the feedback text field"
    )
    public static let feedbackAnalyticsOff = NSLocalizedString(
      "feedbackAnalyticsOff",
      tableName: "Browther",
      bundle: .module,
      value:
        "Sending goes through the anonymous usage statistics, which are turned off. You can still email us.",
      comment: "Replaces the privacy note when usage statistics are off (Send is then disabled)"
    )
    public static let feedbackEmailHint = NSLocalizedString(
      "feedbackEmailHint",
      tableName: "Browther",
      bundle: .module,
      value: "Want a reply? Email us",
      comment: "Link under the Send button, opens the email contact"
    )
    public static let feedbackSend = NSLocalizedString(
      "feedbackSend",
      tableName: "Browther",
      bundle: .module,
      value: "Send",
      comment: "Button sending the feedback message"
    )
    public static let feedbackOptOut = NSLocalizedString(
      "feedbackOptOut",
      tableName: "Browther",
      bundle: .module,
      value: "Don't ask me again",
      comment: "Button of the feedback form when it opened on its own"
    )
    public static let feedbackThanksTitle = NSLocalizedString(
      "feedbackThanksTitle",
      tableName: "Browther",
      bundle: .module,
      value: "Thank you",
      comment: "Title shown after the feedback was sent"
    )
    public static let feedbackThanksBody = NSLocalizedString(
      "feedbackThanksBody",
      tableName: "Browther",
      bundle: .module,
      value: "Your message has been sent. We read it, even if we can't reply.",
      comment: "Text shown after the feedback was sent"
    )
    public static let contactTitle = NSLocalizedString(
      "contactTitle",
      tableName: "Browther",
      bundle: .module,
      value: "Email us",
      comment: "Title of the dialog asking who is writing, before opening the mail app"
    )
    public static let contactMessage = NSLocalizedString(
      "contactMessage",
      tableName: "Browther",
      bundle: .module,
      value: "Messages from brothers and sisters are read by different people.",
      comment: "Explains why the dialog asks whether the user is a brother or a sister"
    )
    public static let contactBrother = NSLocalizedString(
      "contactBrother",
      tableName: "Browther",
      bundle: .module,
      value: "I'm a brother",
      comment: "Dialog button — opens a mail to the brothers' address"
    )
    public static let contactSister = NSLocalizedString(
      "contactSister",
      tableName: "Browther",
      bundle: .module,
      value: "I'm a sister",
      comment: "Dialog button — opens a mail to the sisters' address"
    )
    public static let contactNoMailApp = NSLocalizedString(
      "contactNoMailApp",
      tableName: "Browther",
      bundle: .module,
      value: "No mail app is set up on this device. Our address has been copied: %@",
      comment: "Shown when no mail app can open the message. %@ is the email address"
    )
    public static let whatsNewTitle = NSLocalizedString(
      "whatsNewTitle",
      tableName: "Browther",
      bundle: .module,
      value: "What's changed",
      comment: "Title of the New Tab card listing what changed in the latest update"
    )
    public static let whatsNewAcknowledge = NSLocalizedString(
      "whatsNewAcknowledge",
      tableName: "Browther",
      bundle: .module,
      value: "Got it",
      comment: "Button closing the What's changed card"
    )
  }
}
