/* Copyright (c) 2026 The Browther Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * you can obtain one at https://mozilla.org/MPL/2.0/. */

#ifndef BRAVE_COMPONENTS_SAWTUNAA_RENDERER_SAWTUNAA_RENDER_FRAME_OBSERVER_H_
#define BRAVE_COMPONENTS_SAWTUNAA_RENDERER_SAWTUNAA_RENDER_FRAME_OBSERVER_H_

#include "base/memory/weak_ptr.h"
#include "brave/components/sawtunaa/common/mojom/sawtunaa.mojom.h"
#include "content/public/renderer/render_frame_observer.h"
#include "mojo/public/cpp/bindings/associated_receiver_set.h"
#include "mojo/public/cpp/bindings/remote.h"

namespace sawtunaa {

// Observer renderer-side du pipeline Sawtunaa, par main frame :
//   1. Implémente `mojom::SawtunaaConfig` (browser→renderer, AssociatedInterface)
//      pour recevoir l'état de la pref `kSawtunaaEnabled` poussé par le browser.
//   2. Au `DidClearWindowObject`, installe le V8 binding
//      `window.__sawtunaa.send/isEnabled` puis injecte le script
//      `SawtunaaScript.js` dans le main world — pref ON ou OFF (éteint, le
//      script reste en veille).
//   3. À chaque changement de la pref, dispatche `sawtunaa-state` sur
//      `window` : le script relit `isEnabled()` et s'allume / s'éteint en
//      direct, sans rechargement (2026-10-01).
//
// Le binding `window.__sawtunaa.isEnabled()` lit `is_enabled()` ci-dessous.
class SawtunaaRenderFrameObserver : public content::RenderFrameObserver,
                                    public mojom::SawtunaaConfig {
 public:
  explicit SawtunaaRenderFrameObserver(content::RenderFrame* render_frame);
  SawtunaaRenderFrameObserver(const SawtunaaRenderFrameObserver&) = delete;
  SawtunaaRenderFrameObserver& operator=(const SawtunaaRenderFrameObserver&) =
      delete;
  ~SawtunaaRenderFrameObserver() override;

  // content::RenderFrameObserver
  void DidCommitProvisionalLoad(ui::PageTransition transition) override;
  void DidClearWindowObject() override;
  void OnDestruct() override;

  // mojom::SawtunaaConfig (browser → renderer)
  void SetEnabled(bool enabled) override;

  // Lecture sync de l'état pour le JsHandler / le script JS.
  bool is_enabled() const { return enabled_; }

 private:
  // Lazy-bind la remote vers le binder browser-side (un binder par frame).
  void EnsureRemote();

  // Bind callback pour `AssociatedInterfaceRegistry::AddInterface`.
  void BindConfigReceiver(
      mojo::PendingAssociatedReceiver<mojom::SawtunaaConfig> pending);

  // Installe `window.__sawtunaa` + injecte `SawtunaaScript.js` dans le main
  // world. Idempotent au sein d'un même Window object (script_injected_).
  void InstallBindingAndInjectScript();

  // Dispatche `sawtunaa-state` sur `window` (main world) : le script relit
  // l'état et s'allume / s'éteint.
  void DispatchStateEvent();

  mojo::Remote<mojom::Sawtunaa> sawtunaa_;
  mojo::AssociatedReceiverSet<mojom::SawtunaaConfig> config_receivers_;

  // État poussé par le browser. Défaut false : tant que le push n'est pas
  // arrivé, le script reste en veille (il ne touche pas au son) ; le push
  // le réveille via `sawtunaa-state`.
  bool enabled_ = false;

  // Suit l'injection du script pour le window object courant. Reset au
  // `DidClearWindowObject` (nouvelle Window = nouveau JS context).
  bool script_injected_ = false;

  base::WeakPtrFactory<SawtunaaRenderFrameObserver> weak_factory_{this};
};

}  // namespace sawtunaa

#endif  // BRAVE_COMPONENTS_SAWTUNAA_RENDERER_SAWTUNAA_RENDER_FRAME_OBSERVER_H_
