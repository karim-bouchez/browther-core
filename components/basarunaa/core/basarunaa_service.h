// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_COMPONENTS_BASARUNAA_CORE_BASARUNAA_SERVICE_H_
#define BRAVE_COMPONENTS_BASARUNAA_CORE_BASARUNAA_SERVICE_H_

#include <memory>
#include <mutex>
#include <optional>
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

// 17 COCO keypoints retournés par YOLO11n-pose : nose, eyes, ears, shoulders,
// elbows, wrists, hips, knees, ankles. Coords pixel image originale.
struct DetectedKeyPoint {
  float x = 0.f;
  float y = 0.f;
  float confidence = 0.f;
};

// Bbox visage déduite des keypoints face (M1.4).
struct DetectedFaceBbox {
  float x1 = 0.f;
  float y1 = 0.f;
  float x2 = 0.f;
  float y2 = 0.f;
};

// Phase 3.1.5 — M1.4. One detection per person : bbox + score + 17 keypoints
// (nécessaires au pipeline MV3 pour matching face↔body et alignement face
// InsightFace) + faceBbox dérivé des keypoints 0-4.
struct DetectedPerson {
  DetectedPerson();
  DetectedPerson(const DetectedPerson&);
  DetectedPerson(DetectedPerson&&) noexcept;
  DetectedPerson& operator=(const DetectedPerson&);
  DetectedPerson& operator=(DetectedPerson&&) noexcept;
  ~DetectedPerson();

  // Bbox in pixel coordinates of the input image (NOT the 640x640 letterbox).
  float x = 0.f;
  float y = 0.f;
  float w = 0.f;
  float h = 0.f;
  // Person class score in [0, 1].
  float score = 0.f;
  // 17 keypoints, indexed COCO order. Empty if pose decoding failed.
  std::vector<DetectedKeyPoint> keypoints;
  // Derived from keypoints 0-4 (nose + eyes + ears) with 40% padding;
  // nullopt if < 2 keypoints visible (confidence > 0.3).
  std::optional<DetectedFaceBbox> face_bbox;
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

  // ort_env_ peut être créé concurremment par LoadYoloPoseModel et
  // LoadYoloFaceModel (deux call_once sur des flags différents). On
  // sérialise sa création via env_init_flag_ pour éviter la race.
  void EnsureOrtEnv();
  std::once_flag env_init_flag_;
  std::unique_ptr<Ort::Env> ort_env_;
  // Serializes the lazy load. Multiple worker threads may race into
  // AnalyzeImageRgba on first use; without serialization, several
  // concurrent `LoadYoloPoseModel()` runs corrupt `yolo_pose_session_`
  // (assignment to the unique_ptr destroys a half-built `Ort::Session`
  // on another thread → SEGV in `~InferenceSession`). std::call_once
  // is the right primitive: thread-safe one-time init, simpler than a
  // base::Lock (which we tried first — kept hitting a DCHECK on Acquire
  // we never fully diagnosed). Once `yolo_pose_ready_` is true,
  // `Ort::Session::Run` itself is thread-safe.
  std::once_flag init_flag_;
  std::unique_ptr<Ort::Session> yolo_pose_session_;
  bool yolo_pose_ready_ = false;
#endif
};

}  // namespace basarunaa

#endif  // BRAVE_COMPONENTS_BASARUNAA_CORE_BASARUNAA_SERVICE_H_
