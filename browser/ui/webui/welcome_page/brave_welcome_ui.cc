/* Copyright (c) 2019 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

#include "brave/browser/ui/webui/welcome_page/brave_welcome_ui.h"

#include <algorithm>
#include <memory>
#include <string>

#include "base/check.h"
#include "base/feature_list.h"
#include "base/memory/raw_ptr.h"
#include "base/task/single_thread_task_runner.h"
#include "brave/browser/brave_browser_features.h"
#include "brave/browser/ui/webui/brave_webui_source.h"
#include "brave/browser/ui/webui/settings/brave_import_bulk_data_handler.h"
#include "brave/browser/ui/webui/settings/brave_search_engines_handler.h"
#include "brave/browser/ui/webui/welcome_page/brave_welcome_ui_prefs.h"
#include "brave/browser/ui/webui/welcome_page/welcome_dom_handler.h"
#include "brave/components/brave_welcome/common/features.h"
#include "brave/components/brave_welcome/resources/grit/brave_welcome_generated_map.h"
#include "brave/components/constants/browther_early_access.h"
#include "brave/components/constants/pref_names.h"
#include "brave/components/constants/webui_url_constants.h"
#include "brave/components/p3a/pref_names.h"
#include "brave/components/web_discovery/buildflags/buildflags.h"
#include "brave/grit/brave_generated_resources.h"
#include "chrome/browser/browser_process.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/regional_capabilities/regional_capabilities_service_factory.h"
#include "chrome/browser/ui/browser.h"
#include "chrome/browser/ui/browser_finder.h"
#include "chrome/browser/ui/webui/settings/privacy_sandbox_handler.h"
#include "chrome/browser/ui/webui/settings/settings_default_browser_handler.h"
#include "chrome/browser/ui/webui/theme_source.h"
#include "chrome/common/pref_names.h"
#include "chrome/grit/branded_strings.h"
#include "chrome/grit/generated_resources.h"
#include "components/country_codes/country_codes.h"
#include "components/grit/brave_components_resources.h"
#include "components/grit/brave_components_strings.h"
#include "components/metrics/metrics_pref_names.h"
#include "components/prefs/pref_service.h"
#include "components/regional_capabilities/regional_capabilities_prefs.h"
#include "content/public/browser/gpu_data_manager.h"
#include "content/public/browser/page_navigator.h"
#include "content/public/browser/url_data_source.h"
#include "content/public/browser/web_ui_data_source.h"
#include "content/public/browser/web_ui_message_handler.h"
#include "ui/base/l10n/l10n_util.h"
#include "brave/browser/browther/referral/browther_referral_launch.h"
#include "brave/browser/ui/webui/browther_referral/browther_referral_ui.h"

namespace {

constexpr webui::LocalizedString kLocalizedStrings[] = {
    {"headerText", IDS_WELCOME_HEADER},
    {"braveWelcomeTitle", IDS_BRAVE_WELCOME_TITLE},
    {"braveWelcomeDesc", IDS_BRAVE_WELCOME_DESC},
    {"braveWelcomeImportSettingsTitle",
     IDS_BRAVE_WELCOME_IMPORT_SETTINGS_TITLE},
    {"braveWelcomeImportSettingsDesc", IDS_BRAVE_WELCOME_IMPORT_SETTINGS_DESC},
    {"braveWelcomeSelectProfileLabel", IDS_BRAVE_WELCOME_SELECT_PROFILE_LABEL},
    {"braveWelcomeSelectProfileDesc", IDS_BRAVE_WELCOME_SELECT_PROFILE_DESC},
    {"braveWelcomeImportButtonLabel", IDS_BRAVE_WELCOME_IMPORT_BUTTON_LABEL},
    {"braveWelcomeImportProfilesButtonLabel",
     IDS_BRAVE_WELCOME_IMPORT_PROFILES_BUTTON_LABEL},
    {"braveWelcomeSkipButtonLabel", IDS_BRAVE_WELCOME_SKIP_BUTTON_LABEL},
    {"braveWelcomeBackButtonLabel", IDS_BRAVE_WELCOME_BACK_BUTTON_LABEL},
    {"braveWelcomeNextButtonLabel", IDS_BRAVE_WELCOME_NEXT_BUTTON_LABEL},
    {"braveWelcomeFinishButtonLabel", IDS_BRAVE_WELCOME_FINISH_BUTTON_LABEL},
    {"braveWelcomeSetDefaultButtonLabel",
     IDS_BRAVE_WELCOME_SET_DEFAULT_BUTTON_LABEL},
    {"braveWelcomeSelectAllButtonLabel",
     IDS_BRAVE_WELCOME_SELECT_ALL_BUTTON_LABEL},
    {"braveWelcomeHelpImproveBraveTitle",
     IDS_BRAVE_WELCOME_HELP_IMPROVE_BRAVE_TITLE},
    {"braveWelcomeStabilityDiagnosticsTitle",
     IDS_BRAVE_WELCOME_STABILITY_DIAGNOSTICS_TITLE},
    {"braveWelcomeSendReportsLabel", IDS_BRAVE_WELCOME_SEND_REPORTS_LABEL},
    {"braveWelcomeSendInsightsLabel", IDS_BRAVE_WELCOME_SEND_INSIGHTS_LABEL},
    {"braveWelcomeSetupCompleteLabel", IDS_BRAVE_WELCOME_SETUP_COMPLETE_LABEL},
    {"braveWelcomeChangeSettingsNote", IDS_BRAVE_WELCOME_CHANGE_SETTINGS_NOTE},
    {"braveWelcomePrivacyPolicyNote", IDS_BRAVE_WELCOME_PRIVACY_POLICY_NOTE},
    {"braveWelcomeSelectThemeLabel", IDS_BRAVE_WELCOME_SELECT_THEME_LABEL},
    {"braveWelcomeSelectThemeNote", IDS_BRAVE_WELCOME_SELECT_THEME_NOTE},
    {"braveWelcomeSelectThemeSystemLabel",
     IDS_BRAVE_WELCOME_SELECT_THEME_SYSTEM_LABEL},
    {"braveWelcomeSelectThemeLightLabel",
     IDS_BRAVE_WELCOME_SELECT_THEME_LIGHT_LABEL},
    {"braveWelcomeSelectThemeDarkLabel",
     IDS_BRAVE_WELCOME_SELECT_THEME_DARK_LABEL},
    // Browther : dernière étape, « suivre les canaux dev&din ».
    {"braveWelcomeFollowChannelsTitle",
     IDS_BRAVE_WELCOME_FOLLOW_CHANNELS_TITLE},
    {"braveWelcomeFollowChannelsHook", IDS_BRAVE_WELCOME_FOLLOW_CHANNELS_HOOK},
    {"braveWelcomeFollowChannelsWhatsApp",
     IDS_BRAVE_WELCOME_FOLLOW_CHANNELS_WHATSAPP},
    {"braveWelcomeFollowChannelsTelegram",
     IDS_BRAVE_WELCOME_FOLLOW_CHANNELS_TELEGRAM},
    {"braveWelcomeFollowChannelsScanHint",
     IDS_BRAVE_WELCOME_FOLLOW_CHANNELS_SCAN_HINT},
    {"braveWelcomeFollowChannelsOpenHere",
     IDS_BRAVE_WELCOME_FOLLOW_CHANNELS_OPEN_HERE},
    {"braveWelcomeFollowChannelsSameContent",
     IDS_BRAVE_WELCOME_FOLLOW_CHANNELS_SAME_CONTENT},
    // Browther : l'introduction (six écrans), cf. ONBOARDING-SPEC.md.
    {"browtherIntroWelcomeTitle", IDS_BROWTHER_INTRO_WELCOME_TITLE},
    {"browtherIntroVerseTranslation", IDS_BROWTHER_INTRO_VERSE_TRANSLATION},
    {"browtherIntroVerseReference", IDS_BROWTHER_INTRO_VERSE_REFERENCE},
    {"browtherIntroProtectionAds", IDS_BROWTHER_INTRO_PROTECTION_ADS},
    {"browtherIntroProtectionMusic", IDS_BROWTHER_INTRO_PROTECTION_MUSIC},
    {"browtherIntroProtectionImages", IDS_BROWTHER_INTRO_PROTECTION_IMAGES},
    {"browtherIntroStatusActive", IDS_BROWTHER_INTRO_STATUS_ACTIVE},
    {"browtherIntroStatusActiveDetail",
     IDS_BROWTHER_INTRO_STATUS_ACTIVE_DETAIL},
    {"browtherIntroStatusSoon", IDS_BROWTHER_INTRO_STATUS_SOON},
    {"browtherIntroStartButton", IDS_BROWTHER_INTRO_START_BUTTON},
    {"browtherIntroSignatureLabel", IDS_BROWTHER_INTRO_SIGNATURE_LABEL},
    {"browtherIntroAdsTitle", IDS_BROWTHER_INTRO_ADS_TITLE},
    {"browtherIntroAdsSubtitle", IDS_BROWTHER_INTRO_ADS_SUBTITLE},
    {"browtherIntroAdsPill", IDS_BROWTHER_INTRO_ADS_PILL},
    {"browtherIntroAdsSwitchOff", IDS_BROWTHER_INTRO_ADS_SWITCH_OFF},
    {"browtherIntroAdsSwitchOn", IDS_BROWTHER_INTRO_ADS_SWITCH_ON},
    {"browtherIntroShieldsName", IDS_BROWTHER_INTRO_SHIELDS_NAME},
    {"browtherIntroTurnOnToContinue", IDS_BROWTHER_INTRO_TURN_ON_TO_CONTINUE},
    {"browtherIntroContinue", IDS_BROWTHER_INTRO_CONTINUE},
    {"browtherIntroDemoSiteName", IDS_BROWTHER_INTRO_DEMO_SITE_NAME},
    {"browtherIntroDemoArticleTitle", IDS_BROWTHER_INTRO_DEMO_ARTICLE_TITLE},
    {"browtherIntroDemoArticleBody", IDS_BROWTHER_INTRO_DEMO_ARTICLE_BODY},
    {"browtherIntroDemoAdSound", IDS_BROWTHER_INTRO_DEMO_AD_SOUND},
    {"browtherIntroDemoAdSkip", IDS_BROWTHER_INTRO_DEMO_AD_SKIP},
    {"browtherIntroDemoAdSkipNow", IDS_BROWTHER_INTRO_DEMO_AD_SKIP_NOW},
    {"browtherIntroDemoAdLabel", IDS_BROWTHER_INTRO_DEMO_AD_LABEL},
    {"browtherIntroDemoAdSponsored", IDS_BROWTHER_INTRO_DEMO_AD_SPONSORED},
    {"browtherIntroDemoBlockedCount", IDS_BROWTHER_INTRO_DEMO_BLOCKED_COUNT},
    {"browtherIntroStampHalal", IDS_BROWTHER_INTRO_STAMP_HALAL},
    {"browtherIntroStampHaram", IDS_BROWTHER_INTRO_STAMP_HARAM},
    {"browtherIntroTileImage", IDS_BROWTHER_INTRO_TILE_IMAGE},
    {"browtherIntroTileVideo", IDS_BROWTHER_INTRO_TILE_VIDEO},
    {"browtherIntroBlurTitle", IDS_BROWTHER_INTRO_BLUR_TITLE},
    {"browtherIntroBlurSubtitle", IDS_BROWTHER_INTRO_BLUR_SUBTITLE},
    {"browtherIntroBlurWomen", IDS_BROWTHER_INTRO_BLUR_WOMEN},
    {"browtherIntroBlurMen", IDS_BROWTHER_INTRO_BLUR_MEN},
    {"browtherIntroBlurBoth", IDS_BROWTHER_INTRO_BLUR_BOTH},
    {"browtherIntroBlurCurtain", IDS_BROWTHER_INTRO_BLUR_CURTAIN},
    {"browtherIntroBlurSwitchOff", IDS_BROWTHER_INTRO_BLUR_SWITCH_OFF},
    {"browtherIntroBlurSwitchOn", IDS_BROWTHER_INTRO_BLUR_SWITCH_ON},
    {"browtherIntroMusicTitle", IDS_BROWTHER_INTRO_MUSIC_TITLE},
    {"browtherIntroMusicSubtitle", IDS_BROWTHER_INTRO_MUSIC_SUBTITLE},
    {"browtherIntroMusicCompat", IDS_BROWTHER_INTRO_MUSIC_COMPAT},
    {"browtherIntroMusicLaneVoice", IDS_BROWTHER_INTRO_MUSIC_LANE_VOICE},
    {"browtherIntroMusicLaneMusic", IDS_BROWTHER_INTRO_MUSIC_LANE_MUSIC},
    {"browtherIntroMusicRemoved", IDS_BROWTHER_INTRO_MUSIC_REMOVED},
    {"browtherIntroMusicSwitchOff", IDS_BROWTHER_INTRO_MUSIC_SWITCH_OFF},
    {"browtherIntroMusicSwitchOn", IDS_BROWTHER_INTRO_MUSIC_SWITCH_ON},
    {"browtherIntroMusicListen", IDS_BROWTHER_INTRO_MUSIC_LISTEN},
    {"browtherIntroMusicPause", IDS_BROWTHER_INTRO_MUSIC_PAUSE},
    {"browtherIntroVolumeMuted", IDS_BROWTHER_INTRO_VOLUME_MUTED},
    {"browtherIntroVolumeLabel", IDS_BROWTHER_INTRO_VOLUME_LABEL},
    {"browtherIntroDefaultTitle", IDS_BROWTHER_INTRO_DEFAULT_TITLE},
    {"browtherIntroDefaultSubtitle", IDS_BROWTHER_INTRO_DEFAULT_SUBTITLE},
    {"browtherIntroLaterButton", IDS_BROWTHER_INTRO_LATER_BUTTON},
    {"browtherIntroDemoMessagingApp", IDS_BROWTHER_INTRO_DEMO_MESSAGING_APP},
    {"browtherIntroDemoContactName", IDS_BROWTHER_INTRO_DEMO_CONTACT_NAME},
    {"browtherIntroDemoMessageIncoming",
     IDS_BROWTHER_INTRO_DEMO_MESSAGE_INCOMING},
    {"browtherIntroDemoOpenedIn", IDS_BROWTHER_INTRO_DEMO_OPENED_IN},
    {"browtherIntroDemoStatAds", IDS_BROWTHER_INTRO_DEMO_STAT_ADS},
    {"browtherIntroDemoStatMusic", IDS_BROWTHER_INTRO_DEMO_STAT_MUSIC},
    {"browtherIntroDemoStatImages", IDS_BROWTHER_INTRO_DEMO_STAT_IMAGES},
    {"browtherIntroSoonTitle", IDS_BROWTHER_INTRO_SOON_TITLE},
    {"browtherIntroSoonBlurBody", IDS_BROWTHER_INTRO_SOON_BLUR_BODY},
    {"browtherIntroSoonMusicBody", IDS_BROWTHER_INTRO_SOON_MUSIC_BODY},
    {"browtherIntroSoonNote", IDS_BROWTHER_INTRO_SOON_NOTE},
    {"browtherIntroSoonPrimaryButton", IDS_BROWTHER_INTRO_SOON_PRIMARY_BUTTON},
    {"browtherIntroSoonClose", IDS_BROWTHER_INTRO_SOON_CLOSE},
    {"browtherIntroChannelsSoonTitle", IDS_BROWTHER_INTRO_CHANNELS_SOON_TITLE},
    {"browtherIntroChannelsSoonDescription",
     IDS_BROWTHER_INTRO_CHANNELS_SOON_DESCRIPTION},
    {"browtherIntroChannelsSameContent",
     IDS_BROWTHER_INTRO_CHANNELS_SAME_CONTENT},
    {"browtherIntroStartBrowsing", IDS_BROWTHER_INTRO_START_BROWSING},
    {"browtherIntroNotifBlur", IDS_BROWTHER_INTRO_NOTIF_BLUR},
    {"browtherIntroNotifMusic", IDS_BROWTHER_INTRO_NOTIF_MUSIC},
    {"browtherIntroNotifNewProject", IDS_BROWTHER_INTRO_NOTIF_NEW_PROJECT},
    {"browtherIntroChannelsScanHere", IDS_BROWTHER_INTRO_CHANNELS_SCAN_HERE},
    {"browtherIntroImportTitle", IDS_BROWTHER_INTRO_IMPORT_TITLE},
    {"browtherIntroImportSubtitle", IDS_BROWTHER_INTRO_IMPORT_SUBTITLE},
    {"browtherIntroImportInProgress", IDS_BROWTHER_INTRO_IMPORT_IN_PROGRESS},
    {"browtherIntroImportDone", IDS_BROWTHER_INTRO_IMPORT_DONE},
    {"browtherIntroImportFailed", IDS_BROWTHER_INTRO_IMPORT_FAILED},
    {"browtherIntroImportKeychainNote",
     IDS_BROWTHER_INTRO_IMPORT_KEYCHAIN_NOTE},
    // Les cases d'import des Réglages : déjà traduites dans toutes les langues.
    {"browtherIntroImportFavorites", IDS_SETTINGS_IMPORT_FAVORITES_CHECKBOX},
    {"browtherIntroImportPasswords", IDS_SETTINGS_IMPORT_PASSWORDS_CHECKBOX},
    {"browtherIntroImportHistory", IDS_SETTINGS_IMPORT_HISTORY_CHECKBOX},
    {"browtherIntroImportExtensions", IDS_SETTINGS_IMPORT_EXTENSIONS_CHECKBOX},
    {"browtherIntroImportPayments", IDS_SETTINGS_IMPORT_PAYMENTS_CHECKBOX},
    {"browtherIntroImportAutofill",
     IDS_SETTINGS_IMPORT_AUTOFILL_FORM_DATA_CHECKBOX},
    {"browtherIntroImportSearch", IDS_SETTINGS_IMPORT_SEARCH_ENGINES_CHECKBOX}};

void OpenJapanWelcomePage(Profile* profile) {
  CHECK(profile);
  Browser* browser = chrome::FindBrowserWithProfile(profile);
  if (browser) {
    content::OpenURLParams open_params(
        GURL("https://brave.com/ja/desktop-ntp-tutorial"), content::Referrer(),
        WindowOpenDisposition::NEW_BACKGROUND_TAB,
        ui::PAGE_TRANSITION_AUTO_TOPLEVEL, false);
    browser->OpenURL(open_params, /*navigation_handle_callback=*/{});
  }
}

}  // namespace

