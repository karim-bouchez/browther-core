// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_COMPONENTS_BASARUNAA_CORE_BASARUNAA_SERVICE_H_
#define BRAVE_COMPONENTS_BASARUNAA_CORE_BASARUNAA_SERVICE_H_

#include <memory>
#include <string>

#include "components/keyed_service/core/keyed_service.h"

#if defined(BASARUNAA_NATIVE_ML)
namespace Ort {
struct Env;
struct Session;
}  // namespace Ort
#endif

namespace basarunaa {

// Phase 3.1.5 — Étape 1 scaffolding (M1.1) + M1.2 model load.
// Browser-process service that hosts the native ONNX Runtime inference for
// the Basarunaa pipeline. Owns the long-lived `Ort::Env` and one
// `Ort::Session` per loaded model. CPU EP only for now.
class BasarunaaService : public KeyedService {
 public:
  BasarunaaService();
  BasarunaaService(const BasarunaaService&) = delete;
  BasarunaaService& operator=(const BasarunaaService&) = delete;
  ~BasarunaaService() override;

  // Returns "scaffold-v0" + ORT version + "+yolo" if YOLO loaded.
  std::string GetVersion() const;

  // True iff the service is alive AND (when native ML is enabled) the YOLO
  // session was created without error.
  bool Ping() const;

 private:
#if defined(BASARUNAA_NATIVE_ML)
  // Resolve the model path from `base::DIR_EXE` (extension bundle path —
  // shared with the MV3 extension during the migration; will move to
  // component-updater data dir in a later milestone) and create the session.
  void LoadYoloPoseModel();

  std::unique_ptr<Ort::Env> ort_env_;
  std::unique_ptr<Ort::Session> yolo_pose_session_;
  bool yolo_pose_ready_ = false;
#endif
};

}  // namespace basarunaa

#endif  // BRAVE_COMPONENTS_BASARUNAA_CORE_BASARUNAA_SERVICE_H_
