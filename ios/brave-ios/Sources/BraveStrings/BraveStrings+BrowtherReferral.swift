// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Strings

// MARK: - Browther : le parrainage dev&din
//
// Les textes du flow commun (`docs/PARRAINAGE.md`, textes de référence
// `docs/PARRAINAGE-textes-fr.json`), avec le bloc `vars` de Browther.
//
// ⚠️ **Une table à part (`BrowtherReferral.strings`)**, hors du générateur de
// `Browther.strings` : ces textes n'ont AUCUN pendant desktop à réutiliser
// (le parrainage n'y est pas encore), et le français est la langue de
// référence (relu par Karim), pas l'anglais.
//
// 🔴 **Langues** : fr et ar traduits, l'anglais est la valeur de repli. Les 36
// autres langues de Browther retombent sur l'anglais — ⛔ acceptable
// UNIQUEMENT tant que le parrainage est éteint dans les builds du store
// (`ReferralLaunch.inStoreBuilds`). À traduire avant de l'allumer.
//
// ⚠️ **Pluriels** : pas de `.stringsdict` dans ce paquet, donc une règle en code
// (`plural`) — clés `<clé>.one` / `.other`, et pour l'arabe `.zero` / `.two` /
// `.few` / `.many` en plus (six formes).
//
// ⚠️ **Vocabulaire** (§ 6) : « parrainage » (programme, code, rubrique),
// « inviter un proche » (le geste), « invitation » (chaque envoi),
// « fonctionnalités supplémentaires » — ⛔ jamais « premium », « essai »,
// « gratuit » en étiquette. « Grâce à Allah, puis à toi » — ⛔ jamais « grâce à
// toi » seul.
extension Strings {
  public enum BrowtherReferral {
    static let table = "BrowtherReferral"

    static func t(_ key: String, _ english: String) -> String {
      NSLocalizedString(key, tableName: table, bundle: .module, value: english, comment: "")
    }

    /// Remplace `{nom}` par sa valeur — ⛔ jamais `%@` : l'ordre des mots
    /// change d'une langue à l'autre, les noms restent.
    public static func fill(_ template: String, _ values: [String: String]) -> String {
      values.reduce(template) { $0.replacingOccurrences(of: "{\($1.key)}", with: $1.value) }
    }

    /// La langue dans laquelle les textes sont réellement servis.
    static var language: String {
      Bundle.module.preferredLocalizations.first ?? "en"
    }

    /// La catégorie de pluriel CLDR d'un nombre ENTIER, pour la langue servie —
    /// les règles des 40 langues de Browther (`private/assets/ios-referral-strings/`
    /// liste les formes attendues par langue, `gen-ios-referral-strings.py`).
    static func category(_ count: Int) -> String {
      category(count, language: Self.language)
    }

