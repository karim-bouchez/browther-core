// Copyright (c) 2026 The Browther Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_COMPONENTS_SAWTUNAA_RENDERER_SAWTUNAA_RENDER_FRAME_OBSERVER_H_
#define BRAVE_COMPONENTS_SAWTUNAA_RENDERER_SAWTUNAA_RENDER_FRAME_OBSERVER_H_

#include "brave/components/sawtunaa/common/mojom/sawtunaa.mojom.h"
#include "content/public/renderer/render_frame_observer.h"
#include "mojo/public/cpp/bindings/remote.h"

namespace sawtunaa {

// Observer renderer-side qui, pour le Jalon 2.B.4, valide la chaîne Mojo
// renderer → browser en envoyant un ping `Sawtunaa.LogJs(...)` au commit
// de navigation du main frame. Pas encore de JS injecté ni de hook MSE —
// c'est juste un témoin C++→C++ pour vérifier que :
//   1. le binder C++ (RegisterBrowserInterfaceBindersForFrame) répond,
//   2. SawtunaaTabHelper est bien créé par WebContents,
//   3. LOG(INFO) "[Sawtunaa/JS] hello..." apparaît dans logcat.
//
// La couche JS (injection user-script + bindings web platform pour qu'une
// page YouTube appelle `Sawtunaa.LogJs` depuis son main world) viendra
// avec le port `SawtunaaScript.js` au Jalon 2.C.
class SawtunaaRenderFrameObserver : public content::RenderFrameObserver {
 public:
  explicit SawtunaaRenderFrameObserver(content::RenderFrame* render_frame);
  SawtunaaRenderFrameObserver(const SawtunaaRenderFrameObserver&) = delete;
  SawtunaaRenderFrameObserver& operator=(const SawtunaaRenderFrameObserver&) =
      delete;
  ~SawtunaaRenderFrameObserver() override;

  // content::RenderFrameObserver
  void DidCommitProvisionalLoad(ui::PageTransition transition) override;
  void OnDestruct() override;

 private:
  // Lazy-bind la remote vers le binder browser-side (un binder par frame).
  void EnsureRemote();

  mojo::Remote<mojom::Sawtunaa> sawtunaa_;
};

}  // namespace sawtunaa

#endif  // BRAVE_COMPONENTS_SAWTUNAA_RENDERER_SAWTUNAA_RENDER_FRAME_OBSERVER_H_
