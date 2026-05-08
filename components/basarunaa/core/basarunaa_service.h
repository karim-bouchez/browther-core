// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_COMPONENTS_BASARUNAA_CORE_BASARUNAA_SERVICE_H_
#define BRAVE_COMPONENTS_BASARUNAA_CORE_BASARUNAA_SERVICE_H_

#include <memory>
#include <string>
#include <vector>

#include "components/keyed_service/core/keyed_service.h"

#if defined(BASARUNAA_NATIVE_ML)
namespace Ort {
struct Env;
struct Session;
}  // namespace Ort
#endif

namespace basarunaa {

// Phase 3.1.5 — M1.3 minimal output. One detection per person; only the
// bounding box (in original image coordinates) and the YOLO score are
// populated. Gender / face / keypoints will follow in M1.4+ once yolov8n-face
// + InsightFace genderage are wired up.
struct DetectedPerson {
  // Bbox in pixel coordinates of the input image (NOT the 640x640 letterbox).
  float x = 0.f;
  float y = 0.f;
  float w = 0.f;
  float h = 0.f;
  // Person class score in [0, 1].
  float score = 0.f;
};

class BasarunaaService : public KeyedService {
 public:
  BasarunaaService();
  BasarunaaService(const BasarunaaService&) = delete;
  BasarunaaService& operator=(const BasarunaaService&) = delete;
  ~BasarunaaService() override;

  std::string GetVersion() const;
  bool Ping() const;

  // Phase 3.1.5 — M1.3: run YOLO11n-pose on a packed 4-channel buffer and
  // return detected persons. Empty vector on error or if the model is not
  // loaded. Caller-owned buffer; must be `width * height * 4` bytes.
  // `bgra` true means byte order [B, G, R, A] (typical for SkBitmap on
  // macOS), false means [R, G, B, A].
  std::vector<DetectedPerson> AnalyzeImageRgba(const uint8_t* rgba,
                                               int width,
                                               int height,
                                               bool bgra = false);

  // Debug-only: load a JPEG bundled at
  // `<DIR_EXE>/basarunaa/test/groupe.jpg`, run AnalyzeImageRgba, log every
  // detection, return the result.
  std::vector<DetectedPerson> AnalyzeTestImage();

 private:
#if defined(BASARUNAA_NATIVE_ML)
  void LoadYoloPoseModel();

  std::unique_ptr<Ort::Env> ort_env_;
  std::unique_ptr<Ort::Session> yolo_pose_session_;
  bool yolo_pose_ready_ = false;
#endif
};

}  // namespace basarunaa

#endif  // BRAVE_COMPONENTS_BASARUNAA_CORE_BASARUNAA_SERVICE_H_
