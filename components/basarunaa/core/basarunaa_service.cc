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
#include "build/build_config.h"
#include "onnxruntime_cxx_api.h"
#if BUILDFLAG(IS_MAC)
// EP GPU/ANE : le CoreML EP est compilé dans la dylib bundlée (symbole
// OrtSessionOptionsAppendExecutionProvider_CoreML exporté ; la dylib linke déjà
// CoreML.framework/Foundation → aucun ldflag à ajouter côté chrome_dll).
#include "coreml_provider_factory.h"
#endif
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
// Gris 128 (comme la v1 : `#808080`), pas 114 (ultralytics) — colle aux
// benchmarks accuracy faits sur la v1.
constexpr float kYoloPad = 128.0f / 255.0f;

// Tunables — match the POC defaults. (Le seuil de score personne est désormais
// un paramètre `person_conf` branché sur la pref conf_body.)
constexpr float kNmsIou = 0.5f;

// genderage.onnx (InsightFace). Entrée 1x3x96x96, RGB 0-255 (raw, PAS de
// normalisation ImageNet), NCHW. Sortie [1,>=2] : 2 logits genre (index 0 =
// female) suivis de l'age. Port de classifiers/onnx_generic.js (inputH/W:96,
// normalization:'raw', outputMode:'binary_softmax', femaleIndex:0).
constexpr base::FilePath::CharType kGenderAgeRelPath[] =
    FILE_PATH_LITERAL("basarunaa/models/genderage.onnx");
constexpr int kGenderInputSize = 96;

// pplcnet_pedestrian_attribute.onnx (PP-LCNet, PULC person_attribute). Entrée
// "x" [1,3,256,192] CHW ImageNet-normalisé (crop corps ÉTIRÉ, pas letterbox).
// Sortie "fetch_name_0" [1,26] probas sigmoïde ; index 22 = Female. Port de
// classifiers/pplcnet.js.
constexpr base::FilePath::CharType kPplcnetRelPath[] =
    FILE_PATH_LITERAL("basarunaa/models/pplcnet_pedestrian_attribute.onnx");
constexpr int kPplcnetInputH = 256;
constexpr int kPplcnetInputW = 192;
constexpr int kPplcnetFemaleAttr = 22;

// yolov8n-face.onnx (détecteur visages). Entrée 640x640 (même letterbox que le
// pose). 3 sorties = 3 têtes FPN [1,80,H,W] (strides 8/16/32) ; 80 = 64 (DFL
// bbox 4×16 bins) + 1 conf + 15 (5 landmarks ×3). Port de detectors/yolo_face.js.
constexpr base::FilePath::CharType kYoloFaceRelPath[] =
    FILE_PATH_LITERAL("basarunaa/models/yolov8n-face.onnx");
constexpr int kYoloFaceDflBins = 16;
// (Le seuil de confiance visage est désormais un paramètre `face_conf` branché
// sur la pref conf_face — plus de constante hardcodée à 0.5.)
constexpr float kYoloFaceIou = 0.4f;

// NanoDet (sentinelle légère) retiré à la refonte 2026-07-04 : trop bruité, et
// le nouveau flow (keyframe garanti + cut n-1/n côté renderer) n'en a plus besoin.

// Threads intra-op pour les DÉTECTEURS lourds (YOLO-pose + yolo-face, ~640²).
// L'inférence est sérialisée globalement (analyze_mutex_) → une seule tourne à
// la fois, donc on peut lui donner plusieurs threads sans sur-souscrire. Bench
// M4 : 1 thread = 92 ms/détecteur, 4 threads = ~28 ms (optimum ; 6 threads
// régresse par contention P/E-cores). → full (pose+face+genre) ~57 ms, ~17/s.
// genderage (0,6 ms) et pplcnet (6 ms) restent à 1 thread (trop petits).
constexpr int kOrtDetectorThreads = 4;

// [Browther/Basarunaa] Bascule GPU/ANE des DÉTECTEURS lourds (pose + face) via
// le CoreML EP. CoreML dispatche les gros conv sur ANE/GPU (repli CPU auto pour
// les ops non supportées), ce qui (1) sort l'inférence du CPU — qui se bat avec
// le décodage vidéo LOGICIEL sur les machines sans HW decode AV1/VP9 (grosse
// part de l'audience Windows) — et (2) réduit fortement la latence (~180 ms CPU
// → ~30-50 ms attendu). Les petits modèles (genderage 0,6 ms, pplcnet 6 ms)
// RESTENT en CPU : le dispatch CoreML n'est pas rentable sous quelques ms.
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
    LOG(INFO) << "[Basarunaa] CoreML EP activé (" << tag << ")";
  } catch (const Ort::Exception& e) {
    LOG(WARNING) << "[Basarunaa] CoreML EP indisponible (" << tag
                 << "), repli CPU: " << e.what();
  }
#endif
}

float Sigmoid(float x) {
  return 1.f / (1.f + std::exp(-x));
}

// Visage détecté par yolov8n-face : bbox + 5 landmarks en ordre COCO
// (0 nose, 1 left_eye, 2 right_eye, 3 left_mouth, 4 right_mouth).
struct DetectedFace {
  float x1 = 0.f;
  float y1 = 0.f;
  float x2 = 0.f;
  float y2 = 0.f;
  float conf = 0.f;
  std::array<DetectedKeyPoint, 5> landmarks;
};

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

