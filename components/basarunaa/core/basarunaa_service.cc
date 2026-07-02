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
// avec un tenseur RGB 0-255 NCHW (3*96*96) prêt pour genderage. Retourne false
// si aucun visage exploitable (ni yeux fiables ni face_bbox).
//
// ⚠️ La ROTATION (aligner les yeux à l'horizontale) est la partie critique :
// un simple crop carré casse la classification quand les yeux ne sont pas déjà
// horizontaux (précédent FaceAlign.swift 2026-05-16, photo TF1 famille-repas).
// Les yeux = keypoints COCO 1 (left_eye) / 2 (right_eye) du YOLO11n-pose.
bool BuildAlignedFaceTensor(base::span<const uint8_t> rgba,
                            int width,
                            int height,
                            bool bgra,
                            const DetectedPerson& person,
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

  const bool has_face = person.face_bbox.has_value();
  // Yeux : keypoints COCO 1 (left_eye) et 2 (right_eye).
  const bool has_kps = person.keypoints.size() > 2;
  const DetectedKeyPoint* le = has_kps ? &person.keypoints[1] : nullptr;
  const DetectedKeyPoint* re = has_kps ? &person.keypoints[2] : nullptr;
  const bool has_eyes =
      le && re && le->confidence > 0.3f && re->confidence > 0.3f;

  if (has_eyes) {
    const float eye_dist = std::hypot(re->x - le->x, re->y - le->y);
    const float face_w = has_face
                             ? (person.face_bbox->x2 - person.face_bbox->x1)
                             : eye_dist * 2.8f;
    // Skip rotation si yeux trop proches (<5px) ou visage trop petit (<35px) :
    // les artefacts d'interpolation dégradent l'accuracy (cf. face_align.js).
    if (eye_dist >= 5.f && face_w >= 35.f) {
      const float angle = std::atan2(re->y - le->y, re->x - le->x);
      float cx, cy, face_size;
      if (has_face) {
        cx = (person.face_bbox->x1 + person.face_bbox->x2) * 0.5f;
        cy = (person.face_bbox->y1 + person.face_bbox->y2) * 0.5f;
        face_size =
            std::max(person.face_bbox->x2 - person.face_bbox->x1,
                     person.face_bbox->y2 - person.face_bbox->y1) *
            1.1f;
      } else {
        cx = (le->x + re->x) * 0.5f;
        cy = (le->y + re->y) * 0.5f + eye_dist * 0.15f;
        face_size = eye_dist * 2.8f;
      }
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
  if (!has_face) {
    return false;
  }
  const float fx1 = person.face_bbox->x1;
  const float fy1 = person.face_bbox->y1;
  const float fx2 = person.face_bbox->x2;
  const float fy2 = person.face_bbox->y2;
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
  // [Browther/Basarunaa] Sérialisation GLOBALE (cf. analyze_mutex_ dans le
  // header) : une seule inférence à la fois sur la session ORT partagée, tous
  // WebContents confondus. Corrige la corruption de tas cross-onglet que le cap
  // per-WebContents de BasarunaaImageAnalyzer ne couvrait pas.
  std::lock_guard<std::mutex> lock(analyze_mutex_);
  // One-time init across worker threads (see init_flag_ docs in header).
  // genderage chargé dans le même call_once (best-effort : son échec ne bloque
  // pas le YOLO, le genre reste juste kUnknown).
  std::call_once(init_flag_, [this]() {
    LoadYoloPoseModel();
    LoadGenderAgeModel();
    LoadPplcnetModel();
  });
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

  // Classification par personne : d'abord le VISAGE (genderage/InsightFace) ;
  // si pas de visage exploitable (dos tourné, flou…), repli CORPS (pplcnet).
  // Mirror du dual pipeline JS (_processDual) branche « no face → body only ».
  // Une personne qui reste kUnknown (ni visage ni corps classables) est
  // FLOUTÉE côté browser (« inconnu = sûr », VIDEO_V2.md §4).
  for (auto& person : nms) {
    ClassifyGender(rgba_span, width, height, bgra, person);
    if (person.gender == Gender::kUnknown) {
      ClassifyBodyGender(rgba_span, width, height, bgra, person);
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
                                      DetectedPerson& person) {
  if (!genderage_ready_) {
    return;
  }
  // Garde-fou anti-dos : n'emprunter la voie VISAGE que si le NEZ (keypoint
  // COCO 0) est franchement visible. YOLO pose HALLUCINE des keypoints de
  // visage (yeux/oreilles) même pour une personne de dos → sans ce filtre,
  // genderage tournait sur l'arrière du crâne et l'étiquetait « visage » à
  // tort. De dos, le nez est occlus (conf basse) → on laisse kUnknown → le
  // repli pplcnet (« corps ») prend le relais. Interim : le vrai fix est le
  // détecteur yolov8n-face dédié (cf. TODO §Étapes 3-4).
  constexpr float kNoseVisibleConf = 0.5f;
  if (person.keypoints.empty() ||
      person.keypoints[0].confidence < kNoseVisibleConf) {
    return;
  }
  std::vector<float> tensor;
  if (!BuildAlignedFaceTensor(rgba, width, height, bgra, person, tensor)) {
    return;  // pas de visage exploitable → reste kUnknown / -1
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
    if (female_prob > 0.5f) {
      person.gender = Gender::kFemale;
      person.gender_conf = female_prob;
    } else {
      person.gender = Gender::kMale;
      person.gender_conf = 1.f - female_prob;
    }
    person.gender_source = GenderSource::kFace;
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
    const float female_prob = out_span[kPplcnetFemaleAttr];
    if (female_prob > 0.5f) {
      person.gender = Gender::kFemale;
      person.gender_conf = female_prob;
    } else {
      person.gender = Gender::kMale;
      person.gender_conf = 1.f - female_prob;
    }
    person.gender_source = GenderSource::kBody;
  } catch (const Ort::Exception& e) {
    LOG(ERROR) << "[Basarunaa] pplcnet inference failed: " << e.what();
  }
}
#endif  // defined(BASARUNAA_NATIVE_ML)

}  // namespace basarunaa
