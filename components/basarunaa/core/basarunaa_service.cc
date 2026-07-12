// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/components/basarunaa/core/basarunaa_service.h"

#include <algorithm>
#include <array>
#include <cmath>

#include "base/compiler_specific.h"
#include "base/containers/span.h"
#include "base/logging.h"

#if defined(BASARUNAA_NATIVE_ML)
#include "base/files/file_path.h"
#include "base/files/file_util.h"
#include "base/functional/bind.h"
#include "base/location.h"
#include "base/path_service.h"
#include "base/strings/string_number_conversions.h"
#include "base/task/thread_pool.h"
#include "base/time/time.h"
#include "build/build_config.h"
#include "onnxruntime_cxx_api.h"
#if BUILDFLAG(IS_MAC)
#include "base/apple/bundle_locations.h"
// EP GPU/ANE : le CoreML EP est compilé dans la dylib bundlée (symbole
// OrtSessionOptionsAppendExecutionProvider_CoreML exporté ; la dylib linke déjà
// CoreML.framework/Foundation → aucun ldflag à ajouter côté chrome_dll).
#include "coreml_provider_factory.h"
#endif
#endif

namespace basarunaa {

#if defined(BASARUNAA_NATIVE_ML)
namespace {

// Modèle single-shot gender-v2n, déposé par deploy-extensions.sh (dev Component)
// ou stagé dans Contents/Resources (Release macOS signé). Bougera sous
// component-updater quand l'Étape 5 supprimera l'extension.
constexpr base::FilePath::CharType kGenderV2nRelPath[] =
    FILE_PATH_LITERAL("basarunaa/models/gender-v2n-640.onnx");

// Resolve a model path shipped with the built-in extension. Mirrors
// ResolveBrowtherExtensionPath (brave_component_loader.cc):
//   1. DIR_EXE/<rel> — dev Component builds (deploy-extensions.sh) + Win/Linux.
//   2. macOS: Browther.app/Contents/Resources/<rel> — GN bundle_data staging
//      (brave/browther_extensions/), the only layout present in signed
//      Release/DMG builds (codesign rejects non-Mach-O data in Contents/MacOS).
base::FilePath ResolveModelPath(const base::FilePath::CharType* rel_path) {
  base::FilePath exe_dir;
  if (base::PathService::Get(base::DIR_EXE, &exe_dir)) {
    base::FilePath exe_path = exe_dir.Append(rel_path);
    if (base::PathExists(exe_path)) {
      return exe_path;
    }
  }
#if BUILDFLAG(IS_MAC)
  return base::apple::OuterBundlePath()
      .Append("Contents")
      .Append("Resources")
      .Append(rel_path);
#else
  return exe_dir.Append(rel_path);
#endif
}

// gender-v2n : entrée fixe 640x640 RGB float32 NCHW ; sortie [1, 58, N] =
// [1, 4 bbox + 3 classes (male/female/child) + 17 kpts × 3, anchors]. N (= 8400
// à 640) est lu DYNAMIQUEMENT de la sortie. Le genre d'une personne = la classe
// argmax, sa confiance = le score de cette classe (pas de canal "person" séparé).
constexpr int kYoloInputSize = 640;
constexpr int kV2nChannels = 58;
constexpr int kV2nNumClasses = 3;
constexpr int kV2nKptOffset = 4 + kV2nNumClasses;  // 7 : 1er canal des keypoints
// Gris 128 (comme la v1 : `#808080`), pas 114 (ultralytics) — colle aux
// benchmarks accuracy faits sur la v1.
constexpr float kYoloPad = 128.0f / 255.0f;

// Tunables — match the POC defaults. (Le seuil de score personne est désormais
// un paramètre `person_conf` branché sur la pref conf_body.)
constexpr float kNmsIou = 0.5f;

// Marqo ViT NSFW (image entière → [NSFW, SFW] logits). Input 384×384.
constexpr base::FilePath::CharType kMarqoRelPath[] =
    FILE_PATH_LITERAL("basarunaa/models/nsfw-marqo-vit-384.onnx");
constexpr int kMarqoInputSize = 384;

// NudeNet (détecteur parties du corps, YOLO-style [1,22,2100]). Input 320×320.
// 22 = 4 (cx,cy,w,h) + 18 classes. Indices des parties EXPOSÉES (déclenchent le
// flou même sans Marqo) : cf. FLAGGED_CLASSES v1 (classifiers/nsfw.js).
constexpr base::FilePath::CharType kNudenetRelPath[] =
    FILE_PATH_LITERAL("basarunaa/models/nudenet-320.onnx");
constexpr int kNudenetInputSize = 320;
constexpr int kNudenetNumClasses = 18;
constexpr std::array<int, 6> kNudenetExposedClasses = {2, 3, 4, 5, 6, 14};

// NanoDet (sentinelle légère) retiré à la refonte 2026-07-04, et la cascade
// visage/genderage/pplcnet retirée au passage single-shot gender-v2n
// (2026-07-12) : le modèle porte directement le genre + les keypoints.

// Threads intra-op pour le détecteur single-shot gender-v2n (~640²).
// L'inférence est sérialisée globalement (analyze_mutex_) → une seule tourne à
// la fois, donc on peut lui donner plusieurs threads sans sur-souscrire. Bench
// M4 : 1 thread = 92 ms, 4 threads = ~28 ms (optimum ; 6 threads régresse par
// contention P/E-cores). Le single-shot fait tourner UN modèle (vs 5 en cascade).
constexpr int kOrtDetectorThreads = 4;

// [Browther/Basarunaa] Bascule GPU/ANE du détecteur gender-v2n via le CoreML EP.
// CoreML dispatche les gros conv sur ANE/GPU (repli CPU auto pour les ops non
// supportées), ce qui (1) sort l'inférence du CPU — qui se bat avec le décodage
// vidéo LOGICIEL sur les machines sans HW decode AV1/VP9 (grosse part de
// l'audience Windows) — et (2) réduit fortement la latence (~180 ms CPU →
// ~30-50 ms attendu).
//
// Flags = USE_NONE : CoreML choisit lui-même ANE/GPU/CPU (couverture de nœuds
// maximale). On n'active PAS ONLY_ALLOW_STATIC_INPUT_SHAPES : si le graphe ONNX
// déclare des dims dynamiques (batch/spatial), ce flag ferait rejeter les nœuds
// par CoreML → tout retomberait en CPU (GPU silencieusement désactivé). À
// retenter comme optimisation une fois le light-up GPU mesuré.
#if BUILDFLAG(IS_MAC)
constexpr uint32_t kCoreMLFlags = COREML_FLAG_USE_NONE;
#endif

// Appose l'EP GPU sur |opts| avant création de session (no-op hors mac). Best
// effort : si l'append échoue (EP indispo), on loggue et on retombe en CPU.
void AppendGpuEP(Ort::SessionOptions& opts, const char* tag) {
#if BUILDFLAG(IS_MAC)
  try {
    Ort::ThrowOnError(
        OrtSessionOptionsAppendExecutionProvider_CoreML(opts, kCoreMLFlags));
    VLOG(1) << "[Basarunaa] CoreML EP activé (" << tag << ")";
  } catch (const Ort::Exception& e) {
    LOG(WARNING) << "[Basarunaa] CoreML EP indisponible (" << tag
                 << "), repli CPU: " << e.what();
  }
#endif
}

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

// Marqo ViT NSFW (image ENTIÈRE). Port de _runMarqo (classifiers/nsfw.js) : stretch
// 384×384, NCHW, normalisation (px/255 − 0.5)/0.5 RGB, softmax sur [NSFW=0, SFW=1].
// Retourne le score NSFW [0,1], ou -1.f en cas d'échec. `bgra` géré par le sampler.
float RunMarqoNsfwScore(Ort::Session* session,
                        base::span<const uint8_t> rgba,
                        int width,
                        int height,
                        bool bgra) {
  const int size = kMarqoInputSize;
  const int plane = size * size;
  std::vector<float> nchw(3 * plane);
  for (int y = 0; y < size; ++y) {
    for (int x = 0; x < size; ++x) {
      // Stretch : image entière → 384×384 (align-centres, cf. drawImage v1).
      const float sx = (x + 0.5f) * width / size - 0.5f;
      const float sy = (y + 0.5f) * height / size - 0.5f;
      float r, g, b;
      BilinearSampleRgba(rgba, width, height, sx, sy, bgra, r, g, b);
      const int idx = y * size + x;
      nchw[idx] = (r - 0.5f) / 0.5f;
      nchw[plane + idx] = (g - 0.5f) / 0.5f;
      nchw[2 * plane + idx] = (b - 0.5f) / 0.5f;
    }
  }
  try {
    auto memory_info =
        Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);
    const std::array<int64_t, 4> shape = {1, 3, size, size};
    Ort::Value input = Ort::Value::CreateTensor<float>(
        memory_info, nchw.data(), nchw.size(), shape.data(), shape.size());
    Ort::AllocatorWithDefaultOptions alloc;
    auto in_name = session->GetInputNameAllocated(0, alloc);
    auto out_name = session->GetOutputNameAllocated(0, alloc);
    const char* in_names[] = {in_name.get()};
    const char* out_names[] = {out_name.get()};
    auto outputs = session->Run(Ort::RunOptions{nullptr}, in_names, &input, 1,
                                out_names, 1);
    const size_t out_len =
        outputs[0].GetTensorTypeAndShapeInfo().GetElementCount();
    if (out_len < 2) {
      return -1.f;
    }
    const auto out = UNSAFE_BUFFERS(
        base::span<const float>(outputs[0].GetTensorData<float>(), out_len));
    // Softmax [NSFW=0, SFW=1] → proba NSFW.
    const float l0 = out[0];
    const float l1 = out[1];
    const float m = std::max(l0, l1);
    const float e0 = std::exp(l0 - m);
    const float e1 = std::exp(l1 - m);
    return e0 / (e0 + e1);
  } catch (const Ort::Exception& e) {
    LOG(ERROR) << "[Basarunaa] marqo inference failed: " << e.what();
    return -1.f;
  }
}

// NudeNet : détecte-t-il une partie EXPOSÉE (≥ conf) ? Port de _runNudenet
// (classifiers/nsfw.js) réduit au booléen (pas de décodage bbox/NMS : pour le flou
// PLEIN CADRE on n'a besoin que de « une partie exposée existe »). Preprocess :
// letterbox 320 (gris 128), NCHW RGB /255. Sortie [1, 22, 2100] : canaux 0-3 =
// bbox, 4-21 = 18 classes ; layout data[canal*2100 + anchor].
bool RunNudenetHasExposed(Ort::Session* session,
                          base::span<const uint8_t> rgba,
                          int width,
                          int height,
                          bool bgra,
                          float nudenet_conf) {
  const int size = kNudenetInputSize;
  const int plane = size * size;
  const float scale =
      std::min(static_cast<float>(size) / width,
               static_cast<float>(size) / height);
  const float scaled_w = width * scale;
  const float scaled_h = height * scale;
  const float pad_x = (size - scaled_w) / 2.f;
  const float pad_y = (size - scaled_h) / 2.f;
  std::vector<float> nchw(3 * plane);
  for (int y = 0; y < size; ++y) {
    for (int x = 0; x < size; ++x) {
      // Letterbox inverse : pixel destination → source (gris 128 hors image).
      const float sx = (x - pad_x) / scale;
      const float sy = (y - pad_y) / scale;
      float r, g, b;
      if (sx < 0 || sy < 0 || sx >= width || sy >= height) {
        r = g = b = 128.f / 255.f;
      } else {
        BilinearSampleRgba(rgba, width, height, sx, sy, bgra, r, g, b);
      }
      const int idx = y * size + x;
      nchw[idx] = r;
      nchw[plane + idx] = g;
      nchw[2 * plane + idx] = b;
    }
  }
  try {
    auto memory_info =
        Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);
    const std::array<int64_t, 4> shape = {1, 3, size, size};
    Ort::Value input = Ort::Value::CreateTensor<float>(
        memory_info, nchw.data(), nchw.size(), shape.data(), shape.size());
    Ort::AllocatorWithDefaultOptions alloc;
    auto in_name = session->GetInputNameAllocated(0, alloc);
    auto out_name = session->GetOutputNameAllocated(0, alloc);
    const char* in_names[] = {in_name.get()};
    const char* out_names[] = {out_name.get()};
    auto outputs = session->Run(Ort::RunOptions{nullptr}, in_names, &input, 1,
                                out_names, 1);
    const auto info = outputs[0].GetTensorTypeAndShapeInfo();
    const auto dims = info.GetShape();
    if (dims.size() != 3) {
      return false;
    }
    const int num_anchors = static_cast<int>(dims[2]);  // 2100
    const size_t total = info.GetElementCount();
    const auto data = UNSAFE_BUFFERS(
        base::span<const float>(outputs[0].GetTensorData<float>(), total));
    // Pour chaque anchor : argmax des 18 classes ; si la meilleure ≥ conf ET
    // c'est une classe EXPOSÉE → flou plein cadre (court-circuit).
    for (int i = 0; i < num_anchors; ++i) {
      int best_class = 0;
      float best_conf = 0.f;
      for (int c = 0; c < kNudenetNumClasses; ++c) {
        const float conf = data[(4 + c) * num_anchors + i];
        if (conf > best_conf) {
          best_conf = conf;
          best_class = c;
        }
      }
      if (best_conf < nudenet_conf) {
        continue;
      }
      for (int ec : kNudenetExposedClasses) {
        if (best_class == ec) {
          return true;
        }
      }
    }
    return false;
  } catch (const Ort::Exception& e) {
    LOG(ERROR) << "[Basarunaa] nudenet inference failed: " << e.what();
    return false;
  }
}

}  // namespace
#endif  // defined(BASARUNAA_NATIVE_ML)