    static func category(_ n: Int, language: String) -> String {
      let base = String(language.split(separator: "-").first ?? Substring(language))
      let mod10 = n % 10
      let mod100 = n % 100
      switch base {
      case "ar":
        if n == 0 { return "zero" }
        if n == 1 { return "one" }
        if n == 2 { return "two" }
        if (3...10).contains(mod100) { return "few" }
        if (11...99).contains(mod100) { return "many" }
        return "other"
      case "fr", "pt", "hi":
        return n == 0 || n == 1 ? "one" : "other"
      case "ru", "uk":
        if mod10 == 1 && mod100 != 11 { return "one" }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return "few" }
        return "many"
      case "pl":
        if n == 1 { return "one" }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return "few" }
        return "many"
      case "cs", "sk":
        if n == 1 { return "one" }
        if (2...4).contains(n) { return "few" }
        return "other"
      case "hr", "bs", "sr":
        if mod10 == 1 && mod100 != 11 { return "one" }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return "few" }
        return "other"
      case "ro":
        if n == 1 { return "one" }
        if n == 0 || (2...19).contains(mod100) { return "few" }
        return "other"
      case "he":
        if n == 1 { return "one" }
        if n == 2 { return "two" }
        return "other"
      case "ja", "ko", "zh", "th", "vi", "id", "ms":
        return "other"
      default:
        return n == 1 ? "one" : "other"
      }
    }

    /// Un texte au pluriel : la forme de la langue servie, sinon `other`, sinon
    /// l'anglais. `{count}` est remplacé par le nombre.
    public static func plural(_ key: String, _ count: Int, one: String, other: String) -> String {
      let missing = "\u{1}"
      let english = count == 1 ? one : other
      var value = NSLocalizedString(
        "\(key).\(category(count))",
        tableName: table,
        bundle: .module,
        value: missing,
        comment: ""
      )
      if value == missing {
        value = NSLocalizedString("\(key).other", tableName: table, bundle: .module, value: missing, comment: "")
      }
      if value == missing { value = english }
      // Un nombre et son unité ne se coupent jamais en fin de ligne (§ 12.26) :
      // « 3 jours », « 2 mois » — espace insécable.
      value = value.replacingOccurrences(of: "{count} ", with: "{count}\u{00A0}")
      return fill(value, ["count": "\(count)"])
    }

    // MARK: Composant « fonctionnalités » (§ 2.2)

    public static var featuresFreeHead: String { t("features.freeHead", "Available, forever") }
    public static var featuresFreeHeadDua: String { "إن شاء الله" }
    public static var featuresExtrasHead: String { t("features.extrasHead", "Additional features") }
    public static var featuresGainHead: String { t("features.gainHead", "What you unlock") }
    public static var featuresOffered: String { t("features.offered", "Free for 1 month") }
    public static func featuresUntil(_ date: String) -> String {
      fill(t("features.until", "Until {date}"), ["date": date])
    }
    public static func featuresSoon(_ days: Int) -> String {
      plural("features.soon", days, one: "Paused tomorrow", other: "Paused in {count} d")
    }
    public static var featuresPaused: String { t("features.paused", "Paused") }
    public static var featuresIncluded: String { t("features.included", "Included") }
    public static var featureBlur: String { t("features.essential.blur", "Blurring images and videos") }
    public static var featureShields: String { t("features.essential.shields", "Blocking ads and trackers") }
    public static var featureBrowsing: String { t("features.essential.browsing", "Browsing, tabs, bookmarks") }
    public static var featureMusicRemoval: String { t("features.extras.musicRemoval", "Removing music from videos") }
    public static var featuresEssentialLine: String {
      t("features.essentialLine", "The essentials stay available: blurring, ad blocking, browsing.")
    }

    // MARK: La garde d'une fonctionnalité en pause (un toast, § 12.16)

    public static var lockedMusicRemoval: String {
      t("locked.musicRemoval", "Music removal is one of the additional features.")
    }
    /// ⚠️ La RAISON, pas la rançon (§ 12.20) : la même phrase que l'écran J0.
    public static var lockedBody: String {
      t("locked.body", "For these apps to stay free, the dev&din studio needs you.")
    }
    public static var supportDevndin: String { t("locked.cta", "Support dev&din") }
    /// Le bouton du panneau de la fonctionnalité en pause. ⚠️ La clé existait
    /// déjà dans les 36 langues : le natif du desktop la lit dans le pool
    /// commun (`browther_referral_files.cc`). iOS l'affiche depuis le
    /// 2026-09-24 — c'est la MÊME surface, portée (§ 12.33).
    public static var lockedUnlock: String { t("locked.unlock", "Unlock") }

    // MARK: 0 bis — « plus tard », confirmé (un toast)

    public static var laterTitle: String { t("announceLater.title", "Got it") }
    public static func laterBody(_ date: String) -> String {
      fill(
        t("announceLater.body", "The additional features are on us until {date}. We'll remind you before it ends."),
        ["date": date]
      )
    }
    public static var laterBodyNoDate: String {
      t("announceLater.bodyNoDate", "The additional features are on us for a month. We'll remind you before it ends.")
    }
    public static var laterWhere: String {
      t("announceLater.where", "In the meantime, your referral code is waiting in Settings, under “Referrals”.")
    }

    // MARK: 5 — les 3 jours offerts (un toast, § 4)

    public static var graceTitle: String { t("grace.title", "+3 days on us") }
    public static var graceBody: String {
      t(
        "grace.body",
        "You had less than 3 days left: here are a few more, while the person installs the app. The point isn't to block you, it's to reward your invitation."
      )
    }
    public static func graceStatus(_ date: String) -> String {
      fill(t("grace.status", "Additional features until {date}."), ["date": date])
    }

    // MARK: La jauge (§ 2.2, § 12.4)

    public static var gaugeIf: String { t("gauge.if", "If I invite") }
    public static func gaugeUnit(_ count: Int) -> String {
      plural("gauge.unit", count, one: "person", other: "people")
    }
    public static var gaugeThen: String { t("gauge.then", "I earn") }
    public static var gaugeRestIf: String { t("gauge.restIf", "Confirmed invitations") }
    public static var gaugeRestThen: String { t("gauge.restThen", "Months earned") }
    public static var gaugeIfElastic: String { t("gauge.ifElastic", "If I confirm") }
    public static var gaugeThenElastic: String { t("gauge.thenElastic", "I would earn") }
    public static func gaugeUnitInvitation(_ count: Int) -> String {
      plural("gauge.unitInv", count, one: "invitation", other: "invitations")
    }
    public static func gaugeMonths(_ count: Int) -> String {
      plural("gauge.months", count, one: "month", other: "months")
    }
    public static var gaugeLifetime: String { t("gauge.lifetime", "for life") }
    /// `**…**` = en gras.
    public static func gaugeBonus(_ bonus: Int) -> String {
      fill(t("gauge.bonus", "including **+{bonus} bonus months**"), ["bonus": "\(bonus)"])
    }
    public static func gaugeNow(_ count: Int) -> String {
      plural("gauge.now", count, one: "You're at {count} confirmed invitation.", other: "You're at {count} confirmed invitations.")
    }
    public static var gaugeHelp: String { t("gauge.help", "1 month per confirmed invitation, plus the tier bonuses.") }
    public static var gaugeLifeTitle: String { t("gauge.lifeTitle", "For life") }
    public static func gaugeLifeSub(_ count: Int) -> String {
      plural("gauge.lifeSub", count, one: "from {count} confirmed invitation", other: "from {count} confirmed invitations")
    }
    public static var gaugeLifeReached: String { t("gauge.lifeReached", "Browther is 100% unlocked.") }
    public static func gaugeTickBonus(_ count: Int) -> String {
      plural("gauge.tickBonus", count, one: "+{count} month", other: "+{count} months")
    }
    public static var gaugeTickLifetime: String { t("gauge.tickLifetime", "for life") }
    public static var gaugeA11y: String { t("gauge.a11y", "Number of invitations") }

    // MARK: La carte du code (§ 12.3)

    public static var cardCodeHead: String { t("card.codeHead", "Your referral code") }
    public static var cardCopy: String { t("card.copy", "Copy") }
    public static var cardCopied: String { t("card.copied", "Copied") }

    // MARK: Le code d'un proche (écran O, onglet « Code reçu », § 12.6)

    public static var redeemHead: String { t("redeem.head", "Did someone tell you about Browther?") }
    public static var redeemBody: String {
      t("redeem.body", "Ask them for their referral code: two months of additional features, one for you and one for them.")
    }
    public static var redeemPlaceholder: String { t("redeem.placeholder", "Referral code") }
    public static var redeemPaste: String { t("redeem.paste", "Paste") }
    public static var redeemValidate: String { t("redeem.validate", "Confirm") }
    public static var redeemValidatedLine: String {
      t("redeem.validatedLine", "All set: two months of additional features, one for you and one for them.")
    }
    public static var redeemErrorLength: String { t("redeem.inputError.length", "A referral code has 6 characters.") }
    public static var redeemErrorAlphabet: String {
      t(
        "redeem.inputError.alphabet",
        "This code contains a character no code uses (such as O, 0, I or 1): check it with them."
      )
    }
    public static var refusalUnknownCode: String {
      t("redeem.refusal.unknown_code", "That code doesn't match anyone. Check it with the person who gave it to you.")
    }
    public static var refusalSelf: String { t("redeem.refusal.self", "That's your own code.") }
    public static var refusalSameDevice: String { t("redeem.refusal.same_device", "That code was created on this phone.") }
    public static var refusalAlreadyRedeemed: String {
      t("redeem.refusal.already_redeemed", "You've already used a referral code.")
    }
    public static var refusalWrongProduct: String {
      t("redeem.refusal.wrong_product", "That code belongs to another dev&din app.")
    }
    public static var refusalUnavailable: String {
      t("redeem.refusal.unavailable", "We can't reach the service. Please try again in a moment.")
    }
    public static var later: String { t("welcome.later", "Later") }

    // MARK: 0 — l'annonce

    public static var announceTitle: String { t("announce.title", "Help us keep this app free") }
    public static var announceBody: String {
      t(
        "announce.body",
        "The dev&din studio needs your support to keep offering apps like this one for free. All we're asking is that you spread the word."
      )
    }
    public static var inviteSomeone: String { t("announce.invite", "Invite someone") }
    /// ⚠️ Le même bouton quand une invitation est déjà partie : « Inviter un
    /// proche » sonnerait comme si rien n'avait été fait.
    public static var inviteAnother: String { t("invite.another", "Invite someone else") }
    public static var announceInviteSub: String { t("announce.inviteSub", "And aim for free lifetime access") }
    public static var announceLater: String { t("announce.later", "Remind me later") }

    // MARK: 1 — J−10 / J−3

    public static func endingTitle(_ days: Int) -> String {
      plural(
        "ending.title",
        days,
        one: "Tomorrow, some additional features will pause.",
        other: "In {count} days, some additional features will pause."
      )
    }
    /// ⭐ L'issue se lit À PART du constat, dans l'or du texte (§ 12.30) :
    /// fondue dans le titre, elle se lisait comme la fin d'une mauvaise
    /// nouvelle.
    public static var endingHook: String {
      t("ending.hook", "But you can keep them for life, for free!")
    }
    /// `**…**` = en gras.
    public static var endingBody: String {
      t(
        "ending.body",
        "The dev&din studio **needs your support** to keep offering free apps. All we're asking is that you help your contacts discover it. If you really can't, you can also support us financially, or with a du'a."
      )
    }
    public static var supportSub: String { t("ending.supportSub", "Invite someone, financially, or with a du'a") }

    // MARK: 2 — J0

    public static var pausedTitle: String { t("paused.title", "Additional features are paused") }
    public static var pausedBody: String {
      t("paused.body", "For these apps to stay free, the dev&din studio needs you.")
    }
    public static var pausedFoot: String {
      t("paused.foot", "This screen will come back now and then, never more than once a week.")
    }

    // MARK: 2b — les trois façons

    public static var supportTitle: String {
      t("support.title", "How many people do you think you could invite?")
    }
    public static func supportInviteSub(_ days: Int) -> String {
      plural(
        "support.inviteSub",
        days,
        one: "Browther as default browser for {count} day = confirmed invitation",
        other: "Browther as default browser for {count} days = confirmed invitation"
      )
    }
    /// ⭐ Le bouton répond avec le nombre de la jauge (§ 12.30) : l'écran
    /// demande « combien penses-tu pouvoir inviter ? », le bouton le reprend.
    public static func supportInviteCount(_ count: Int) -> String {
      plural("support.inviteCount", count, one: "Invite {count} person", other: "Invite {count} people")
    }
    public static var supportOr: String { t("support.or", "or") }
    public static func supportMoney(_ price: String) -> String {
      fill(t("support.money", "Support financially · {price}/month"), ["price": price])
    }
    public static var supportDua: String { t("support.none", "A du'a is all I can do for now") }

    // MARK: 3 — les rappels (§ 3.3)

    public static func reminderTitleFeatures(_ days: Int) -> String {
      plural(
        "reminder.featuresTitle",
        days,
        one: "Tomorrow, your additional features will pause.",
        other: "In {count} days, your additional features will pause."
      )
    }
    public static var reminderNoneOpened: String {
      t(
        "reminder.noneOpened",
        "Your invitation hasn't been opened yet. You can send it again, or invite someone else."
      )
    }
    public static var reminderInProgress: String {
      t(
        "reminder.inProgress",
        "One of your invitations is on its way: your code has been used, only a few days with Browther as default browser are missing."
      )
    }
    public static func reminderInProgressCount(_ days: Int) -> String {
      plural(
        "reminder.inProgressCount",
        days,
        one: "One of your invitations is on its way: {count} more day with Browther as default browser and it's confirmed.",
        other: "One of your invitations is on its way: {count} more days with Browther as default browser and it's confirmed."
      )
    }
    public static func reminderTitleMonths(_ days: Int) -> String {
      plural(
        "reminder.monthsTitle",
        days,
        one: "Tomorrow, the months you earned come to an end.",
        other: "In {count} days, the months you earned come to an end."
      )
    }
    public static var reminderMonths: String {
      t("reminder.months", "Every confirmed invitation adds one more.")
    }
    /// ⭐ Le rappel dit le GAIN, ⛔ pas le « palier suivant » : « palier » ne veut
    /// rien dire pour qui n'a pas lu le barème (recette Karim, 2026-09-23).
    /// Deux phrases, parce que le prochain jalon est soit des mois en bonus,
    /// soit l'accès à vie — `ReferralMilestones.Next.lifetime` tranche.
    public static func reminderMonthsNext(_ left: Int, bonus: Int) -> String {
      fill(
        plural(
          "reminder.monthsNext",
          left,
          one: "Each confirmed invitation adds one. {count} more and you get a {bonus}-month bonus.",
          other: "Each confirmed invitation adds one. {count} more and you get a {bonus}-month bonus."
        ),
        ["bonus": "\(bonus)"]
      )
    }
    public static func reminderMonthsNextLife(_ left: Int) -> String {
      plural(
        "reminder.monthsNextLife",
        left,
        one: "Each confirmed invitation adds one. {count} more and Browther is unlocked for life.",
        other: "Each confirmed invitation adds one. {count} more and Browther is unlocked for life."
      )
    }
    public static func reminderTitleSubscription(_ days: Int) -> String {
      plural(
        "reminder.subscriptionTitle",
        days,
        one: "Your subscription ends tomorrow.",
        other: "Your subscription ends in {count} days."
      )
    }
    public static var reminderSubscription: String {
      t(
        "reminder.subscription",
        "Thank you for your support. You can keep the additional features by inviting someone, or by renewing."
      )
    }

    // MARK: 4 — inviter

    public static var inviteEyebrow: String { t("invite.eyebrow", "Invite") }
    public static var shareMyCode: String { t("invite.share", "Share my code") }
    /// Le 2ᵉ geste, à côté de « Partager mon code » (2026-09-29,
    /// `devndin/docs/PARRAINAGE-partage-statut.md`) : ⭐ le libellé CITE WhatsApp —
    /// l'image dit « Clique sur le lien en dessous », vrai seulement là où le
    /// lien devient la légende (⛔ pas les stories Instagram / Facebook).
    public static var shareStatus: String { t("invite.shareStatus", "Post to my WhatsApp status") }

    // MARK: La feuille « Partager mon code » : Statut WhatsApp, puis Message
    //
    // `private/docs/PARRAINAGE.md` § 11 (2026-10-08) — les mots de Fajrunaa
    // (`referral.status.*`, `referral.share.*`), ⚠️ les mêmes d'un produit à
    // l'autre : c'est le même système.

    public static var statusTab: String { t("status.tab", "WhatsApp status") }
    public static var statusPreviewA11y: String {
      t("status.previewA11y", "Your status image, with your code, and the link as its caption")
    }
    public static var statusFailed: String {
      t("status.failed", "The image couldn't be prepared. Try again, or share the message.")
    }
    public static var statusFailedVideo: String {
      t("status.failedVideo", "The video couldn't be shared. Try again, or post your image alone.")
    }
    public static var statusVideoLabel: String { t("status.videoLabel", "The video") }
    public static var statusVideoSub: String { t("status.videoSub", "It shows the app") }
    public static var statusImageLabel: String { t("status.imageLabel", "Your image") }
    public static var statusImageSub: String { t("status.imageSub", "It carries your code") }
    public static var statusPublished: String { t("status.published", "Posted") }
    public static var statusPublishBoth: String { t("status.publishBoth", "Post both statuses") }
    public static var statusPublishVideo: String { t("status.publishVideo", "Post the video") }
    public static var statusPublishImage: String { t("status.publishImage", "Post your image") }
    public static var statusPublishVideoNext: String { t("status.publishVideoNext", "Post the video · 2 of 2") }
    public static var statusPublishImageNext: String { t("status.publishImageNext", "Post your image · 2 of 2") }
    public static var statusPickOne: String { t("status.pickOne", "Pick at least one status") }
    public static var statusHintBoth: String {
      t("status.hintBoth", "WhatsApp opens once per status: each one goes with your link.")
    }
    public static var statusHintOne: String { t("status.hintOne", "Tap the other card to post both.") }
    public static var statusHintVideoDone: String {
      t("status.hintVideoDone", "The video is posted. Your image is next.")
    }
    public static var statusHintImageDone: String {
      t("status.hintImageDone", "Your image is posted. The video is next.")
    }
    public static var statusHintVideoDoneAuto: String {
      t("status.hintVideoDoneAuto", "The video is posted. Your image follows in a moment.")
    }
    public static var statusHintImageDoneAuto: String {
      t("status.hintImageDoneAuto", "Your image is posted. The video follows in a moment.")
    }
    public static var statusHintNone: String { t("status.hintNone", "Tap a card to bring it back.") }
    public static var shareTabMessage: String { t("share.tabMessage", "Message") }
    public static var shareAttachVideo: String { t("share.attachVideo", "Attach the video") }
    public static var shareSend: String { t("share.send", "Send to someone") }
    public static var sharePreviewA11y: String {
      t("share.previewA11y", "Your message, as the person will receive it")
    }
    public static var back: String { t("invite.back", "Back") }
    public static var backToApp: String { t("invite.closeAfterShare", "Back to the app") }
    public static func inviteFoot(_ days: Int) -> String {
      plural(
        "invite.foot",
        days,
        one: "An invitation is confirmed once the person has kept Browther as their default browser for {count} day.",
        other: "An invitation is confirmed once the person has kept Browther as their default browser for {count} days."
      )
    }

    // MARK: Le message partagé (§ 12.10)

    public static func shareMessage(code: String) -> String {
      fill(
        t(
          "share.message",
          "I'm inviting you to discover Browther: the browser that mutes music and blurs haram images.\nWith my code {code}, you get a month of additional features."
        ),
        ["code": code]
      )
    }

    // MARK: 8 — la seule notification

    /// ⭐ § 12.32 : 8 et 8 bis sont les seules fenêtres que personne n'a
    /// demandées — elles tombent des semaines plus tard, par-dessus l'écran en
    /// cours. D'où le sujet (cet eyebrow), le gain en accroche, puis la cause.
    // MARK: Les portes d'entrée (Paramètres, panneau de la fonctionnalité)

    /// ⛔ L'offre n'est pas servie par le store : on le dit, ⛔ pas un bouton
    /// grisé muet.
    public static var billingUnavailable: String {
      t("billing.unavailable", "The plans aren't loading right now.")
    }
    public static var billingRetry: String { t("billing.retry", "Try again") }
    /// ⭐ Le libellé du menu « … » : il dit ce qu'on fait ET où (Karim,
    /// 2026-09-23) — « Parrainage » seul ne donne envie à personne.
    public static var menuInvite: String {
      t("menu.invite", "Invite someone to Browther")
    }
    /// La ligne des Paramètres : ce qu'on y gagne, en une ligne.
    public static var settingsSubtitle: String {
      t("settings.subtitle", "Earn hassanat and lifetime access")
    }
    /// L'étiquette de la pastille (lecteurs d'écran).
    public static var settingsNews: String { t("settings.news", "New") }
    /// ⭐ Le rappel DANS le panneau de la fonctionnalité supplémentaire.
    public static var panelExtraBadge: String {
      t("panel.extraBadge", "Additional feature")
    }
    public static var panelCovered: String { t("panel.covered", "Yours for now.") }
    public static func panelCoveredUntil(_ date: String) -> String {
      fill(t("panel.coveredUntil", "Yours until {date}."), ["date": date])
    }
    public static var panelPausedLine: String {
      t("panel.pausedLine", "Paused: invite someone to get it back.")
    }
    public static var panelKeepForLife: String {
      t("panel.keepForLife", "Keep it for life")
    }

    public static var noticeEyebrow: String { t("notice.eyebrow", "Referrals") }
    public static var noticeTitle: String { t("notice.title", "Invitation confirmed!") }
    /// La cause, au présent immédiat — ⛔ jamais le mécanisme ni une consigne.
    public static func noticeWhy(_ days: Int) -> String {
      plural(
        "notice.why",
        days,
        one: "Someone used your referral code, and has just kept Browther as their default browser for {count} day.",
        other: "Someone used your referral code, and has just kept Browther as their default browser for {count} days."
      )
    }
    public static func noticeBody(months: Int, date: String) -> String {
      fill(
        plural(
          "notice.body",
          months,
          one: "+{count} month of additional features, until {date}.",
          other: "+{count} months of additional features, until {date}."
        ),
        ["date": date]
      )
    }
    public static func noticeBodyNoDate(months: Int) -> String {
      plural(
        "notice.bodyNoDate",
        months,
        one: "+{count} month of additional features.",
        other: "+{count} months of additional features."
      )
    }
    public static var noticeLifetime: String {
      t("notice.bodyLifetime", "You made it: Browther is 100% unlocked, for life.")
    }
    public static var noticeSee: String { t("notice.see", "See my referrals") }

    // MARK: 8 bis — côté filleul (§ 5.3)

    public static var refereeTitle: String { t("referee.title", "Your referral") }
    public static func refereeProgress(_ days: Int) -> String {
      plural(
        "referee.progress",
        days,
        one: "{count} more day with Browther as default browser and they earn 1 month of additional features.",
        other: "{count} more days with Browther as default browser and they earn 1 month of additional features."
      )
    }
    public static var refereeDone: String {
      t("referee.done", "Done: they earned 1 month of additional features. Thank you on their behalf.")
    }
    public static func refereeHint(_ days: Int) -> String {
      plural(
        "referee.hint",
        days,
        one: "Someone helped you discover Browther. You received two months; theirs is added once you've kept Browther as your default browser for {count} day.",
        other: "Someone helped you discover Browther. You received two months; theirs is added once you've kept Browther as your default browser for {count} days."
      )
    }
    public static var refereeNoticeTitle: String { t("referee.noticeTitle", "Thank you!") }
    public static var refereeNoticeBody: String {
      t("referee.noticeBody", "They earned 1 month of additional features — by Allah's grace, then thanks to you.")
    }
    /// La cause, côté filleul (`criterion_self` du § 12.32), au genre neutre.
    public static func refereeNoticeWhy(_ days: Int) -> String {
      plural(
        "referee.noticeWhy",
        days,
        one: "You used their referral code, and you have just kept Browther as your default browser for {count} day.",
        other: "You used their referral code, and you have just kept Browther as your default browser for {count} days."
      )
    }
    public static var refereeInviteToo: String { t("referee.inviteToo", "My turn to invite someone") }
    public static func refereeMeter(current: Int, target: Int) -> String {
      fill(
        plural("referee.meter", target, one: "{current} of {count} day", other: "{current} of {count} days"),
        ["current": "\(current)"]
      )
    }
    /// La proposition : régler Browther comme navigateur par défaut — c'est ce
    /// qui valide l'invitation du proche (§ 9).
    public static var refereeSetDefault: String {
      t("referee.setDefault", "Set Browther as default browser")
    }

    // MARK: Mes invitations (§ 12.1)

    public static var invitationValidated: String { t("invitations.validated", "Confirmed") }
    public static var invitationInProgress: String { t("invitations.inProgress", "In progress") }
    public static func invitationMonths(_ count: Int) -> String {
      plural("invitations.months", count, one: "+{count} month", other: "+{count} months")
    }
    public static func invitationRowValidated(_ days: Int) -> String {
      plural(
        "invitations.rowValidated",
        days,
        one: "{count} day as default browser: your month is added.",
        other: "{count} days as default browser: your month is added."
      )
    }
    public static func invitationRowInProgress(_ days: Int) -> String {
      plural(
        "invitations.rowInProgress",
        days,
        one: "Your code has been used. {count} more day with Browther as default browser before it's confirmed.",
        other: "Your code has been used. {count} more days with Browther as default browser before it's confirmed."
      )
    }
    public static func invitationRowInProgressUnknown(_ days: Int) -> String {
      plural(
        "invitations.rowInProgressUnknown",
        days,
        one: "Your code has been used. The invitation is confirmed once the person has kept Browther as their default browser for {count} day.",
        other: "Your code has been used. The invitation is confirmed once the person has kept Browther as their default browser for {count} days."
      )
    }
    public static func invitationMilestone(bonus: Int, at: Int) -> String {
      fill(
        plural("invitations.milestone", bonus, one: "+{count} bonus month · tier {at} reached", other: "+{count} bonus months · tier {at} reached"),
        ["at": "\(at)"]
      )
    }

    // MARK: 7 — soutenir financièrement (§ 3 ; le bouton nomme le GESTE)

    public static var billingEyebrow: String { t("billing.eyebrow", "Support financially") }
    public static var billingTitle: String { t("billing.title", "Unlock everything, with nothing to do") }
    public static var billingBody: String {
      t("billing.body", "You get all of Browther's additional features, right away. Cancel any time.")
    }
    public static var billingYear: String { t("billing.year", "One year") }
    public static var billingYearBadge: String { t("billing.yearBadge", "2 months free") }
    public static func billingYearSub(_ price: String) -> String {
      fill(t("billing.yearSub", "that's {price} per month"), ["price": price])
    }
    public static var billingMonth: String { t("billing.month", "One month") }
    public static var billingMonthSub: String { t("billing.monthSub", "cancel whenever you want") }
    public static func billingCtaYear(_ price: String) -> String {
      fill(t("billing.ctaYear", "I support · {price} per year"), ["price": price])
    }
    public static func billingCtaMonth(_ price: String) -> String {
      fill(t("billing.ctaMonth", "I support · {price} per month"), ["price": price])
    }
    public static var billingLegal: String {
      t("billing.legal", "Renews automatically, cancel any time from your Apple account settings.")
    }
    public static var billingTerms: String { t("billing.terms", "Terms of use") }
    public static var billingPrivacy: String { t("billing.privacy", "Privacy") }
    /// ⚠️ StoreKit ne ramène QUE ce qui a été payé à Apple, avec ce compte
    /// Apple : l'ancien libellé (« Déjà abonné sur un autre iPhone ? ») a
    /// envoyé Karim sur une fausse piste pour un abonnement payé sur le Mac
    /// (recette du 2026-09-24). Le Mac, c'est `billingElsewhere`.
    public static var billingRestore: String {
      t("billing.restore", "Paid with your Apple account? Restore my purchases")
    }
    /// La vraie réponse à « j'ai payé ailleurs » : le compte dev&din.
    public static var billingElsewhere: String {
      t("billing.elsewhere", "Paid on your computer? Sign in")
    }
    public static var billingRestored: String { t("billing.restored", "Done: your subscription is back.") }
    public static var billingRestoreNone: String { t("billing.restoreNone", "Nothing to restore for now.") }
    public static var billingFailed: String {
      t("billing.failed", "The payment didn't go through. Please try again in a moment.")
    }
    public static var billingManage: String { t("billing.manage", "Manage my subscription") }
    public static var billingManageHint: String {
      t("billing.manageHint", "Cancelling and invoices go through your Apple account: it is the one that charges you.")
    }
    public static var billingAlreadyTitle: String { t("billing.alreadyTitle", "You already support dev&din") }
    public static var billingAlreadyBody: String {
      t("billing.alreadyBody", "Thank you! All of Browther's additional features are unlocked.")
    }
    public static func billingRenews(_ date: String) -> String {
      fill(t("billing.renews", "Your subscription renews automatically on {date}, in sha Allah."), ["date": date])
    }
    public static func billingEnds(_ date: String) -> String {
      fill(t("billing.ends", "Your subscription ends on {date}, in sha Allah."), ["date": date])
    }

    // MARK: 7 bis — « Merci » (§ 12.17)

    public static var thanksTitle: String { t("thanks.title", "Thank you for your support!") }
    /// 🔴 « Grâce à Allah, puis à toi » — ⛔ jamais « grâce à toi » seul (§ 6).
    public static var thanksBodyActive: String {
      t(
        "thanks.bodyActive",
        "All additional features are unlocked. By Allah's grace, then thanks to you, the dev&din studio can keep offering free apps."
      )
    }
    public static var thanksBodyPending: String {
      t("thanks.bodyPending", "Your subscription is being set up: the additional features will unlock in a moment.")
    }

    // MARK: 6 — l'écran Parrainage

    public static var homeTitle: String { t("home.title", "Referrals") }
    public static var homeListHead: String { t("home.listHead", "My invitations") }
    public static var homeAsReferee: String { t("home.asReferee", "A code from someone close") }
    public static var tabInvite: String { t("home.tabs.invite", "Invite") }
    public static var tabInvitations: String { t("home.tabs.invitations", "Invitations") }
    public static var tabCode: String { t("home.tabs.code", "Got a code") }
    public static var tabSupport: String { t("home.tabs.support", "Support") }
    public static var homeUnreachable: String {
      t("home.unreachable", "We can't reach the referral service. Check your connection.")
    }
    public static var retry: String { t("home.retry", "Try again") }
    public static var coverA: String { t("home.coverA", "Additional features") }
    public static var coverLifetime: String { t("home.coverLifetime", "forever") }
    public static var coverPaid: String { t("home.coverPaid", "included in your subscription") }
    public static var coverPaused: String { t("home.coverPaused", "paused") }
    public static func coverUntil(_ date: String) -> String {
      fill(t("home.coverUntil", "until {date}"), ["date": date])
    }
    /// ⚠️ Avant l'annonce, rien n'a démarré : « offertes », ⛔ pas « offertes
    /// pendant 1 mois » — chez Browther, le mois attend Sawtunaa (§ 9).
    public static var coverOpen: String { t("home.coverOpen", "on us") }
    public static var whatExtras: String { t("home.whatExtras", "What are the additional features?") }
    public static var whyPaused: String {
      t(
        "home.whyPaused",
        "They come back as soon as an invitation is confirmed, or by supporting us financially. Blurring and ad blocking stay on."
      )
    }
    /// `**…**` = en gras.
    public static func homeProgress(count: Int, months: Int, left: Int, bonus: Int) -> String {
      fill(
        plural(
          "home.progress",
          count,
          one: "**{count} confirmed invitation** = {months} months. {left} more for +{bonus} bonus months.",
          other: "**{count} confirmed invitations** = {months} months. {left} more for +{bonus} bonus months."
        ),
        ["months": "\(months)", "left": "\(left)", "bonus": "\(bonus)"]
      )
    }
    public static func homeProgressToLife(count: Int, months: Int, left: Int) -> String {
      fill(
        plural(
          "home.progressToLife",
          count,
          one: "**{count} confirmed invitation** = {months} months. {left} more for lifetime access.",
          other: "**{count} confirmed invitations** = {months} months. {left} more for lifetime access."
        ),
        ["months": "\(months)", "left": "\(left)"]
      )
    }
    public static func homeProgressLife(count: Int) -> String {
      plural(
        "home.progressLife",
        count,
        one: "**{count} confirmed invitation**: Browther is 100% unlocked, for life.",
        other: "**{count} confirmed invitations**: Browther is 100% unlocked, for life."
      )
    }
    public static var homeEmpty: String { t("home.empty", "You haven't invited anyone yet.") }
    public static var homeEmptyHint: String {
      t("home.emptyHint", "They'll show up here as soon as someone uses your code.")
    }
    // MARK: Sur tes autres appareils (le compte facultatif, § 7.1)

    public static var accountHead: String { t("home.accountHead", "On your other devices") }
    /// ⚠️ **« Parrainage », ⛔ plus « soutien »** (contrat commun du compte,
    /// `docs/PARRAINAGE.md` § 7.1) : « ton soutien » se lisait « soutien
    /// financier », et qui n'a rien payé ne s'y reconnaissait pas. Le compte
    /// NOMME ce qu'il porte : code, invitations, mois gagnés, abonnement.
    /// ⚠️ « appareil », ⛔ pas « iPhone » : les textes du contrat sont les mêmes
    /// sur l'iPhone, l'ordinateur et Android.
    public static var accountTitle: String { t("account.title", "My account") }
    public static var accountOff: String { t("account.off", "Not connected") }
    public static var accountOn: String { t("account.on", "Connected") }
    public static var accountManage: String { t("account.manage", "See my account") }
    /// Qui a quelque chose en jeu (un code parti, une invitation, un abonnement).
    public static var accountBodyShelter: String {
      t(
        "account.bodyShelter",
        "With an account, your code, your invitations, your earned months and your subscription follow you on your other devices, and if you change or lose one."
      )
    }
    /// Qui arrive sur un appareil neuf : il n'a rien à mettre à l'abri, il RETROUVE.
    public static var accountBodyRecover: String {
      t(
        "account.bodyRecover",
        "Already have an account? Sign in to get your code, your invitations, your earned months and your subscription back here."
      )
    }
    /// ⭐ **dev&din se présente DANS la page du compte**, pas à ses portes
    /// (Karim, 2026-10-08 : « les utilisateurs ne connaissent pas forcément la
    /// marque, le studio ») : aux points d'entrée le compte s'appelle « Mon
    /// compte » ; une fois entré, cette phrase dit ce qu'est le studio et
    /// pourquoi le compte est le sien. ⚠️ Le nom reste sur « Supprimer mon
    /// compte dev&din » : la suppression vaut pour toutes ses apps.
    public static var accountAbout: String {
      t(
        "account.about",
        "Browther is a browser by the dev&din studio. Your account is a dev&din account: it also works in its other apps."
      )
    }
    public static var accountOnly: String {
      t(
        "account.only",
        "The account only keeps your referrals and your subscription: code, invitations, earned months. Never your history, bookmarks or tabs."
      )
    }
    public static var accountConnectedBody: String {
      t(
        "account.connectedBody",
        "Everything is safe. On another device, connect this same account to get your code, your invitations, your earned months and your subscription back."
      )
    }
    /// Le piège des deux comptes (Apple « masquer mon adresse » ici, Google là-bas).
    public static var accountSameWay: String {
      t("account.sameWay", "On another device, sign in the same way: same button, or same address.")
    }
    /// Le tampon du bouton Google (`docs/AUTH.md` § « Quel SSO mettre en avant »).
    public static var accountRecommended: String { t("account.recommended", "Recommended") }

    // La proposition du compte, onglet par onglet : chacun a SA rangée, avec
    // ses mots (`ReferralAccountStake`).
    public static var accountHintInviteTitle: String { t("account.hint.invite.title", "Keep your code safe") }
    public static var accountHintInviteSub: String {
      t(
        "account.hint.invite.sub",
        "Sign in: your code and the invitations to come follow you if you change devices."
      )
    }
    public static var accountHintInvitationsTitle: String {
      t("account.hint.invitations.title", "Keep your invitations safe")
    }
    public static var accountHintInvitationsSub: String {
      t(
        "account.hint.invitations.sub",
        "Sign in: your invitations and your earned months follow you if you change devices."
      )
    }
    public static var accountHintRefereeTitle: String {
      t("account.hint.referee.title", "Keep your free month safe")
    }
    public static var accountHintRefereeSub: String {
      t(
        "account.hint.referee.sub",
        "Sign in: your free month and your progress follow you if you change devices."
      )
    }
    public static var accountHintPaidTitle: String { t("account.hint.paid.title", "Keep your subscription safe") }
    public static var accountHintPaidSub: String {
      t(
        "account.hint.paid.sub",
        "Sign in: you get it back on your other devices, and if you change devices."
      )
    }

    // La suppression du compte, DANS l'app (Apple 5.1.1(v)) : ce qui part,
    // puis le code à six chiffres reçu par e-mail.
    public static var accountDelete: String { t("account.delete", "Delete my dev&din account") }
    public static var accountDeleteBody: String {
      t(
        "account.deleteBody",
        "Your dev&din account will be deleted for every dev&din app where you use it, along with your referral code, your invitations and your earned months. This is permanent."
      )
    }
    /// ⛔ Ne nomme aucune boutique : le compte vaut pour tous les appareils.
    public static var accountDeleteSubscription: String {
      t(
        "account.deleteSubscription",
        "A running subscription is not cancelled by this deletion: remember to cancel it where you took it out."
      )
    }
    public static var accountDeleteSend: String { t("account.deleteSend", "Get the confirmation code") }
    public static var accountDeleteSendFailed: String {
      t("account.deleteSendFailed", "We couldn't send the code. Try again in a moment.")
    }
    public static func accountDeleteSent(_ destination: String) -> String {
      fill(t("account.deleteSent", "Code sent to {destination}. Enter it to confirm."), ["destination": destination])
    }
    public static var accountDeleteConfirm: String { t("account.deleteConfirm", "Delete permanently") }
    public static var accountDeleteFailed: String {
      t("account.deleteFailed", "The deletion didn't go through. Try again in a moment.")
    }
    public static func accountDeleteElsewhere(_ apps: String) -> String {
      fill(
        t(
          "account.deleteElsewhere",
          "This account is also used by {apps}: delete it from that app. Here, you can disconnect this device."
        ),
        ["apps": apps]
      )
    }
    public static var accountDeleteElsewhereUnknown: String {
      t(
        "account.deleteElsewhereUnknown",
        "This dev&din account was created in another dev&din app: delete it from that app. Here, you can disconnect this device."
      )
    }
    public static var accountDeleted: String { t("account.deleted", "Your dev&din account is deleted.") }
    public static var accountConnect: String { t("account.connect", "Sign in") }
    public static var accountWithApple: String { t("account.withApple", "Continue with Apple") }
    public static var accountWithGoogle: String { t("account.withGoogle", "Continue with Google") }
    public static var accountWithEmail: String { t("account.withEmail", "Continue with an email") }
    public static var accountEmailPlaceholder: String { t("account.emailPlaceholder", "example@address.com") }
    public static var accountSendCode: String { t("account.sendCode", "Get a code") }
    public static func accountCodeSent(_ email: String) -> String {
      fill(t("account.codeSent", "Code sent to {email}. It's valid for 15 minutes."), ["email": email])
    }
    public static var accountVerify: String { t("account.verify", "Sign in") }
    public static var accountBadCode: String {
      t("account.badCode", "This code doesn't work. Check it, or ask for a new one.")
    }
    public static var accountRetry: String { t("account.retry", "Try again") }
    public static var accountCancel: String { t("account.cancel", "Cancel") }
    public static var accountUnreachable: String {
      t("account.unreachable", "We can't reach the sign-in service. Check your connection.")
    }
    public static var accountError: String { t("account.error", "The sign-in didn't go through.") }
    public static var accountConnected: String { t("account.connected", "You're signed in.") }
    /// « Masquer mon adresse » d'Apple : le relais est illisible, on dit par où
    /// se reconnecter (`ReferralAccountLabel`).
    public static var accountConnectedApple: String {
      t("account.connectedApple", "Signed in with Apple.")
    }
    public static func accountConnectedAs(_ email: String) -> String {
      fill(t("account.connectedAs", "Signed in with {email}"), ["email": email])
    }
    /// ⭐ Le message de connexion NOMME ce qui suit — et ne cite l'abonnement
    /// que s'il y en a un (`accountLinkedPaid`).
    public static var accountLinked: String {
      t("account.linked", "Done: your code, your invitations and your earned months follow you on this device.")
    }
    public static var accountLinkedPaid: String {
      t(
        "account.linkedPaid",
        "Done: your code, your invitations, your earned months and your subscription follow you on this device."
      )
    }
    public static var accountSignOut: String { t("account.signOutPhone", "Disconnect this iPhone") }

    // Relier un appareil : l'appareil connecté affiche un QR, l'autre le scanne.
    public static var accountScan: String { t("account.scan", "Scan my computer's QR code") }
    /// ⚠️ Le chemin se compose des VRAIS libellés (l'entrée du menu ⋯ du
    /// desktop, le bouton d'en-tête de son écran Parrainage) : traduits une
    /// fois, ils ne peuvent pas diverger de ce que la personne voit à l'écran.
    /// Depuis le 2026-10-07, le compte du desktop est dans l'EN-TÊTE
    /// (« Mon compte »), plus dans une rubrique « Sur tes autres appareils ».
    public static var accountScanHint: String {
      fill(
        t("account.scanHint", "On your computer, in Browther: ⋯ menu › {menu} › {section}."),
        ["menu": t("menu.invite", "Invite someone to Browther"), "section": accountTitle]
      )
    }
    public static var accountOtherWay: String { t("account.otherWay", "Sign in another way") }
    public static var accountScanComputer: String { t("account.scanComputer", "Link a computer") }
    public static var accountScanUnknown: String {
      t("account.scanUnknown", "This QR code doesn't come from Browther.")
    }
    public static func accountLinkConfirm(_ email: String) -> String {
      fill(t("account.linkConfirm", "Connect this iPhone to the account {email}?"), ["email": email])
    }
    public static var accountLinkConfirmGeneric: String {
      t("account.linkConfirmGeneric", "Connect this iPhone to your account?")
    }
    public static var accountLinkCta: String { t("account.linkCta", "Connect") }
    public static var accountApproveTitle: String {
      t("account.approveTitle", "Allow Browther on this computer?")
    }
    public static func accountApproveBody(_ code: String) -> String {
      fill(t("account.approveBody", "Check that the computer shows the code {code}."), ["code": code])
    }
    public static var accountApproveCta: String { t("account.approveCta", "Allow") }
    public static var accountApproved: String {
      t("account.approved", "Done: your computer is linked to your account.")
    }
    public static var accountSignInFirst: String {
      t(
        "account.signInFirst",
        "First sign in on this iPhone: the computer will be allowed right after."
      )
    }
    public static var accountExpired: String { t("account.expired", "The code has expired.") }

    public static func homeLinkOpens(_ count: Int) -> String {
      fill(t("home.linkOpens", "Link opens: {count}"), ["count": "\(count)"])
    }
    public static var homeLegend: String {
      t(
        "home.legend",
        "We never know who received your code, nor what the person does in the app: only how many days are left before your month is added."
      )
    }
    public static var messageCopied: String {
      t("share.copied", "Message copied: just paste it to the person you're inviting.")
    }
    public static var close: String { t("common.close", "Close") }

    // MARK: L'image du statut WhatsApp (2026-09-29)

    /// Les textes DANS l'image du statut — `devndin/docs/PARRAINAGE-partage-statut.md`
    /// § 3 et § 5. ⚠️ **Hors de la table traduite, exprès** : l'image n'existe
    /// qu'en fr, en et ar (décision du 2026-09-28 : une police par écriture
    /// n'en vaut pas le coût tant qu'on n'a pas mesuré), les autres langues
    /// retombent sur l'anglais. Jumeau du site : `website/messages/*.json`
    /// → `sharePage.statusImage` (mêmes mots, relus par Karim en français).
    ///
    /// `[[…]]` = surligné (sauge), `{{…}}` = surligné or (l'accès à vie),
    /// `{life}` = le seuil du barème (`lifetimeAt`, ⛔ jamais en dur).
    /// 🔴 ⛔ Jamais « gratuit » pour le mois offert. Arabe : au PLURIEL (un
    /// statut parle à tout le monde, le singulier imposerait un genre).
    public struct StatusImage {
      public let language: String
      public let paragraphs: [String]
      public let sticker: String
      public let cardLabel: String
      public let cardTab: String
      public let cardOmni: String
      public let cardGift: String
      public let tag: String
      /// « Mon code : {code} » — la ligne du message envoyé à un proche (onglet
      /// « Message »). ⚠️ Ici et pas dans la table traduite : elle suit le texte
      /// de l'image, donc SA langue (fr, en, ar) — un message ne mélange pas deux
      /// langues.
      public let codeLine: String

      public var isRTL: Bool { language == "ar" }

      public func codeLine(code: String) -> String {
        BrowtherReferral.fill(codeLine, ["code": code])
      }

      /// Les textes dans la langue servie à l'écran (fr, en ou ar ; sinon l'anglais).
      public static func current(lifetimeAt: Int) -> StatusImage {
        let base = String(BrowtherReferral.language.split(separator: "-").first ?? "en")
        return texts(language: base, lifetimeAt: lifetimeAt)
      }

      public static func texts(language: String, lifetimeAt: Int) -> StatusImage {
        let life = "\(lifetimeAt)"
        switch language {
        case "fr":
          return StatusImage(
            language: "fr",
            paragraphs: [
              "Si toi aussi tu cherches à naviguer sur [[internet sans musique ni images haram]], essaie ce navigateur : il supprime toute musique et floute les hommes et/ou les femmes. Dispo sur mobile et PC.",
              "Avec mon code, tu as [[un mois de fonctionnalités bonus]].",
              "Et si \(life) personnes l'installent avec ton code, tu as tout de {{débloqué à vie}} !",
            ],
            sticker: "Clique sur le lien en dessous 👇",
            cardLabel: "Mon code",
            cardTab: "Parrainage",
            cardOmni: "Musique coupée · images floutées",
            cardGift: "1\u{00A0}mois de bonus",
            tag: "Un projet",
            codeLine: "Mon code : {code}"
          )
        case "ar":
          return StatusImage(
            language: "ar",
            paragraphs: [
              "إذا كنتم تبحثون أنتم أيضًا عن تصفّح [[الإنترنت بلا موسيقى ولا صور محرّمة]]، جرّبوا هذا المتصفّح: يحذف كل الموسيقى ويموّه صور الرجال و/أو النساء. متوفّر على الجوال والكمبيوتر.",
              "برمزي، تحصلون على [[شهر من الميزات الإضافية]].",
              "وإذا ثبّته \(life) أشخاص برمزكم، تُفتح لكم {{كل الميزات مدى الحياة}}!",
            ],
            sticker: "اضغطوا على الرابط في الأسفل 👇",
            cardLabel: "رمزي",
            cardTab: "التزكية",
            cardOmni: "الموسيقى مقطوعة · الصور مموّهة",
            cardGift: "شهر من الميزات",
            tag: "مشروع من",
            codeLine: "رمزي: {code}"
          )
        default:
          return StatusImage(
            language: "en",
            paragraphs: [
              "If you're also looking to browse [[the internet without music or haram images]], try this browser: it removes all music and blurs men and/or women. Available on mobile and PC.",
              "With my code, you get [[a month of bonus features]].",
              "And if \(life) people install it with your code, you get {{everything unlocked for life}}!",
            ],
            sticker: "Tap the link below 👇",
            cardLabel: "My code",
            cardTab: "Referrals",
            cardOmni: "Music off · images blurred",
            cardGift: "1\u{00A0}month of bonus",
            tag: "A project by",
            codeLine: "My code: {code}"
          )
        }
      }
    }
  }
}
