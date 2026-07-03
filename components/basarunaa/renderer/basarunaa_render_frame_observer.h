// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_COMPONENTS_BASARUNAA_RENDERER_BASARUNAA_RENDER_FRAME_OBSERVER_H_
#define BRAVE_COMPONENTS_BASARUNAA_RENDERER_BASARUNAA_RENDER_FRAME_OBSERVER_H_

#include <cstdint>
#include <vector>

#include "base/functional/callback.h"
#include "base/memory/weak_ptr.h"
#include "base/time/time.h"
#include "brave/components/basarunaa/common/mojom/basarunaa.mojom.h"
#include "content/public/renderer/render_frame_observer.h"
#include "content/public/renderer/render_frame_observer_tracker.h"
#include "mojo/public/cpp/bindings/remote.h"

namespace basarunaa {

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
  // décodée-en-avance et lance l'analyse ML (Mojo AnalyzeImage, kBgra8).
  void OnVideoLeadFrame(std::vector<uint8_t> bgra,
                        int width,
                        int height,
                        base::TimeDelta media_time);
  // ④a : reçoit le verdict ML (bboxes en pixels de l'image analysée
  // |width|×|height|) + le temps média, et pousse le résultat au JS de la page
  // (CustomEvent 'bsr-native-result', detail = string JSON, coords normalisées).
  void OnAnalyzed(base::TimeDelta media_time,
                  int width,
                  int height,
                  std::vector<mojom::AnalyzedPersonPtr> persons,
                  const std::string& debug_mode,
                  bool blur_enabled,
                  bool scene_cut);
  // Exécute le dispatch JS. Posté en tâche fraîche (pas dans le callback Mojo)
  // pour éviter un ExecuteScript en zone ScriptForbiddenScope.
  void DispatchResultToPage(std::string script);

  mojo::Remote<mojom::ImageAnalyzer> image_analyzer_;
  base::WeakPtrFactory<BasarunaaRenderFrameObserver> weak_ptr_factory_{this};
};

}  // namespace basarunaa

#endif  // BRAVE_COMPONENTS_BASARUNAA_RENDERER_BASARUNAA_RENDER_FRAME_OBSERVER_H_
