// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Strings

// MARK: - Browther : introduction (premier lancement)
//
// ⚠️ Ces textes sont NEUFS : ils n'ont pas d'équivalent desktop, donc pas de
// traduction à récupérer par hash grit. Anglais ici, français dans
// `Resources/fr.lproj/Browther.strings` ; les 37 autres langues attendent que
// le texte soit validé à l'écran — un `.strings` généré maintenant serait à
// refaire au premier mot changé (cf. `private/docs/ONBOARDING.md`).
//
// ⛔ Ne pas nommer de service tiers (YouTube…) : c'est ce qui fait refuser une
// mise à jour. Ce qui fait reconnaître la scène, c'est la pub avant la vidéo et
// son « Passer dans 5 s ».
extension Strings {
  public enum BrowtherIntro {
    // MARK: Accueil

    public static let welcomeTitle = NSLocalizedString(
      "introWelcomeTitle",
      tableName: "Browther",
      bundle: .module,
      value: "Protect what you see and what you hear.",
      comment: "Title of the first introduction screen"
    )
    public static let verseTranslation = NSLocalizedString(
      "introVerseTranslation",
      tableName: "Browther",
      bundle: .module,
      value:
        "\u{201C}Hearing, sight and heart \u{2014} of all these one will be questioned.\u{201D}",
      comment: "Translation of Quran 17:36, shown under the Arabic verse"
    )
    public static let verseReference = NSLocalizedString(
      "introVerseReference",
      tableName: "Browther",
      bundle: .module,
      value: "Quran \u{00B7} Al-Isr\u{0101}\u{02BE}, 17:36",
      comment: "Source of the verse"
    )
    public static let protectionAds = NSLocalizedString(
      "introProtectionAds",
      tableName: "Browther",
      bundle: .module,
      value: "Ads",
      comment: "One of the three protections listed on the welcome screen"
    )
    public static let protectionMusic = NSLocalizedString(
      "introProtectionMusic",
      tableName: "Browther",
      bundle: .module,
      value: "Music",
      comment: "One of the three protections listed on the welcome screen"
    )
    public static let protectionImages = NSLocalizedString(
      "introProtectionImages",
      tableName: "Browther",
      bundle: .module,
      value: "Images",
      comment: "One of the three protections listed on the welcome screen"
    )
    public static let statusActive = NSLocalizedString(
      "introStatusActive",
      tableName: "Browther",
      bundle: .module,
      value: "Active",
      comment: "Status of a protection that already works"
    )
    public static let statusActiveDetail = NSLocalizedString(
      "introStatusActiveDetail",
      tableName: "Browther",
      bundle: .module,
      value: "right away",
      comment: "Second line under 'Active', balancing the 'in shaa Allah' line"
    )
    public static let statusSoon = NSLocalizedString(
      "introStatusSoon",
      tableName: "Browther",
      bundle: .module,
      value: "Soon",
      comment: "Status of a protection still in development"
    )
    public static let startButton = NSLocalizedString(
      "introStartButton",
      tableName: "Browther",
      bundle: .module,
      value: "Get started",
      comment: "Button of the first introduction screen"
    )

    // MARK: Pubs

    public static let adsTitle = NSLocalizedString(
      "introAdsTitle",
      tableName: "Browther",
      bundle: .module,
      value: "Ads don\u{2019}t only sell products.",
      comment: "Title of the ads screen"
    )
    public static let adsSubtitle = NSLocalizedString(
      "introAdsSubtitle",
      tableName: "Browther",
      bundle: .module,
      value:
        "They force music and images you never chose on you. Browther blocks them from the start, including the ones that play before videos.",
      comment: "Subtitle of the ads screen"
    )
    public static let adsPill = NSLocalizedString(
      "introAdsPill",
      tableName: "Browther",
      bundle: .module,
      value: "Already on, every site",
      comment: "Status pill on the ads screen"
    )
    public static let adsSwitchOff = NSLocalizedString(
      "introAdsSwitchOff",
      tableName: "Browther",
      bundle: .module,
      value: "Off \u{00B7} the ads get through",
      comment: "State of the demo switch, ads screen"
    )
    public static let adsSwitchOn = NSLocalizedString(
      "introAdsSwitchOn",
      tableName: "Browther",
      bundle: .module,
      value: "3 items blocked on this page",
      comment: "State of the demo switch once Browther is on"
    )

    // MARK: Page de démonstration

