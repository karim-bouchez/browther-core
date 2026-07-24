// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_COMPONENTS_SAWTUNAA_CORE_NSNET2_STREAM_H_
#define BRAVE_COMPONENTS_SAWTUNAA_CORE_NSNET2_STREAM_H_

#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include "base/containers/span.h"
#include "base/memory/raw_ptr.h"

// Ce header n'est compilé que par des targets qui définissent
// SAWTUNAA_NATIVE_ML (la classe n'existe pas sans ORT). Contrairement au
// service, PAS de membres gatés par macro ici : le fichier entier est gated
// côté BUILD.gn → pas de piège ODR.
#if !defined(SAWTUNAA_NATIVE_ML)
#error "nsnet2_stream.h requires SAWTUNAA_NATIVE_ML (gate it in BUILD.gn)"
#endif

namespace Ort {
struct Session;
}  // namespace Ort

struct PFFFT_Setup;

namespace sawtunaa {

// État + DSP NSNet2 pour UN flux audio (un media player). Portage fidèle de
// private/extensions/sawtunaa/src/nsnet2-processor.ts (lui-même porté de
// sawtunaa_engine.py, la référence DSP) :
//   STFT sqrt-Hann (win 960, fft 1024, hop 512) → features log-power [513]
//   sur le spectre du DOWNMIX (moyenne des spectres L/R — linéarité STFT,
//   une seule inférence par frame) → masque appliqué à CHAQUE canal →
//   iSTFT + overlap-add. Knobs qualité portés : silence-reset peak-hold
//   (RMS sortie 0.02, τ 2 s, ≥ 5 s continu, filet forcé 5 min) ; mask floor
//   (défaut 0 = no-op).
//
// Flux d'échantillons : ProcessBatch(planar) renvoie CE QUI EST PRÊT
// (multiple de 512 par canal) — la rétention structurelle est de 448-959
// samples (latence algorithmique de l'overlap-add). La sortie est alignée
// échantillon-près sur l'entrée (sortie[k] = entrée[k] traité) : le renderer
// reconstruit les timestamps en continu. flush=true (EOS) : la queue est
// vidée (padding zéro interne) et la sortie totale du flux == l'entrée
// totale, exactement.
//
// Threading : AUCUNE synchronisation interne — l'appelant
// (SawtunaaAudioService) sérialise TOUS les appels, tous streams confondus,
// sous son mutex global (pattern analyze_mutex_ de BasarunaaService).
//
// V1 : 48 kHz uniquement (le modèle est entraîné à 48 k). L'appelant vérifie
// le rate en amont ; les flux 44.1 k restent en passthrough tant que le
// resampler aller-retour n'est pas branché (cf. AUDIO_TAP_V2.md § resampling).
class Nsnet2Stream {
 public:
  static constexpr int kSampleRate = 48000;
  static constexpr int kMaxChannels = 2;

  // |session| non-owned, partagée entre tous les streams (durée de vie
  // garantie par SawtunaaAudioService qui possède tout).
  Nsnet2Stream(Ort::Session* session, int channels);
  Nsnet2Stream(const Nsnet2Stream&) = delete;
  Nsnet2Stream& operator=(const Nsnet2Stream&) = delete;
  ~Nsnet2Stream();

  int channels() const { return channels_; }

  // |planar| : |channels| blocs contigus de |frames| samples float32.
  // Renvoie le PCM traité, même layout planar (taille = n_out * channels,
  // n_out multiple de 512, possiblement 0 au premier batch). flush=true :
  // vide la queue — après l'appel, sortie cumulée == entrée cumulée.
  // Vecteur vide + false en cas d'erreur ORT (l'appelant fait passthrough).
  bool ProcessBatch(base::span<const float> planar,
                    int frames,
                    bool flush,
                    std::vector<float>* out);

  // Seek/flush pipeline : drop rings + overlap + états GRU + compteurs.
  void Reset();

 private:
  class PffftDeleter {
   public:
    void operator()(PFFFT_Setup* p) const;
  };

  // Traite les frames complètes du ring d'entrée ; sortie (n*512 par canal)
  // appended à out_l_/out_r_. Renvoie false sur erreur ORT.
  bool DrainReadyFrames();
  bool ProcessOneFrame();
  void MaybeResetGruStates();
  void UpdateSilenceTracking(base::span<const float> out_l,
                             base::span<const float> out_r,
                             int n);
  // Spectre déjà masqué → iFFT → fenêtre synthèse → overlap-add (1 canal).
  // La sortie (512 samples) est appended à |out|.
  void MaskAndSynthesize(base::span<const float> spec_re,
                         base::span<const float> spec_im,
                         base::span<float> overlap,
                         std::vector<float>* out);

  const raw_ptr<Ort::Session> session_;
  const int channels_;

  std::unique_ptr<PFFFT_Setup, PffftDeleter> fft_;

  // Fenêtres (analyse sqrt-Hann périodique + synthèse pinv), calculées au ctor.
  std::vector<float> win_;
  std::vector<float> awin_;

  // Rings d'entrée par canal (mono : ring R inutilisé).
  std::vector<float> input_l_;
  std::vector<float> input_r_;
  size_t input_len_ = 0;

  // Queues d'overlap-add (448 samples par canal).
  std::vector<float> overlap_l_;
  std::vector<float> overlap_r_;

  // États GRU persistants (recopiés après chaque run).
  std::vector<float> h1_;
  std::vector<float> h2_;

  // Scratch par frame — buffers PFFFT alignés 16 (exigence SIMD), les autres
  // en vector standard.
  struct AlignedBuffers;
  std::unique_ptr<AlignedBuffers> aligned_;
  std::vector<float> spec_l_re_, spec_l_im_;
  std::vector<float> spec_r_re_, spec_r_im_;
  std::vector<float> features_;
  std::vector<float> masked_re_, masked_im_;

  // Accumulateurs de sortie du batch courant.
  std::vector<float> out_l_;
  std::vector<float> out_r_;

  // Silence-reset peak-hold + filet 5 min (unités : samples @48k).
  int64_t samples_since_reset_ = 0;
  int64_t silence_samples_ = 0;
  float out_peak_ = 0.f;

  // Comptes globaux du flux, pour le flush exact (sortie totale == entrée
  // totale) : le padding zéro du flush produit un excédent à tronquer.
  int64_t total_in_ = 0;
  int64_t total_out_ = 0;

  // Noms I/O du modèle, résolus une fois au ctor.
  std::vector<std::string> output_names_;
};

}  // namespace sawtunaa

#endif  // BRAVE_COMPONENTS_SAWTUNAA_CORE_NSNET2_STREAM_H_