DetectedPerson::DetectedPerson() = default;
DetectedPerson::DetectedPerson(const DetectedPerson&) = default;
DetectedPerson::DetectedPerson(DetectedPerson&&) noexcept = default;
DetectedPerson& DetectedPerson::operator=(const DetectedPerson&) = default;
DetectedPerson& DetectedPerson::operator=(DetectedPerson&&) noexcept = default;
DetectedPerson::~DetectedPerson() = default;

BasarunaaService::BasarunaaService(bool eager_warmup) {
#if defined(BASARUNAA_NATIVE_ML)
  // [Browther/Basarunaa] Eager-load : la factory ne demande le warmup
  // (chargement des 6 modèles + compilation CoreML ~2s) QUE si la feature
  // vidéo ET la pref utilisateur kBasarunaaEnabled sont ON — sinon un profil
  // Basarunaa-OFF payait RAM + CPU au boot pour rien. Pref OFF → service
  // froid ; le premier AnalyzeImageRgba charge lazy (LoadAllModelsOnce).
  // Warmup posté sur le ThreadPool — jamais le thread UI (l'init ORT sur UI
  // provoquait des SEGV au spawn de threads ORT). base::Unretained : le
  // service est profile-keyed et survit à la tâche (même contrat que
  // RunYoloOnPool).
  if (eager_warmup) {
    VLOG(1) << "[Basarunaa] service constructed (eager warmup posted)";
    base::ThreadPool::PostTask(
        FROM_HERE, {base::MayBlock(), base::TaskPriority::USER_VISIBLE},
        base::BindOnce(&BasarunaaService::WarmUpModels,
                       base::Unretained(this)));
  }
#endif
}
BasarunaaService::~BasarunaaService() = default;

