// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_COMPONENTS_BASARUNAA_RENDERER_BASARUNAA_RENDERER_INSTALLER_H_
#define BRAVE_COMPONENTS_BASARUNAA_RENDERER_BASARUNAA_RENDERER_INSTALLER_H_

#include "content/public/renderer/render_frame_observer.h"

namespace basarunaa {

// Phase 3.1.5 — Phase 2 V1. RenderFrameObserver standard (heap normal,
// pas cppgc) qui hook DidCreateScriptContext et alloue/installe le
// BasarunaaJSHandler uniquement quand l'origin du frame correspond à
// celui de l'extension MV3 Basarunaa.
//
// Une instance par RenderFrame (créée depuis BraveContentRendererClient).
// Self-deleting via OnDestruct().
class BasarunaaRendererInstaller final : public content::RenderFrameObserver {
 public:
  explicit BasarunaaRendererInstaller(content::RenderFrame* render_frame);
  BasarunaaRendererInstaller(const BasarunaaRendererInstaller&) = delete;
  BasarunaaRendererInstaller& operator=(const BasarunaaRendererInstaller&) =
      delete;

 private:
  ~BasarunaaRendererInstaller() override;

  // content::RenderFrameObserver:
  void OnDestruct() override;
  void DidCreateScriptContext(v8::Local<v8::Context> context,
                              int32_t world_id) override;
};

}  // namespace basarunaa

#endif  // BRAVE_COMPONENTS_BASARUNAA_RENDERER_BASARUNAA_RENDERER_INSTALLER_H_
