// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/browser/ui/webui/browther_referral/browther_referral_handler.h"

#include "brave/browser/ui/webui/browther_referral/browther_referral_dialog.h"

#include <optional>
#include <utility>
#include <vector>

#include "base/functional/bind.h"
#include "base/json/json_reader.h"
#include "base/json/json_writer.h"
#include "base/memory/scoped_refptr.h"
#include "base/strings/strcat.h"
#include "base/strings/string_util.h"
#include "base/strings/utf_string_conversions.h"
#include "base/uuid.h"
#include "brave/browser/browther/referral/browther_referral_access.h"
#include "brave/browser/browther/referral/browther_referral_account.h"
#include "brave/browser/browther/referral/browther_referral_launch.h"
#include "brave/browser/browther/referral/browther_referral_net.h"
#include "brave/browser/browther/referral/browther_referral_prefs.h"
#include "brave/browser/browther/referral/browther_referral_usage.h"
#include "brave/components/browther_analytics/browther_analytics_service.h"
#include "brave/components/constants/pref_names.h"
#include "build/build_config.h"
#include "chrome/browser/browser_process.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/shell_integration.h"
#include "chrome/browser/ui/browser_navigator_params.h"
#include "chrome/browser/ui/singleton_tabs.h"
#include "components/prefs/pref_service.h"
#include "components/prefs/scoped_user_pref_update.h"
#include "components/version_info/version_info.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_ui.h"
#include "ui/base/clipboard/scoped_clipboard_writer.h"
#include "ui/base/page_transition_types.h"
#include "ui/base/window_open_disposition.h"
#include "url/gurl.h"

namespace {

using browther_referral::BrowtherReferralAccount;

constexpr char kMessage[] = "browtherReferral";
constexpr char kReplyFunction[] = "browtherReferralReply";
// Une valeur de l'état tient en quelques Ko (le statut complet en fait ~6) :
// au-delà, c'est une fuite, pas une donnée.
constexpr size_t kMaxStoreValue = 64 * 1024;

PrefService* LocalState() {
  return g_browser_process ? g_browser_process->local_state() : nullptr;
}

const char* HostName(BrowtherReferralHandler::Host host) {
  switch (host) {
    case BrowtherReferralHandler::Host::kPage:
      return "page";
    case BrowtherReferralHandler::Host::kNewTab:
      return "ntp";
    case BrowtherReferralHandler::Host::kWelcome:
      return "welcome";
    case BrowtherReferralHandler::Host::kModal:
      return "modal";
  }
  return "page";
}

const char* OsName() {
#if BUILDFLAG(IS_MAC)
  return "mac";
#elif BUILDFLAG(IS_WIN)
  return "win";
#else
  return "linux";
#endif
}

// Une clé d'état, un nom d'évènement : un alphabet fermé et court.
bool IsSafeKey(const std::string& key) {
  if (key.empty() || key.size() > 64) {
    return false;
  }
  for (char c : key) {
    if (!base::IsAsciiAlphaNumeric(c) && c != '_' && c != '.' && c != '-') {
      return false;
    }
  }
  return true;
}

std::string EnsureDeviceId(PrefService* local_state) {
  std::string id = local_state->GetString(browther_referral::prefs::kDeviceId);
  if (id.empty()) {
    id = base::Uuid::GenerateRandomV4().AsLowercaseString();
    local_state->SetString(browther_referral::prefs::kDeviceId, id);
  }
  return id;
}

base::Value Ok() {
  base::DictValue dict;
  dict.Set("ok", true);
  return base::Value(std::move(dict));
}

// Les pages qu'on ouvre depuis le flow : le paiement (Polar), la connexion
// (auth-service), le site et le lien traqué. ⛔ Rien d'autre.
bool IsAllowedExternalUrl(const GURL& url) {
  if (!url.is_valid() || !url.SchemeIs("https")) {
    return false;
  }
  const std::string_view host = url.host();
  return host == "polar.sh" || host.ends_with(".polar.sh") ||
         host == "auth.devndin.com" || host == "browther.devndin.com" ||
         host == "devndin.com" || host == "go.devndin.com";
}

}  // namespace