std::vector<DetectedPerson> BasarunaaService::AnalyzeImageRgba(
    const uint8_t* rgba,
    int width,
    int height,
    bool bgra,
    float person_conf,
    float* out_nsfw_score,
    bool* out_nsfw_exposed,
    float nudenet_conf) {
#if defined(BASARUNAA_NATIVE_ML)
  if (out_nsfw_score) {
    *out_nsfw_score = -1.f;
  }
  if (out_nsfw_exposed) {
    *out_nsfw_exposed = false;
  }
  if (!rgba || width <= 0 || height <= 0) {
    return {};
  }
  // [Browther/Basarunaa] Sérialisation GLOBALE (cf. analyze_mutex_ dans le
  // header) : une seule inférence à la fois sur la session ORT partagée, tous
  // WebContents confondus. Corrige la corruption de tas cross-onglet que le cap
  // per-WebContents de BasarunaaImageAnalyzer ne couvrait pas.
  std::lock_guard<std::mutex> lock(analyze_mutex_);
  // One-time init across worker threads (see init_flag_ docs in header). Peut
  // déjà avoir tourné via le warmup eager (WarmUpModels) — call_once garantit
  // un seul chargement.
  LoadAllModelsOnce();

  // Wrap caller-owned buffer in a span for safe indexing. The raw pointer
  // comes from a public C-style API (or SkBitmap::getPixels) so we lean on
  // UNSAFE_BUFFERS to acknowledge the construction.
  const auto rgba_span = UNSAFE_BUFFERS(base::span<const uint8_t>(
      rgba, static_cast<size_t>(width) * height * 4));

  if (!yolo_pose_ready_) {
    return {};
  }
  const auto start = base::TimeTicks::Now();

  // Preprocess.
  std::vector<float> input_tensor;
  float scale = 1.f, pad_x = 0.f, pad_y = 0.f;
  LetterboxRgbaToNchw(rgba_span, width, height, bgra, input_tensor, scale,
                      pad_x, pad_y);

  // Run.
  std::vector<float> output_data;
  int num_anchors = 0;
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
    // Sortie [1, 58, N] : on lit N (anchors) dynamiquement de la forme.
    const auto out_shape = outputs[0].GetTensorTypeAndShapeInfo().GetShape();
    if (out_shape.size() != 3 || out_shape[1] != kV2nChannels) {
      LOG(ERROR) << "[Basarunaa] forme de sortie gender-v2n inattendue "
                 << ShapeToString(out_shape) << " (attendu [1," << kV2nChannels
                 << ",N])";
      return {};
    }
    num_anchors = static_cast<int>(out_shape[2]);
    // ORT expose float* + longueur ; UNSAFE_BUFFERS comme le span d'entrée.
    const auto out_span = UNSAFE_BUFFERS(base::span<const float>(
        outputs[0].GetTensorData<float>(),
        static_cast<size_t>(kV2nChannels) * num_anchors));
    output_data.assign(out_span.begin(), out_span.end());
  } catch (const Ort::Exception& e) {
    LOG(ERROR) << "[Basarunaa] inference failed: " << e.what();
    return {};
  }

  // Décodage anchor channel-major : out[c * N + i]. Canaux 0..3 = cx,cy,w,h ;
  // 4..6 = scores des 3 classes (male/female/child) ; 7..57 = 17 keypoints × 3
  // (x, y, conf). Tout dans l'espace 640² letterbox → pixel image via (v-pad)/scale.
  constexpr int kNumKeypoints = 17;
  const int N = num_anchors;

  std::vector<DetectedPerson> raw;
  raw.reserve(64);
  for (int i = 0; i < N; ++i) {
    // Le genre = classe argmax sur les 3 scores ; sa confiance = ce score
    // (NMS class-agnostic : une personne = une boîte, la classe gagnante décide).
    float score = 0.f;
    int cls = 0;
    for (int k = 0; k < kV2nNumClasses; ++k) {
      const float s = output_data[(4 + k) * N + i];
      if (s > score) {
        score = s;
        cls = k;
      }
    }
    if (score < person_conf) {
      continue;
    }
    const float cx = output_data[0 * N + i];
    const float cy = output_data[1 * N + i];
    const float bw = output_data[2 * N + i];
    const float bh = output_data[3 * N + i];
    DetectedPerson d;
    // Centre-wh (espace 640) → top-left-wh (image originale).
    d.x = (cx - bw / 2 - pad_x) / scale;
    d.y = (cy - bh / 2 - pad_y) / scale;
    d.w = bw / scale;
    d.h = bh / scale;
    d.score = score;
    d.gender = cls == 0   ? Gender::kMale
               : cls == 1 ? Gender::kFemale
                          : Gender::kChild;
    d.gender_conf = score;

    // Décode les 17 keypoints (1er canal à kV2nKptOffset = 7).
    d.keypoints.reserve(kNumKeypoints);
    for (int k = 0; k < kNumKeypoints; ++k) {
      const int base_ch = kV2nKptOffset + k * 3;
      const float kx = output_data[base_ch * N + i];
      const float ky = output_data[(base_ch + 1) * N + i];
      const float kconf = output_data[(base_ch + 2) * N + i];
      DetectedKeyPoint kp;
      kp.x = (kx - pad_x) / scale;
      kp.y = (ky - pad_y) / scale;
      kp.confidence = kconf;
      d.keypoints.push_back(kp);
    }

    raw.push_back(std::move(d));
  }

  auto nms = NonMaxSuppression(std::move(raw));

  // NSFW image entière (Marqo, score) + NudeNet (partie exposée). Best-effort.
  // Décision finale (score≥nsfw_conf OU exposé) faite côté analyzer. Ne tourne que
  // si le RFO l'a demandé (out non-nuls = throttle ~1/s + cuts).
  if (out_nsfw_score && marqo_ready_) {
    *out_nsfw_score =
        RunMarqoNsfwScore(marqo_session_.get(), rgba_span, width, height, bgra);
  }
  if (out_nsfw_exposed && nudenet_ready_) {
    *out_nsfw_exposed = RunNudenetHasExposed(nudenet_session_.get(), rgba_span,
                                             width, height, bgra, nudenet_conf);
  }

  const auto elapsed_ms = (base::TimeTicks::Now() - start).InMillisecondsF();
  VLOG(1) << "[Basarunaa] inference: " << width << "x" << height << " → "
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

