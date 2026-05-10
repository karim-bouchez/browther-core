// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_COMPONENTS_BASARUNAA_RENDERER_BASARUNAA_RENDER_FRAME_OBSERVER_H_
#define BRAVE_COMPONENTS_BASARUNAA_RENDERER_BASARUNAA_RENDER_FRAME_OBSERVER_H_

#include <vector>

#include "base/memory/weak_ptr.h"
#include "brave/components/basarunaa/common/mojom/basarunaa.mojom.h"
#include "content/public/renderer/render_frame_observer.h"
#include "mojo/public/cpp/bindings/remote.h"

namespace basarunaa {

// Phase 3.1.5 — Étape 2 mini-spike (2026-05-10). RFO C++ pur (pas de V8)
// qui valide le pattern Mojo IPC renderer→browser pour Basarunaa.
//
// **Spike V1** : sur `DidFinishLoad`, envoie 1 IPC `AnalyzeImage` avec un
// dummy buffer 128×128 RGBA noir. Le browser-side stub log + répond [].
// On vérifie que sous stress (rechargements rapides Google Images), aucun
// crash n'apparaît — ce qui confirmera que le bug du bridge V1 venait bien
// de la chaîne V8/cppgc et pas de Mojo+BigBuffer.
//
// Quand validé, M2.2 remplacera ce stub par un vrai hook sur les
// évènements Blink image (`ImageNotifyFinished`).
class BasarunaaRenderFrameObserver final
    : public content::RenderFrameObserver {
 public:
  explicit BasarunaaRenderFrameObserver(content::RenderFrame* render_frame);

  BasarunaaRenderFrameObserver(const BasarunaaRenderFrameObserver&) = delete;
  BasarunaaRenderFrameObserver& operator=(
      const BasarunaaRenderFrameObserver&) = delete;

 private:
  ~BasarunaaRenderFrameObserver() override;

  // RenderFrameObserver:
  void DidFinishLoad() override;
  void OnDestruct() override;

  bool EnsureConnected();
  void OnAnalyzed(std::vector<mojom::AnalyzedPersonPtr> persons);

  mojo::Remote<mojom::ImageAnalyzer> image_analyzer_;
  base::WeakPtrFactory<BasarunaaRenderFrameObserver> weak_ptr_factory_{this};
};

}  // namespace basarunaa

#endif  // BRAVE_COMPONENTS_BASARUNAA_RENDERER_BASARUNAA_RENDER_FRAME_OBSERVER_H_