BrowtherReferralHandler::BrowtherReferralHandler(Host host) : host_(host) {}

BrowtherReferralHandler::~BrowtherReferralHandler() = default;

void BrowtherReferralHandler::RegisterMessages() {
  web_ui()->RegisterMessageCallback(
      kMessage, base::BindRepeating(&BrowtherReferralHandler::HandleCall,
                                    base::Unretained(this)));
}

void BrowtherReferralHandler::OnJavascriptDisallowed() {
  // Une réponse réseau qui arrive après un rechargement ne doit rien écrire
  // dans la nouvelle page.
  weak_factory_.InvalidateWeakPtrs();
}

void BrowtherReferralHandler::HandleCall(const base::ListValue& args) {
  if (args.size() < 2 || !args[0].is_string() || !args[1].is_string()) {
    return;
  }
  AllowJavascript();
  const std::string id = args[0].GetString();
  const std::string method = args[1].GetString();
  base::DictValue empty;
  const base::DictValue& payload =
      args.size() > 2 && args[2].is_dict() ? args[2].GetDict() : empty;

  // ⛔ Parrainage éteint dans ce binaire : l'app le sait par le contexte et ne
  // demande rien d'autre. Tout le reste est refusé ici aussi.
  if (method != "getContext" && !browther_referral::IsEnabled()) {
    Reply(id, false, base::Value("disabled"));
    return;
  }

  if (method == "getContext") {
    Reply(id, true, BuildContext());
  } else if (method == "storeSet") {
    Reply(id, true, StoreSet(payload));
  } else if (method == "setAccess") {
    browther_referral::SetAccessSnapshot(LocalState(), payload.Clone());
    Reply(id, true, Ok());
  } else if (method == "claimDay") {
    Reply(id, true, ClaimDay(payload));
  } else if (method == "track") {
    Reply(id, true, Track(payload));
  } else if (method == "openPage") {
    Reply(id, true, OpenPage(payload));
  } else if (method == "openUrl") {
    Reply(id, true, OpenUrl(payload));
  } else if (method == "copyText") {
    Reply(id, true, CopyText(payload));
  } else if (method == "openModal") {
    Reply(id, true, OpenModal(payload));
  } else if (method == "resizeModal") {
    browther_referral::ResizeModal(payload.FindInt("delta").value_or(0));
    Reply(id, true, Ok());
  } else if (method == "closeModal") {
    browther_referral::CloseModal();
    Reply(id, true, Ok());
  } else if (method == "enforcePause") {
    Reply(id, true, EnforcePause());
  } else if (method == "recette") {
    Reply(id, true, Recette(payload));
  } else if (method == "request") {
    Request(id, payload);
  } else if (method == "setDefaultBrowser") {
    SetDefaultBrowser(id);
  } else if (method == "checkDefaultBrowser") {
    CheckDefault(id);
  } else if (method == "accountStart") {
    BrowtherReferralAccount::Get()->StartLogin(
        base::BindOnce(&BrowtherReferralHandler::Reply,
                       weak_factory_.GetWeakPtr(), id, true));
  } else if (method == "accountPoll") {
    BrowtherReferralAccount::Get()->PollLogin(
        base::BindOnce(&BrowtherReferralHandler::Reply,
                       weak_factory_.GetWeakPtr(), id, true));
  } else if (method == "accountCancel") {
    BrowtherReferralAccount::Get()->CancelLogin();
    Reply(id, true, Ok());
  } else if (method == "accountSignOut") {
    BrowtherReferralAccount::Get()->SignOut(base::BindOnce(
        [](base::WeakPtr<BrowtherReferralHandler> self, std::string id) {
          if (self) {
            self->Reply(id, true, Ok());
          }
        },
        weak_factory_.GetWeakPtr(), id));
  } else {
    Reply(id, false, base::Value("unknown_method"));
  }
}