// Port FIDÈLE de utils/face_align.js (alignFace + _cropFromBbox). Remplit `out`
// avec un tenseur RGB 0-255 NCHW (3*96*96) prêt pour genderage. Reçoit les yeux
// (landmarks left/right du détecteur de visages) + la bbox visage. Retourne
// toujours true (la bbox est toujours fournie) — false réservé aux cas dégénérés.
//
// ⚠️ La ROTATION (aligner les yeux à l'horizontale) est la partie critique :
// un simple crop carré casse la classification quand les yeux ne sont pas déjà
// horizontaux (précédent FaceAlign.swift 2026-05-16, photo TF1 famille-repas).
bool BuildAlignedFaceTensor(base::span<const uint8_t> rgba,
                            int width,
                            int height,
                            bool bgra,
                            const DetectedKeyPoint& le,
                            const DetectedKeyPoint& re,
                            const DetectedFaceBbox& fb,
                            std::vector<float>& out) {
  const size_t r_idx = bgra ? 2 : 0;
  const size_t b_idx = bgra ? 0 : 2;
  // Échantillon bilinéaire, RGB 0-255, padding NOIR (0) hors image — mirror du
  // drawImage canvas (les zones hors source restent transparentes/0).
  auto sample = [&](float sx, float sy, float& r, float& g, float& b) {
    if (sx < 0 || sy < 0 || sx >= width || sy >= height) {
      r = g = b = 0.f;
      return;
    }
    const int x0 = static_cast<int>(std::floor(sx));
    const int y0 = static_cast<int>(std::floor(sy));
    const int x1 = std::min(x0 + 1, width - 1);
    const int y1 = std::min(y0 + 1, height - 1);
    const float fx = sx - x0;
    const float fy = sy - y0;
    auto px = [&](int xx, int yy, float& rr, float& gg, float& bb) {
      const size_t off = static_cast<size_t>(yy * width + xx) * 4;
      rr = rgba[off + r_idx];
      gg = rgba[off + 1];
      bb = rgba[off + b_idx];
    };
    float r00, g00, b00, r10, g10, b10, r01, g01, b01, r11, g11, b11;
    px(x0, y0, r00, g00, b00);
    px(x1, y0, r10, g10, b10);
    px(x0, y1, r01, g01, b01);
    px(x1, y1, r11, g11, b11);
    const float w00 = (1 - fx) * (1 - fy);
    const float w10 = fx * (1 - fy);
    const float w01 = (1 - fx) * fy;
    const float w11 = fx * fy;
    r = r00 * w00 + r10 * w10 + r01 * w01 + r11 * w11;
    g = g00 * w00 + g10 * w10 + g01 * w01 + g11 * w11;
    b = b00 * w00 + b10 * w10 + b01 * w01 + b11 * w11;
  };

  const int kS = kGenderInputSize;
  out.assign(3 * kS * kS, 0.f);
  const int plane = kS * kS;
  auto write = [&](int dx, int dy, float r, float g, float b) {
    const int idx = dy * kS + dx;
    out[0 * plane + idx] = r;
    out[1 * plane + idx] = g;
    out[2 * plane + idx] = b;
  };

  const bool has_eyes = le.confidence > 0.3f && re.confidence > 0.3f;

  if (has_eyes) {
    const float eye_dist = std::hypot(re.x - le.x, re.y - le.y);
    const float face_w = fb.x2 - fb.x1;
    // Skip rotation si yeux trop proches (<5px) ou visage trop petit (<35px) :
    // les artefacts d'interpolation dégradent l'accuracy (cf. face_align.js).
    if (eye_dist >= 5.f && face_w >= 35.f) {
      const float angle = std::atan2(re.y - le.y, re.x - le.x);
      const float cx = (fb.x1 + fb.x2) * 0.5f;
      const float cy = (fb.y1 + fb.y2) * 0.5f;
      const float face_size =
          std::max(fb.x2 - fb.x1, fb.y2 - fb.y1) * 1.1f;
      const float scale = kS / face_size;
      const float ca = std::cos(angle);
      const float sa = std::sin(angle);
      // Pour chaque pixel de sortie, inverse de la CTM canvas
      // translate(S/2)·rotate(-angle)·scale·translate(-c) appliquée à (ix,iy).
      for (int dy = 0; dy < kS; ++dy) {
        for (int dx = 0; dx < kS; ++dx) {
          const float rx = dx - kS / 2.0f;
          const float ry = dy - kS / 2.0f;
          const float qx = rx * ca - ry * sa;
          const float qy = rx * sa + ry * ca;
          const float ix = qx / scale + cx;
          const float iy = qy / scale + cy;
          float r, g, b;
          sample(ix, iy, r, g, b);
          write(dx, dy, r, g, b);
        }
      }
      return true;
    }
  }

  // Repli _cropFromBbox : crop axis-aligned depuis face_bbox + 15% padding.
  const float fx1 = fb.x1;
  const float fy1 = fb.y1;
  const float fx2 = fb.x2;
  const float fy2 = fb.y2;
  const float fw = fx2 - fx1;
  const float fh = fy2 - fy1;
  const float max_dim = std::max(fw, fh);
  const float padding = max_dim * 0.15f;
  const float face_size = max_dim + padding * 2.f;
  const float cx = (fx1 + fx2) * 0.5f;
  const float cy = (fy1 + fy2) * 0.5f;
  const float sx0 = cx - face_size * 0.5f;
  const float sy0 = cy - face_size * 0.5f;
  for (int dy = 0; dy < kS; ++dy) {
    for (int dx = 0; dx < kS; ++dx) {
      const float ix = sx0 + (dx / static_cast<float>(kS)) * face_size;
      const float iy = sy0 + (dy / static_cast<float>(kS)) * face_size;
      float r, g, b;
      sample(ix, iy, r, g, b);
      write(dx, dy, r, g, b);
    }
  }
  return true;
}

// ---- Repli corps pplcnet : polygone corps + masque (port body_polygon.js) ----

struct PolyPoint {
  float x = 0.f;
  float y = 0.f;
};

