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

#include "base/containers/span.h"
#include "components/keyed_service/core/keyed_service.h"

// ⚠️ ODR : `BASARUNAA_NATIVE_ML` conditionne des MEMBRES de BasarunaaService
// ci-dessous → il change le sizeof de la classe. TOUT target GN qui inclut ce
// header ET alloue/possède un BasarunaaService (`make_unique`, membre par
// valeur…) DOIT définir ce macro de façon identique au target `core`, sinon
// débordement de tas (crash malloc free-block, incident 2026-07-02). Défini
// pour `//brave/components/basarunaa/core` ET `//brave/browser/basarunaa`.
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

// Résultat de la classification genderage (InsightFace). kUnknown = pas de
// visage exploitable → NON classifié (≠ classifié incertain). Mirror des
// valeurs 'male'/'female' du POC JS (classifiers/onnx_generic.js).
enum class Gender { kUnknown = -1, kMale = 0, kFemale = 1 };

// D'où vient la classification de genre : kFace = genderage sur le visage,
// kBody = repli pplcnet sur le corps, kNone = non classifié.
enum class GenderSource { kNone = 0, kFace = 1, kBody = 2 };

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

  // Genre FUSIONNÉ (repli simple : visage si dispo, sinon corps). kUnknown si
  // aucun des deux classé. gender_conf = confiance [0,1], ou -1.f si non classifié.
  // La VRAIE fusion + le vote temporel se font côté overlay (POC JS) à partir des
  // sorties brutes face_/body_ ci-dessous.
  Gender gender = Gender::kUnknown;
  float gender_conf = -1.f;
  GenderSource gender_source = GenderSource::kNone;

  // Sorties BRUTES par-modèle, SÉPARÉES (les DEUX tournent maintenant par
  // personne, plus de repli conditionnel) — pour fusion+vote+debug côté overlay.
  Gender face_gender = Gender::kUnknown;  // genderage (visage aligné)
  float face_conf = -1.f;
  Gender body_gender = Gender::kUnknown;  // pplcnet (corps)
  float body_conf = -1.f;
  // Corps entier visible (keypoints jambes 13-16 conf>0.3) → pplcnet fiable.
  bool has_legs = false;
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
  std::vector<DetectedPerson> AnalyzeImageRgba(
      const uint8_t* rgba,
      int width,
      int height,
      bool bgra = false);

 private:
#if defined(BASARUNAA_NATIVE_ML)
  void LoadYoloPoseModel();
  // Charge genderage.onnx (InsightFace, 96x96). Best-effort : si absent/échec,
  // gender reste kUnknown et le YOLO fonctionne toujours.
  void LoadGenderAgeModel();
  // Charge yolov8n-face.onnx (détecteur de visages dédié, 640x640, 3 têtes FPN
  // + landmarks). Best-effort.
  void LoadYoloFaceModel();
  // Aligne + classifie un VISAGE (détecté par yolov8n-face) : rotation yeux +
  // crop -> genderage. Reçoit les yeux (landmarks 1/2) + la bbox du visage
  // (port utils/face_align.js + classifiers/onnx_generic.js). Renseigne
  // person.face_gender / face_conf (sortie BRUTE visage, pas la fusion). No-op si
  // genderage indisponible ou visage non alignable (face_gender reste kUnknown).
  void ClassifyGender(base::span<const uint8_t> rgba,
                      int width,
                      int height,
                      bool bgra,
                      const DetectedKeyPoint& left_eye,
                      const DetectedKeyPoint& right_eye,
                      const DetectedFaceBbox& face_bbox,
                      DetectedPerson& person);
  // Charge pplcnet_pedestrian_attribute.onnx (PP-LCNet, 256x192). Best-effort.
  void LoadPplcnetModel();
  // Classification CORPS pplcnet : masque polygone corps + pplcnet (port de
  // classifiers/pplcnet.js + utils/body_polygon.js + utils/preprocessing.js).
  // Renseigne person.body_gender / body_conf (sortie BRUTE corps). Tourne
  // TOUJOURS (plus de repli conditionnel) : la fusion visage/corps est côté overlay.
  void ClassifyBodyGender(base::span<const uint8_t> rgba,
                          int width,
                          int height,
                          bool bgra,
                          DetectedPerson& person);

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

  // Session genderage (chargée dans le même std::call_once(init_flag_) que le
  // YOLO, donc sous la même sérialisation). Run() est thread-safe une fois
  // prête ; l'unique appelant tient déjà analyze_mutex_.
  std::unique_ptr<Ort::Session> genderage_session_;
  bool genderage_ready_ = false;

  // Session pplcnet (repli corps). Même call_once/sérialisation.
  std::unique_ptr<Ort::Session> pplcnet_session_;
  bool pplcnet_ready_ = false;

  // Session yolov8n-face (détecteur visages dédié). Même call_once.
  std::unique_ptr<Ort::Session> yolo_face_session_;
  bool yolo_face_ready_ = false;

  // [Browther/Basarunaa] Sérialise GLOBALEMENT AnalyzeImageRgba. Le service est
  // profile-keyed et partagé entre TOUS les WebContents ; le cap "1 en vol" de
  // BasarunaaImageAnalyzer est per-WebContents, donc plusieurs onglets peuvent
  // entrer ici concurremment sur la MÊME Ort::Session + le MÊME allocateur ORT
  // par défaut (GetInputNameAllocated) → corruption de tas ("free block",
  // confirmée Sentry BROWTHER-1Q). Ce mutex garantit une seule inférence à la
  // fois, tous onglets confondus. Toujours pris sur le ThreadPool (jamais le
  // thread UI) → pas de blocage UI.
  std::mutex analyze_mutex_;
#endif
};

}  // namespace basarunaa

#endif  // BRAVE_COMPONENTS_BASARUNAA_CORE_BASARUNAA_SERVICE_H_
