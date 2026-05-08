// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_COMPONENTS_BASARUNAA_CORE_BASARUNAA_SERVICE_H_
#define BRAVE_COMPONENTS_BASARUNAA_CORE_BASARUNAA_SERVICE_H_

#include <string>

#include "components/keyed_service/core/keyed_service.h"

namespace basarunaa {

// Phase 3.1.5 — Étape 1 scaffolding stub. Browser-process service that will
// host the native ML inference engine (ONNX Runtime + CoreML EP) once the
// xcframework is wired up. For now, only exposes GetVersion()/Ping() so the
// panel can prove the service is alive.
class BasarunaaService : public KeyedService {
 public:
  BasarunaaService();
  BasarunaaService(const BasarunaaService&) = delete;
  BasarunaaService& operator=(const BasarunaaService&) = delete;
  ~BasarunaaService() override;

  // Returns a hardcoded scaffolding tag. Will return the bundled model bundle
  // version once models are loaded natively.
  std::string GetVersion() const;

  // No-op health check. Always true while the service object is alive.
  bool Ping() const;
};

}  // namespace basarunaa

#endif  // BRAVE_COMPONENTS_BASARUNAA_CORE_BASARUNAA_SERVICE_H_