    public static let demoSiteName = NSLocalizedString(
      "introDemoSiteName",
      tableName: "Browther",
      bundle: .module,
      value: "The Recipe Notebook",
      comment: "Name of the made-up website shown in the demo"
    )
    public static let demoArticleTitle = NSLocalizedString(
      "introDemoArticleTitle",
      tableName: "Browther",
      bundle: .module,
      value: "Msemen, step by step",
      comment: "Headline of the made-up article shown in the demo"
    )
    public static let demoArticleBody = NSLocalizedString(
      "introDemoArticleBody",
      tableName: "Browther",
      bundle: .module,
      value:
        "Mix the fine semolina, the flour and a pinch of salt, then add the warm water little by little.",
      comment: "First lines of the made-up article"
    )
    public static let demoAdCountdown = NSLocalizedString(
      "introDemoAdCountdown",
      tableName: "Browther",
      bundle: .module,
      value: "Ad \u{00B7} 0:15",
      comment: "Label on the ad that plays before the video"
    )
    public static let demoAdSound = NSLocalizedString(
      "introDemoAdSound",
      tableName: "Browther",
      bundle: .module,
      value: "Sound on",
      comment: "Label saying the ad plays with sound"
    )
    public static let demoAdSkip = NSLocalizedString(
      "introDemoAdSkip",
      tableName: "Browther",
      bundle: .module,
      value: "Skip in 5s",
      comment: "Skip button of the ad that plays before the video"
    )
    public static let demoAdLabel = NSLocalizedString(
      "introDemoAdLabel",
      tableName: "Browther",
      bundle: .module,
      value: "Ad",
      comment: "Label of the banner ad in the demo page"
    )
    public static let demoAdSponsored = NSLocalizedString(
      "introDemoAdSponsored",
      tableName: "Browther",
      bundle: .module,
      value: "Sponsored content",
      comment: "Second line of the banner ad"
    )
    public static let demoBlockedCount = NSLocalizedString(
      "introDemoBlockedCount",
      tableName: "Browther",
      bundle: .module,
      value: "3 blocked",
      comment: "Counter shown once Browther blocked the ads of the demo page"
    )
    public static let blurredTag = NSLocalizedString(
      "introBlurredTag",
      tableName: "Browther",
      bundle: .module,
      value: "Blurred",
      comment: "Tag on a blurred person in the preview"
    )
    public static let stampHalal = NSLocalizedString(
      "introStampHalal",
      tableName: "Browther",
      bundle: .module,
      value: "HALAL",
      comment: "Word on the halal stamp"
    )
    public static let stampHaram = NSLocalizedString(
      "introStampHaram",
      tableName: "Browther",
      bundle: .module,
      value: "HARAM",
      comment: "Word on the haram stamp"
    )

    // MARK: Floutage

    public static let blurTitle = NSLocalizedString(
      "introBlurTitle",
      tableName: "Browther",
      bundle: .module,
      value: "Choose who gets blurred.",
      comment: "Title of the blurring screen"
    )
    public static let blurSubtitle = NSLocalizedString(
      "introBlurSubtitle",
      tableName: "Browther",
      bundle: .module,
      value: "On images and videos, on every site, before they even appear.",
      comment: "Subtitle of the blurring screen"
    )
    public static let blurWomen = NSLocalizedString(
      "introBlurWomen",
      tableName: "Browther",
      bundle: .module,
      value: "Women",
      comment: "Blurring choice"
    )
    public static let blurMen = NSLocalizedString(
      "introBlurMen",
      tableName: "Browther",
      bundle: .module,
      value: "Men",
      comment: "Blurring choice"
    )
    public static let blurBoth = NSLocalizedString(
      "introBlurBoth",
      tableName: "Browther",
      bundle: .module,
      value: "Both",
      comment: "Blurring choice"
    )
    public static let activateBlur = NSLocalizedString(
      "introActivateBlur",
      tableName: "Browther",
      bundle: .module,
      value: "Turn on blurring",
      comment: "Main button of the blurring screen"
    )
    public static let laterButton = NSLocalizedString(
      "introLaterButton",
      tableName: "Browther",
      bundle: .module,
      value: "Later",
      comment: "Secondary button that moves on without turning the feature on"
    )

    // MARK: Musique

