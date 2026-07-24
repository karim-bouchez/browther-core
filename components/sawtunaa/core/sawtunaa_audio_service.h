// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_COMPONENTS_SAWTUNAA_CORE_SAWTUNAA_AUDIO_SERVICE_H_
#define BRAVE_COMPONENTS_SAWTUNAA_CORE_SAWTUNAA_AUDIO_SERVICE_H_

#include <cstdint>
#include <map>
#include <memory>
#include <mutex>
#include <vector>

#include "base/containers/span.h"
#include "components/keyed_service/core/keyed_service.h"

// ⚠️ ODR : `SAWTUNAA_NATIVE_ML` conditionne des MEMBRES de
// SawtunaaAudioService ci-dessous → il change le sizeof de la classe. TOUT
// target GN qui inclut ce header ET alloue/possède un SawtunaaAudioService
// DOIT définir ce macro de façon identique au target `core`, sinon
// débordement de tas (même piège que BASARUNAA_NATIVE_ML, incident
// 2026-07-02). Défini pour `//brave/components/sawtunaa/core` ET le futur
// `//brave/browser/sawtunaa`.
#if defined(SAWTUNAA_NATIVE_ML)
namespace Ort {
struct Env;
struct Session;
}  // namespace Ort
#endif

namespace sawtunaa {

#if defined(SAWTUNAA_NATIVE_ML)
class Nsnet2Stream;
#endif

// Audio tap V2 — suppression musique/bruit NSNet2 native (ORT C++), process
// browser, jumeau de BasarunaaService (KeyedService par profil, inférence sur
// base::ThreadPool, PAS d'utility process). Un « stream » = un media player
// (AudioRendererImpl) côté renderer ; le PCM décodé arrive par batchs Mojo
// (BigBuffer planar float32), est traité dans le budget d'avance decode-ahead
// 2 s, et repart traité. Cf. private/docs/sawtunaa/AUDIO_TAP_V2.md.
class SawtunaaAudioService : public KeyedService {
 public:
  // `eager_warmup` : charge le modèle + 1 run à vide au boot du profil (posté
  // sur ThreadPool par la factory si la pref kSawtunaaEnabled est ON). Sinon
  // chargement lazy au 1er batch.
  explicit SawtunaaAudioService(bool eager_warmup);
  SawtunaaAudioService(const SawtunaaAudioService&) = delete;
  SawtunaaAudioService& operator=(const SawtunaaAudioService&) = delete;
  ~SawtunaaAudioService() override;

  // Traite un batch PCM planar float32 (|channels| blocs de |frames|).
  // Renvoie true + |out| rempli (peut être plus court que l'entrée — rétention
  // STFT ; plus long au flush) si le traitement a eu lieu ; false = l'appelant
  // doit faire PASSTHROUGH (modèle absent, rate ≠ 48 k tant que le resampler
  // n'est pas branché, > 2 canaux, erreur ORT).
  // À appeler UNIQUEMENT sur le ThreadPool (jamais le thread UI) — bloque sur
  // le mutex global le temps de l'inférence.
  bool ProcessBatch(int64_t stream_id,
                    base::span<const float> planar,
                    int frames,
                    int channels,
                    int sample_rate,
                    bool flush,
                    std::vector<float>* out);

  // Seek/flush pipeline côté renderer : drop rings + overlap + états GRU.
  void ResetStream(int64_t stream_id);

  // Fin de vie du media player. Sans appel (crash renderer), le filet
  // kMaxStreams évince les plus anciens.
  void DestroyStream(int64_t stream_id);

 private:
#if defined(SAWTUNAA_NATIVE_ML)
  void EnsureOrtEnv();
  void LoadModelOnce();
  // Warmup eager : charge le modèle + 1 inférence à vide (pagine les poids,
  // ~25 Mo). Posté sur ThreadPool par le constructeur.
  void WarmUp();

  std::once_flag env_init_flag_;
  std::once_flag init_flag_;
  std::unique_ptr<Ort::Env> ort_env_;
  std::unique_ptr<Ort::Session> session_;
  bool session_ready_ = false;

  // Sérialise GLOBALEMENT ProcessBatch/Reset/Destroy (streams_ + Run ORT +
  // états par flux). Service profile-keyed partagé entre tous les WebContents
  // (pattern analyze_mutex_ Basarunaa — corruption de tas confirmée sans).
  // Toujours pris sur le ThreadPool → pas de blocage UI.
  std::mutex process_mutex_;
  std::map<int64_t, std::unique_ptr<Nsnet2Stream>> streams_;
#endif
};

}  // namespace sawtunaa

#endif  // BRAVE_COMPONENTS_SAWTUNAA_CORE_SAWTUNAA_AUDIO_SERVICE_H_
