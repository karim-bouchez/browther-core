// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/browser/sawtunaa/sawtunaa_audio_service_factory.h"

#include "base/feature_list.h"
#include "base/no_destructor.h"
#include "brave/components/constants/pref_names.h"
#include "brave/components/sawtunaa/core/sawtunaa_audio_service.h"
#include "brave/components/sawtunaa/core/sawtunaa_features.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/profile_selections.h"
#include "components/prefs/pref_service.h"

namespace sawtunaa {

// static
SawtunaaAudioService* SawtunaaAudioServiceFactory::GetForProfile(
    Profile* profile) {
  return static_cast<SawtunaaAudioService*>(
      GetInstance()->GetServiceForBrowserContext(profile, /*create=*/true));
}

// static
SawtunaaAudioServiceFactory* SawtunaaAudioServiceFactory::GetInstance() {
  static base::NoDestructor<SawtunaaAudioServiceFactory> instance;
  return instance.get();
}

SawtunaaAudioServiceFactory::SawtunaaAudioServiceFactory()
    : ProfileKeyedServiceFactory(
          "SawtunaaAudioService",
          ProfileSelections::BuildRedirectedInIncognito()) {}

SawtunaaAudioServiceFactory::~SawtunaaAudioServiceFactory() = default;

std::unique_ptr<KeyedService>
SawtunaaAudioServiceFactory::BuildServiceInstanceForBrowserContext(
    content::BrowserContext* context) const {
  PrefService* prefs = Profile::FromBrowserContext(context)->GetPrefs();

  // Publie la CAPACITÉ native de ce build/plateforme (étape 4 — bascule) :
  // lue par le browser (injection du switch renderer, retrait option A) et
  // par l'extension MV3 (gate de capture tabCapture, via settingsPrivate).
  // SAWTUNAA_NATIVE_ML n'est défini que sur les builds où la dylib ORT est
  // bundlée (macOS arm64 aujourd'hui).
#if defined(SAWTUNAA_NATIVE_ML)
  const bool native_available =
      base::FeatureList::IsEnabled(kSawtunaaNativeAudio);
#else
  const bool native_available = false;
#endif
  prefs->SetBoolean(kSawtunaaNativeTapActive, native_available);

  // Warmup eager seulement si Sawtunaa est activé par l'utilisateur — sinon le
  // service reste froid (chargement lazy au 1er batch). Évite ~25 Mo + le run
  // à vide au boot des profils OFF.
  const bool eager_warmup = prefs->GetBoolean(kSawtunaaEnabled);
  return std::make_unique<SawtunaaAudioService>(eager_warmup);
}

bool SawtunaaAudioServiceFactory::ServiceIsCreatedWithBrowserContext() const {
  // Toujours créer : le service est vide sans warmup, et sa construction
  // publie kSawtunaaNativeTapActive à CHAQUE boot — y compris pour la remettre
  // à false quand la feature (kill-switch) est coupée, sinon l'extension
  // resterait désactivée avec une valeur périmée d'un boot précédent.
  return true;
}

}  // namespace sawtunaa
