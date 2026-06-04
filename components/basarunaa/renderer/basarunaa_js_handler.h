// Copyright (c) 2026 The Browther Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_COMPONENTS_BASARUNAA_RENDERER_BASARUNAA_JS_HANDLER_H_
#define BRAVE_COMPONENTS_BASARUNAA_RENDERER_BASARUNAA_JS_HANDLER_H_

#include "base/memory/raw_ptr.h"
#include "brave/components/basarunaa/common/mojom/basarunaa_android.mojom.h"
#include "content/public/renderer/render_frame.h"
#include "gin/wrappable.h"
#include "mojo/public/cpp/bindings/remote.h"
#include "v8/include/v8-forward.h"

namespace gin {
class Arguments;
}  // namespace gin

namespace basarunaa {
namespace android {

class BasarunaaRenderFrameObserverAndroid;

// V8 binding exposant `window.__basarunaa.send(action, data)` +
// `window.__basarunaa.isEnabled()` + `window.__basarunaa.getConfig()` au main
// world de chaque main frame committed (Android-only, gated par
// `BUILDFLAG(IS_ANDROID)` côté brave_content_renderer_client).
//
// Le script JS `basarunaa_script_android.js` (Jalon 2.G) appellera
// `send(...)` pour 5 actions (log, metric, analyzeImage, cancelAnalyze,
// pageReset), `isEnabled()` pour fail-early si la pref bascule OFF entre
// boot et premier scan, et `getConfig()` pour lire le mode + thresholds
// courants poussés par le browser.
//
// L'instance est gérée par cppgc (V8 garbage collector) : créée par
// `Install()` à `DidClearWindowObject` et libérée quand le contexte JS
// disparaît. Pas de delete manuel.
//
// La Mojo Remote vers `mojom::BasarunaaAndroid` est lazy-bindée au premier
// `send()`. Côté browser, le `BasarunaaTabHelper` reçoit les appels.
class BasarunaaJsHandler : public gin::Wrappable<BasarunaaJsHandler> {
 public:
  static constexpr gin::WrapperInfo kWrapperInfo = {
      {gin::kEmbedderNativeGin}, gin::kBasarunaaBindings};

  static void Install(content::RenderFrame* render_frame,
                      BasarunaaRenderFrameObserverAndroid* rfo);

  // Public pour cppgc::MakeGarbageCollected<>. Les callers passent par
  // Install().
  BasarunaaJsHandler(content::RenderFrame* render_frame,
                     BasarunaaRenderFrameObserverAndroid* rfo);
  BasarunaaJsHandler(const BasarunaaJsHandler&) = delete;
  BasarunaaJsHandler& operator=(const BasarunaaJsHandler&) = delete;
  ~BasarunaaJsHandler() override;

 private:
  // gin::WrappableBase
  gin::ObjectTemplateBuilder GetObjectTemplateBuilder(
      v8::Isolate* isolate) override;
  const gin::WrapperInfo* wrapper_info() const override;

  // window.__basarunaa.send(action: string, data: string?) -> void
  //
  // Actions dispatchées :
  //   "log"           → mojom::LogJs(data)
  //   "metric"        → mojom::EmitMetric(data) (data = JSON encodé)
  //   "analyzeImage"  → mojom::AnalyzeImage(imageId, bytes)
  //                     data format : "imageId|base64(bytes)"
  //   "cancelAnalyze" → mojom::CancelAnalyze(imageId) (data = imageId str)
  //   "pageReset"     → mojom::PageReset(url)
  void Send(gin::Arguments* args);

  // window.__basarunaa.isEnabled() -> bool
  // Lit la config courante poussée par le browser au RFO.
  bool IsEnabled();

  // window.__basarunaa.getConfig() -> {enabled, mode, confBody, confFace,
  // genderCertainty, debugMode}
  // Snapshot du `BasarunaaSettings` courant. Le script JS l'appelle à l'init
  // et à chaque event `basarunaa-config-changed`.
  v8::Local<v8::Object> GetConfig(gin::Arguments* args);

  bool EnsureRemote();

  // raw_ptr car ni le render_frame ni le rfo ne sont owned. cppgc nous libère
  // quand le V8 context du frame disparaît → render_frame_ encore valide.
  raw_ptr<content::RenderFrame> render_frame_;
  raw_ptr<BasarunaaRenderFrameObserverAndroid> rfo_;
  mojo::Remote<mojom::BasarunaaAndroid> basarunaa_;
};

}  // namespace android
}  // namespace basarunaa

#endif  // BRAVE_COMPONENTS_BASARUNAA_RENDERER_BASARUNAA_JS_HANDLER_H_