void BasarunaaService::LoadAllModelsOnce() {
  // gender-v2n (critique) + Marqo/NudeNet (NSFW, best-effort : leur échec ne
  // bloque pas la détection, le NSFW reste off). init_flag_ garantit un seul
  // chargement (warmup eager vs 1re analyse).
  std::call_once(init_flag_, [this]() {
    LoadYoloPoseModel();
    LoadMarqoModel();
    LoadNudenetModel();
  });
}

void BasarunaaService::WarmUpModels() {
  // Sérialisé avec l'inférence (analyze_mutex_) : si une vraie analyse démarre
  // en parallèle du warmup, l'un charge, l'autre attend, puis les deux voient
  // les sessions prêtes. Toujours sur le ThreadPool (posté par le constructeur).
  std::lock_guard<std::mutex> lock(analyze_mutex_);
  const auto t0 = base::TimeTicks::Now();
  LoadAllModelsOnce();
  // Force la compilation CoreML de chaque modèle : le 1er Run compile le graphe
  // ANE (~2s cumulés), c'est CE coût qui plombait la 1re frame. On le paie ici,
  // au démarrage du profil, plutôt que sur la 1re vidéo de l'utilisateur.
  WarmUpSession(yolo_pose_session_.get(), yolo_pose_ready_, "gender-v2n");
  WarmUpSession(marqo_session_.get(), marqo_ready_, "marqo");
  WarmUpSession(nudenet_session_.get(), nudenet_ready_, "nudenet");
  LOG(INFO) << "[Basarunaa] eager warmup done in "
            << (base::TimeTicks::Now() - t0).InMillisecondsF() << " ms";
}

