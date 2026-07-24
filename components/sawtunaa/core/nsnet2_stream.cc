// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/components/sawtunaa/core/nsnet2_stream.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <numbers>

#include "base/check_op.h"
#include "base/compiler_specific.h"
#include "base/logging.h"
#include "base/memory/aligned_memory.h"
#include "onnxruntime_cxx_api.h"
#include "third_party/pffft/src/pffft.h"

namespace sawtunaa {

namespace {

// Constantes DSP — identiques à nsnet2-processor.ts (ne pas dévier : le
// modèle nsnet2-stateful.onnx est entraîné pour cette config exacte).
constexpr int kNWin = 960;    // fenêtre d'analyse 20 ms @48k
constexpr int kNFft = 1024;   // FFT zero-paddée
constexpr int kNHop = 512;    // 10.67 ms
constexpr int kNOverlap = kNWin - kNHop;  // 448
constexpr int kNBins = kNFft / 2 + 1;     // 513
constexpr int kGruHidden = 600;
constexpr float kLogFloor = 1e-12f;

// Silence-reset peak-hold (cf. bloc SILENCE_RESET_* du TS : reset propre du
// GRU quand le silence de SORTIE dure ≥ 5 s en continu — évite « parole
// étouffée après une longue intro musicale » — + filet forcé 5 min).
constexpr float kSilenceResetRms = 0.02f;
constexpr float kSilenceResetHoldSec = 2.0f;
constexpr int64_t kSilenceResetMinSamples =
    5 * static_cast<int64_t>(Nsnet2Stream::kSampleRate);
constexpr int64_t kGruResetForceSamples =
    300 * static_cast<int64_t>(Nsnet2Stream::kSampleRate);

// Mask floor : plancher de gain post-inférence (défaut 0 = no-op, comme
// l'extension/le standalone). Mode « hard pleine bande » seulement en natif
// V1 — la variante bande parole (150-7000 Hz) reste un knob extension.
constexpr float kMaskFloor = 0.f;

// Fenêtre d'analyse sqrt(Hann) périodique (sym=False).
std::vector<float> MakeAnalysisWindow() {
  std::vector<float> w(kNWin);
  for (int i = 0; i < kNWin; ++i) {
    w[i] = std::sqrt(
        0.5f * (1.f - std::cos(2.f * std::numbers::pi_v<float> * i / kNWin)));
  }
  return w;
}

// Fenêtre de synthèse pour reconstruction parfaite par overlap-add
// (pseudo-inverse par offset de hop, cf. makeSynthesisWindow du TS).
std::vector<float> MakeSynthesisWindow(const std::vector<float>& win) {
  std::vector<float> awin(kNWin);
  for (int k = 0; k < kNHop; ++k) {
    float sum_sq = 0.f;
    for (int idx = k; idx < kNWin; idx += kNHop) {
      sum_sq += win[idx] * win[idx];
    }
    for (int idx = k; idx < kNWin; idx += kNHop) {
      awin[idx] = win[idx] / sum_sq;
    }
  }
  return awin;
}

}  // namespace

// Buffers PFFFT alignés 16 octets (exigence SIMD NEON) : entrée fenêtrée
// zero-paddée, spectre packé (format « ordered » PFFFT), sortie de synthèse,
// et scratch de travail.
struct Nsnet2Stream::AlignedBuffers {
  AlignedBuffers()
      : windowed(base::AlignedUninit<float>(kNFft, 16)),
        packed(base::AlignedUninit<float>(kNFft, 16)),
        synth(base::AlignedUninit<float>(kNFft, 16)),
        work(base::AlignedUninit<float>(kNFft, 16)) {}