void BrowtherReferralHandler::Reply(const std::string& id,
                                    bool ok,
                                    base::Value result) {
  if (!IsJavascriptAllowed()) {
    return;
  }
  CallJavascriptFunction(kReplyFunction, base::Value(id), base::Value(ok),
                         result);
}

base::Value BrowtherReferralHandler::BuildContext() {
  PrefService* local_state = LocalState();
  base::DictValue context;
  context.Set("enabled", browther_referral::IsEnabled());
  context.Set("dev", browther_referral::IsDevBuild());
  context.Set("extrasReleased", browther_referral::kExtrasReleased);
  context.Set("host", HostName(host_));
  context.Set("platform", "desktop");
  context.Set("os", OsName());
  context.Set("locale", g_browser_process->GetApplicationLocale());
  context.Set("appVersion", version_info::GetVersionNumber());
  if (!local_state || !browther_referral::IsEnabled()) {
    return base::Value(std::move(context));
  }
  context.Set("deviceId", EnsureDeviceId(local_state));
  context.Set("usage", browther_referral::UsageSnapshot(local_state));
  context.Set("account", BrowtherReferralAccount::Get()->Info());
  context.Set("store",
              local_state->GetDict(browther_referral::prefs::kStore).Clone());
  context.Set("dayLock",
              local_state->GetDict(browther_referral::prefs::kDayLock).Clone());
  context.Set("canBeDefault", shell_integration::CanSetAsDefaultBrowser());
  Profile* profile = Profile::FromWebUI(web_ui());
  context.Set("sawtunaaEnabled",
              profile && profile->GetPrefs()->GetBoolean(kSawtunaaEnabled));
  auto* analytics = browther_analytics::BrowtherAnalyticsService::GetInstance();
  context.Set("analyticsOn", analytics && analytics->IsTrackingEnabled());
  return base::Value(std::move(context));
}

base::Value BrowtherReferralHandler::StoreSet(const base::DictValue& payload) {
  const std::string* key = payload.FindString("key");
  PrefService* local_state = LocalState();
  if (!key || !IsSafeKey(*key) || !local_state) {
    return base::Value("bad_key");
  }
  ScopedDictPrefUpdate update(local_state, browther_referral::prefs::kStore);
  const base::Value* value = payload.Find("value");
  if (!value || value->is_none()) {
    update->Remove(*key);
    return Ok();
  }
  std::string serialized;
  if (!base::JSONWriter::Write(*value, &serialized) ||
      serialized.size() > kMaxStoreValue) {
    return base::Value("too_large");
  }
  update->Set(*key, value->Clone());
  return Ok();
}

base::Value BrowtherReferralHandler::ClaimDay(const base::DictValue& payload) {
  // Le verrou du jour (§ 3.4) : « une sollicitation par jour », COMMUN à toutes
  // les surfaces de Browther desktop — le parrainage en est aujourd'hui la
  // seule (`SURFACES-COMMUNES.md` : rien d'autre ne s'ouvre seul sur desktop).
  // ⚠️ Posé ici, dans le Local State, et pas dans l'app : deux Nouveaux
  // Onglets dans deux fenêtres se le disputent au même instant.
  const std::string* owner = payload.FindString("owner");
  PrefService* local_state = LocalState();
  base::DictValue out;
  if (!owner || !IsSafeKey(*owner) || !local_state) {
    out.Set("granted", false);
    return base::Value(std::move(out));
  }
  const std::string today = browther_referral::LocalDayKey(base::Time::Now());
  const base::DictValue& lock =
      local_state->GetDict(browther_referral::prefs::kDayLock);
  const std::string* day = lock.FindString("day");
  const std::string* holder = lock.FindString("owner");
  if (day && *day == today && holder && *holder != *owner) {
    out.Set("granted", false);
    out.Set("owner", *holder);
    return base::Value(std::move(out));
  }
  base::DictValue next;
  next.Set("day", today);
  next.Set("owner", *owner);
  local_state->SetDict(browther_referral::prefs::kDayLock, std::move(next));
  out.Set("granted", true);
  out.Set("owner", *owner);
  return base::Value(std::move(out));
}