void BasarunaaService::WarmUpSession(Ort::Session* session,
                                     bool ready,
                                     const char* tag) {
  if (!session || !ready) {
    return;
  }
  try {
    Ort::AllocatorWithDefaultOptions alloc;
    const size_t n_in = session->GetInputCount();
    const size_t n_out = session->GetOutputCount();
    auto mem = Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);

    std::vector<Ort::AllocatedStringPtr> in_holders;
    std::vector<const char*> in_names;
    std::vector<Ort::Value> inputs;
    // reserve(n_in) : pas de réallocation → les pointeurs passés à CreateTensor
    // (buffers.back().data()) restent valides jusqu'au Run.
    std::vector<std::vector<float>> buffers;
    in_holders.reserve(n_in);
    in_names.reserve(n_in);
    inputs.reserve(n_in);
    buffers.reserve(n_in);

    for (size_t i = 0; i < n_in; ++i) {
      in_holders.push_back(session->GetInputNameAllocated(i, alloc));
      in_names.push_back(in_holders.back().get());
      auto shape = session->GetInputTypeInfo(i)
                       .GetTensorTypeAndShapeInfo()
                       .GetShape();
      int64_t count = 1;
      for (auto& d : shape) {
        if (d < 0) {
          d = 1;  // dim dynamique (batch) → 1
        }
        count *= d;
      }
      if (count <= 0) {
        return;  // forme inattendue → on laisse le lazy warmer ce modèle
      }
      buffers.emplace_back(static_cast<size_t>(count), 0.f);
      inputs.push_back(Ort::Value::CreateTensor<float>(
          mem, buffers.back().data(), buffers.back().size(), shape.data(),
          shape.size()));
    }

    std::vector<Ort::AllocatedStringPtr> out_holders;
    std::vector<const char*> out_names;
    out_holders.reserve(n_out);
    out_names.reserve(n_out);
    for (size_t i = 0; i < n_out; ++i) {
      out_holders.push_back(session->GetOutputNameAllocated(i, alloc));
      out_names.push_back(out_holders.back().get());
    }

    session->Run(Ort::RunOptions{nullptr}, in_names.data(), inputs.data(), n_in,
                 out_names.data(), n_out);
  } catch (const Ort::Exception& e) {
    LOG(WARNING) << "[Basarunaa] warmup (" << tag << ") failed: " << e.what();
  }
}

