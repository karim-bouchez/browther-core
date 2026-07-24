// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/components/sawtunaa/core/sawtunaa_rate_adapter.h"

#include <algorithm>
#include <utility>

#include "base/check_op.h"
#include "base/functional/bind.h"
#include "media/base/audio_bus.h"
#include "media/base/multi_channel_resampler.h"

namespace sawtunaa {

namespace {
// Tranche de sortie par appel Resample — petite pour borner la rétention,
// assez grande pour amortir le coût par appel.
constexpr int kChunkFrames = 512;
}  // namespace

// Un sens de resampling : FIFO d'entrée planar + MultiChannelResampler.
struct RateAdapter::Direction {
  Direction(int channels, double io_ratio)
      : scratch(media::AudioBus::Create(channels, kChunkFrames)) {
    resampler = std::make_unique<media::MultiChannelResampler>(
        channels, io_ratio, kChunkFrames,
        base::BindRepeating(&Direction::ProvideInput,
                            base::Unretained(this)));
    fifo.resize(static_cast<size_t>(channels));
  }

  void ProvideInput(int frame_delay, media::AudioBus* dest) {
    // Remplit |dest| depuis la FIFO ; zéro-pad le manque (n'arrive qu'en
    // flush, où l'appelant a paddé — le pad est tronqué en sortie).
    const int want = dest->frames();
    const int have =
        std::min(want, static_cast<int>(fifo.empty() ? 0 : fifo[0].size()));
    for (size_t ch = 0; ch < fifo.size(); ++ch) {
      auto dst = dest->AllChannels()[ch];
      std::copy(fifo[ch].begin(), fifo[ch].begin() + have, dst.begin());
      std::fill(dst.begin() + have, dst.end(), 0.f);
      fifo[ch].erase(fifo[ch].begin(), fifo[ch].begin() + have);
    }
  }

  int fifo_frames() const {
    return fifo.empty() ? 0 : static_cast<int>(fifo[0].size());
  }