base::Value BrowtherReferralHandler::Track(const base::DictValue& payload) {
  const std::string* event = payload.FindString("event");
  auto* analytics = browther_analytics::BrowtherAnalyticsService::GetInstance();
  if (!event || !IsSafeKey(*event) || !analytics) {
    return base::Value("ignored");
  }
  const base::DictValue* props = payload.FindDict("props");
  base::DictValue properties = props ? props->Clone() : base::DictValue();
  properties.Set("platform", "desktop");
  analytics->Track(*event, std::move(properties));
  return Ok();
}

base::Value BrowtherReferralHandler::OpenPage(const base::DictValue& payload) {
  const std::string* query = payload.FindString("query");
  std::string url = browther_referral::kReferralURL;
  if (query && !query->empty() && query->size() < 200) {
    url = base::StrCat({url, "?", *query});
  }
  const GURL target(url);
  content::WebContents* web_contents = web_ui()->GetWebContents();
  // Depuis un écran du flow posé sur le Nouvel Onglet, « Inviter un proche »
  // REMPLACE ce Nouvel Onglet par l'écran Parrainage (§ 12.15) : c'est une
  // vraie page sur laquelle on peut revenir, ⛔ pas un onglet de plus.
  if (payload.FindBool("sameTab").value_or(false) || host_ == Host::kPage) {
    web_contents->GetController().LoadURL(target, content::Referrer(),
                                          ui::PAGE_TRANSITION_AUTO_TOPLEVEL,
                                          std::string());
    return Ok();
  }
  Profile* profile = Profile::FromWebUI(web_ui());
  if (profile) {
    ShowSingletonTabOverwritingNTP(profile, target,
                                   NavigateParams::IGNORE_AND_NAVIGATE);
  }
  return Ok();
}

base::Value BrowtherReferralHandler::OpenUrl(const base::DictValue& payload) {
  const std::string* spec = payload.FindString("url");
  const GURL url(spec ? *spec : std::string());
  if (!IsAllowedExternalUrl(url)) {
    return base::Value("refused");
  }
  web_ui()->GetWebContents()->OpenURL(
      content::OpenURLParams(url, content::Referrer(),
                             WindowOpenDisposition::NEW_FOREGROUND_TAB,
                             ui::PAGE_TRANSITION_LINK,
                             /*is_renderer_initiated=*/false),
      /*navigation_handle_callback=*/{});
  return Ok();
}

base::Value BrowtherReferralHandler::CopyText(const base::DictValue& payload) {
  const std::string* text = payload.FindString("text");
  if (!text || text->empty() || text->size() > 4096) {
    return base::Value("refused");
  }
  ui::ScopedClipboardWriter writer(ui::ClipboardBuffer::kCopyPaste);
  writer.WriteText(base::UTF8ToUTF16(*text));
  return Ok();
}

/**
 * ⭐ Une fenêtre qui ATTEND une réponse sort de la page : le navigateur la
 * rouvre en MODALE DE FENÊTRE (`browther_referral_dialog.h`). Dans une page,
 * elle se contourne en tapant dans la barre d'adresse — ce n'est pas un choix,
 * c'est une fuite (recette Karim, 2026-09-23).
 *
 * ⛔ Depuis la modale elle-même, rien : c'est elle qui affiche l'écran.
 */
