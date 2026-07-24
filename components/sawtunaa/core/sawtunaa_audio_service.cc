// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/components/sawtunaa/core/sawtunaa_audio_service.h"

#include <utility>

#include "base/logging.h"

#if defined(SAWTUNAA_NATIVE_ML)
#include "base/files/file_path.h"
#include "base/files/file_util.h"
#include "base/functional/bind.h"
#include "base/path_service.h"
#include "base/task/thread_pool.h"
#include "base/time/time.h"
#include "brave/components/sawtunaa/core/nsnet2_stream.h"
#include "build/build_config.h"
#include "onnxruntime_cxx_api.h"
#if BUILDFLAG(IS_MAC)
#include "base/apple/bundle_locations.h"
#endif
#endif

namespace sawtunaa {

#if defined(SAWTUNAA_NATIVE_ML)
namespace {

// Modèle NSNet2 stateful, déployé avec l'extension built-in Sawtunaa
// (deploy-extensions.sh en dev Component ; staging GN Contents/Resources en
// Release signé — même mécanique que les modèles Basarunaa).
constexpr base::FilePath::CharType kNsnet2RelPath[] =
    FILE_PATH_LITERAL("sawtunaa/models/nsnet2-stateful.onnx");

// Copie de ResolveModelPath (basarunaa_service.cc) :
//   1. DIR_EXE/<rel> — dev Component + Win/Linux.
//   2. macOS : Browther.app/Contents/Resources/<rel> — Release/DMG signé.
base::FilePath ResolveModelPath(const base::FilePath::CharType* rel_path) {
  base::FilePath exe_dir;
  if (base::PathService::Get(base::DIR_EXE, &exe_dir)) {
    base::FilePath exe_path = exe_dir.Append(rel_path);
    if (base::PathExists(exe_path)) {
      return exe_path;
    }
  }
#if BUILDFLAG(IS_MAC)
  return base::apple::OuterBundlePath()
      .Append("Contents")
      .Append("Resources")
      .Append(rel_path);
#else
  return exe_dir.Append(rel_path);
#endif
}

// NSNet2 = GRU léger, inference par frame ~sub-ms : 1 thread intra-op suffit
// et évite de voler des cœurs au décodage média (l'inférence est déjà
// sérialisée globalement par process_mutex_).
constexpr int kOrtIntraOpThreads = 1;

// Filet anti-fuite : si un renderer meurt sans DestroyStream, on évince le
// stream le plus ancien au-delà de ce cap (un stream ≈ 60 Ko d'états).
constexpr size_t kMaxStreams = 64;

}  // namespace
#endif  // defined(SAWTUNAA_NATIVE_ML)

SawtunaaAudioService::SawtunaaAudioService(bool eager_warmup) {
#if defined(SAWTUNAA_NATIVE_ML)
  if (eager_warmup) {
    base::ThreadPool::PostTask(
        FROM_HERE, {base::TaskPriority::USER_VISIBLE, base::MayBlock()},
        base::BindOnce(&SawtunaaAudioService::WarmUp,
                       // Unretained OK : KeyedService détruit au shutdown du
                       // profil, après drain du ThreadPool (même contrat que
                       // le warmup BasarunaaService).
                       base::Unretained(this)));
  }
#endif
}

SawtunaaAudioService::~SawtunaaAudioService() = default;

#if defined(SAWTUNAA_NATIVE_ML)

void SawtunaaAudioService::EnsureOrtEnv() {
  std::call_once(env_init_flag_, [this]() {
    try {
      ort_env_ =
          std::make_unique<Ort::Env>(ORT_LOGGING_LEVEL_WARNING, "sawtunaa");
    } catch (const Ort::Exception& e) {
      LOG(ERROR) << "[swtTAP] ORT env creation failed: " << e.what();
    }
  });
}

void SawtunaaAudioService::LoadModelOnce() {
  std::call_once(init_flag_, [this]() {
    EnsureOrtEnv();
    if (!ort_env_) {
      return;
    }
    const base::FilePath model_path = ResolveModelPath(kNsnet2RelPath);
    if (!base::PathExists(model_path)) {
      LOG(WARNING) << "[swtTAP] NSNet2 model not found: " << model_path;
      return;
    }
    const auto t0 = base::TimeTicks::Now();
    try {
      Ort::SessionOptions opts;
      opts.SetIntraOpNumThreads(kOrtIntraOpThreads);
      opts.SetGraphOptimizationLevel(ORT_ENABLE_ALL);
      // CPU volontaire (pas de CoreML EP) : NSNet2 est léger et le pipeline
      // audio veut une latence PRÉDICTIBLE — même choix que l'extension
      // (executionProviders: ["wasm"]) et le moteur standalone.
      session_ = std::make_unique<Ort::Session>(
          *ort_env_, model_path.value().c_str(), opts);
      session_ready_ = true;
      LOG(INFO) << "[swtTAP] NSNet2 loaded in "
                << (base::TimeTicks::Now() - t0).InMillisecondsF() << " ms";
    } catch (const Ort::Exception& e) {
      LOG(ERROR) << "[swtTAP] NSNet2 load failed: " << e.what();
      session_.reset();
      session_ready_ = false;
    }
  });
}

void SawtunaaAudioService::WarmUp() {
  std::lock_guard<std::mutex> lock(process_mutex_);
  LoadModelOnce();
  if (!session_ready_) {
    return;
  }
  // Une frame de silence à travers un stream jetable : pagine les poids
  // (~25 Mo) et amorce l'arena ORT — le 1er vrai batch ne paie plus rien.
  const auto t0 = base::TimeTicks::Now();
  Nsnet2Stream warm(session_.get(), 1);
  std::vector<float> silence(Nsnet2Stream::kSampleRate / 50, 0.f);
  std::vector<float> out;
  warm.ProcessBatch(silence, static_cast<int>(silence.size()), /*flush=*/true,
                    &out);
  VLOG(1) << "[swtTAP] warmup run in "
          << (base::TimeTicks::Now() - t0).InMillisecondsF() << " ms";
}

bool SawtunaaAudioService::ProcessBatch(int64_t stream_id,
                                        base::span<const float> planar,
                                        int frames,
                                        int channels,
                                        int sample_rate,
                                        bool flush,
                                        std::vector<float>* out) {
  if (frames <= 0 || channels < 1 || channels > Nsnet2Stream::kMaxChannels) {
    return false;
  }
  // V1 : 48 kHz uniquement (modèle entraîné à 48 k). Les flux 44.1 k restent
  // en passthrough tant que le resampler aller-retour n'est pas branché
  // (AUDIO_TAP_V2.md § resampling — requis avant la bascule étape 4).
  if (sample_rate != Nsnet2Stream::kSampleRate) {
    return false;
  }
  if (planar.size() != static_cast<size_t>(frames) * channels) {
    return false;
  }

  std::lock_guard<std::mutex> lock(process_mutex_);
  LoadModelOnce();
  if (!session_ready_) {
    return false;
  }

  auto it = streams_.find(stream_id);
  if (it != streams_.end() && it->second->channels() != channels) {
    // Changement de layout mid-stream (config change) : repartir propre.
    streams_.erase(it);
    it = streams_.end();
  }
  if (it == streams_.end()) {
    if (streams_.size() >= kMaxStreams) {
      // Filet : évince le plus ancien (map ordonnée par id croissant ; les
      // ids sont attribués croissants côté renderer).
      streams_.erase(streams_.begin());
    }
    it = streams_
             .emplace(stream_id,
                      std::make_unique<Nsnet2Stream>(session_.get(), channels))
             .first;
  }
  return it->second->ProcessBatch(planar, frames, flush, out);
}

void SawtunaaAudioService::ResetStream(int64_t stream_id) {
  std::lock_guard<std::mutex> lock(process_mutex_);
  auto it = streams_.find(stream_id);
  if (it != streams_.end()) {
    it->second->Reset();
  }
}

void SawtunaaAudioService::DestroyStream(int64_t stream_id) {
  std::lock_guard<std::mutex> lock(process_mutex_);
  streams_.erase(stream_id);
}

#else  // !defined(SAWTUNAA_NATIVE_ML)

bool SawtunaaAudioService::ProcessBatch(int64_t,
                                        base::span<const float>,
                                        int,
                                        int,
                                        int,
                                        bool,
                                        std::vector<float>*) {
  return false;
}

void SawtunaaAudioService::ResetStream(int64_t) {}

void SawtunaaAudioService::DestroyStream(int64_t) {}

#endif  // defined(SAWTUNAA_NATIVE_ML)

}  // namespace sawtunaa
