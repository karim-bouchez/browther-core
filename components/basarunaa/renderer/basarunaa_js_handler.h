// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_COMPONENTS_BASARUNAA_RENDERER_BASARUNAA_JS_HANDLER_H_
#define BRAVE_COMPONENTS_BASARUNAA_RENDERER_BASARUNAA_JS_HANDLER_H_

#include "base/memory/weak_ptr.h"
#include "gin/wrappable.h"
#include "v8/include/v8.h"

namespace content {
class RenderFrame;
}

namespace basarunaa {

class BasarunaaRenderFrameObserver;

// Phase 3.1.5 — M2.5. Tiny v8 binding the renderer JS uses to push freshly
// observed `<img>` elements into the native pipeline. Installed once per
// RenderFrame in the main world at `DidCreateScriptContext` and bound to
// `window.__basarunaa_native_notify`. The injected `MutationObserver` (also
// installed at DCSC) calls it for every newly inserted IMG once the image
// has decoded pixels.
//
// Lifetime: cppgc-allocated, GC'd by V8 along with the script context.
// Holds a WeakPtr to the owning RenderFrameObserver so it can no-op safely
// after frame teardown.
class BasarunaaJSHandler final : public gin::Wrappable<BasarunaaJSHandler> {
 public:
  static constexpr gin::WrapperInfo kWrapperInfo = {{gin::kEmbedderNativeGin},
                                                    gin::kBasarunaaBindings};

  // Allocates the handler via cppgc, sets up `window.__basarunaa_native_notify`
  // in `render_frame`'s main-world script context. Re-entrant: if the
  // property already exists (e.g., reload before GC), the reinstall is a
  // no-op.
  static void Install(content::RenderFrame* render_frame,
                      base::WeakPtr<BasarunaaRenderFrameObserver> observer);

  BasarunaaJSHandler(const BasarunaaJSHandler&) = delete;
  BasarunaaJSHandler& operator=(const BasarunaaJSHandler&) = delete;

 protected:
  // gin::WrappableBase
  gin::ObjectTemplateBuilder GetObjectTemplateBuilder(
      v8::Isolate* isolate) override;
  const gin::WrapperInfo* wrapper_info() const override;

 public:
  explicit BasarunaaJSHandler(
      base::WeakPtr<BasarunaaRenderFrameObserver> observer);
  ~BasarunaaJSHandler() override;

 private:

  // window.__basarunaa_native_notify(element)
  void OnImageObserved(v8::Isolate* isolate, v8::Local<v8::Value> element);

  base::WeakPtr<BasarunaaRenderFrameObserver> observer_;
};

}  // namespace basarunaa

#endif  // BRAVE_COMPONENTS_BASARUNAA_RENDERER_BASARUNAA_JS_HANDLER_H_
