// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/components/basarunaa/core/basarunaa_service.h"

#include "base/logging.h"

#if defined(BASARUNAA_NATIVE_ML)
#include "base/files/file_path.h"
#include "base/files/file_util.h"
#include "base/path_service.h"
#include "base/strings/string_number_conversions.h"
#include "onnxruntime_cxx_api.h"
#endif

namespace basarunaa {

#if defined(BASARUNAA_NATIVE_ML)
namespace {

// Path of the YOLO11n-pose model relative to the executable. The Basarunaa
// MV3 extension is bundled at `Browther.app/Contents/MacOS/basarunaa/` (cf.
// `private/scripts/deploy-extensions.sh`), and we reuse its `models/` dir
// during the MV3 → native migration. Once Étape 5 deletes the extension, the
// models will move under `Resources/` or be served by the component updater.
constexpr base::FilePath::CharType kYoloPoseRelPath[] =
    FILE_PATH_LITERAL("basarunaa/models/yolo11n-pose.onnx");

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

}  // namespace
#endif  // defined(BASARUNAA_NATIVE_ML)

BasarunaaService::BasarunaaService() {
#if defined(BASARUNAA_NATIVE_ML)
  // Phase 3.1.5 — M1.1: prove the ORT static archive linked correctly.
  // GetVersionString() reads a constant baked into the library; if this
  // returns a non-empty string we know symbol resolution + the C ABI work.
  LOG(INFO) << "[Basarunaa] ONNX Runtime linked, version="
            << Ort::GetVersionString();
  // Phase 3.1.5 — M1.2: load YOLO11n-pose to validate the full session
  // pipeline (env, options, session ctor, IO introspection).
  LoadYoloPoseModel();
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

#if defined(BASARUNAA_NATIVE_ML)
void BasarunaaService::LoadYoloPoseModel() {
  base::FilePath exe_dir;
  if (!base::PathService::Get(base::DIR_EXE, &exe_dir)) {
    LOG(ERROR) << "[Basarunaa] base::DIR_EXE lookup failed";
    return;
  }
  const base::FilePath model_path = exe_dir.Append(kYoloPoseRelPath);
  if (!base::PathExists(model_path)) {
    LOG(WARNING) << "[Basarunaa] YOLO model not found at "
                 << model_path.value()
                 << " (expected when the MV3 extension bundle is missing — "
                    "deploy-extensions.sh must have run)";
    return;
  }

  try {
    ort_env_ = std::make_unique<Ort::Env>(ORT_LOGGING_LEVEL_WARNING,
                                          "basarunaa");
    Ort::SessionOptions opts;
    opts.SetIntraOpNumThreads(1);
    opts.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);
    yolo_pose_session_ = std::make_unique<Ort::Session>(
        *ort_env_, model_path.value().c_str(), opts);
  } catch (const Ort::Exception& e) {
    LOG(ERROR) << "[Basarunaa] ORT session creation failed: " << e.what();
    ort_env_.reset();
    yolo_pose_session_.reset();
    return;
  }

  // Introspect IO. yolo11n-pose: input "images" [1,3,640,640],
  // output "output0" [1,56,8400] (4 bbox + 1 obj + 51 kpts × N anchors).
  // GetTensorTypeAndShapeInfo() returns an unowned view of the parent
  // Ort::TypeInfo. The parent must stay alive for the chain — keep it in a
  // named variable rather than dotting through a temporary.
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
