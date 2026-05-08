// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/components/basarunaa/core/basarunaa_service.h"

#include "base/logging.h"

#if defined(BASARUNAA_NATIVE_ML)
#include "onnxruntime_cxx_api.h"
#endif

namespace basarunaa {

BasarunaaService::BasarunaaService() {
#if defined(BASARUNAA_NATIVE_ML)
  // Phase 3.1.5 — M1.1: prove the ORT static archive linked correctly.
  // GetVersionString() reads a constant baked into the library; if this
  // returns a non-empty string we know symbol resolution + the C ABI work.
  LOG(INFO) << "[Basarunaa] ONNX Runtime linked, version="
            << Ort::GetVersionString();
#endif
}
BasarunaaService::~BasarunaaService() = default;

std::string BasarunaaService::GetVersion() const {
#if defined(BASARUNAA_NATIVE_ML)
  return "scaffold-v0+ort-" + Ort::GetVersionString();
#else
  return "scaffold-v0";
#endif
}

bool BasarunaaService::Ping() const {
  return true;
}

}  // namespace basarunaa
