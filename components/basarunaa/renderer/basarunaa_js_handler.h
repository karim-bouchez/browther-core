// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_COMPONENTS_BASARUNAA_RENDERER_BASARUNAA_JS_HANDLER_H_
#define BRAVE_COMPONENTS_BASARUNAA_RENDERER_BASARUNAA_JS_HANDLER_H_

#include <string>
#include <vector>

#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "brave/components/basarunaa/common/mojom/basarunaa.mojom.h"
#include "content/public/renderer/render_frame.h"
#include "gin/wrappable.h"
#include "mojo/public/cpp/bindings/associated_remote.h"
#include "v8/include/v8.h"

namespace basarunaa {

// Phase 3.1.5 — Phase 2 V1. Bridge entre l'extension MV3 Basarunaa
// (offscreen document) et le service ML natif côté browser process.
//
// Allocation: cppgc::MakeGarbageCollected déclenchée seulement par
// `Install()` (appelée depuis BasarunaaRendererInstaller au
// DidCreateScriptContext si l'origin matche). C'est l'install dans
// `window.__basarunaa` qui maintient la référence V8 que cppgc voit.
// Allouer sans installer = GC immédiat → DidCreateScriptContext jamais
// reçu (bug observé en V1 initial).
//
// Méthode exposée :
//   window.__basarunaa.analyze(pixels, width, height, format)
//     -> Promise<Array<{x, y, w, h, score}>>
// où pixels est un Uint8Array RGBA8 ou BGRA8 packé (width*height*4 bytes)
// et format est la string 'rgba8' ou 'bgra8'.
class BasarunaaJSHandler final : public gin::Wrappable<BasarunaaJSHandler> {
 public:
  static constexpr gin::WrapperInfo kWrapperInfo = {{gin::kEmbedderNativeGin},
                                                    gin::kBasarunaaBindings};

  // Allocates the handler via cppgc et l'installe sur `window.__basarunaa`.
  // Le caller est responsable de l'origin check.
  static void Install(content::RenderFrame* render_frame,
                      v8::Local<v8::Context> context);

  explicit BasarunaaJSHandler(content::RenderFrame* render_frame);
  BasarunaaJSHandler(const BasarunaaJSHandler&) = delete;
  BasarunaaJSHandler& operator=(const BasarunaaJSHandler&) = delete;
  ~BasarunaaJSHandler() override;

 private:
  // gin::WrappableBase
  gin::ObjectTemplateBuilder GetObjectTemplateBuilder(
      v8::Isolate* isolate) override;
  const gin::WrapperInfo* wrapper_info() const override;

  bool EnsureConnected();

  // window.__basarunaa.analyze(pixels, width, height, format)
  v8::Local<v8::Promise> Analyze(v8::Isolate* isolate,
                                 v8::Local<v8::Value> pixels,
                                 int32_t width,
                                 int32_t height,
                                 std::string format);
  void OnAnalyzed(v8::Global<v8::Promise::Resolver> resolver,
                  v8::Isolate* isolate,
                  v8::Global<v8::Context> context,
                  std::vector<mojom::AnalyzedPersonPtr> persons);

  // RenderFrame est valide tant qu'il existe. Si le RF est détruit avant
  // que cppgc collecte ce JSHandler, on no-op via les checks dans
  // EnsureConnected/Analyze.
  raw_ptr<content::RenderFrame> render_frame_;

  mojo::AssociatedRemote<mojom::ImageAnalyzer> image_analyzer_;
  base::WeakPtrFactory<BasarunaaJSHandler> weak_ptr_factory_{this};
};

}  // namespace basarunaa

#endif  // BRAVE_COMPONENTS_BASARUNAA_RENDERER_BASARUNAA_JS_HANDLER_H_