// Andrew's monotone chain (port de _convexHull). Retourne le hull ; si < 3
// points en entrée, renvoie l'entrée telle quelle.
std::vector<PolyPoint> ConvexHull(std::vector<PolyPoint> pts) {
  if (pts.size() < 3) {
    return pts;
  }
  std::sort(pts.begin(), pts.end(), [](const PolyPoint& a, const PolyPoint& b) {
    return a.x < b.x || (a.x == b.x && a.y < b.y);
  });
  const int n = static_cast<int>(pts.size());
  auto cross = [](const PolyPoint& o, const PolyPoint& a, const PolyPoint& b) {
    return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
  };
  std::vector<PolyPoint> lower;
  for (int i = 0; i < n; ++i) {
    while (lower.size() >= 2 &&
           cross(lower[lower.size() - 2], lower[lower.size() - 1], pts[i]) <=
               0) {
      lower.pop_back();
    }
    lower.push_back(pts[i]);
  }
  std::vector<PolyPoint> upper;
  for (int i = n - 1; i >= 0; --i) {
    while (upper.size() >= 2 &&
           cross(upper[upper.size() - 2], upper[upper.size() - 1], pts[i]) <=
               0) {
      upper.pop_back();
    }
    upper.push_back(pts[i]);
  }
  lower.pop_back();
  upper.pop_back();
  lower.insert(lower.end(), upper.begin(), upper.end());
  return lower;
}

// Port FIDÈLE de buildBodyPolygon. bbox en coords pixel (x1,y1,x2,y2).
// `is_body_shaped` false = repli bbox (aucun masque appliqué côté appelant).
std::vector<PolyPoint> BuildBodyPolygon(
    const std::vector<DetectedKeyPoint>& kps,
    float bx1,
    float by1,
    float bx2,
    float by2,
    int img_w,
    int img_h,
    bool& is_body_shaped) {
  constexpr float kConf = 0.3f;
  const float bw = bx2 - bx1;
  const float bh = by2 - by1;
  auto bbox_fallback = [&]() -> std::vector<PolyPoint> {
    is_body_shaped = false;
    return {{bx1, by1}, {bx2, by1}, {bx2, by2}, {bx1, by2}};
  };
  if (kps.size() < 17) {
    return bbox_fallback();
  }
  int n_conf = 0;
  for (const auto& k : kps) {
    if (k.confidence >= kConf) {
      ++n_conf;
    }
  }
  if (n_conf < 4) {
    return bbox_fallback();
  }

  // Demi-largeur corps depuis les épaules (5,6).
  float half_width;
  if (kps[5].confidence >= kConf && kps[6].confidence >= kConf) {
    half_width = std::abs(kps[6].x - kps[5].x) * 0.55f;
  } else {
    half_width = bw * 0.25f;
  }
  half_width = std::max(half_width, bw * 0.2f);

  auto region_scale = [](int idx) -> float {
    if (idx <= 4) {
      return 0.8f;  // head
    }
    if (idx <= 6) {
      return 1.0f;  // shoulder
    }
    if (idx <= 8) {
      return 0.7f;  // elbow
    }
    if (idx <= 10) {
      return 0.6f;  // wrist
    }
    if (idx <= 12) {
      return 1.1f;  // hip
    }
    if (idx <= 14) {
      return 0.8f;  // knee
    }
    return 0.7f;  // ankle
  };

  std::vector<PolyPoint> pts;
  for (int i = 0; i < static_cast<int>(kps.size()); ++i) {
    if (kps[i].confidence < kConf) {
      continue;
    }
    const float w = half_width * region_scale(i);
    pts.push_back({kps[i].x - w, kps[i].y});
    pts.push_back({kps[i].x + w, kps[i].y});
  }

  // Padding tête au-dessus du keypoint tête le plus haut (0-4).
  {
    std::vector<int> head_kps;
    for (int i = 0; i < 5; ++i) {
      if (kps[i].confidence >= kConf) {
        head_kps.push_back(i);
      }
    }
    if (!head_kps.empty()) {
      float top_y = std::numeric_limits<float>::infinity();
      float sum_x = 0.f;
      for (int i : head_kps) {
        top_y = std::min(top_y, kps[i].y);
        sum_x += kps[i].x;
      }
      const float head_cx = sum_x / static_cast<float>(head_kps.size());
      const float head_pad_y = std::max(half_width * 0.6f, bh * 0.08f);
      const float head_pad_x = std::max(half_width * 0.9f, bw * 0.25f);
      pts.push_back({head_cx - head_pad_x, top_y - head_pad_y});
      pts.push_back({head_cx + head_pad_x, top_y - head_pad_y});
    }
  }

  // Extrapolation mains au-delà du poignet (7→9 gauche, 8→10 droite).
  auto extend_hand = [&](int elbow_idx, int wrist_idx) {
    const auto& e = kps[elbow_idx];
    const auto& wr = kps[wrist_idx];
    if (e.confidence < kConf || wr.confidence < kConf) {
      return;
    }
    const float dx = wr.x - e.x;
    const float dy = wr.y - e.y;
    const float hx = wr.x + dx * 0.3f;
    const float hy = wr.y + dy * 0.3f;
    const float w = half_width * 0.6f;
    pts.push_back({hx - w, hy});
    pts.push_back({hx + w, hy});
  };
  extend_hand(7, 9);
  extend_hand(8, 10);

  // Extension pieds sous les chevilles (15,16).
  const float foot_extend = bh * 0.08f;
  for (int ankle_idx : std::array<int, 2>{15, 16}) {
    const auto& a = kps[ankle_idx];
    if (a.confidence >= kConf) {
      const float w = half_width * 0.7f;
      pts.push_back({a.x - w, a.y + foot_extend});
      pts.push_back({a.x + w, a.y + foot_extend});
    }
  }

  std::vector<PolyPoint> hull = ConvexHull(std::move(pts));
  if (hull.size() < 3) {
    return bbox_fallback();
  }

  // Étire le polygone (forme préservée) aux bornes de la bbox.
  float p_min_x = std::numeric_limits<float>::infinity();
  float p_max_x = -std::numeric_limits<float>::infinity();
  float p_min_y = std::numeric_limits<float>::infinity();
  float p_max_y = -std::numeric_limits<float>::infinity();
  for (const auto& p : hull) {
    p_min_x = std::min(p_min_x, p.x);
    p_max_x = std::max(p_max_x, p.x);
    p_min_y = std::min(p_min_y, p.y);
    p_max_y = std::max(p_max_y, p.y);
  }
  const float p_cx = (p_min_x + p_max_x) / 2.f;
  const float p_cy = (p_min_y + p_max_y) / 2.f;
  const float bbox_cx = (bx1 + bx2) / 2.f;
  const float bbox_cy = (by1 + by2) / 2.f;
  const float px_range = p_max_x - p_min_x;
  const float py_range = p_max_y - p_min_y;
  const float sx = bw / (px_range != 0.f ? px_range : 1.f);
  const float sy = bh / (py_range != 0.f ? py_range : 1.f);
  std::vector<PolyPoint> scaled;
  scaled.reserve(hull.size());
  for (const auto& p : hull) {
    scaled.push_back(
        {bbox_cx + (p.x - p_cx) * sx, bbox_cy + (p.y - p_cy) * sy});
  }

  // Edge snapping (port _snapToEdges) : uniquement si la personne est rognée.
  const bool has_ankles =
      kps[15].confidence >= kConf || kps[16].confidence >= kConf;
  const bool has_head = kps[0].confidence >= kConf ||
                        kps[1].confidence >= kConf ||
                        kps[2].confidence >= kConf;
  constexpr float kEdge = 0.05f;
  const float fimg_w = static_cast<float>(img_w);
  const float fimg_h = static_cast<float>(img_h);
  const bool snap_bottom = !has_ankles && by2 / fimg_h > (1.f - kEdge);
  const bool snap_top = !has_head && by1 / fimg_h < kEdge;
  const bool snap_left = bx1 / fimg_w < kEdge;
  const bool snap_right = bx2 / fimg_w > (1.f - kEdge);
  is_body_shaped = true;
  if (!snap_bottom && !snap_top && !snap_left && !snap_right) {
    return scaled;
  }
  float min_x = std::numeric_limits<float>::infinity();
  float max_x = -std::numeric_limits<float>::infinity();
  float min_y = std::numeric_limits<float>::infinity();
  float max_y = -std::numeric_limits<float>::infinity();
  for (const auto& p : scaled) {
    min_x = std::min(min_x, p.x);
    max_x = std::max(max_x, p.x);
    min_y = std::min(min_y, p.y);
    max_y = std::max(max_y, p.y);
  }
  const float x_range = (max_x - min_x) != 0.f ? (max_x - min_x) : 1.f;
  const float y_range = (max_y - min_y) != 0.f ? (max_y - min_y) : 1.f;
  constexpr float kNear = 0.15f;
  for (auto& p : scaled) {
    if (snap_bottom && p.y > max_y - y_range * kNear) {
      p.y = static_cast<float>(img_h);
    }
    if (snap_top && p.y < min_y + y_range * kNear) {
      p.y = 0.f;
    }
    if (snap_left && p.x < min_x + x_range * kNear) {
      p.x = 0.f;
    }
    if (snap_right && p.x > max_x - x_range * kNear) {
      p.x = static_cast<float>(img_w);
    }
  }
  return scaled;
}

