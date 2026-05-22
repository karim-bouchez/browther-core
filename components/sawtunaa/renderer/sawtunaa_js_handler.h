// Copyright (c) 2026 The Browther Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_COMPONENTS_SAWTUNAA_RENDERER_SAWTUNAA_JS_HANDLER_H_
#define BRAVE_COMPONENTS_SAWTUNAA_RENDERER_SAWTUNAA_JS_HANDLER_H_

#include "base/memory/raw_ptr.h"
#include "brave/components/sawtunaa/common/mojom/sawtunaa.mojom.h"
#include "content/public/renderer/render_frame.h"
#include "gin/wrappable.h"
#include "mojo/public/cpp/bindings/remote.h"

namespace gin {
class Arguments;
}  // namespace gin

namespace sawtunaa {

// V8 binding exposing `window.__sawtunaa.send(action, data)` to the main
// world of every committed frame. The injected `SawtunaaScript.js` (port
// of iOS, à venir au Jalon 2.C.3) appellera cette méthode pour dispatch
// les 11 actions audio (log, metric, preprocess, playAt, …) au browser.
//
// L'instance est gérée par cppgc (V8 garbage collector) : créée par
// `Install()` à `DidClearWindowObject` et libérée quand le contexte JS
// disparaît. Pas de delete manuel — pas de RenderFrameObserver.
//
// La Mojo Remote vers `sawtunaa::mojom::Sawtunaa` est lazy-bindée au
// premier `send()`. Côté browser, le `SawtunaaTabHelper` reçoit les
// appels (gated par la pref `kSawtunaaEnabled` depuis Jalon 2.B.6).
class SawtunaaJsHandler : public gin::Wrappable<SawtunaaJsHandler> {
 public:
  static constexpr gin::WrapperInfo kWrapperInfo = {
      {gin::kEmbedderNativeGin}, gin::kSawtunaaBindings};

  static void Install(content::RenderFrame* render_frame);

  // Public pour permettre à cppgc::MakeGarbageCollected<> d'instancier ;
  // les callers doivent quand même passer par Install() — ne pas appeler
  // directement.
  explicit SawtunaaJsHandler(content::RenderFrame* render_frame);
  SawtunaaJsHandler(const SawtunaaJsHandler&) = delete;
  SawtunaaJsHandler& operator=(const SawtunaaJsHandler&) = delete;
  ~SawtunaaJsHandler() override;

 private:

  // gin::WrappableBase
  gin::ObjectTemplateBuilder GetObjectTemplateBuilder(
      v8::Isolate* isolate) override;
  const gin::WrapperInfo* wrapper_info() const override;

  // window.__sawtunaa.send(action: string, data: string) -> void
  //
  // Dispatch sur `action` :
  //   "log" / "metric" / "playAt" / "clearChunks" / "pageReset" /
  //   "seekTo" / "evictRange" / "pauseAudio" / "resumeAudio" : actions
  //   simples (string ou doubles à parser depuis data).
  //   "preprocess" / "syncRanges" : data binaire/JSON, supportées partielle-
  //   ment au Jalon 2.C.2.
  void Send(gin::Arguments* args);

  bool EnsureRemote();

  // render_frame_ est non-owned. Le handler peut survivre brièvement à la
  // RenderFrame (cppgc GC) — chaque accès doit vérifier la validité.
  // En pratique, le `Install()` est appelé à DidClearWindowObject donc le
  // handler ne devrait pas survivre la navigation, mais on protège quand
  // même au cas où.
  raw_ptr<content::RenderFrame> render_frame_;
  mojo::Remote<mojom::Sawtunaa> sawtunaa_;
};

}  // namespace sawtunaa

#endif  // BRAVE_COMPONENTS_SAWTUNAA_RENDERER_SAWTUNAA_JS_HANDLER_H_
