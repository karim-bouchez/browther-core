// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/browser/sawtunaa/sawtunaa_audio_processor.h"

#include <algorithm>
#include <utility>

#include "base/containers/span.h"
#include "base/functional/bind.h"
#include "base/logging.h"
#include "base/task/thread_pool.h"
#include "brave/browser/sawtunaa/sawtunaa_audio_service_factory.h"
#include "brave/components/browther_analytics/browther_analytics_service.h"
#include "brave/components/constants/pref_names.h"
#include "brave/components/sawtunaa/core/sawtunaa_audio_service.h"
#include "components/prefs/pref_service.h"
#include "chrome/browser/profiles/profile.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/web_contents.h"
#include "mojo/public/cpp/bindings/callback_helpers.h"

namespace sawtunaa {

namespace {

// Tourne sur la séquence pool du processor. |service| est un KeyedService du
// profil : vivant tant que le profil l'est (SKIP_ON_SHUTDOWN sur la tâche).
std::pair<bool, std::vector<float>> RunNsnet2OnPool(
    SawtunaaAudioService* service,
    int64_t stream_key,
    std::vector<float> planar,
    int frames,
    int channels,
    int sample_rate,
    bool flush) {
  std::vector<float> out;
  const bool ok = service->ProcessBatch(stream_key, planar, frames, channels,
                                        sample_rate, flush, &out);
  return {ok, std::move(out)};
}

}  // namespace

// static
void SawtunaaAudioProcessor::BindReceiver(
    content::RenderFrameHost* rfh,
    mojo::PendingReceiver<mojom::AudioTapProcessor> receiver) {
  auto* web_contents = content::WebContents::FromRenderFrameHost(rfh);
  if (!web_contents) {
    return;
  }
  SawtunaaAudioProcessor::CreateForWebContents(web_contents);
  if (auto* processor = SawtunaaAudioProcessor::FromWebContents(web_contents)) {
    processor->receivers_.Add(processor, std::move(receiver),
                              processor->next_receiver_context_++);
  }
}

SawtunaaAudioProcessor::SawtunaaAudioProcessor(
    content::WebContents* web_contents)
    : content::WebContentsUserData<SawtunaaAudioProcessor>(*web_contents),
      content::WebContentsObserver(web_contents),
      task_runner_(base::ThreadPool::CreateSequencedTaskRunner(
          {base::MayBlock(), base::TaskPriority::USER_VISIBLE,
           base::TaskShutdownBehavior::SKIP_ON_SHUTDOWN})) {}

SawtunaaAudioProcessor::~SawtunaaAudioProcessor() = default;

// static
bool SawtunaaAudioProcessor::HasTappedAudio(
    content::WebContents* web_contents) {
  if (!web_contents) {
    return false;
  }
  auto* processor = FromWebContents(web_contents);
  return processor && processor->has_tapped_audio_;
}

void SawtunaaAudioProcessor::PrimaryPageChanged(content::Page& page) {
  // Nouvelle page = nouveaux WebMediaPlayer : ce qu'on a tapé avant ne dit
  // plus rien de celle-ci. Couvre aussi la restauration depuis le bfcache.
  has_tapped_audio_ = false;
}

int64_t SawtunaaAudioProcessor::MakeStreamKey(int64_t stream_id) const {
  // Contexte du receiver courant (monotone par bind) dans les 16 bits hauts,
  // stream_id renderer (croissant, petit) dans les 48 bas.
  const int64_t ctx = receivers_.current_context();
  return (ctx << 48) ^ (stream_id & ((int64_t{1} << 48) - 1));
}

void SawtunaaAudioProcessor::ProcessBatch(int64_t stream_id,
                                          mojo_base::BigBuffer pcm_planar,
                                          int32_t frames,
                                          int32_t channels,
                                          int32_t sample_rate,
                                          bool flush,
                                          ProcessBatchCallback callback) {
  const size_t expected_floats =
      static_cast<size_t>(std::max(0, frames)) *
      static_cast<size_t>(std::max(0, channels));
  // frames == 0 accepté UNIQUEMENT en flush (drain de la queue STFT en fin
  // de flux, batch vide).
  if (frames < 0 || (frames == 0 && !flush) || channels <= 0 ||
      pcm_planar.size() != expected_floats * sizeof(float)) {
    std::move(callback).Run(false, mojo_base::BigBuffer());
    return;
  }

  // Un batch valide est arrivé : le tap tourne pour cette page. C'est ce qui
  // permet au panel de ne PAS proposer un reload qui ne servirait à rien.
  has_tapped_audio_ = true;

  auto* profile =
      Profile::FromBrowserContext(GetWebContents().GetBrowserContext());
  auto* service =
      profile ? SawtunaaAudioServiceFactory::GetForProfile(profile) : nullptr;
  if (!service) {
    std::move(callback).Run(false, mojo_base::BigBuffer());
    return;
  }

  // Toggle OFF quasi-live : le switch renderer est figé à la création du
  // process (pref lue à ce moment-là) → c'est ICI, à chaque batch (UI
  // thread), que la pref courante fait foi. OFF → decline → le renderer
  // passe ce flux en passthrough définitif (musique en clair ~2 s plus tard,
  // le temps de vider le buffer d'avance déjà traité), sans reload.
  // Remettre ON reprend sur les nouveaux players (reload d'onglet) tant que
  // le process garde le switch ; un process né pendant OFF nécessite un
  // restart (comme le tap vidéo Basarunaa).
  if (!profile->GetPrefs()->GetBoolean(kSawtunaaEnabled)) {
    std::move(callback).Run(false, mojo_base::BigBuffer());
    return;
  }

  // BigBuffer (octets) → vector<float> possédé par la tâche pool.
  // allow_nonunique_obj : requis pour réinterpréter des float en octets.
  std::vector<float> planar(expected_floats);
  base::as_writable_byte_span(base::allow_nonunique_obj, planar)
      .copy_from(base::span(pcm_planar).first(expected_floats * sizeof(float)));

  // Onglet détruit pendant la tâche → le callback wrappé répond ok=false
  // (jamais de responder Mojo dangling).
  auto safe_callback = mojo::WrapCallbackWithDefaultInvokeIfNotRun(
      std::move(callback), false, mojo_base::BigBuffer());

  task_runner_->PostTaskAndReplyWithResult(
      FROM_HERE,
      base::BindOnce(&RunNsnet2OnPool, base::Unretained(service),
                     MakeStreamKey(stream_id), std::move(planar), frames,
                     channels, sample_rate, flush),
      base::BindOnce(&SawtunaaAudioProcessor::OnBatchDone,
                     weak_factory_.GetWeakPtr(), std::move(safe_callback),
                     channels, sample_rate));
}

void SawtunaaAudioProcessor::OnBatchDone(
    ProcessBatchCallback callback,
    int channels,
    int sample_rate,
    std::pair<bool, std::vector<float>> result) {
  if (!result.first) {
    std::move(callback).Run(false, mojo_base::BigBuffer());
    return;
  }

  // Stat « secondes de musique supprimée » (widget NTP + backend, gaté
  // consentement dans le service analytics) — reprend le rôle de l'extension
  // (qui ne capture plus quand le tap natif est actif). UI thread ✓.
  if (channels > 0 && sample_rate > 0) {
    music_seconds_accumulator_ +=
        static_cast<double>(result.second.size() / channels) / sample_rate;
    const int whole = static_cast<int>(music_seconds_accumulator_);
    if (whole > 0) {
      music_seconds_accumulator_ -= whole;
      browther_analytics::BrowtherAnalyticsService::GetInstance()
          ->IncrementMusicSeconds(whole);
    }
  }

  std::move(callback).Run(
      true, mojo_base::BigBuffer(
                base::as_byte_span(base::allow_nonunique_obj, result.second)));
}

void SawtunaaAudioProcessor::ResetStream(int64_t stream_id) {
  auto* profile =
      Profile::FromBrowserContext(GetWebContents().GetBrowserContext());
  auto* service =
      profile ? SawtunaaAudioServiceFactory::GetForProfile(profile) : nullptr;
  if (!service) {
    return;
  }
  task_runner_->PostTask(
      FROM_HERE, base::BindOnce(&SawtunaaAudioService::ResetStream,
                                base::Unretained(service),
                                MakeStreamKey(stream_id)));
}

void SawtunaaAudioProcessor::DestroyStream(int64_t stream_id) {
  auto* profile =
      Profile::FromBrowserContext(GetWebContents().GetBrowserContext());
  auto* service =
      profile ? SawtunaaAudioServiceFactory::GetForProfile(profile) : nullptr;
  if (!service) {
    return;
  }
  task_runner_->PostTask(
      FROM_HERE, base::BindOnce(&SawtunaaAudioService::DestroyStream,
                                base::Unretained(service),
                                MakeStreamKey(stream_id)));
}

WEB_CONTENTS_USER_DATA_KEY_IMPL(SawtunaaAudioProcessor);

}  // namespace sawtunaa