base::Value BrowtherReferralHandler::OpenModal(const base::DictValue& payload) {
  base::DictValue out;
  const std::string* screen = payload.FindString("screen");
  if (host_ == Host::kModal || !screen || screen->empty()) {
    out.Set("opened", false);
    return base::Value(std::move(out));
  }
  out.Set("opened",
          browther_referral::ShowModal(web_ui()->GetWebContents(), *screen));
  return base::Value(std::move(out));
}

base::Value BrowtherReferralHandler::EnforcePause() {
  // 🟠 La pause quand le retrait de la musique est DÉJÀ allumé (décision par
  // défaut du 2026-09-22, iOS : `enforcePauseIfNeeded`) — la garde ne porte que
  // sur le geste d'allumer ; sans ça, qui le laisse allumé ne verrait jamais la
  // pause (⛔ « blocage seulement affiché », § 11.2). Appelé au Nouvel Onglet,
  // jamais au milieu d'une vidéo.
  base::DictValue out;
  Profile* profile = Profile::FromWebUI(web_ui());
  const bool paused = browther_referral::IsMusicRemovalPaused(LocalState());
  const bool on = profile && profile->GetPrefs()->GetBoolean(kSawtunaaEnabled);
  if (paused && on) {
    profile->GetPrefs()->SetBoolean(kSawtunaaEnabled, false);
    if (auto* analytics =
            browther_analytics::BrowtherAnalyticsService::GetInstance()) {
      base::DictValue props;
      props.Set("feature", "music_removal");
      props.Set("platform", "desktop");
      analytics->Track("feature_paused", std::move(props));
    }
  }
  out.Set("changed", paused && on);
  return base::Value(std::move(out));
}

base::Value BrowtherReferralHandler::Recette(const base::DictValue& payload) {
  // 🧪 L'outil de recette (§ 12.18) — 🔴 builds de dev SEULEMENT : un geste qui
  // touche une limite tenue par le client ne doit pas exister en prod.
  if (!browther_referral::IsDevBuild()) {
    return base::Value("refused");
  }
  PrefService* local_state = LocalState();
  const std::string* action = payload.FindString("action");
  if (!local_state || !action) {
    return base::Value("refused");
  }
  if (*action == "proofToday") {
    browther_referral::RecordDefaultProofForTesting(local_state);
  } else if (*action == "pagesToday") {
    browther_referral::SetPagesTodayForTesting(
        local_state, payload.FindInt("value").value_or(0));
  } else if (*action == "releaseDay") {
    local_state->ClearPref(browther_referral::prefs::kDayLock);
  } else if (*action == "resetDevice") {
    // Un appareil neuf : nouvelle identité, rien de vu, aucun fait d'usage.
    // ⚠️ Le compte reste : s'en déconnecter est un geste de l'écran 6.
    local_state->ClearPref(browther_referral::prefs::kDeviceId);
    local_state->ClearPref(browther_referral::prefs::kStore);
    local_state->ClearPref(browther_referral::prefs::kUsage);
    local_state->ClearPref(browther_referral::prefs::kAccess);
    local_state->ClearPref(browther_referral::prefs::kDayLock);
  } else if (*action == "sawtunaa") {
    if (Profile* profile = Profile::FromWebUI(web_ui())) {
      profile->GetPrefs()->SetBoolean(
          kSawtunaaEnabled, payload.FindBool("value").value_or(false));
    }
  } else {
    return base::Value("unknown_action");
  }
  return Ok();
}

