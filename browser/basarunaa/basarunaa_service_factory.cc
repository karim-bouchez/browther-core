// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/browser/basarunaa/basarunaa_service_factory.h"

#include "base/no_destructor.h"
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
  return true;
}

}  // namespace basarunaa