// Rasterise le polygone en masque binaire pleine image (port polygonToMask).
std::vector<uint8_t> PolygonToMask(const std::vector<PolyPoint>& points,
                                   int img_w,
                                   int img_h) {
  std::vector<uint8_t> data(static_cast<size_t>(img_w) * img_h, 0);
  if (points.size() < 3) {
    return data;
  }
  float min_yf = std::numeric_limits<float>::infinity();
  float max_yf = -std::numeric_limits<float>::infinity();
  for (const auto& p : points) {
    min_yf = std::min(min_yf, p.y);
    max_yf = std::max(max_yf, p.y);
  }
  const int min_y = std::max(0, static_cast<int>(std::floor(min_yf)));
  const int max_y = std::min(img_h - 1, static_cast<int>(std::ceil(max_yf)));
  const int np = static_cast<int>(points.size());
  std::vector<float> xs;
  for (int y = min_y; y <= max_y; ++y) {
    xs.clear();
    const float yf = static_cast<float>(y);
    for (int i = 0; i < np; ++i) {
      const PolyPoint& a = points[i];
      const PolyPoint& b = points[(i + 1) % np];
      if ((a.y <= yf && b.y > yf) || (b.y <= yf && a.y > yf)) {
        xs.push_back(a.x + (yf - a.y) / (b.y - a.y) * (b.x - a.x));
      }
    }
    std::sort(xs.begin(), xs.end());
    for (size_t i = 0; i + 1 < xs.size(); i += 2) {
      const int x1 = std::max(0, static_cast<int>(std::floor(xs[i])));
      const int x2 = std::min(img_w - 1, static_cast<int>(std::ceil(xs[i + 1])));
      for (int x = x1; x <= x2; ++x) {
        data[static_cast<size_t>(y) * img_w + x] = 1;
      }
    }
  }
  return data;
}

// ---- Détecteur de visages yolov8n-face (port detectors/yolo_face.js) ----

