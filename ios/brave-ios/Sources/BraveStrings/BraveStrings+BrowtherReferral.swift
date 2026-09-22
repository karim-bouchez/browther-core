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

    /// La catégorie de pluriel CLDR d'un nombre, pour la langue servie.
    static func category(_ count: Int) -> String {
      let language = Self.language
      if language.hasPrefix("ar") {
        let mod100 = count % 100
        switch count {
        case 0: return "zero"
        case 1: return "one"
        case 2: return "two"
        default:
          if (3...10).contains(mod100) { return "few" }
          if (11...99).contains(mod100) { return "many" }
          return "other"
        }
      }
      if language.hasPrefix("fr") {
        return count == 0 || count == 1 ? "one" : "other"
      }
      return count == 1 ? "one" : "other"
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
    public static var gaugeLifeReached: String { t("gauge.lifeReached", "You made it: Browther is 100% unlocked.") }
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
    public static var announceInviteSub: String { t("announce.inviteSub", "And aim for free lifetime access") }
    public static var announceLater: String { t("announce.later", "Remind me later") }

    // MARK: 1 — J−10 / J−3

    public static func endingTitle(_ days: Int) -> String {
      plural(
        "ending.title",
        days,
        one: "Tomorrow, some additional features will pause… but you can keep them for life, for free!",
        other: "In {count} days, some additional features will pause… but you can keep them for life, for free!"
      )
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
    public static func reminderMonthsNext(_ left: Int) -> String {
      plural(
        "reminder.monthsNext",
        left,
        one: "Every confirmed invitation adds one more. {count} more and you reach the next tier.",
        other: "Every confirmed invitation adds one more. {count} more and you reach the next tier."
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
          "I'm inviting you to discover Browther: the browser that mutes music and blurs haram images.\nWith my code {code}, you get two months of additional features."
        ),
        ["code": code]
      )
    }

    // MARK: 8 — la seule notification

    public static var noticeTitle: String { t("notice.title", "Invitation confirmed!") }
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
    public static var refereeInviteToo: String { t("referee.inviteToo", "Your turn to invite") }
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
  }
}
