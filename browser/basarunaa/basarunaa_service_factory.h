// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_BROWSER_BASARUNAA_BASARUNAA_SERVICE_FACTORY_H_
#define BRAVE_BROWSER_BASARUNAA_BASARUNAA_SERVICE_FACTORY_H_

#include <memory>

#include "base/no_destructor.h"
#include "chrome/browser/profiles/profile_keyed_service_factory.h"

class KeyedService;
class Profile;

namespace basarunaa {

class BasarunaaService;

class BasarunaaServiceFactory : public ProfileKeyedServiceFactory {
 public:
  static BasarunaaService* GetForProfile(Profile* profile);
  static BasarunaaServiceFactory* GetInstance();

  BasarunaaServiceFactory(const BasarunaaServiceFactory&) = delete;
  BasarunaaServiceFactory& operator=(const BasarunaaServiceFactory&) = delete;

 private:
  friend base::NoDestructor<BasarunaaServiceFactory>;

  BasarunaaServiceFactory();
  ~BasarunaaServiceFactory() override;

  // ProfileKeyedServiceFactory:
  std::unique_ptr<KeyedService> BuildServiceInstanceForBrowserContext(
      content::BrowserContext* context) const override;
  // Eager-create le service au démarrage du profil quand le pipeline vidéo
  // decode-ahead est actif, pour que le warmup ML (chargement des 6 modèles +
  // compilation CoreML ~2s) tourne AVANT que l'utilisateur n'ouvre une vidéo.
  bool ServiceIsCreatedWithBrowserContext() const override;
};

}  // namespace basarunaa

#endif  // BRAVE_BROWSER_BASARUNAA_BASARUNAA_SERVICE_FACTORY_H_