  std::unique_ptr<media::MultiChannelResampler> resampler;
  std::vector<std::vector<float>> fifo;  // par canal
  std::unique_ptr<media::AudioBus> scratch;
  int64_t in_total = 0;
  int64_t out_total = 0;
};

RateAdapter::RateAdapter(int src_rate, int channels)
    : src_rate_(src_rate),
      channels_(channels),
      to_model_(std::make_unique<Direction>(
          channels,
          static_cast<double>(src_rate) / kModelRate)),
      from_model_(std::make_unique<Direction>(
          channels,
          static_cast<double>(kModelRate) / src_rate)) {}

RateAdapter::~RateAdapter() = default;

void RateAdapter::Reset() {
  for (Direction* dir : {to_model_.get(), from_model_.get()}) {
    dir->resampler->Flush();
    for (auto& ch : dir->fifo) {
      ch.clear();
    }
    dir->in_total = 0;
    dir->out_total = 0;
  }
  src_in_total_ = 0;
  src_out_total_ = 0;
}

void RateAdapter::PushInput(Direction* dir,
                            base::span<const float> planar,
                            int frames) {
  for (int ch = 0; ch < channels_; ++ch) {
    auto src = planar.subspan(static_cast<size_t>(ch) * frames,
                              static_cast<size_t>(frames));
    dir->fifo[static_cast<size_t>(ch)].insert(
        dir->fifo[static_cast<size_t>(ch)].end(), src.begin(), src.end());
  }
  dir->in_total += frames;
}

void RateAdapter::Pull(Direction* dir,
                       int max_out,
                       bool exact,
                       std::vector<float>* out) {
  std::vector<std::vector<float>> produced(
      static_cast<size_t>(channels_));
  int remaining = max_out;
  while (remaining > 0) {
    const int chunk = std::min(remaining, kChunkFrames);
    if (!exact && dir->resampler->GetMaxInputFramesRequested(chunk) >
                      dir->fifo_frames()) {
      break;  // pas assez d'entrée pour garantir cette tranche sans zéro-pad
    }
    dir->resampler->Resample(chunk, dir->scratch.get());
    for (int ch = 0; ch < channels_; ++ch) {
      auto src = dir->scratch->AllChannels()[static_cast<size_t>(ch)];
      produced[static_cast<size_t>(ch)].insert(
          produced[static_cast<size_t>(ch)].end(), src.begin(),
          src.begin() + chunk);
    }
    dir->out_total += chunk;
    remaining -= chunk;
  }
  const int n = max_out - remaining;
  if (n <= 0) {
    return;
  }
  const size_t base = out->size();
  // Ré-agrégation planar : [déjà présent][L…][R…] — l'appelant passe toujours
  // un |out| vide, CHECK par sécurité (sinon l'interleave serait faux).
  CHECK_EQ(base, 0u);
  out->reserve(static_cast<size_t>(n) * channels_);
  for (int ch = 0; ch < channels_; ++ch) {
    out->insert(out->end(), produced[static_cast<size_t>(ch)].begin(),
                produced[static_cast<size_t>(ch)].end());
  }
}

std::vector<float> RateAdapter::ToModel(base::span<const float> planar_src,
                                        int frames,
                                        bool flush) {
  if (frames > 0) {
    CHECK_EQ(planar_src.size(),
             static_cast<size_t>(frames) * channels_);
    PushInput(to_model_.get(), planar_src, frames);
    src_in_total_ += frames;
  }
  std::vector<float> out;
  if (flush) {
    // Cible exacte : tout ce que l'entrée source représente à 48 k.
    const int64_t target =
        src_in_total_ * kModelRate / src_rate_;
    const int due = static_cast<int>(target - to_model_->out_total);
    if (due > 0) {
      // Padder la FIFO pour couvrir le tirage exact.
      const int need = to_model_->resampler->GetMaxInputFramesRequested(due);
      const int pad = std::max(0, need - to_model_->fifo_frames());
      for (auto& ch : to_model_->fifo) {
        ch.insert(ch.end(), static_cast<size_t>(pad), 0.f);
      }
      Pull(to_model_.get(), due, /*exact=*/true, &out);
    }
  } else {
    // Tirer tout ce qui est couvert par la FIFO (multiple de tranche).
    const int64_t max_out =
        to_model_->in_total * kModelRate / src_rate_ - to_model_->out_total;
    Pull(to_model_.get(), static_cast<int>(std::max<int64_t>(0, max_out)),
         /*exact=*/false, &out);
  }
  return out;
}

std::vector<float> RateAdapter::FromModel(base::span<const float> planar_48,
                                          int frames,
                                          bool flush) {
  if (frames > 0) {
    CHECK_EQ(planar_48.size(),
             static_cast<size_t>(frames) * channels_);
    PushInput(from_model_.get(), planar_48, frames);
  }
  std::vector<float> out;
  if (flush) {
    // Contrat du service : sortie source cumulée == entrée source cumulée.
    const int due = static_cast<int>(src_in_total_ - src_out_total_);
    if (due > 0) {
      const int need =
          from_model_->resampler->GetMaxInputFramesRequested(due);
      const int pad = std::max(0, need - from_model_->fifo_frames());
      for (auto& ch : from_model_->fifo) {
        ch.insert(ch.end(), static_cast<size_t>(pad), 0.f);
      }
      Pull(from_model_.get(), due, /*exact=*/true, &out);
    }
  } else {
    const int64_t max_out = from_model_->in_total * src_rate_ / kModelRate -
                            from_model_->out_total;
    Pull(from_model_.get(), static_cast<int>(std::max<int64_t>(0, max_out)),
         /*exact=*/false, &out);
  }
  src_out_total_ += static_cast<int64_t>(out.size()) / channels_;
  return out;
}

}  // namespace sawtunaa
