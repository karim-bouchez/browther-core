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

class SawtunaaRenderFrameObserver;

// V8 binding exposing `window.__sawtunaa.send(action, data)` +
// `window.__sawtunaa.isEnabled()` to the main world of every committed
// main frame. The injected `SawtunaaScript.js` (port of iOS, Jalon 2.C.3)
// appellera `send` pour dispatch les 11 actions audio (log, metric,
// preprocess, playAt, …) au browser, et `isEnabled` pour fail-early si la
// pref `kSawtunaaEnabled` est OFF (évite d'installer un force-mute qui
// rendrait le `<video>` muet permanent quand le pipeline Java est coupé).
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

  static void Install(content::RenderFrame* render_frame,
                      SawtunaaRenderFrameObserver* rfo);

  // Public pour permettre à cppgc::MakeGarbageCollected<> d'instancier ;
  // les callers doivent quand même passer par Install() — ne pas appeler
  // directement.
  SawtunaaJsHandler(content::RenderFrame* render_frame,
                    SawtunaaRenderFrameObserver* rfo);
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

  // window.__sawtunaa.isEnabled() -> bool
  // Lit l'état courant de la pref `kSawtunaaEnabled` poussé par le browser
  // au RFO. Permet au script JS de fail-early avant `forceMuteVideo()`.
  bool IsEnabled();

  bool EnsureRemote();

  // render_frame_ est non-owned. Le handler peut survivre brièvement à la
  // RenderFrame (cppgc GC) — chaque accès doit vérifier la validité.
  // En pratique, le `Install()` est appelé à DidClearWindowObject donc le
  // handler ne devrait pas survivre la navigation, mais on protège quand
  // même au cas où.
  raw_ptr<content::RenderFrame> render_frame_;
  // rfo_ est non-owned. Le RFO survit au handler (le RFO se delete lui-même
  // sur OnDestruct). Le handler ne survit qu'au sein d'un même JS context
  // d'un frame existant. Si le frame est gone, le handler est gone aussi
  // (via cppgc). On peut donc utiliser un raw_ptr sans risque de UAF.
  raw_ptr<SawtunaaRenderFrameObserver> rfo_;
  mojo::Remote<mojom::Sawtunaa> sawtunaa_;
};

}  // namespace sawtunaa

#endif  // BRAVE_COMPONENTS_SAWTUNAA_RENDERER_SAWTUNAA_JS_HANDLER_H_
