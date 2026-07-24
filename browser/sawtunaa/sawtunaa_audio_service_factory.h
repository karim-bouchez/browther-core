// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_BROWSER_SAWTUNAA_SAWTUNAA_AUDIO_SERVICE_FACTORY_H_
#define BRAVE_BROWSER_SAWTUNAA_SAWTUNAA_AUDIO_SERVICE_FACTORY_H_

#include <memory>

#include "base/no_destructor.h"
#include "chrome/browser/profiles/profile_keyed_service_factory.h"

class KeyedService;
class Profile;

namespace sawtunaa {

class SawtunaaAudioService;

// Jumeau de BasarunaaServiceFactory : service NSNet2 natif par profil
// (audio tap V2, cf. private/docs/sawtunaa/AUDIO_TAP_V2.md).
class SawtunaaAudioServiceFactory : public ProfileKeyedServiceFactory {
 public:
  static SawtunaaAudioService* GetForProfile(Profile* profile);
  static SawtunaaAudioServiceFactory* GetInstance();

  SawtunaaAudioServiceFactory(const SawtunaaAudioServiceFactory&) = delete;
  SawtunaaAudioServiceFactory& operator=(const SawtunaaAudioServiceFactory&) =
      delete;

 private:
  friend base::NoDestructor<SawtunaaAudioServiceFactory>;

  SawtunaaAudioServiceFactory();
  ~SawtunaaAudioServiceFactory() override;

  // ProfileKeyedServiceFactory:
  std::unique_ptr<KeyedService> BuildServiceInstanceForBrowserContext(
      content::BrowserContext* context) const override;
  // Eager-create quand la feature native audio est active : le warmup
  // (chargement modèle ~25 Mo + 1 run à vide) tourne au boot du profil, la
  // 1re lecture ne paie rien.
  bool ServiceIsCreatedWithBrowserContext() const override;
};

}  // namespace sawtunaa

#endif  // BRAVE_BROWSER_SAWTUNAA_SAWTUNAA_AUDIO_SERVICE_FACTORY_H_