void BasarunaaService::LoadYoloPoseModel() {
  const base::FilePath model_path = ResolveModelPath(kGenderV2nRelPath);
  if (!base::PathExists(model_path)) {
    LOG(WARNING) << "[Basarunaa] gender-v2n model not found at "
                 << model_path.value() << " (deploy-extensions.sh must have run)";
    return;
  }

  EnsureOrtEnv();
  if (!ort_env_) {
    return;
  }
  try {
    Ort::SessionOptions opts;
    opts.SetIntraOpNumThreads(kOrtDetectorThreads);
    opts.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);
    AppendGpuEP(opts, "gender-v2n");
    yolo_pose_session_ = std::make_unique<Ort::Session>(
        *ort_env_, model_path.value().c_str(), opts);
  } catch (const Ort::Exception& e) {
    LOG(ERROR) << "[Basarunaa] ORT gender-v2n session creation failed: "
               << e.what();
    yolo_pose_session_.reset();
    return;
  }

  Ort::AllocatorWithDefaultOptions alloc;
  const size_t inputs = yolo_pose_session_->GetInputCount();
  for (size_t i = 0; i < inputs; ++i) {
    auto name = yolo_pose_session_->GetInputNameAllocated(i, alloc);
    auto type_info = yolo_pose_session_->GetInputTypeInfo(i);
    const auto shape = type_info.GetTensorTypeAndShapeInfo().GetShape();
    VLOG(1) << "[Basarunaa] YOLO input[" << i << "] name=" << name.get()
              << " shape=" << ShapeToString(shape);
  }
  const size_t outputs = yolo_pose_session_->GetOutputCount();
  for (size_t i = 0; i < outputs; ++i) {
    auto name = yolo_pose_session_->GetOutputNameAllocated(i, alloc);
    auto type_info = yolo_pose_session_->GetOutputTypeInfo(i);
    const auto shape = type_info.GetTensorTypeAndShapeInfo().GetShape();
    VLOG(1) << "[Basarunaa] YOLO output[" << i << "] name=" << name.get()
              << " shape=" << ShapeToString(shape);
  }

  yolo_pose_ready_ = true;
  VLOG(1) << "[Basarunaa] gender-v2n session ready";
}