// NMS glouton sur des visages (bbox + conf), port utils/nms.js.
std::vector<DetectedFace> NmsFaces(std::vector<DetectedFace> faces,
                                   float iou_thr) {
  std::sort(faces.begin(), faces.end(),
            [](const DetectedFace& a, const DetectedFace& b) {
              return a.conf > b.conf;
            });
  auto iou = [](const DetectedFace& a, const DetectedFace& b) {
    const float x1 = std::max(a.x1, b.x1);
    const float y1 = std::max(a.y1, b.y1);
    const float x2 = std::min(a.x2, b.x2);
    const float y2 = std::min(a.y2, b.y2);
    const float inter = std::max(0.f, x2 - x1) * std::max(0.f, y2 - y1);
    const float ua = (a.x2 - a.x1) * (a.y2 - a.y1) +
                     (b.x2 - b.x1) * (b.y2 - b.y1) - inter;
    return ua > 0.f ? inter / ua : 0.f;
  };
  std::vector<DetectedFace> kept;
  std::vector<bool> suppressed(faces.size(), false);
  for (size_t i = 0; i < faces.size(); ++i) {
    if (suppressed[i]) {
      continue;
    }
    kept.push_back(faces[i]);
    for (size_t j = i + 1; j < faces.size(); ++j) {
      if (!suppressed[j] && iou(faces[i], faces[j]) > iou_thr) {
        suppressed[j] = true;
      }
    }
  }
  return kept;
}

// Décode les 3 têtes FPN (DFL bbox + conf + 5 landmarks), port _postprocess.
std::vector<DetectedFace> RunYoloFaceImpl(Ort::Session* session,
                                          base::span<const uint8_t> rgba,
                                          int width,
                                          int height,
                                          bool bgra,
                                          float face_conf) {
  std::vector<float> nchw;
  float scale = 1.f, pad_x = 0.f, pad_y = 0.f;
  LetterboxRgbaToNchw(rgba, width, height, bgra, nchw, scale, pad_x, pad_y);
  std::vector<DetectedFace> faces;
  try {
    auto mem = Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);
    const std::array<int64_t, 4> shape = {1, 3, kYoloInputSize, kYoloInputSize};
    Ort::Value input = Ort::Value::CreateTensor<float>(
        mem, nchw.data(), nchw.size(), shape.data(), shape.size());
    Ort::AllocatorWithDefaultOptions alloc;
    auto in_name = session->GetInputNameAllocated(0, alloc);
    const char* in_names[] = {in_name.get()};
    const size_t n_out = session->GetOutputCount();
    std::vector<Ort::AllocatedStringPtr> out_name_holders;
    std::vector<const char*> out_names;
    out_name_holders.reserve(n_out);
    out_names.reserve(n_out);
    for (size_t i = 0; i < n_out; ++i) {
      out_name_holders.push_back(session->GetOutputNameAllocated(i, alloc));
      out_names.push_back(out_name_holders.back().get());
    }
    auto outputs = session->Run(Ort::RunOptions{nullptr}, in_names, &input, 1,
                                out_names.data(), n_out);
    for (auto& output : outputs) {
      const auto dims = output.GetTensorTypeAndShapeInfo().GetShape();
      if (dims.size() != 4 || dims[1] != 80) {
        continue;
      }
      const int grid_h = static_cast<int>(dims[2]);
      const int grid_w = static_cast<int>(dims[3]);
      if (grid_h <= 0 || grid_w <= 0) {
        continue;
      }
      const int stride = kYoloInputSize / grid_h;  // 8, 16, 32
      const float stridef = static_cast<float>(stride);
      const size_t plane = static_cast<size_t>(grid_h) * grid_w;
      const auto data = UNSAFE_BUFFERS(
          base::span<const float>(output.GetTensorData<float>(), 80 * plane));
      for (int gy = 0; gy < grid_h; ++gy) {
        for (int gx = 0; gx < grid_w; ++gx) {
          const size_t cell = static_cast<size_t>(gy) * grid_w + gx;
          const float conf = Sigmoid(data[64 * plane + cell]);
          if (conf < face_conf) {
            continue;
          }
          // DFL : 4 distances (softmax sur 16 bins → somme pondérée).
          std::array<float, 4> dist = {0.f, 0.f, 0.f, 0.f};
          for (int d = 0; d < 4; ++d) {
            float maxv = -std::numeric_limits<float>::infinity();
            for (int b = 0; b < kYoloFaceDflBins; ++b) {
              maxv = std::max(
                  maxv, data[(d * kYoloFaceDflBins + b) * plane + cell]);
            }
            float sum = 0.f, wsum = 0.f;
            for (int b = 0; b < kYoloFaceDflBins; ++b) {
              const float e =
                  std::exp(data[(d * kYoloFaceDflBins + b) * plane + cell] -
                           maxv);
              sum += e;
              wsum += e * static_cast<float>(b);
            }
            dist[d] = sum > 0.f ? wsum / sum : 0.f;
          }
          const float ax = (gx + 0.5f) * stridef;
          const float ay = (gy + 0.5f) * stridef;
          DetectedFace f;
          f.x1 = std::max(0.f, (ax - dist[0] * stridef - pad_x) / scale);
          f.y1 = std::max(0.f, (ay - dist[1] * stridef - pad_y) / scale);
          f.x2 = std::min(static_cast<float>(width),
                          (ax + dist[2] * stridef - pad_x) / scale);
          f.y2 = std::min(static_cast<float>(height),
                          (ay + dist[3] * stridef - pad_y) / scale);
          f.conf = conf;
          // 5 landmarks bruts (left_eye, right_eye, nose, l_mouth, r_mouth).
          std::array<DetectedKeyPoint, 5> raw;
          for (int l = 0; l < 5; ++l) {
            const int bc = 65 + l * 3;
            const float lx = data[bc * plane + cell];
            const float ly = data[(bc + 1) * plane + cell];
            const float lv = data[(bc + 2) * plane + cell];
            raw[l].x = (lx * stridef + ax - pad_x) / scale;
            raw[l].y = (ly * stridef + ay - pad_y) / scale;
            raw[l].confidence = Sigmoid(lv);
          }
          // → ordre COCO [nose, left_eye, right_eye, l_mouth, r_mouth].
          f.landmarks[0] = raw[2];
          f.landmarks[1] = raw[0];
          f.landmarks[2] = raw[1];
          f.landmarks[3] = raw[3];
          f.landmarks[4] = raw[4];
          faces.push_back(f);
        }
      }
    }
  } catch (const Ort::Exception& e) {
    LOG(ERROR) << "[Basarunaa] yolo-face inference failed: " << e.what();
    return {};
  }
  return NmsFaces(std::move(faces), kYoloFaceIou);
}

