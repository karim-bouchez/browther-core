// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_COMPONENTS_SAWTUNAA_CORE_SAWTUNAA_RATE_ADAPTER_H_
#define BRAVE_COMPONENTS_SAWTUNAA_CORE_SAWTUNAA_RATE_ADAPTER_H_

#include <cstdint>
#include <memory>
#include <vector>

#include "base/containers/span.h"

#if !defined(SAWTUNAA_NATIVE_ML)
#error "sawtunaa_rate_adapter.h requires SAWTUNAA_NATIVE_ML (gate in BUILD.gn)"
#endif

namespace media {
class AudioBus;
class MultiChannelResampler;
}  // namespace media

namespace sawtunaa {

// Audio tap V2 — adaptation de fréquence aller-retour autour de NSNet2
// (48 kHz obligatoire) pour les flux non-48k (AAC/MP3 44.1 k…) :
//   src_rate → [ToModel] → 48 k → NSNet2 → [FromModel] → src_rate
// Push-based au-dessus de media::MultiChannelResampler (pull) : chaque sens
// garde une FIFO d'entrée et ne tire que les tranches de sortie couvertes par
// la FIFO (GetMaxInputFramesRequested → jamais de zéro-pad accidentel).
//
// Exactitude : les resamplers retiennent ~request+kernel frames ; au flush
// (EOS), les FIFO sont paddées de zéros et la sortie FINALE est tronquée/
// paddée pour que le total sortant == total entrant (côté source), comme
// l'exige le contrat du service (sortie cumulée == entrée cumulée). En
// régime, un délai constant ~2×kernel/2 subsiste (~1,5 ms) — négligeable pour
// le lip-sync.
//
// Threading : aucun verrou interne — sérialisé par l'appelant
// (SawtunaaAudioService, mutex global).
class RateAdapter {
 public:
  static constexpr int kModelRate = 48000;

  RateAdapter(int src_rate, int channels);
  RateAdapter(const RateAdapter&) = delete;
  RateAdapter& operator=(const RateAdapter&) = delete;
  ~RateAdapter();

  int src_rate() const { return src_rate_; }

  // Push |frames| de PCM source (planar) ; renvoie le 48 k disponible
  // (planar, possiblement vide). flush : draine tout le résiduel.
  std::vector<float> ToModel(base::span<const float> planar_src,
                             int frames,
                             bool flush);

  // Push |frames| de PCM 48 k traité (planar) ; renvoie le PCM au rate
  // source. flush : la sortie cumulée de FromModel est ajustée à EXACTEMENT
  // le total poussé dans ToModel (troncature/padding final).
  std::vector<float> FromModel(base::span<const float> planar_48,
                               int frames,
                               bool flush);

  void Reset();

 private:
  struct Direction;

  void PushInput(Direction* dir, base::span<const float> planar, int frames);
  // Tire jusqu'à |max_out| frames de sortie (multiples de la tranche interne,
  // sauf |exact| qui force exactement max_out — flush). Append planar à |out|.
  void Pull(Direction* dir, int max_out, bool exact, std::vector<float>* out);

  const int src_rate_;
  const int channels_;

  std::unique_ptr<Direction> to_model_;    // src → 48 k
  std::unique_ptr<Direction> from_model_;  // 48 k → src

  // Comptes source pour l'exactitude du flush.
  int64_t src_in_total_ = 0;
  int64_t src_out_total_ = 0;
};

}  // namespace sawtunaa

#endif  // BRAVE_COMPONENTS_SAWTUNAA_CORE_SAWTUNAA_RATE_ADAPTER_H_
