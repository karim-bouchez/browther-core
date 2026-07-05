// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_COMPONENTS_BASARUNAA_RENDERER_BASARUNAA_RENDER_FRAME_OBSERVER_H_
#define BRAVE_COMPONENTS_BASARUNAA_RENDERER_BASARUNAA_RENDER_FRAME_OBSERVER_H_

#include <array>
#include <cstdint>
#include <string>
#include <vector>

#include "base/containers/span.h"
#include "base/functional/callback.h"
#include "base/memory/weak_ptr.h"
#include "base/time/time.h"
#include "brave/components/basarunaa/common/mojom/basarunaa.mojom.h"
#include "content/public/renderer/render_frame_observer.h"
#include "content/public/renderer/render_frame_observer_tracker.h"
#include "mojo/public/cpp/bindings/remote.h"

namespace basarunaa {

// Nature de la frame envoyée à l'analyse, décidée par la politique de tap du RFO
// (cf. refonte 2026-07-04). Transmise à l'overlay pour borner l'interpolation.
//  - kKeyframe  : échantillon périodique garanti (~1/s) au sein d'une scène.
//  - kCutBefore : dernière frame de l'ANCIENNE scène (n-1) → borne d'interp fin.
//  - kCutAfter  : première frame de la NOUVELLE scène (n) → snap + nouvelle borne.
enum class FrameKind { kKeyframe = 0, kCutBefore = 1, kCutAfter = 2 };

// RFO C++ pur (pas de V8) du pipeline vidéo decode-ahead Basarunaa. Expose un
// sink (GetVideoLeadFrameSink) que WebMediaPlayerImpl appelle avec chaque frame
// décodée-en-avance ; relaie le buffer BGRA au ML browser via Mojo AnalyzeImage
// (kBgra8), puis pousse le verdict (bboxes normalisées + temps média) au JS de
// la page via CustomEvent 'bsr-native-result' pour l'overlay de flou.
class BasarunaaRenderFrameObserver final
    : public content::RenderFrameObserver,
      public content::RenderFrameObserverTracker<
          BasarunaaRenderFrameObserver> {
 public:
  explicit BasarunaaRenderFrameObserver(content::RenderFrame* render_frame);

  BasarunaaRenderFrameObserver(const BasarunaaRenderFrameObserver&) = delete;
  BasarunaaRenderFrameObserver& operator=(
      const BasarunaaRenderFrameObserver&) = delete;

  // [Browther/Basarunaa] decode-ahead ③ : renvoie un sink POD (bgra, w, h,
  // media_ts) borné au cycle de vie de ce RFO (WeakPtr). Le
  // WebMediaPlayerImpl (blink) l'appelle sur le main thread avec chaque frame
  // décodée-en-avance ; on relaie au ML browser via Mojo AnalyzeImage.
  base::RepeatingCallback<void(std::vector<uint8_t>, int, int, base::TimeDelta)>
  GetVideoLeadFrameSink();

 private:
  ~BasarunaaRenderFrameObserver() override;

  // RenderFrameObserver:
  void OnDestruct() override;

  bool EnsureConnected();
  // [Browther/Basarunaa] decode-ahead ③ : reçoit un buffer BGRA d'une frame
  // décodée-en-avance. Calcule le hash 8×8, applique la politique de tap
  // (keyframe garanti + paire n-1/n de cut) et forwarde sélectivement à l'analyse.
  void OnVideoLeadFrame(std::vector<uint8_t> bgra,
                        int width,
                        int height,
                        base::TimeDelta media_time);
  // Intervalle keyframe ADAPTATIF : borné [MIN, MAX], = round-trip d'analyse
  // mesuré × facteur (défaut avant la 1re mesure). Cf. .cc.
  base::TimeDelta KeyframeInterval() const;
  // Envoie une frame à l'analyse ML (Mojo AnalyzeImage, kBgra8) en taguant sa
  // nature |kind| + le diff hash |diff| et le pic |ratio| de cette frame
  // (rattachés au résultat via le callback lié → jamais sur le fil ; servent au
  // HUD debug pour régler la détection de cut adaptative).
  void ForwardForAnalysis(base::span<const uint8_t> bgra,
                          int width,
                          int height,
                          base::TimeDelta media_time,
                          FrameKind kind,
                          float diff,
                          float ratio);
  // ④a : reçoit le verdict ML (bboxes en pixels de l'image analysée
  // |width|×|height|) + le temps média + la nature |kind| + diff/ratio de la
  // frame, et pousse le résultat au JS de la page (CustomEvent 'bsr-native-result',
  // detail = JSON, coords normalisées).
  void OnAnalyzed(base::TimeDelta media_time,
                  int width,
                  int height,
                  FrameKind kind,
                  float diff,
                  float ratio,
                  base::TimeTicks sent,
                  std::vector<mojom::AnalyzedPersonPtr> persons,
                  const std::string& debug_mode,
                  bool blur_enabled,
                  const std::string& mode,
                  double gender_certainty,
                  double min_skeleton);
  // Exécute le dispatch JS. Posté en tâche fraîche (pas dans le callback Mojo)
  // pour éviter un ExecuteScript en zone ScriptForbiddenScope.
  void DispatchResultToPage(std::string script);

  mojo::Remote<mojom::ImageAnalyzer> image_analyzer_;

  // Politique de tap (accès main thread only). |prev_*| = frame PRÉCÉDENTE tapée,
  // gardée pour pouvoir envoyer n-1 au moment d'un cut. |prev_hash_| sert au
  // frame-diff ; |last_keyframe_ts_| borne la cadence keyframe garantie.
  std::array<uint8_t, 64> prev_hash_ = {};
  bool has_prev_hash_ = false;
  std::vector<uint8_t> prev_bgra_;
  int prev_width_ = 0;
  int prev_height_ = 0;
  base::TimeDelta prev_media_time_;
  bool has_prev_frame_ = false;
  base::TimeDelta last_keyframe_ts_;
  // Détection de cut adaptative : baseline EMA du diff hash + diff/ratio de la
  // frame précédente (rattachés à n-1 quand on tape une paire de cut).
  float ema_diff_ = 0.f;
  bool ema_init_ = false;
  float prev_diff_ = 0.f;
  float prev_ratio_ = 0.f;
  // Confirmation temporelle du cut : la frame précédente était-elle un pic ? Un
  // vrai cut ne se déclenche que sur le FRONT MONTANT (pic isolé) → supprime les
  // faux cuts en rafale d'un pan/zoom (pics soutenus).
  bool prev_was_spike_ = false;
  // Intervalle keyframe adaptatif : EMA du round-trip d'analyse (keyframes).
  double analysis_ema_ms_ = 0.0;
  bool analysis_ema_init_ = false;

  base::WeakPtrFactory<BasarunaaRenderFrameObserver> weak_ptr_factory_{this};
};

}  // namespace basarunaa

#endif  // BRAVE_COMPONENTS_BASARUNAA_RENDERER_BASARUNAA_RENDER_FRAME_OBSERVER_H_
