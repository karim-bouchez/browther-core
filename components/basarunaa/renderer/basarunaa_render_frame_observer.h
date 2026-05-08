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
#include "mojo/public/cpp/bindings/associated_remote.h"

namespace basarunaa {

// Phase 3.1.5 — M2.2. Renderer-process side of the image hook.
//
// At DidFinishLoad, walks `WebDocument::All()`, picks every `<img>` element
// that has decoded pixels exposed via `WebElement::ImageContents()`, packs
// the SkBitmap into a `BigBuffer`, and dispatches an `ImageAnalyzer`
// `AnalyzeImage` Mojo call to the browser process. The `AnalyzedPerson`
// bboxes returned by the browser are logged for now (M2.3 will apply them
// to the DOM as a CSS hide-first overlay).
//
// One instance per `RenderFrame`. Self-deleting via `OnDestruct()` (standard
// `RenderFrameObserver` ownership pattern).
class BasarunaaRenderFrameObserver final : public content::RenderFrameObserver {
 public:
  explicit BasarunaaRenderFrameObserver(content::RenderFrame* render_frame);
  BasarunaaRenderFrameObserver(const BasarunaaRenderFrameObserver&) = delete;
  BasarunaaRenderFrameObserver& operator=(const BasarunaaRenderFrameObserver&) =
      delete;

 private:
  ~BasarunaaRenderFrameObserver() override;

  // content::RenderFrameObserver:
  void OnDestruct() override;
  void DidFinishLoad() override;

  // Lazy-bound; stays alive across navigations.
  const mojo::AssociatedRemote<mojom::ImageAnalyzer>& GetImageAnalyzer();

  // Logs the persons returned for one image (browser stub returns []
  // for now; this hook is where M2.3 will route to the hide-first path).
  void OnAnalyzed(int width,
                  int height,
                  std::vector<mojom::AnalyzedPersonPtr> persons);

  mojo::AssociatedRemote<mojom::ImageAnalyzer> image_analyzer_;
  base::WeakPtrFactory<BasarunaaRenderFrameObserver> weak_ptr_factory_{this};
};

}  // namespace basarunaa

#endif  // BRAVE_COMPONENTS_BASARUNAA_RENDERER_BASARUNAA_RENDER_FRAME_OBSERVER_H_