// Matche chaque visage à une personne (port _matchFacesToBodies) : visage
// entièrement DANS la bbox personne ; assignation gloutonne par distance
// (centre visage ↔ haut-centre du corps). Retourne, par personne, l'index de
// visage matché (ou -1).
std::vector<int> MatchFacesToPersons(const std::vector<DetectedPerson>& persons,
                                     const std::vector<DetectedFace>& faces) {
  struct Pair {
    int pi;
    int fi;
    float dist;
  };
  std::vector<Pair> pairs;
  for (int pi = 0; pi < static_cast<int>(persons.size()); ++pi) {
    const float bx1 = persons[pi].x;
    const float by1 = persons[pi].y;
    const float bx2 = bx1 + persons[pi].w;
    const float by2 = by1 + persons[pi].h;
    const float bcx = (bx1 + bx2) * 0.5f;
    const float bfy = by1 + (by2 - by1) * 0.15f;
    for (int fi = 0; fi < static_cast<int>(faces.size()); ++fi) {
      const DetectedFace& f = faces[fi];
      if (f.x1 < bx1 || f.y1 < by1 || f.x2 > bx2 || f.y2 > by2) {
        continue;
      }
      const float fcx = (f.x1 + f.x2) * 0.5f;
      const float fcy = (f.y1 + f.y2) * 0.5f;
      pairs.push_back({pi, fi, std::hypot(fcx - bcx, fcy - bfy)});
    }
  }
  std::sort(pairs.begin(), pairs.end(),
            [](const Pair& a, const Pair& b) { return a.dist < b.dist; });
  std::vector<int> result(persons.size(), -1);
  std::vector<bool> used_face(faces.size(), false);
  for (const auto& p : pairs) {
    if (result[p.pi] != -1 || used_face[p.fi]) {
      continue;
    }
    result[p.pi] = p.fi;
    used_face[p.fi] = true;
  }
  return result;
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
    bool bgra,
    float person_conf,
    float face_conf) {
#if defined(BASARUNAA_NATIVE_ML)
  if (!rgba || width <= 0 || height <= 0) {
    return {};
  }
  // [Browther/Basarunaa] Sérialisation GLOBALE (cf. analyze_mutex_ dans le
  // header) : une seule inférence à la fois sur la session ORT partagée, tous
  // WebContents confondus. Corrige la corruption de tas cross-onglet que le cap
  // per-WebContents de BasarunaaImageAnalyzer ne couvrait pas.
  std::lock_guard<std::mutex> lock(analyze_mutex_);
  // One-time init across worker threads (see init_flag_ docs in header).
  // genderage/pplcnet chargés dans le même call_once (best-effort : leur échec ne
  // bloque pas le YOLO, le genre reste juste kUnknown).
  std::call_once(init_flag_, [this]() {
    LoadYoloPoseModel();
    LoadYoloFaceModel();
    LoadGenderAgeModel();
    LoadPplcnetModel();
  });

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
    if (score < person_conf) {
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

  // Détection de VISAGES dédiée (yolov8n-face) + matching visage↔personne.
  // Un vrai détecteur ne se déclenche que sur un visage réellement visible →
  // une personne de dos n'a PAS de visage matché → repli corps (pplcnet).
  std::vector<DetectedFace> faces;
  if (yolo_face_ready_) {
    faces = RunYoloFaceImpl(yolo_face_session_.get(), rgba_span, width, height,
                            bgra, face_conf);
  }
  const std::vector<int> face_of = MatchFacesToPersons(nms, faces);

  // Classification par personne : on lance TOUJOURS les DEUX modèles quand ils
  // s'appliquent — VISAGE (genderage) si un visage est matché ET CORPS (pplcnet)
  // systématiquement — et on remonte les DEUX sorties brutes séparées
  // (face_gender / body_gender). La VRAIE fusion visage/corps + le vote temporel
  // se font côté overlay (port _processDual + video_tracker, source de vérité JS).
  // Ici on ne calcule qu'une fusion-repli triviale (gender = visage si dispo,
  // sinon corps) pour le flag `blur` repli + le label. Reste kUnknown (aucun
  // classable) → FLOUTÉE côté browser (« inconnu = sûr », VIDEO_V2.md §4).
  constexpr float kLegKpVisibilityThreshold = 0.3f;
  for (size_t i = 0; i < nms.size(); ++i) {
    DetectedPerson& person = nms[i];
    const int fi = face_of[i];
    if (fi >= 0) {
      const DetectedFace& f = faces[fi];
      DetectedFaceBbox fb;
      fb.x1 = f.x1;
      fb.y1 = f.y1;
      fb.x2 = f.x2;
      fb.y2 = f.y2;
      ClassifyGender(rgba_span, width, height, bgra, f.landmarks[1],
                     f.landmarks[2], fb, person);
    }
    ClassifyBodyGender(rgba_span, width, height, bgra, person);

    // has_legs : corps entier visible (genoux/chevilles COCO 13-16) → pplcnet
    // fiable (cf. _processDual). Pilote la branche « corps partiel » de la fusion
    // overlay. Squelette absent (synthetic/incomplet) → false.
    for (int kp : {13, 14, 15, 16}) {
      if (kp < static_cast<int>(person.keypoints.size()) &&
          person.keypoints[kp].confidence > kLegKpVisibilityThreshold) {
        person.has_legs = true;
        break;
      }
    }

    // Fusion-repli triviale (le vrai cerveau est côté overlay).
    if (person.face_gender != Gender::kUnknown) {
      person.gender = person.face_gender;
      person.gender_conf = person.face_conf;
      person.gender_source = GenderSource::kFace;
    } else if (person.body_gender != Gender::kUnknown) {
      person.gender = person.body_gender;
      person.gender_conf = person.body_conf;
      person.gender_source = GenderSource::kBody;
    }
  }

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
    opts.SetIntraOpNumThreads(kOrtDetectorThreads);
    opts.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);
    AppendGpuEP(opts, "pose");
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

void BasarunaaService::LoadYoloFaceModel() {
  base::FilePath exe_dir;
  if (!base::PathService::Get(base::DIR_EXE, &exe_dir)) {
    return;
  }
  const base::FilePath model_path = exe_dir.Append(kYoloFaceRelPath);
  if (!base::PathExists(model_path)) {
    LOG(WARNING) << "[Basarunaa] yolo-face model not found at "
                 << model_path.value() << " — body fallback only";
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
    AppendGpuEP(opts, "face");
    yolo_face_session_ = std::make_unique<Ort::Session>(
        *ort_env_, model_path.value().c_str(), opts);
  } catch (const Ort::Exception& e) {
    LOG(ERROR) << "[Basarunaa] yolo-face session creation failed: " << e.what();
    yolo_face_session_.reset();
    return;
  }
  yolo_face_ready_ = true;
  LOG(INFO) << "[Basarunaa] yolov8n-face session ready";
}

void BasarunaaService::LoadGenderAgeModel() {
  base::FilePath exe_dir;
  if (!base::PathService::Get(base::DIR_EXE, &exe_dir)) {
    return;
  }
  const base::FilePath model_path = exe_dir.Append(kGenderAgeRelPath);
  if (!base::PathExists(model_path)) {
    LOG(WARNING) << "[Basarunaa] genderage model not found at "
                 << model_path.value() << " — gender stays unknown";
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
    genderage_session_ = std::make_unique<Ort::Session>(
        *ort_env_, model_path.value().c_str(), opts);
  } catch (const Ort::Exception& e) {
    LOG(ERROR) << "[Basarunaa] genderage session creation failed: " << e.what();
    genderage_session_.reset();
    return;
  }
  genderage_ready_ = true;
  LOG(INFO) << "[Basarunaa] genderage session ready";
}

void BasarunaaService::ClassifyGender(base::span<const uint8_t> rgba,
                                      int width,
                                      int height,
                                      bool bgra,
                                      const DetectedKeyPoint& left_eye,
                                      const DetectedKeyPoint& right_eye,
                                      const DetectedFaceBbox& face_bbox,
                                      DetectedPerson& person) {
  if (!genderage_ready_) {
    return;
  }
  // Le visage vient du détecteur DÉDIÉ yolov8n-face (il ne se déclenche que sur
  // un vrai visage visible → plus de faux « visage » sur les gens de dos, plus
  // besoin de garde-fou nez). On aligne depuis SES landmarks (yeux) + sa bbox.
  std::vector<float> tensor;
  if (!BuildAlignedFaceTensor(rgba, width, height, bgra, left_eye, right_eye,
                              face_bbox, tensor)) {
    return;  // visage non alignable → reste kUnknown / -1
  }
  try {
    auto memory_info =
        Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);
    const std::array<int64_t, 4> shape = {1, 3, kGenderInputSize,
                                          kGenderInputSize};
    Ort::Value input = Ort::Value::CreateTensor<float>(
        memory_info, tensor.data(), tensor.size(), shape.data(), shape.size());

    Ort::AllocatorWithDefaultOptions alloc;
    auto in_name = genderage_session_->GetInputNameAllocated(0, alloc);
    auto out_name = genderage_session_->GetOutputNameAllocated(0, alloc);
    const char* in_names[] = {in_name.get()};
    const char* out_names[] = {out_name.get()};

    auto outputs = genderage_session_->Run(Ort::RunOptions{nullptr}, in_names,
                                           &input, 1, out_names, 1);
    const size_t out_len =
        outputs[0].GetTensorTypeAndShapeInfo().GetElementCount();
    if (out_len < 2) {
      return;
    }
    const auto out_span = UNSAFE_BUFFERS(
        base::span<const float>(outputs[0].GetTensorData<float>(), out_len));
    // binary_softmax sur les 2 premiers logits, femaleIndex=0 (cf.
    // _parseOutput du POC : argmax(pred[:2]), female = probs[0]).
    const float l0 = out_span[0];
    const float l1 = out_span[1];
    const float m = std::max(l0, l1);
    const float e0 = std::exp(l0 - m);
    const float e1 = std::exp(l1 - m);
    const float female_prob = e0 / (e0 + e1);
    // Sortie BRUTE visage (face_gender/face_conf) : la fusion visage/corps est
    // désormais côté overlay (POC JS). On n'écrit PAS person.gender ici.
    if (female_prob > 0.5f) {
      person.face_gender = Gender::kFemale;
      person.face_conf = female_prob;
    } else {
      person.face_gender = Gender::kMale;
      person.face_conf = 1.f - female_prob;
    }
  } catch (const Ort::Exception& e) {
    LOG(ERROR) << "[Basarunaa] genderage inference failed: " << e.what();
  }
}

