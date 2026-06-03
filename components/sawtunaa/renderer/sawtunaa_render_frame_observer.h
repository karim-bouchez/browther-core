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
//   2. Au `DidClearWindowObject` ET quand la pref passe à true, installe le
//      V8 binding `window.__sawtunaa.send/isEnabled` puis injecte le script
//      `SawtunaaScript.js` dans le main world.
//   3. Au passage de la pref à false, dispatche `sawtunaa-disable` sur
//      `window` pour que le script JS restaure les descriptors muted/volume
//      natifs et stoppe son scheduler (pas de reload nécessaire).
//
// Le binding `window.__sawtunaa.isEnabled()` lit `is_enabled()` ci-dessous,
// permettant au script JS de fail-early avant d'installer le force-mute si
// la pref est OFF au moment du `DidClearWindowObject`.
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

  // Dispatche `sawtunaa-disable` sur `window` (main world) pour que le
  // script JS restaure le mute natif et stoppe.
  void DispatchDisableEvent();

  mojo::Remote<mojom::Sawtunaa> sawtunaa_;
  mojo::AssociatedReceiverSet<mojom::SawtunaaConfig> config_receivers_;

  // État poussé par le browser. Défaut false : si le push n'arrive jamais
  // (ex: process renderer démarré sans tab Sawtunaa actif), on n'injecte
  // pas → comportement Chromium normal sur les `<video>`.
  bool enabled_ = false;

  // Suit l'injection du script pour le window object courant. Reset au
  // `DidClearWindowObject` (nouvelle Window = nouveau JS context).
  bool script_injected_ = false;

  base::WeakPtrFactory<SawtunaaRenderFrameObserver> weak_factory_{this};
};

}  // namespace sawtunaa

#endif  // BRAVE_COMPONENTS_SAWTUNAA_RENDERER_SAWTUNAA_RENDER_FRAME_OBSERVER_H_