void BrowtherReferralHandler::Request(const std::string& id,
                                      const base::DictValue& payload) {
  const std::string* service_name = payload.FindString("service");
  const std::string* path = payload.FindString("path");
  const std::string* method = payload.FindString("method");
  const std::optional<browther_referral::Service> service =
      service_name ? browther_referral::ServiceFromName(*service_name)
                   : std::nullopt;
  const GURL url = service && path
                       ? browther_referral::ServiceURL(*service, *path)
                       : GURL();
  if (!url.is_valid()) {
    Reply(id, false, base::Value("bad_request"));
    return;
  }
  std::string body;
  if (const base::Value* value = payload.Find("body")) {
    base::JSONWriter::Write(*value, &body);
  }
  std::vector<std::pair<std::string, std::string>> headers;
  // Le jeton d'administration de la recette (§ 12.18) : saisi dans l'outil,
  // gardé sur l'appareil — ⛔ jamais dans le code. Builds de dev seulement.
  if (const std::string* admin = payload.FindString("adminToken");
      admin && !admin->empty() && browther_referral::IsDevBuild() &&
      service == browther_referral::Service::kReferral &&
      path->starts_with("/v1/admin/")) {
    headers.emplace_back("X-Admin-Token", *admin);
  }
  const std::string http_method = method && *method == "GET" ? "GET" : "POST";

  auto send = base::BindOnce(
      [](base::WeakPtr<BrowtherReferralHandler> self, std::string id, GURL url,
         std::string method, std::string body,
         std::vector<std::pair<std::string, std::string>> headers,
         std::optional<std::string> token) {
        if (token) {
          headers.emplace_back("Authorization",
                               base::StrCat({"Bearer ", *token}));
        }
        browther_referral::Fetch(
            url, method, body, headers,
            base::BindOnce(
                [](base::WeakPtr<BrowtherReferralHandler> self, std::string id,
                   browther_referral::FetchResult result) {
                  if (!self) {
                    return;
                  }
                  base::DictValue out;
                  out.Set("status", result.status);
                  std::optional<base::Value> parsed =
                      base::JSONReader::Read(result.body, base::JSON_PARSE_RFC);
                  out.Set("body", parsed ? std::move(*parsed) : base::Value());
                  self->Reply(id, true, base::Value(std::move(out)));
                },
                self, std::move(id)));
      },
      weak_factory_.GetWeakPtr(), id, url, http_method, std::move(body),
      std::move(headers));

  // Le paiement et le compte parlent AU NOM du compte : le jeton s'ajoute ici,
  // ⛔ jamais depuis l'app. Le service de parrainage, lui, n'a pas de session
  // (`referral/docs/API.md` : routes publiques, sujet opaque).
  if (*service == browther_referral::Service::kReferral) {
    std::move(send).Run(std::nullopt);
  } else {
    BrowtherReferralAccount::Get()->WithToken(std::move(send));
  }
}

void BrowtherReferralHandler::SetDefaultBrowser(const std::string& id) {
  auto worker = base::MakeRefCounted<shell_integration::DefaultBrowserWorker>();
  worker->StartSetAsDefault(base::BindOnce(
      [](base::WeakPtr<BrowtherReferralHandler> self, std::string id,
         shell_integration::DefaultWebClientState state) {
        // La réponse du système compte comme la vérification du jour.
        browther_referral::CheckDefaultBrowser(
            LocalState(),
            base::BindOnce(
                [](base::WeakPtr<BrowtherReferralHandler> self, std::string id,
                   std::optional<bool> is_default) {
                  if (!self) {
                    return;
                  }
                  base::DictValue out;
                  if (is_default) {
                    out.Set("isDefault", *is_default);
                  }
                  self->Reply(id, true, base::Value(std::move(out)));
                },
                self, std::move(id)));
      },
      weak_factory_.GetWeakPtr(), id));
}

void BrowtherReferralHandler::CheckDefault(const std::string& id) {
  browther_referral::CheckDefaultBrowser(
      LocalState(),
      base::BindOnce(
          [](base::WeakPtr<BrowtherReferralHandler> self, std::string id,
             std::optional<bool> is_default) {
            if (!self) {
              return;
            }
            base::DictValue out;
            if (is_default) {
              out.Set("isDefault", *is_default);
            }
            self->Reply(id, true, base::Value(std::move(out)));
          },
          weak_factory_.GetWeakPtr(), id));
}