void BasarunaaService::LoadPplcnetModel() {
  base::FilePath exe_dir;
  if (!base::PathService::Get(base::DIR_EXE, &exe_dir)) {
    return;
  }
  const base::FilePath model_path = exe_dir.Append(kPplcnetRelPath);
  if (!base::PathExists(model_path)) {
    LOG(WARNING) << "[Basarunaa] pplcnet model not found at "
                 << model_path.value() << " — no body-gender fallback";
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
    pplcnet_session_ = std::make_unique<Ort::Session>(
        *ort_env_, model_path.value().c_str(), opts);
  } catch (const Ort::Exception& e) {
    LOG(ERROR) << "[Basarunaa] pplcnet session creation failed: " << e.what();
    pplcnet_session_.reset();
    return;
  }
  pplcnet_ready_ = true;
  LOG(INFO) << "[Basarunaa] pplcnet session ready";
}

void BasarunaaService::ClassifyBodyGender(base::span<const uint8_t> rgba,
                                          int width,
                                          int height,
                                          bool bgra,
                                          DetectedPerson& person) {
  if (!pplcnet_ready_) {
    return;
  }
  const float x1 = person.x;
  const float y1 = person.y;
  const float x2 = person.x + person.w;
  const float y2 = person.y + person.h;
  const float crop_w = x2 - x1;
  const float crop_h = y2 - y1;
  if (crop_w <= 0.f || crop_h <= 0.f) {
    return;
  }

  // Masque polygone corps (grise le fond), seulement si "body shaped".
  bool is_body_shaped = false;
  std::vector<PolyPoint> poly = BuildBodyPolygon(person.keypoints, x1, y1, x2,
                                                 y2, width, height,
                                                 is_body_shaped);
  std::vector<uint8_t> mask;
  if (is_body_shaped) {
    mask = PolygonToMask(poly, width, height);
  }
  const bool use_mask = !mask.empty();

  const size_t r_idx = bgra ? 2 : 0;
  const size_t b_idx = bgra ? 0 : 2;
  // Bilinéaire, RGB 0-255, padding GRIS 128 hors image (canvas gris #808080).
  auto sample = [&](float sx, float sy, float& r, float& g, float& b) {
    if (sx < 0 || sy < 0 || sx >= width || sy >= height) {
      r = g = b = 128.f;
      return;
    }
    const int x0 = static_cast<int>(std::floor(sx));
    const int y0 = static_cast<int>(std::floor(sy));
    const int xx1 = std::min(x0 + 1, width - 1);
    const int yy1 = std::min(y0 + 1, height - 1);
    const float fx = sx - x0;
    const float fy = sy - y0;
    auto px = [&](int xx, int yy, float& rr, float& gg, float& bb) {
      const size_t off = static_cast<size_t>(yy * width + xx) * 4;
      rr = rgba[off + r_idx];
      gg = rgba[off + 1];
      bb = rgba[off + b_idx];
    };
    float r00, g00, b00, r10, g10, b10, r01, g01, b01, r11, g11, b11;
    px(x0, y0, r00, g00, b00);
    px(xx1, y0, r10, g10, b10);
    px(x0, yy1, r01, g01, b01);
    px(xx1, yy1, r11, g11, b11);
    const float w00 = (1 - fx) * (1 - fy);
    const float w10 = fx * (1 - fy);
    const float w01 = (1 - fx) * fy;
    const float w11 = fx * fy;
    r = r00 * w00 + r10 * w10 + r01 * w01 + r11 * w11;
    g = g00 * w00 + g10 * w10 + g01 * w01 + g11 * w11;
    b = b00 * w00 + b10 * w10 + b01 * w01 + b11 * w11;
  };

  const int tw = kPplcnetInputW;
  const int th = kPplcnetInputH;
  const int area = tw * th;
  std::vector<float> chw(3 * area);
  const std::array<float, 3> mean = {0.485f, 0.456f, 0.406f};
  const std::array<float, 3> sdv = {0.229f, 0.224f, 0.225f};
  for (int py = 0; py < th; ++py) {
    for (int pxi = 0; pxi < tw; ++pxi) {
      const float ox = x1 + (pxi / static_cast<float>(tw)) * crop_w;
      const float oy = y1 + (py / static_cast<float>(th)) * crop_h;
      float r, g, b;
      sample(ox, oy, r, g, b);
      if (use_mask) {
        const int mox = static_cast<int>(std::lround(ox));
        const int moy = static_cast<int>(std::lround(oy));
        if (mox < 0 || mox >= width || moy < 0 || moy >= height ||
            mask[static_cast<size_t>(moy) * width + mox] == 0) {
          r = g = b = 128.f;
        }
      }
      const int i = py * tw + pxi;
      chw[i] = (r / 255.f - mean[0]) / sdv[0];
      chw[area + i] = (g / 255.f - mean[1]) / sdv[1];
      chw[2 * area + i] = (b / 255.f - mean[2]) / sdv[2];
    }
  }

  try {
    auto memory_info =
        Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);
    const std::array<int64_t, 4> shape = {1, 3, kPplcnetInputH, kPplcnetInputW};
    Ort::Value input = Ort::Value::CreateTensor<float>(
        memory_info, chw.data(), chw.size(), shape.data(), shape.size());

    Ort::AllocatorWithDefaultOptions alloc;
    auto in_name = pplcnet_session_->GetInputNameAllocated(0, alloc);
    auto out_name = pplcnet_session_->GetOutputNameAllocated(0, alloc);
    const char* in_names[] = {in_name.get()};
    const char* out_names[] = {out_name.get()};

    auto outputs = pplcnet_session_->Run(Ort::RunOptions{nullptr}, in_names,
                                         &input, 1, out_names, 1);
    const size_t out_len =
        outputs[0].GetTensorTypeAndShapeInfo().GetElementCount();
    if (static_cast<int>(out_len) <= kPplcnetFemaleAttr) {
      return;
    }
    const auto out_span = UNSAFE_BUFFERS(
        base::span<const float>(outputs[0].GetTensorData<float>(), out_len));
    // Sortie déjà en probas sigmoïde ; index 22 = Female (cf. pplcnet.js).
    // Sortie BRUTE corps (body_gender/body_conf) : fusion côté overlay.
    const float female_prob = out_span[kPplcnetFemaleAttr];
    if (female_prob > 0.5f) {
      person.body_gender = Gender::kFemale;
      person.body_conf = female_prob;
    } else {
      person.body_gender = Gender::kMale;
      person.body_conf = 1.f - female_prob;
    }
  } catch (const Ort::Exception& e) {
    LOG(ERROR) << "[Basarunaa] pplcnet inference failed: " << e.what();
  }
}
#endif  // defined(BASARUNAA_NATIVE_ML)

}  // namespace basarunaa
