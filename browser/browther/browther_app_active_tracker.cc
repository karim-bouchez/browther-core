// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/browser/browther/browther_app_active_tracker.h"

#include <string>
#include <utility>

#include "base/functional/bind.h"
#include "base/memory/ref_counted.h"
#include "base/memory/scoped_refptr.h"
#include "base/strings/string_util.h"
#include "brave/components/browther_analytics/browther_analytics_service.h"
#include "brave/components/constants/pref_names.h"
#include "chrome/browser/browser_process.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser.h"
#include "chrome/browser/ui/browser_finder.h"
#include "chrome/browser/ui/browser_list.h"
#include "components/prefs/pref_service.h"

namespace {

BrowtherAppActiveTracker* g_instance = nullptr;

}  // namespace

BrowtherAppActiveTracker::BrowtherAppActiveTracker() {
  BrowserList::AddObserver(this);
}

BrowtherAppActiveTracker::~BrowtherAppActiveTracker() {
  BrowserList::RemoveObserver(this);
}

// static
void BrowtherAppActiveTracker::CreateInstance() {
  if (g_instance) {
    return;
  }
  g_instance = new BrowtherAppActiveTracker();
  // Le lancement : ⚠️ la fenêtre de démarrage EXISTE DÉJÀ ici — les
  // `PreMainMessageLoopRun` des extra parts passent après la création du
  // navigateur de démarrage, son `OnBrowserAdded` est donc déjà parti (constat
  // du 2026-10-13 : sans cette ligne, un lancement à une seule fenêtre
  // n'envoyait rien tant qu'on ne changeait pas de fenêtre).
  if (Browser* browser = chrome::FindLastActive()) {
    g_instance->MaybeTrack(browser);
  }
}

void BrowtherAppActiveTracker::OnBrowserAdded(Browser* browser) {
  // Lancement sans fenêtre (macOS, ou restauration tardive) puis fenêtres
  // suivantes : chacune arrive ici avec son profil chargé.
  MaybeTrack(browser);
}

void BrowtherAppActiveTracker::OnBrowserSetLastActive(Browser* browser) {
  MaybeTrack(browser);
}

void BrowtherAppActiveTracker::MaybeTrack(Browser* browser) {
  auto* analytics = browther_analytics::BrowtherAnalyticsService::GetInstance();
  // Chemin chaud (chaque activation de fenêtre) : une lecture de pref et une
  // comparaison de date, rien d'autre tant que le jour est déjà envoyé.
  if (!analytics || check_pending_ || !analytics->IsAppActiveDue()) {
    return;
  }
  Profile* profile = browser ? browser->profile() : nullptr;
  if (!profile) {
    return;
  }
  // Plusieurs profils : celui de la fenêtre qu'on vient d'utiliser. Une
  // fenêtre privée lit les réglages du profil dont elle est issue.
  const PrefService* prefs = profile->GetOriginalProfile()->GetPrefs();

  base::DictValue properties;
  // L'interrupteur principal, ⛔ pas la bascule « seulement 5 min »
  // (FeatureTemporarySwitch) : pendant le compte à rebours la pref porte
  // l'état du moment, c'est lui qu'on photographie.
  properties.Set("basarunaa_enabled", prefs->GetBoolean(kBasarunaaEnabled));
  properties.Set("sawtunaa_enabled", prefs->GetBoolean(kSawtunaaEnabled));
  // Langue de l'interface, au format d'iOS (`fr_FR`) : Chromium écrit `en-US`.
  // Les langues sans variante régionale restent nues (`fr`).
  std::string locale = g_browser_process->GetApplicationLocale();
  base::ReplaceChars(locale, "-", "_", &locale);
  properties.Set("locale", locale);

  // La question au système est bloquante en interne, d'où le worker
  // asynchrone : l'event part à sa réponse. Les réglages, eux, sont lus
  // maintenant — le profil peut disparaître d'ici là.
  check_pending_ = true;
  auto worker = base::MakeRefCounted<shell_integration::DefaultBrowserWorker>();
  worker->StartCheckIsDefault(
      base::BindOnce(&BrowtherAppActiveTracker::OnDefaultBrowserChecked,
                     weak_factory_.GetWeakPtr(), std::move(properties)));
}

void BrowtherAppActiveTracker::OnDefaultBrowserChecked(
    base::DictValue properties,
    shell_integration::DefaultWebClientState state) {
  check_pending_ = false;
  // ⛔ Jamais `false` par défaut : état inconnu ⇒ propriété omise.
  if (state == shell_integration::IS_DEFAULT) {
    properties.Set("default_browser", true);
  } else if (state == shell_integration::NOT_DEFAULT ||
             state == shell_integration::OTHER_MODE_IS_DEFAULT) {
    properties.Set("default_browser", false);
  }
  if (auto* analytics =
          browther_analytics::BrowtherAnalyticsService::GetInstance()) {
    // Revérifie le jour et le consentement, et ne note le jour que si l'event
    // a été remis au client.
    analytics->TrackAppActive(std::move(properties));
  }
}