    public static let musicTitle = NSLocalizedString(
      "introMusicTitle",
      tableName: "Browther",
      bundle: .module,
      value: "Keep the voice, cut the music.",
      comment: "Title of the music screen"
    )
    public static let musicSubtitle = NSLocalizedString(
      "introMusicSubtitle",
      tableName: "Browther",
      bundle: .module,
      value:
        "While you watch a video, Browther removes the music and leaves the voice untouched.",
      comment: "Subtitle of the music screen"
    )
    public static let musicCompat = NSLocalizedString(
      "introMusicCompat",
      tableName: "Browther",
      bundle: .module,
      value: "On supported video sites",
      comment: "Where music removal works; the list lives on the website"
    )
    public static let musicLaneVoice = NSLocalizedString(
      "introMusicLaneVoice",
      tableName: "Browther",
      bundle: .module,
      value: "Voice",
      comment: "Name of the voice track in the demo player"
    )
    public static let musicLaneMusic = NSLocalizedString(
      "introMusicLaneMusic",
      tableName: "Browther",
      bundle: .module,
      value: "Music",
      comment: "Name of the music track in the demo player"
    )
    public static let musicRemoved = NSLocalizedString(
      "introMusicRemoved",
      tableName: "Browther",
      bundle: .module,
      value: "removed",
      comment: "Shown next to the flattened music track"
    )
    public static let musicSwitchOff = NSLocalizedString(
      "introMusicSwitchOff",
      tableName: "Browther",
      bundle: .module,
      value: "Off \u{00B7} the music plays",
      comment: "State of the demo switch, music screen"
    )
    public static let musicSwitchOn = NSLocalizedString(
      "introMusicSwitchOn",
      tableName: "Browther",
      bundle: .module,
      value: "Music removed, voice untouched",
      comment: "State of the demo switch once Browther is on"
    )
    public static let activateMusic = NSLocalizedString(
      "introActivateMusic",
      tableName: "Browther",
      bundle: .module,
      value: "Turn on music removal",
      comment: "Main button of the music screen"
    )

    // MARK: Navigateur par défaut

    public static let defaultTitle = NSLocalizedString(
      "introDefaultTitle",
      tableName: "Browther",
      bundle: .module,
      value: "Every link, protected.",
      comment: "Title of the default browser screen"
    )
    public static let defaultSubtitle = NSLocalizedString(
      "introDefaultSubtitle",
      tableName: "Browther",
      bundle: .module,
      value:
        "Make Browther your default browser: the links you open from your messages and your apps get its protections too.",
      comment: "Subtitle of the default browser screen"
    )

    // MARK: Feuille « ça arrive bientôt »

    public static let soonTitle = NSLocalizedString(
      "introSoonTitle",
      tableName: "Browther",
      bundle: .module,
      value: "Coming very soon,",
      comment: "Title of the sheet shown when tapping 'Turn on' during early access; the invocation is added on its own line"
    )
    public static let soonBlurBody = NSLocalizedString(
      "introSoonBlurBody",
      tableName: "Browther",
      bundle: .module,
      value:
        "Blurring is still in development \u{2014} we would rather release it once it is really good. Your choice is saved and will apply as soon as it ships. In the meantime Browther already blocks ads, and they are what forces the most unchosen images on you.",
      comment: "Body of the sheet, blurring"
    )
    public static let soonMusicBody = NSLocalizedString(
      "introSoonMusicBody",
      tableName: "Browther",
      bundle: .module,
      value:
        "Music removal is still in development \u{2014} we would rather release it once it is really good. In the meantime Browther already blocks ads, and the music they bring with them.",
      comment: "Body of the sheet, music"
    )
    public static let soonNote = NSLocalizedString(
      "introSoonNote",
      tableName: "Browther",
      bundle: .module,
      value: "We announce releases on our channels: the last step of this introduction.",
      comment: "Footnote of the sheet"
    )

    // MARK: Canaux (variante accès anticipé)

    public static let channelsSoonTitle = NSLocalizedString(
      "introChannelsSoonTitle",
      tableName: "Browther",
      bundle: .module,
      value: "Don\u{2019}t miss the release",
      comment: "Title of the channels screen while features are in development"
    )
    public static let notifBlur = NSLocalizedString(
      "introNotifBlur",
      tableName: "Browther",
      bundle: .module,
      value: "Blurring is available in Browther. Update the app to get it.",
      comment: "Example notification shown on the channels screen"
    )
    public static let notifMusic = NSLocalizedString(
      "introNotifMusic",
      tableName: "Browther",
      bundle: .module,
      value: "Music removal is coming to your iPhone.",
      comment: "Example notification shown on the channels screen"
    )
    public static let channelsSoonDescription = NSLocalizedString(
      "introChannelsSoonDescription",
      tableName: "Browther",
      bundle: .module,
      value:
        "Blurring and music removal are coming soon. We will announce them on our channels: a rare message, only when it is worth it.",
      comment: "Description of the channels screen while features are in development"
    )
  }
}
