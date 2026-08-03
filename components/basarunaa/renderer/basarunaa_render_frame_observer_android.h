/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

#ifndef BRAVE_COMPONENTS_BASARUNAA_RENDERER_BASARUNAA_RENDER_FRAME_OBSERVER_ANDROID_H_
#define BRAVE_COMPONENTS_BASARUNAA_RENDERER_BASARUNAA_RENDER_FRAME_OBSERVER_ANDROID_H_

#include <string>

#include "base/memory/weak_ptr.h"
#include "brave/components/basarunaa/common/mojom/basarunaa_android.mojom.h"
#include "content/public/renderer/render_frame_observer.h"
#include "mojo/public/cpp/bindings/associated_receiver_set.h"
#include "mojo/public/cpp/bindings/remote.h"

namespace basarunaa {
namespace android {

// Observer renderer-side du pipeline Basarunaa Android, un par main frame.
//
// Rôles :
//   1. Implémente `mojom::BasarunaaConfig` (browser→renderer, AssociatedInterface)
//      pour recevoir la config courante (enabled + mode + sliders + debug)
//      poussée par `BasarunaaTabHelper::PushConfigToFrame`.
//   2. Implémente `mojom::BasarunaaApply` (browser→renderer, AssociatedInterface)
//      pour recevoir le verdict d'une analyse — propage vers le main world JS
//      en évaluant `window.__basarunaaApply(...)`.
//   3. Au `DidClearWindowObject` ET quand `enabled=true`, installe le V8
//      binding `window.__basarunaa.send/isEnabled/getConfig` puis injecte
//      `basarunaa_script_android.js` dans le main world.
//   4. Au passage de la pref à false en live, dispatche `basarunaa-disable`
//      sur `window` pour que le script JS restaure les images (release
//      hide-first) et stoppe le scanner DOM.
//
// Pattern dupliqué de `SawtunaaRenderFrameObserver` (cf. Phase 3.2 Voie B).
// Suffix `_android` pour ne pas collisionner avec le spike Desktop
// `BasarunaaRenderFrameObserver` (M2 `ImageAnalyzer`) qui cohabite dans le
// même dossier renderer.
class BasarunaaRenderFrameObserverAndroid
    : public content::RenderFrameObserver,
      public mojom::BasarunaaConfig,
      public mojom::BasarunaaApply {
 public:
  explicit BasarunaaRenderFrameObserverAndroid(
      content::RenderFrame* render_frame);
  BasarunaaRenderFrameObserverAndroid(
      const BasarunaaRenderFrameObserverAndroid&) = delete;
  BasarunaaRenderFrameObserverAndroid& operator=(
      const BasarunaaRenderFrameObserverAndroid&) = delete;
  ~BasarunaaRenderFrameObserverAndroid() override;

  // content::RenderFrameObserver
  void DidClearWindowObject() override;
  void OnDestruct() override;

  // mojom::BasarunaaConfig
  void SetConfig(mojom::BasarunaaSettingsPtr settings) override;

  // mojom::BasarunaaApply
  void Apply(int32_t image_id,
             const std::string& decision,
             const std::string& persons_json,
             const std::string& debug_mode,
             double elapsed_ms) override;
  void ApplyNsfw(int32_t image_id, double score) override;

  // Lecture sync des champs config pour le JsHandler / le script JS.
  bool is_enabled() const { return settings_ && settings_->enabled; }
  const mojom::BasarunaaSettings* settings() const { return settings_.get(); }

 private:
  void BindConfigReceiver(
      mojo::PendingAssociatedReceiver<mojom::BasarunaaConfig> pending);
  void BindApplyReceiver(
      mojo::PendingAssociatedReceiver<mojom::BasarunaaApply> pending);

  // Installe `window.__basarunaa` (V8 binding) + injecte
  // `basarunaa_script_android.js`. Idempotent sur un même Window object.
  void InstallBindingAndInjectScript();

  // Dispatche `basarunaa-disable` au main world (script JS écoute).
  void DispatchDisableEvent();

  // Exécute `window.__basarunaaApply(...)` ou `window.__basarunaaApplyNsfw(...)`
  // dans le main world avec les params JSON-encodés.
  void DispatchApplyToJs(const std::string& js);

  mojo::AssociatedReceiverSet<mojom::BasarunaaConfig> config_receivers_;
  mojo::AssociatedReceiverSet<mojom::BasarunaaApply> apply_receivers_;

  // Config courante. Null tant que le browser n'a pas push (RenderFrameCreated
  // côté browser → SetConfig au RFO). Tant que null on n'injecte rien :
  // comportement Chromium standard (pas de `window.__basarunaa`).
  mojom::BasarunaaSettingsPtr settings_;

  // Suit l'injection du script pour le window object courant. Reset au
  // `DidClearWindowObject` (nouvelle Window = nouveau JS context).
  bool script_injected_ = false;

  base::WeakPtrFactory<BasarunaaRenderFrameObserverAndroid> weak_factory_{this};
};

}  // namespace android
}  // namespace basarunaa

#endif  // BRAVE_COMPONENTS_BASARUNAA_RENDERER_BASARUNAA_RENDER_FRAME_OBSERVER_ANDROID_H_