BraveWelcomeUI::BraveWelcomeUI(content::WebUI* web_ui, std::string_view name)
    : WebUIController(web_ui) {
  content::WebUIDataSource* source = CreateAndAddWebUIDataSource(
      web_ui, name, kBraveWelcomeGenerated, IDR_BRAVE_WELCOME_HTML,
      /*disable_trusted_types_csp=*/true);

  // Lottie animations tick on a worker thread and requires the document CSP to
  // be set to "worker-src blob: 'self';".
  source->OverrideContentSecurityPolicy(
      network::mojom::CSPDirectiveName::WorkerSrc,
      "worker-src blob: chrome://resources 'self';");

  web_ui->AddMessageHandler(
      std::make_unique<WelcomeDOMHandler>(Profile::FromWebUI(web_ui)));
  web_ui->AddMessageHandler(
      std::make_unique<settings::BraveImportBulkDataHandler>());
  web_ui->AddMessageHandler(
      std::make_unique<settings::DefaultBrowserHandler>());  // set default
                                                             // browser

  Profile* profile = Profile::FromWebUI(web_ui);
  CHECK(profile);
  // added to allow front end to read/modify default search engine
  web_ui->AddMessageHandler(std::make_unique<
                            settings::BraveSearchEnginesHandler>(
      profile,
      regional_capabilities::RegionalCapabilitiesServiceFactory::GetForProfile(
          profile)));

  // Open additional page in Japanese region
  country_codes::CountryId country_id =
      country_codes::CountryId::Deserialize(profile->GetPrefs()->GetInteger(
          regional_capabilities::prefs::kCountryIDAtInstall));
  const bool is_jpn = country_id == country_codes::CountryId("JP");
  if (!profile->GetPrefs()->GetBoolean(
          brave::welcome_ui::prefs::kHasSeenBraveWelcomePage)) {
    if (is_jpn) {
      base::SingleThreadTaskRunner::GetCurrentDefault()->PostDelayedTask(
          FROM_HERE, base::BindOnce(&OpenJapanWelcomePage, profile),
          base::Seconds(3));
    }
  }

  for (const auto& str : kLocalizedStrings) {
    std::u16string l10n_str = l10n_util::GetStringUTF16(str.id);
    source->AddString(str.name, l10n_str);
  }

  // Variables considered when determining which onboarding cards to show
  source->AddString("countryString", country_id.CountryCode());
  source->AddBoolean(
      "showRewardsCard",
      base::FeatureList::IsEnabled(brave_welcome::features::kShowRewardsCard));

  // Browther : pendant l'accès anticipé, « Continuer » sur Basarunaa et
  // Sawtunaa ouvre la feuille « Ça arrive bientôt » au lieu d'allumer le
  // moteur. Même interrupteur que les badges de la barre d'outils.
  source->AddBoolean("browtherEarlyAccess", kBrowtherEarlyAccess);

  // Browther : l'étape « Un proche t'a parlé de Browther ? » (écran O du
  // parrainage, `PARRAINAGE.md` § 12.24 : dans un onboarding, le code SEUL).
  // Son contenu vient de l'app web du parrainage, servie sous
  // `browther-referral/`.
  source->AddBoolean("browtherReferralEnabled", browther_referral::IsEnabled());
  if (browther_referral::IsEnabled()) {
    BrowtherReferralUI::AddToHostPage(web_ui, source, /*is_new_tab=*/false);
  }

  source->AddBoolean(
      "hardwareAccelerationEnabledAtStartup",
      content::GpuDataManager::GetInstance()->HardwareAccelerationEnabled());

  // Add managed state information for welcome flow logic
  PrefService* local_state = g_browser_process->local_state();
  source->AddBoolean(
      "isWebDiscoveryEnabledManaged",
#if BUILDFLAG(ENABLE_EXTENSIONS) || BUILDFLAG(ENABLE_WEB_DISCOVERY_NATIVE)
      profile->GetPrefs()->IsManagedPreference(kWebDiscoveryEnabled));
#else
      false);
#endif
  source->AddBoolean("isMetricsReportingEnabledManaged",
                     local_state->IsManagedPreference(
                         metrics::prefs::kMetricsReportingEnabled));
  source->AddBoolean("isP3AEnabledManaged",
                     local_state->IsManagedPreference(p3a::kP3AEnabled));

  profile->GetPrefs()->SetBoolean(
      brave::welcome_ui::prefs::kHasSeenBraveWelcomePage, true);

  AddBackgroundColorToSource(source, web_ui->GetWebContents());

  content::URLDataSource::Add(profile,
                              std::make_unique<ThemeSource>(profile, true));
}

BraveWelcomeUI::~BraveWelcomeUI() = default;