void BasarunaaService::LoadMarqoModel() {
  const base::FilePath model_path = ResolveModelPath(kMarqoRelPath);
  if (!base::PathExists(model_path)) {
    LOG(WARNING) << "[Basarunaa] marqo model not found at " << model_path.value()
                 << " — no NSFW full-frame blur";
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
    AppendGpuEP(opts, "marqo");
    marqo_session_ = std::make_unique<Ort::Session>(
        *ort_env_, model_path.value().c_str(), opts);
  } catch (const Ort::Exception& e) {
    LOG(ERROR) << "[Basarunaa] marqo session creation failed: " << e.what();
    marqo_session_.reset();
    return;
  }
  marqo_ready_ = true;
  VLOG(1) << "[Basarunaa] marqo session ready";
}

void BasarunaaService::LoadNudenetModel() {
  const base::FilePath model_path = ResolveModelPath(kNudenetRelPath);
  if (!base::PathExists(model_path)) {
    LOG(WARNING) << "[Basarunaa] nudenet model not found at "
                 << model_path.value() << " — no explicit-part NSFW";
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
    AppendGpuEP(opts, "nudenet");
    nudenet_session_ = std::make_unique<Ort::Session>(
        *ort_env_, model_path.value().c_str(), opts);
  } catch (const Ort::Exception& e) {
    LOG(ERROR) << "[Basarunaa] nudenet session creation failed: " << e.what();
    nudenet_session_.reset();
    return;
  }
  nudenet_ready_ = true;
  VLOG(1) << "[Basarunaa] nudenet session ready";
}

#endif  // defined(BASARUNAA_NATIVE_ML)

}  // namespace basarunaa
