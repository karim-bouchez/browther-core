// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/components/sawtunaa/renderer/sawtunaa_audio_tap_client.h"

#include <utility>

#include "base/command_line.h"
#include "base/containers/span.h"
#include "base/functional/bind.h"
#include "base/logging.h"
#include "third_party/blink/public/common/associated_interfaces/associated_interface_registry.h"
#include "base/task/bind_post_task.h"
#include "base/task/sequenced_task_runner.h"
#include "content/public/renderer/render_frame.h"
#include "mojo/public/cpp/bindings/callback_helpers.h"
#include "third_party/blink/public/platform/browser_interface_broker_proxy.h"

namespace sawtunaa {

SawtunaaAudioTapClient::SawtunaaAudioTapClient(
    content::RenderFrame* render_frame)
    : content::RenderFrameObserver(render_frame),
      content::RenderFrameObserverTracker<SawtunaaAudioTapClient>(
          render_frame) {
  // Capacité native du build : switch injecté par le browser sur
  // kSawtunaaNativeTapActive (indépendant de la pref utilisateur).
  native_available_ = base::CommandLine::ForCurrentProcess()->HasSwitch(
      "sawtunaa-audio-tap");
  // Pref utilisateur : poussée par SawtunaaTabHelper (SawtunaaConfig,
  // associated) à RenderFrameCreated + à chaque toggle — même canal que le
  // pipeline Android.
  render_frame->GetAssociatedInterfaceRegistry()
      ->AddInterface<mojom::SawtunaaConfig>(
          base::BindRepeating(&SawtunaaAudioTapClient::BindConfigReceiver,
                              weak_factory_.GetWeakPtr()));
}

SawtunaaAudioTapClient::~SawtunaaAudioTapClient() = default;

void SawtunaaAudioTapClient::BindConfigReceiver(
    mojo::PendingAssociatedReceiver<mojom::SawtunaaConfig> pending) {
  config_receivers_.Add(this, std::move(pending));
}

void SawtunaaAudioTapClient::SetEnabled(bool enabled) {
  pref_enabled_ = enabled;
}

void SawtunaaAudioTapClient::OnDestruct() {
  delete this;
}

bool SawtunaaAudioTapClient::EnsureConnected() {
  if (processor_.is_bound() && processor_.is_connected()) {
    return true;
  }
  processor_.reset();
  if (!render_frame()) {
    return false;
  }
  render_frame()->GetBrowserInterfaceBroker().GetInterface(
      processor_.BindNewPipeAndPassReceiver());
  return processor_.is_bound();
}

SawtunaaAudioTapClient::ProcessCB
SawtunaaAudioTapClient::GetProcessCallback() {
  // BindPostTask : appelable du thread média, exécute sur le main thread du
  // renderer (où vivent le RenderFrame et le Remote). WeakPtr : frame détruit
  // → la tâche est droppée, mais |done| doit TOUJOURS répondre → il est
  // wrappé DefaultInvokeIfNotRun côté ProcessOnMainThread… qui ne tourne pas
  // si la tâche est droppée. D'où le wrap ICI, avant le post : le done wrappé
  // répond (false, {}) à sa destruction si personne ne l'a invoqué.
  auto weak = weak_factory_.GetWeakPtr();
  auto task_runner = base::SequencedTaskRunner::GetCurrentDefault();
  return base::BindRepeating(
      [](base::WeakPtr<SawtunaaAudioTapClient> weak,
         scoped_refptr<base::SequencedTaskRunner> main_runner,
         int64_t stream_id, std::vector<float> planar, int frames,
         int channels, int sample_rate, bool flush, ProcessDoneCB done) {
        auto safe_done = mojo::WrapCallbackWithDefaultInvokeIfNotRun(
            std::move(done), false, std::vector<float>());
        main_runner->PostTask(
            FROM_HERE,
            base::BindOnce(&SawtunaaAudioTapClient::ProcessOnMainThread, weak,
                           stream_id, std::move(planar), frames, channels,
                           sample_rate, flush, std::move(safe_done)));
      },
      weak, task_runner);
}

SawtunaaAudioTapClient::ControlCB
SawtunaaAudioTapClient::GetControlCallback() {
  auto weak = weak_factory_.GetWeakPtr();
  auto task_runner = base::SequencedTaskRunner::GetCurrentDefault();
  return base::BindRepeating(
      [](base::WeakPtr<SawtunaaAudioTapClient> weak,
         scoped_refptr<base::SequencedTaskRunner> main_runner,
         int64_t stream_id, bool destroy) {
        main_runner->PostTask(
            FROM_HERE,
            base::BindOnce(&SawtunaaAudioTapClient::ControlOnMainThread, weak,
                           stream_id, destroy));
      },
      weak, task_runner);
}

void SawtunaaAudioTapClient::ProcessOnMainThread(int64_t stream_id,
                                                 std::vector<float> planar,
                                                 int frames,
                                                 int channels,
                                                 int sample_rate,
                                                 bool flush,
                                                 ProcessDoneCB done) {
  if (!EnsureConnected()) {
    std::move(done).Run(false, {});
    return;
  }
  // done wrappé une 2e fois pour la voie Mojo : pipe déconnecté avant la
  // réponse → les callbacks pending sont droppés → le wrap répond (false, {}).
  auto safe_done = mojo::WrapCallbackWithDefaultInvokeIfNotRun(
      std::move(done), false, std::vector<float>());
  processor_->ProcessBatch(
      stream_id,
      mojo_base::BigBuffer(base::as_byte_span(base::allow_nonunique_obj,
                                              planar)),
      frames, channels, sample_rate, flush,
      base::BindOnce(&SawtunaaAudioTapClient::OnBatchReply,
                     weak_factory_.GetWeakPtr(), std::move(safe_done)));
}

void SawtunaaAudioTapClient::OnBatchReply(ProcessDoneCB done,
                                          bool ok,
                                          mojo_base::BigBuffer processed) {
  if (!ok || processed.size() % sizeof(float) != 0) {
    std::move(done).Run(false, {});
    return;
  }
  std::vector<float> out(processed.size() / sizeof(float));
  base::as_writable_byte_span(base::allow_nonunique_obj, out)
      .copy_from(base::span(processed));
  std::move(done).Run(true, std::move(out));
}

void SawtunaaAudioTapClient::ControlOnMainThread(int64_t stream_id,
                                                 bool destroy) {
  if (!EnsureConnected()) {
    return;
  }
  if (destroy) {
    processor_->DestroyStream(stream_id);
  } else {
    processor_->ResetStream(stream_id);
  }
}

}  // namespace sawtunaa
