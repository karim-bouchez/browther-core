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
#include "third_party/blink/public/platform/web_string.h"
#include "third_party/blink/public/web/web_element.h"
#include "v8/include/v8-forward.h"

namespace basarunaa {

// Phase 3.1.5 — M2.2 + M2.3a + M2.5. Renderer-process side of the image hook.
//
// At DidFinishLoad, walks `WebDocument::All()`, picks every `<img>` element
// that has decoded pixels exposed via `WebElement::ImageContents()`, packs
// the SkBitmap into a `BigBuffer`, applies a hide-first inline `style`,
// and dispatches an `ImageAnalyzer` `AnalyzeImage` Mojo call to the
// browser process. On reply, the bboxes drive whether the blur stays
// (≥ 1 person) or gets removed (no person → restore original style).
//
// M2.5: dynamic image observer. At DidCreateScriptContext (main world only),
// installs a v8 binding `window.__basarunaa.notify(img)` and injects a
// `MutationObserver` script. The JS calls back into C++ for every newly
// inserted `<img>` once it has decoded pixels — same dispatch path,
// event-driven, no polling.
//
// One instance per `RenderFrame`. Self-deleting via `OnDestruct()` (standard
// `RenderFrameObserver` ownership pattern).
class BasarunaaRenderFrameObserver final : public content::RenderFrameObserver {
 public:
  explicit BasarunaaRenderFrameObserver(content::RenderFrame* render_frame);
  BasarunaaRenderFrameObserver(const BasarunaaRenderFrameObserver&) = delete;
  BasarunaaRenderFrameObserver& operator=(const BasarunaaRenderFrameObserver&) =
      delete;

  // Process a single `<img>` element — read its decoded SkBitmap, apply
  // hide-first inline style, dispatch AnalyzeImage, log on reply. Used both
  // by the initial DidFinishLoad scan and by the dynamic JS notifier
  // (M2.5). Public so the JS binding can call it.
  void ProcessImageElement(const blink::WebElement& element);

 private:
  ~BasarunaaRenderFrameObserver() override;

  // content::RenderFrameObserver:
  void OnDestruct() override;
  void DidFinishLoad() override;
  void DidCreateScriptContext(v8::Local<v8::Context> context,
                              int32_t world_id) override;

  // Lazy-bound; stays alive across navigations.
  const mojo::AssociatedRemote<mojom::ImageAnalyzer>& GetImageAnalyzer();

  // M2.3 — full-image blur V1.
  void OnAnalyzed(blink::WebElement element,
                  blink::WebString original_style,
                  int width,
                  int height,
                  std::vector<mojom::AnalyzedPersonPtr> persons);

  size_t images_sent_this_page_ = 0;

  mojo::AssociatedRemote<mojom::ImageAnalyzer> image_analyzer_;
  base::WeakPtrFactory<BasarunaaRenderFrameObserver> weak_ptr_factory_{this};
};

}  // namespace basarunaa

#endif  // BRAVE_COMPONENTS_BASARUNAA_RENDERER_BASARUNAA_RENDER_FRAME_OBSERVER_H_
