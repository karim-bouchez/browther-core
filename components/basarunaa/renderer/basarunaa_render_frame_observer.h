// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_COMPONENTS_BASARUNAA_RENDERER_BASARUNAA_RENDER_FRAME_OBSERVER_H_
#define BRAVE_COMPONENTS_BASARUNAA_RENDERER_BASARUNAA_RENDER_FRAME_OBSERVER_H_

#include "content/public/renderer/render_frame_observer.h"

namespace basarunaa {

// Phase 3.1.5 — M2.2a. Renderer-process side of the image hook. For now this
// observer only walks `WebDocument::Images()` at `DidFinishLoad` and logs the
// dimensions of each decoded `<img>` it can read via
// `WebElement::ImageContents()`. M2.2b will hook the dynamic image lifecycle
// (MutationObserver-equivalent) and call the browser-side `ImageAnalyzer`.
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
};

}  // namespace basarunaa

#endif  // BRAVE_COMPONENTS_BASARUNAA_RENDERER_BASARUNAA_RENDER_FRAME_OBSERVER_H_
