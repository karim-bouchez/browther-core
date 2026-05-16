// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/components/basarunaa/core/basarunaa_service.h"

#include <algorithm>
#include <array>
#include <limits>
#include <cmath>

#include "base/compiler_specific.h"
#include "base/containers/span.h"
#include "base/logging.h"

#if defined(BASARUNAA_NATIVE_ML)
#include "base/files/file_path.h"
#include "base/files/file_util.h"
#include "base/path_service.h"
#include "base/strings/string_number_conversions.h"
#include "base/time/time.h"
#include "onnxruntime_cxx_api.h"
#endif

namespace basarunaa {

#if defined(BASARUNAA_NATIVE_ML)
namespace {

// MV3 extension bundle path during the Phase 3.1.5 migration. Will move under
// component-updater / app Resources when Étape 5 deletes the extension.
constexpr base::FilePath::CharType kYoloPoseRelPath[] =
    FILE_PATH_LITERAL("basarunaa/models/yolo11n-pose.onnx");

// YOLO11n-pose constants. Input is fixed 640x640 RGB float32 NCHW; output is
// [1, 56, 8400] = [1, 4 bbox + 1 person score + 17 kpts × 3, anchors]. We do
// not consume keypoints in M1.3 (just the bbox and the class score).
constexpr int kYoloInputSize = 640;
constexpr int kYoloOutputChannels = 56;
constexpr int kYoloAnchors = 8400;
constexpr float kYoloPad = 114.0f / 255.0f;

// Tunables — match the POC defaults.
constexpr float kScoreThreshold = 0.25f;
constexpr float kNmsIou = 0.5f;

std::string ShapeToString(const std::vector<int64_t>& shape) {
  std::string out = "[";
  for (size_t i = 0; i < shape.size(); ++i) {
    if (i > 0) {
      out += ",";
    }
    out += base::NumberToString(shape[i]);
  }
  out += "]";
  return out;
}

// Bilinear sample of 4-channel packed pixels at fractional pixel (sx, sy).
// Out of bounds returns gray. `bgra` swaps the R and B byte indices.
void BilinearSampleRgba(base::span<const uint8_t> src,
                        int sw,
                        int sh,
                        float sx,
                        float sy,
                        bool bgra,
                        float& r,
                        float& g,
                        float& b) {
  if (sx < 0 || sy < 0 || sx >= sw || sy >= sh) {
    r = g = b = kYoloPad;
    return;
  }
  const int x0 = static_cast<int>(std::floor(sx));
  const int y0 = static_cast<int>(std::floor(sy));
  const int x1 = std::min(x0 + 1, sw - 1);
  const int y1 = std::min(y0 + 1, sh - 1);
  const float fx = sx - x0;
  const float fy = sy - y0;

  const size_t r_idx = bgra ? 2 : 0;
  const size_t b_idx = bgra ? 0 : 2;
  auto get = [&](int xx, int yy, float& rr, float& gg, float& bb) {
    const size_t off = static_cast<size_t>(yy * sw + xx) * 4;
    rr = src[off + r_idx] / 255.0f;
    gg = src[off + 1] / 255.0f;
    bb = src[off + b_idx] / 255.0f;
  };
  float r00, g00, b00, r10, g10, b10, r01, g01, b01, r11, g11, b11;
  get(x0, y0, r00, g00, b00);
  get(x1, y0, r10, g10, b10);
  get(x0, y1, r01, g01, b01);
  get(x1, y1, r11, g11, b11);
  const float w00 = (1 - fx) * (1 - fy);
  const float w10 = fx * (1 - fy);
  const float w01 = (1 - fx) * fy;
  const float w11 = fx * fy;
  r = r00 * w00 + r10 * w10 + r01 * w01 + r11 * w11;
  g = g00 * w00 + g10 * w10 + g01 * w01 + g11 * w11;
  b = b00 * w00 + b10 * w10 + b01 * w01 + b11 * w11;
}

// Letterbox-normalize-pack: convert a packed RGBA buffer into a 1×3×640×640
// float32 NCHW tensor matching the ultralytics YOLO11n-pose preprocessing
// (resize-with-aspect, pad to 640 with gray=114, RGB normalized to [0,1]).
//
// `scale_out`, `pad_x_out`, `pad_y_out` are filled so the caller can map
// detection coordinates back to the original image space.
void LetterboxRgbaToNchw(base::span<const uint8_t> rgba,
                         int width,
                         int height,
                         bool bgra,
                         std::vector<float>& nchw,
                         float& scale_out,
                         float& pad_x_out,
                         float& pad_y_out) {
  const float scale = std::min(static_cast<float>(kYoloInputSize) / width,
                               static_cast<float>(kYoloInputSize) / height);
  const int new_w = static_cast<int>(std::round(width * scale));
  const int new_h = static_cast<int>(std::round(height * scale));
  const float pad_x = (kYoloInputSize - new_w) / 2.0f;
  const float pad_y = (kYoloInputSize - new_h) / 2.0f;

  nchw.assign(3 * kYoloInputSize * kYoloInputSize, kYoloPad);
  const int plane = kYoloInputSize * kYoloInputSize;
  for (int dy = 0; dy < kYoloInputSize; ++dy) {
    for (int dx = 0; dx < kYoloInputSize; ++dx) {
      const float sx = (dx - pad_x) / scale;
      const float sy = (dy - pad_y) / scale;
      if (sx < 0 || sy < 0 || sx >= width || sy >= height) {
        continue;  // already gray
      }
      float r, g, b;
      BilinearSampleRgba(rgba, width, height, sx, sy, bgra, r, g, b);
      const int idx = dy * kYoloInputSize + dx;
      nchw[0 * plane + idx] = r;
      nchw[1 * plane + idx] = g;
      nchw[2 * plane + idx] = b;
    }
  }
  scale_out = scale;
  pad_x_out = pad_x;
  pad_y_out = pad_y;
}

float Iou(const DetectedPerson& a, const DetectedPerson& b) {
  const float x1 = std::max(a.x, b.x);
  const float y1 = std::max(a.y, b.y);
  const float x2 = std::min(a.x + a.w, b.x + b.w);
  const float y2 = std::min(a.y + a.h, b.y + b.h);
  const float inter = std::max(0.f, x2 - x1) * std::max(0.f, y2 - y1);
  const float ua = a.w * a.h + b.w * b.h - inter;
  return ua > 0 ? inter / ua : 0.f;
}

std::vector<DetectedPerson> NonMaxSuppression(
    std::vector<DetectedPerson> dets) {
  std::sort(dets.begin(), dets.end(),
            [](const DetectedPerson& l, const DetectedPerson& r) {
              return l.score > r.score;
            });
  std::vector<DetectedPerson> kept;
  std::vector<bool> suppressed(dets.size(), false);
  for (size_t i = 0; i < dets.size(); ++i) {
    if (suppressed[i]) {
      continue;
    }
    kept.push_back(dets[i]);
    for (size_t j = i + 1; j < dets.size(); ++j) {
      if (!suppressed[j] && Iou(dets[i], dets[j]) > kNmsIou) {
        suppressed[j] = true;
      }
    }
  }
  return kept;
}

}  // namespace
#endif  // defined(BASARUNAA_NATIVE_ML)

DetectedPerson::DetectedPerson() = default;
DetectedPerson::DetectedPerson(const DetectedPerson&) = default;
DetectedPerson::DetectedPerson(DetectedPerson&&) noexcept = default;
DetectedPerson& DetectedPerson::operator=(const DetectedPerson&) = default;
DetectedPerson& DetectedPerson::operator=(DetectedPerson&&) noexcept = default;
DetectedPerson::~DetectedPerson() = default;

BasarunaaService::BasarunaaService() {
#if defined(BASARUNAA_NATIVE_ML)
  // Lazy: ORT version log + YOLO load run on first inference call (worker
  // pool, where blocking I/O is allowed). Doing it eagerly on the UI thread
  // at profile init triggered intermittent SEGVs in ORT thread spawn.
  LOG(INFO) << "[Basarunaa] service constructed (lazy init)";
#endif
}
BasarunaaService::~BasarunaaService() = default;

std::string BasarunaaService::GetVersion() const {
#if defined(BASARUNAA_NATIVE_ML)
  std::string v = "scaffold-v0+ort-" + Ort::GetVersionString();
  if (yolo_pose_ready_) {
    v += "+yolo";
  }
  return v;
#else
  return "scaffold-v0";
#endif
}

bool BasarunaaService::Ping() const {
#if defined(BASARUNAA_NATIVE_ML)
  return yolo_pose_ready_;
#else
  return true;
#endif
}

std::vector<DetectedPerson> BasarunaaService::AnalyzeImageRgba(
    const uint8_t* rgba,
    int width,
    int height,
    bool bgra) {
#if defined(BASARUNAA_NATIVE_ML)
  if (!rgba || width <= 0 || height <= 0) {
    return {};
  }
  // One-time init across worker threads (see init_flag_ docs in header).
  std::call_once(init_flag_, [this]() { LoadYoloPoseModel(); });
  if (!yolo_pose_ready_) {
    return {};
  }
  const auto start = base::TimeTicks::Now();

  // Preprocess.
  std::vector<float> input_tensor;
  float scale = 1.f, pad_x = 0.f, pad_y = 0.f;
  // Wrap caller-owned buffer in a span for safe indexing. The raw pointer
  // comes from a public C-style API (or SkBitmap::getPixels) so we lean on
  // UNSAFE_BUFFERS to acknowledge the construction.
  const auto rgba_span = UNSAFE_BUFFERS(base::span<const uint8_t>(
      rgba, static_cast<size_t>(width) * height * 4));
  LetterboxRgbaToNchw(rgba_span, width, height, bgra, input_tensor, scale,
                      pad_x, pad_y);

  // Run.
  std::vector<float> output_data;
  try {
    auto memory_info = Ort::MemoryInfo::CreateCpu(OrtArenaAllocator,
                                                  OrtMemTypeDefault);
    const std::array<int64_t, 4> input_shape = {1, 3, kYoloInputSize,
                                                kYoloInputSize};
    Ort::Value input_value = Ort::Value::CreateTensor<float>(
        memory_info, input_tensor.data(), input_tensor.size(),
        input_shape.data(), input_shape.size());

    Ort::AllocatorWithDefaultOptions alloc;
    auto in_name = yolo_pose_session_->GetInputNameAllocated(0, alloc);
    auto out_name = yolo_pose_session_->GetOutputNameAllocated(0, alloc);
    const char* in_names[] = {in_name.get()};
    const char* out_names[] = {out_name.get()};

    auto outputs = yolo_pose_session_->Run(Ort::RunOptions{nullptr}, in_names,
                                           &input_value, 1, out_names, 1);
    // ORT exposes raw float* + length; wrap with UNSAFE_BUFFERS for the same
    // reason as the input span above.
    const auto out_span = UNSAFE_BUFFERS(base::span<const float>(
        outputs[0].GetTensorData<float>(),
        static_cast<size_t>(kYoloOutputChannels) * kYoloAnchors));
    output_data.assign(out_span.begin(), out_span.end());
  } catch (const Ort::Exception& e) {
    LOG(ERROR) << "[Basarunaa] inference failed: " << e.what();
    return {};
  }

  // Decode anchors. Output layout is channel-major: out[c * anchors + i].
  // Channels 0..3 = cx, cy, w, h ; channel 4 = score ; channels 5..56 = 17
  // keypoints * 3 (x, y, confidence). Tous dans l'espace 640x640 letterbox,
  // converti en pixel image originale via (val - pad) / scale.
  constexpr int kNumKeypoints = 17;
  constexpr float kFaceKpVisibilityThreshold = 0.3f;
  constexpr float kFacePadding = 0.4f;

  std::vector<DetectedPerson> raw;
  raw.reserve(64);
  for (int i = 0; i < kYoloAnchors; ++i) {
    const float score = output_data[4 * kYoloAnchors + i];
    if (score < kScoreThreshold) {
      continue;
    }
    const float cx = output_data[0 * kYoloAnchors + i];
    const float cy = output_data[1 * kYoloAnchors + i];
    const float bw = output_data[2 * kYoloAnchors + i];
    const float bh = output_data[3 * kYoloAnchors + i];
    DetectedPerson d;
    // Convert center-wh in 640 input space → top-left-wh in original image.
    d.x = (cx - bw / 2 - pad_x) / scale;
    d.y = (cy - bh / 2 - pad_y) / scale;
    d.w = bw / scale;
    d.h = bh / scale;
    d.score = score;

    // Decode the 17 keypoints (M1.4).
    d.keypoints.reserve(kNumKeypoints);
    for (int k = 0; k < kNumKeypoints; ++k) {
      const int base_ch = 5 + k * 3;
      const float kx = output_data[base_ch * kYoloAnchors + i];
      const float ky = output_data[(base_ch + 1) * kYoloAnchors + i];
      const float kconf = output_data[(base_ch + 2) * kYoloAnchors + i];
      DetectedKeyPoint kp;
      kp.x = (kx - pad_x) / scale;
      kp.y = (ky - pad_y) / scale;
      kp.confidence = kconf;
      d.keypoints.push_back(kp);
    }

    // Derive face bbox from keypoints 0..4 (nose, left_eye, right_eye,
    // left_ear, right_ear). Mirror du _deriveFaceBbox du POC JS.
    float min_x = std::numeric_limits<float>::infinity();
    float min_y = std::numeric_limits<float>::infinity();
    float max_x = -std::numeric_limits<float>::infinity();
    float max_y = -std::numeric_limits<float>::infinity();
    int visible_face_kps = 0;
    for (int k = 0; k < 5; ++k) {
      const auto& kp = d.keypoints[k];
      if (kp.confidence > kFaceKpVisibilityThreshold) {
        ++visible_face_kps;
        min_x = std::min(min_x, kp.x);
        min_y = std::min(min_y, kp.y);
        max_x = std::max(max_x, kp.x);
        max_y = std::max(max_y, kp.y);
      }
    }
    if (visible_face_kps >= 2) {
      const float face_w = max_x - min_x;
      const float face_h = max_y - min_y;
      const float face_size = std::max(face_w, face_h);
      const float center_x = (min_x + max_x) * 0.5f;
      const float center_y = (min_y + max_y) * 0.5f;
      const float half_size = (face_size * (1.f + kFacePadding)) * 0.5f;
      DetectedFaceBbox fb;
      fb.x1 = std::max(0.f, center_x - half_size);
      fb.y1 = std::max(0.f, center_y - half_size);
      fb.x2 = std::min(static_cast<float>(width), center_x + half_size);
      fb.y2 = std::min(static_cast<float>(height), center_y + half_size);
      d.face_bbox = fb;
    }

    raw.push_back(std::move(d));
  }

  auto nms = NonMaxSuppression(std::move(raw));
  const auto elapsed_ms = (base::TimeTicks::Now() - start).InMillisecondsF();
  LOG(INFO) << "[Basarunaa] inference: " << width << "x" << height << " → "
            << nms.size() << " persons (" << elapsed_ms << " ms)";
  return nms;
#else
  return {};
#endif  // defined(BASARUNAA_NATIVE_ML)
}

#if defined(BASARUNAA_NATIVE_ML)
void BasarunaaService::EnsureOrtEnv() {
  std::call_once(env_init_flag_, [this]() {
    try {
      ort_env_ = std::make_unique<Ort::Env>(ORT_LOGGING_LEVEL_WARNING,
                                            "basarunaa");
    } catch (const Ort::Exception& e) {
      LOG(ERROR) << "[Basarunaa] ORT env creation failed: " << e.what();
    }
  });
}

void BasarunaaService::LoadYoloPoseModel() {
  base::FilePath exe_dir;
  if (!base::PathService::Get(base::DIR_EXE, &exe_dir)) {
    LOG(ERROR) << "[Basarunaa] base::DIR_EXE lookup failed";
    return;
  }
  const base::FilePath model_path = exe_dir.Append(kYoloPoseRelPath);
  if (!base::PathExists(model_path)) {
    LOG(WARNING) << "[Basarunaa] YOLO model not found at " << model_path.value()
                 << " (deploy-extensions.sh must have run)";
    return;
  }

  EnsureOrtEnv();
  if (!ort_env_) {
    return;
  }
  try {
    Ort::SessionOptions opts;
    opts.SetIntraOpNumThreads(1);
    opts.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);
    yolo_pose_session_ = std::make_unique<Ort::Session>(
        *ort_env_, model_path.value().c_str(), opts);
  } catch (const Ort::Exception& e) {
    LOG(ERROR) << "[Basarunaa] ORT pose session creation failed: " << e.what();
    yolo_pose_session_.reset();
    return;
  }