  base::AlignedHeapArray<float> windowed;
  base::AlignedHeapArray<float> packed;
  base::AlignedHeapArray<float> synth;
  base::AlignedHeapArray<float> work;
};

void Nsnet2Stream::PffftDeleter::operator()(PFFFT_Setup* p) const {
  if (p) {
    pffft_destroy_setup(p);
  }
}

Nsnet2Stream::Nsnet2Stream(Ort::Session* session, int channels)
    : session_(session),
      channels_(std::min(channels, kMaxChannels)),
      fft_(pffft_new_setup(kNFft, PFFFT_REAL)),
      win_(MakeAnalysisWindow()),
      awin_(MakeSynthesisWindow(win_)),
      input_l_(),
      input_r_(),
      overlap_l_(kNOverlap, 0.f),
      overlap_r_(kNOverlap, 0.f),
      h1_(kGruHidden, 0.f),
      h2_(kGruHidden, 0.f),
      aligned_(std::make_unique<AlignedBuffers>()),
      spec_l_re_(kNBins),
      spec_l_im_(kNBins),
      spec_r_re_(kNBins),
      spec_r_im_(kNBins),
      features_(kNBins),
      masked_re_(kNBins),
      masked_im_(kNBins) {
  DCHECK(session_);
  input_l_.reserve(kNWin * 8);
  input_r_.reserve(kNWin * 8);
  // Noms de sortie du modèle (ordre du graphe : mask, gru1_h_out, gru2_h_out
  // — même convention que outputNames côté onnxruntime-web).
  try {
    Ort::AllocatorWithDefaultOptions allocator;
    const size_t n = session_->GetOutputCount();
    for (size_t i = 0; i < n; ++i) {
      auto name = session_->GetOutputNameAllocated(i, allocator);
      output_names_.emplace_back(name.get());
    }
  } catch (const Ort::Exception& e) {
    LOG(WARNING) << "[swtTAP] GetOutputName failed: " << e.what();
  }
}

Nsnet2Stream::~Nsnet2Stream() = default;

void Nsnet2Stream::Reset() {
  std::ranges::fill(h1_, 0.f);
  std::ranges::fill(h2_, 0.f);
  std::ranges::fill(overlap_l_, 0.f);
  std::ranges::fill(overlap_r_, 0.f);
  input_l_.clear();
  input_r_.clear();
  input_len_ = 0;
  samples_since_reset_ = 0;
  silence_samples_ = 0;
  out_peak_ = 0.f;
  total_in_ = 0;
  total_out_ = 0;
}

bool Nsnet2Stream::ProcessBatch(base::span<const float> planar,
                                int frames,
                                bool flush,
                                std::vector<float>* out) {
  DCHECK(out);
  out->clear();
  if (output_names_.size() < 3) {
    return false;  // modèle inattendu → passthrough
  }
  CHECK_EQ(planar.size(), static_cast<size_t>(frames) * channels_);

  // Append au ring d'entrée (planar : L puis R).
  base::span<const float> in_l = planar.first(static_cast<size_t>(frames));
  input_l_.insert(input_l_.end(), in_l.begin(), in_l.end());
  if (channels_ == 2) {
    base::span<const float> in_r =
        planar.subspan(static_cast<size_t>(frames), static_cast<size_t>(frames));
    input_r_.insert(input_r_.end(), in_r.begin(), in_r.end());
  }
  input_len_ += static_cast<size_t>(frames);
  total_in_ += frames;

  // Reset GRU au niveau batch (comme le moteur Python / TS).
  MaybeResetGruStates();

  out_l_.clear();
  out_r_.clear();
  if (!DrainReadyFrames()) {
    return false;
  }

  if (flush) {
    // Vider la queue : padder 960 zéros → dernières frames → tronquer pour
    // que la sortie totale du flux == l'entrée totale, exactement.
    const int64_t due = total_in_ - total_out_ -
                        static_cast<int64_t>(out_l_.size());
    input_l_.resize(input_len_ + kNWin, 0.f);
    if (channels_ == 2) {
      input_r_.resize(input_len_ + kNWin, 0.f);
    }
    input_len_ += kNWin;
    if (!DrainReadyFrames()) {
      return false;
    }
    const size_t keep = static_cast<size_t>(
        std::clamp<int64_t>(due, 0, static_cast<int64_t>(out_l_.size())));
    out_l_.resize(keep);
    if (channels_ == 2) {
      out_r_.resize(keep);
    }
  }

  const int n = static_cast<int>(out_l_.size());
  UpdateSilenceTracking(out_l_, out_r_, n);
  total_out_ += n;

  // Sortie planar (L puis R).
  out->reserve(out_l_.size() * channels_);
  out->insert(out->end(), out_l_.begin(), out_l_.end());
  if (channels_ == 2) {
    out->insert(out->end(), out_r_.begin(), out_r_.end());
  }

  if (flush) {
    Reset();
  }
  return true;
}

bool Nsnet2Stream::DrainReadyFrames() {
  while (input_len_ >= static_cast<size_t>(kNWin)) {
    if (!ProcessOneFrame()) {
      return false;
    }
    // Avance du hop (shift-left ; std::rotate = pas de chevauchement UB).
    std::rotate(input_l_.begin(), input_l_.begin() + kNHop,
                input_l_.begin() + static_cast<ptrdiff_t>(input_len_));
    if (channels_ == 2) {
      std::rotate(input_r_.begin(), input_r_.begin() + kNHop,
                  input_r_.begin() + static_cast<ptrdiff_t>(input_len_));
    }
    input_len_ -= kNHop;
    input_l_.resize(input_len_);
    if (channels_ == 2) {
      input_r_.resize(input_len_);
    }
    samples_since_reset_ += kNHop;
  }
  return true;
}

bool Nsnet2Stream::ProcessOneFrame() {
  const bool stereo = channels_ == 2;
  base::span<float> windowed = aligned_->windowed.as_span();
  base::span<float> packed = aligned_->packed.as_span();
  base::span<float> work = aligned_->work.as_span();

  // 1-2. Fenêtre d'analyse + RFFT par canal. Sortie PFFFT « ordered » :
  // packed[0] = DC.re, packed[1] = Nyquist.re, puis (re, im) des bins
  // 1..511 — convention numpy côté signe (forward e^{-i…}).
  for (int i = 0; i < kNWin; ++i) {
    windowed[i] = input_l_[i] * win_[i];
  }
  std::fill(windowed.begin() + kNWin, windowed.end(), 0.f);
  pffft_transform_ordered(fft_.get(), windowed.data(), packed.data(),
                          work.data(), PFFFT_FORWARD);
  spec_l_re_[0] = packed[0];
  spec_l_im_[0] = 0.f;
  spec_l_re_[kNBins - 1] = packed[1];
  spec_l_im_[kNBins - 1] = 0.f;
  for (int k = 1; k < kNBins - 1; ++k) {
    spec_l_re_[k] = packed[2 * k];
    spec_l_im_[k] = packed[2 * k + 1];
  }
  if (stereo) {
    for (int i = 0; i < kNWin; ++i) {
      windowed[i] = input_r_[i] * win_[i];
    }
    std::fill(windowed.begin() + kNWin, windowed.end(), 0.f);
    pffft_transform_ordered(fft_.get(), windowed.data(), packed.data(),
                            work.data(), PFFFT_FORWARD);
    spec_r_re_[0] = packed[0];
    spec_r_im_[0] = 0.f;
    spec_r_re_[kNBins - 1] = packed[1];
    spec_r_im_[kNBins - 1] = 0.f;
    for (int k = 1; k < kNBins - 1; ++k) {
      spec_r_re_[k] = packed[2 * k];
      spec_r_im_[k] = packed[2 * k + 1];
    }
  }

  // 3. Features log-power sur le spectre du downmix (moyenne des spectres —
  // linéarité de la STFT, une seule inférence par frame).
  for (int i = 0; i < kNBins; ++i) {
    float re = spec_l_re_[i];
    float im = spec_l_im_[i];
    if (stereo) {
      re = 0.5f * (re + spec_r_re_[i]);
      im = 0.5f * (im + spec_r_im_[i]);
    }
    const float power = re * re + im * im;
    features_[i] = std::log10(std::max(power, kLogFloor));
  }

  // 4. Inférence ONNX (masque + états GRU). Sérialisation globale assurée
  // par l'appelant (mutex du service) — pas de lock ici.
  try {
    Ort::MemoryInfo mem_info =
        Ort::MemoryInfo::CreateCpu(OrtDeviceAllocator, OrtMemTypeCPU);
    const std::array<int64_t, 3> feat_shape = {1, 1, kNBins};
    const std::array<int64_t, 3> gru_shape = {1, 1, kGruHidden};
    std::array<Ort::Value, 3> inputs = {
        Ort::Value::CreateTensor<float>(mem_info, features_.data(),
                                        features_.size(), feat_shape.data(),
                                        feat_shape.size()),
        Ort::Value::CreateTensor<float>(mem_info, h1_.data(), h1_.size(),
                                        gru_shape.data(), gru_shape.size()),
        Ort::Value::CreateTensor<float>(mem_info, h2_.data(), h2_.size(),
                                        gru_shape.data(), gru_shape.size())};
    const std::array<const char*, 3> input_names = {"input", "gru1_h_in",
                                                    "gru2_h_in"};
    const std::array<const char*, 3> output_names = {
        output_names_[0].c_str(), output_names_[1].c_str(),
        output_names_[2].c_str()};

    auto results =
        session_->Run(Ort::RunOptions{nullptr}, input_names.data(),
                      inputs.data(), inputs.size(), output_names.data(),
                      output_names.size());

    // ORT expose ptr + longueur ; UNSAFE_BUFFERS comme basarunaa_service.cc.
    const auto mask = UNSAFE_BUFFERS(base::span<const float>(
        results[0].GetTensorData<float>(), static_cast<size_t>(kNBins)));
    const auto h1_out = UNSAFE_BUFFERS(base::span<const float>(
        results[1].GetTensorData<float>(), static_cast<size_t>(kGruHidden)));
    const auto h2_out = UNSAFE_BUFFERS(base::span<const float>(
        results[2].GetTensorData<float>(), static_cast<size_t>(kGruHidden)));
    std::ranges::copy(h1_out, h1_.begin());
    std::ranges::copy(h2_out, h2_.begin());

    // Mask floor (no-op à 0). Copie locale du masque si plancher actif.
    for (int i = 0; i < kNBins; ++i) {
      float m = mask[i];
      if (kMaskFloor > 0.f && m < kMaskFloor) {
        m = kMaskFloor;
      }
      masked_re_[i] = spec_l_re_[i] * m;
      masked_im_[i] = spec_l_im_[i] * m;
    }
    MaskAndSynthesize(masked_re_, masked_im_, overlap_l_, &out_l_);
    if (stereo) {
      for (int i = 0; i < kNBins; ++i) {
        float m = mask[i];
        if (kMaskFloor > 0.f && m < kMaskFloor) {
          m = kMaskFloor;
        }
        masked_re_[i] = spec_r_re_[i] * m;
        masked_im_[i] = spec_r_im_[i] * m;
      }
      MaskAndSynthesize(masked_re_, masked_im_, overlap_r_, &out_r_);
    }
  } catch (const Ort::Exception& e) {
    LOG(WARNING) << "[swtTAP] ORT Run failed: " << e.what();
    return false;
  }
  return true;
}

void Nsnet2Stream::MaskAndSynthesize(base::span<const float> spec_re,
                                     base::span<const float> spec_im,
                                     base::span<float> overlap,
                                     std::vector<float>* out) {
  // |spec_re|/|spec_im| arrivent déjà masqués (masked_re_/masked_im_).
  base::span<float> packed = aligned_->packed.as_span();
  base::span<float> synth = aligned_->synth.as_span();
  base::span<float> work = aligned_->work.as_span();

  // 6. iRFFT — repack au format « ordered » PFFFT, inverse, normalisation 1/N
  // (sémantique numpy.irfft, cf. fft.ts).
  packed[0] = spec_re[0];
  packed[1] = spec_re[kNBins - 1];
  for (int k = 1; k < kNBins - 1; ++k) {
    packed[2 * k] = spec_re[k];
    packed[2 * k + 1] = spec_im[k];
  }
  pffft_transform_ordered(fft_.get(), packed.data(), synth.data(), work.data(),
                          PFFFT_BACKWARD);
  constexpr float kInvN = 1.f / kNFft;

  // 7-8. Fenêtre de synthèse + overlap-add. Sortie = kNHop premiers samples.
  for (int i = 0; i < kNWin; ++i) {
    synth[i] *= kInvN * awin_[i];
  }
  for (int i = 0; i < kNOverlap; ++i) {
    synth[i] += overlap[i];
  }
  out->insert(out->end(), synth.begin(), synth.begin() + kNHop);
  // Queue pour la frame suivante.
  std::copy(synth.begin() + kNHop, synth.begin() + kNWin, overlap.begin());
}

void Nsnet2Stream::MaybeResetGruStates() {
  const bool silence_due = silence_samples_ >= kSilenceResetMinSamples;
  const bool force_due = samples_since_reset_ >= kGruResetForceSamples;
  if (!silence_due && !force_due) {
    return;
  }
  std::ranges::fill(h1_, 0.f);
  std::ranges::fill(h2_, 0.f);
  samples_since_reset_ = 0;
  if (silence_due) {
    silence_samples_ = 0;
  }
  VLOG(1) << "[swtTAP] reset GRU ("
          << (silence_due ? "silence sortie >= 5 s" : "filet 5 min") << ")";
}

void Nsnet2Stream::UpdateSilenceTracking(base::span<const float> out_l,
                                         base::span<const float> out_r,
                                         int n) {
  if (n <= 0) {
    return;
  }
  float sum_sq = 0.f;
  if (channels_ == 2) {
    for (int i = 0; i < n; ++i) {
      const float s = 0.5f * (out_l[i] + out_r[i]);
      sum_sq += s * s;
    }
  } else {
    for (int i = 0; i < n; ++i) {
      sum_sq += out_l[i] * out_l[i];
    }
  }
  const float rms = std::sqrt(sum_sq / n);
  const float decay =
      std::exp(-static_cast<float>(n) / (kSampleRate * kSilenceResetHoldSec));
  out_peak_ = std::max(rms, out_peak_ * decay);
  if (out_peak_ >= kSilenceResetRms) {
    silence_samples_ = 0;
  } else {
    silence_samples_ += n;
  }
}

}  // namespace sawtunaa
