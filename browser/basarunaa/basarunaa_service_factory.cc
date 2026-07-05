// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/browser/basarunaa/basarunaa_service_factory.h"

#include "base/feature_list.h"
#include "base/no_destructor.h"
#include "brave/components/basarunaa/core/basarunaa_features.h"
#include "brave/components/basarunaa/core/basarunaa_service.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/profile_selections.h"

namespace basarunaa {

// static
BasarunaaService* BasarunaaServiceFactory::GetForProfile(Profile* profile) {
  return static_cast<BasarunaaService*>(
      GetInstance()->GetServiceForBrowserContext(profile, /*create=*/true));
}

// static
BasarunaaServiceFactory* BasarunaaServiceFactory::GetInstance() {
  static base::NoDestructor<BasarunaaServiceFactory> instance;
  return instance.get();
}

BasarunaaServiceFactory::BasarunaaServiceFactory()
    : ProfileKeyedServiceFactory(
          "BasarunaaService",
          ProfileSelections::BuildRedirectedInIncognito()) {}

BasarunaaServiceFactory::~BasarunaaServiceFactory() = default;

std::unique_ptr<KeyedService>
BasarunaaServiceFactory::BuildServiceInstanceForBrowserContext(
    content::BrowserContext* context) const {
  return std::make_unique<BasarunaaService>();
}

bool BasarunaaServiceFactory::ServiceIsCreatedWithBrowserContext() const {
  // Sans la feature vidéo, le service n'est jamais utilisé (le RFO ne tap
  // aucune frame) → inutile de charger 6 modèles ONNX à chaque lancement. Avec
  // la feature, on crée le service dès l'init du profil : son constructeur
  // poste le warmup (ThreadPool) et la 1re vidéo est déjà chaude.
  return base::FeatureList::IsEnabled(kBasarunaaVideoDecodeAhead);
}

}  // namespace basarunaa