  Ort::AllocatorWithDefaultOptions alloc;
  const size_t inputs = yolo_pose_session_->GetInputCount();
  for (size_t i = 0; i < inputs; ++i) {
    auto name = yolo_pose_session_->GetInputNameAllocated(i, alloc);
    auto type_info = yolo_pose_session_->GetInputTypeInfo(i);
    const auto shape = type_info.GetTensorTypeAndShapeInfo().GetShape();
    LOG(INFO) << "[Basarunaa] YOLO input[" << i << "] name=" << name.get()
              << " shape=" << ShapeToString(shape);
  }
  const size_t outputs = yolo_pose_session_->GetOutputCount();
  for (size_t i = 0; i < outputs; ++i) {
    auto name = yolo_pose_session_->GetOutputNameAllocated(i, alloc);
    auto type_info = yolo_pose_session_->GetOutputTypeInfo(i);
    const auto shape = type_info.GetTensorTypeAndShapeInfo().GetShape();
    LOG(INFO) << "[Basarunaa] YOLO output[" << i << "] name=" << name.get()
              << " shape=" << ShapeToString(shape);
  }

  yolo_pose_ready_ = true;
  LOG(INFO) << "[Basarunaa] YOLO11n-pose session ready";
}
#endif  // defined(BASARUNAA_NATIVE_ML)

}  // namespace basarunaa
