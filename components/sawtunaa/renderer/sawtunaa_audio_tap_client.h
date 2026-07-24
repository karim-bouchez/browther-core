// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_COMPONENTS_SAWTUNAA_RENDERER_SAWTUNAA_AUDIO_TAP_CLIENT_H_
#define BRAVE_COMPONENTS_SAWTUNAA_RENDERER_SAWTUNAA_AUDIO_TAP_CLIENT_H_

#include <cstdint>
#include <vector>

#include "base/functional/callback.h"
#include "base/memory/weak_ptr.h"
#include "brave/components/sawtunaa/common/mojom/sawtunaa.mojom.h"
#include "content/public/renderer/render_frame_observer.h"
#include "content/public/renderer/render_frame_observer_tracker.h"
#include "mojo/public/cpp/bindings/remote.h"

namespace sawtunaa {

// Audio tap V2, côté renderer : pont entre AudioRendererImpl (thread média,
// callbacks POD posés via RendererImplFactory — jumeau du LeadFrameCB vidéo)
// et l'interface Mojo AudioTapProcessor (browser, bindée sur le
// BrowserInterfaceBroker du frame, main thread).
//
// Threading : les callbacks rendus par GetProcessCallback/GetControlCallback
// sont POSTÉS sur le main thread (BindPostTask) ; le |done| reçu du media
// thread est déjà re-posté par l'appelant (BindPostTaskToCurrentDefault côté
// AudioRendererImpl) → on peut l'invoquer d'ici. Perte du pipe / frame
// détruit : |done| est wrappé DefaultInvokeIfNotRun(false, {}) → le renderer
// fait passthrough, jamais de batch bloqué.
class SawtunaaAudioTapClient
    : public content::RenderFrameObserver,
      public content::RenderFrameObserverTracker<SawtunaaAudioTapClient> {
 public:
  using ProcessDoneCB =
      base::OnceCallback<void(bool ok, std::vector<float> processed)>;
  using ProcessCB = base::RepeatingCallback<void(int64_t stream_id,
                                                 std::vector<float> planar,
                                                 int frames,
                                                 int channels,
                                                 int sample_rate,
                                                 bool flush,
                                                 ProcessDoneCB done)>;
  // |destroy| false = reset (seek/flush), true = fin de vie du player.
  using ControlCB = base::RepeatingCallback<void(int64_t stream_id,
                                                 bool destroy)>;

  // Get(render_frame) fourni par RenderFrameObserverTracker. L'instance est
  // créée par BraveContentRendererClient::RenderFrameCreated (une par frame,
  // auto-détruite avec lui).
  explicit SawtunaaAudioTapClient(content::RenderFrame* render_frame);
  SawtunaaAudioTapClient(const SawtunaaAudioTapClient&) = delete;
  SawtunaaAudioTapClient& operator=(const SawtunaaAudioTapClient&) = delete;
  ~SawtunaaAudioTapClient() override;

  // Callbacks POD prêts à traverser la couche media/ (appelables de n'importe
  // quel thread — hop main thread interne, WeakPtr gate).
  ProcessCB GetProcessCallback();
  ControlCB GetControlCallback();

 private:
  // content::RenderFrameObserver:
  void OnDestruct() override;

  void ProcessOnMainThread(int64_t stream_id,
                           std::vector<float> planar,
                           int frames,
                           int channels,
                           int sample_rate,
                           bool flush,
                           ProcessDoneCB done);
  void ControlOnMainThread(int64_t stream_id, bool destroy);
  void OnBatchReply(ProcessDoneCB done,
                    bool ok,
                    mojo_base::BigBuffer processed);

  bool EnsureConnected();

  mojo::Remote<mojom::AudioTapProcessor> processor_;

  base::WeakPtrFactory<SawtunaaAudioTapClient> weak_factory_{this};
};

}  // namespace sawtunaa

#endif  // BRAVE_COMPONENTS_SAWTUNAA_RENDERER_SAWTUNAA_AUDIO_TAP_CLIENT_H_
