// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/components/basarunaa/renderer/basarunaa_render_frame_observer.h"

#include <algorithm>
#include <array>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "base/containers/span.h"
#include "base/functional/bind.h"
#include "base/json/json_writer.h"
#include "base/location.h"
#include "base/logging.h"
#include "base/task/single_thread_task_runner.h"
#include "base/values.h"
#include "content/public/renderer/render_frame.h"
#include "mojo/public/cpp/base/big_buffer.h"
#include "third_party/blink/public/platform/browser_interface_broker_proxy.h"
#include "third_party/blink/public/platform/task_type.h"
#include "third_party/blink/public/platform/web_string.h"
#include "third_party/blink/public/web/web_local_frame.h"
#include "third_party/blink/public/web/web_script_source.h"

namespace basarunaa {

namespace {

// Refonte 2026-07-04 — politique de tap DANS LE RENDERER (le browser n'a plus de
// cadence). On reçoit chaque frame décodée-en-avance (~2 s), on calcule un hash
// 8×8, et on décide QUOI envoyer à l'analyse ML :
//   - un KEYFRAME à cadence GARANTIE (toutes les kKeyframeIntervalMs), même en
//     plan statique → le store côté overlay ne gèle jamais (fix de l'avance qui
//     décroît : cf. BASARUNAA_VIDEO_NATIVE_PLAN.md).
//   - sur un CUT (diff hash > seuil), la paire n-1 / n (dernière frame ancienne
//     scène + première nouvelle) → bornes d'interpolation nettes pour l'overlay.
// Les autres frames sont droppées (l'overlay interpole entre deux keyframes).
constexpr int kKeyframeIntervalMs = 1000;
constexpr float kCutThreshold = 0.12f;  // seuil scène (v1)

// Hash 8×8 grayscale (moyenne par bloc) — port de core/video/frame-diff.ts.
// Grayscale pondéré (R*2 + G*3 + B)/6 comme la v1. Le sink délivre du BGRA
// (kN32 Apple, cf. WebMediaPlayerImpl::OnLeadFrame) → r_idx=2, b_idx=0.
std::array<uint8_t, 64> ComputeHash8x8(base::span<const uint8_t> px,
                                       int w,
                                       int h) {
  std::array<uint64_t, 64> sum = {};
  std::array<uint32_t, 64> cnt = {};
  constexpr size_t r_idx = 2;  // BGRA
  constexpr size_t b_idx = 0;
  for (int y = 0; y < h; ++y) {
    const int cy = std::min(7, y * 8 / std::max(1, h));
    for (int x = 0; x < w; ++x) {
      const int cx = std::min(7, x * 8 / std::max(1, w));
      const size_t off = (static_cast<size_t>(y) * w + x) * 4;
      if (off + 2 >= px.size()) {
        continue;
      }
      const uint32_t gray =
          (px[off + r_idx] * 2u + px[off + 1] * 3u + px[off + b_idx]) / 6u;
      const int cell = cy * 8 + cx;
      sum[cell] += gray;
      cnt[cell] += 1;
    }
  }
  std::array<uint8_t, 64> hash = {};
  for (int i = 0; i < 64; ++i) {
    hash[i] = cnt[i] ? static_cast<uint8_t>(sum[i] / cnt[i]) : 0;
  }
  return hash;
}

// Ratio de diff [0,1] entre deux hash (somme des |Δ| / (64*255)).
float HashDiff(const std::array<uint8_t, 64>& a,
               const std::array<uint8_t, 64>& b) {
  int total = 0;
  for (int i = 0; i < 64; ++i) {
    const int d = static_cast<int>(a[i]) - static_cast<int>(b[i]);
    total += d < 0 ? -d : d;
  }
  return total / (64.f * 255.f);
}

}  // namespace

BasarunaaRenderFrameObserver::BasarunaaRenderFrameObserver(
    content::RenderFrame* render_frame)
    : content::RenderFrameObserver(render_frame),
      content::RenderFrameObserverTracker<BasarunaaRenderFrameObserver>(
          render_frame) {}

BasarunaaRenderFrameObserver::~BasarunaaRenderFrameObserver() = default;

bool BasarunaaRenderFrameObserver::EnsureConnected() {
  if (!image_analyzer_.is_bound()) {
    if (!render_frame()) {
      return false;
    }
    render_frame()->GetBrowserInterfaceBroker().GetInterface(
        image_analyzer_.BindNewPipeAndPassReceiver());
    image_analyzer_.reset_on_disconnect();
  }
  return image_analyzer_.is_bound();
}

base::RepeatingCallback<void(std::vector<uint8_t>, int, int, base::TimeDelta)>
BasarunaaRenderFrameObserver::GetVideoLeadFrameSink() {
  return base::BindRepeating(
      &BasarunaaRenderFrameObserver::OnVideoLeadFrame,
      weak_ptr_factory_.GetWeakPtr());
}

void BasarunaaRenderFrameObserver::ForwardForAnalysis(
    base::span<const uint8_t> bgra,
    int width,
    int height,
    base::TimeDelta media_time,
    FrameKind kind) {
  if (!EnsureConnected()) {
    return;
  }
  mojo_base::BigBuffer buffer{bgra};
  image_analyzer_->AnalyzeImage(
      std::move(buffer), width, height, mojom::ImageFormat::kBgra8,
      base::BindOnce(&BasarunaaRenderFrameObserver::OnAnalyzed,
                     weak_ptr_factory_.GetWeakPtr(), media_time, width, height,
                     kind));
}

void BasarunaaRenderFrameObserver::OnVideoLeadFrame(std::vector<uint8_t> bgra,
                                                    int width,
                                                    int height,
                                                    base::TimeDelta media_time) {
  // ③a : reçoit une frame BGRA décodée-en-avance. On décide QUOI analyser
  // (keyframe garanti + paire n-1/n de cut) et on forwarde sélectivement.
  const auto span = base::span<const uint8_t>(bgra);
  const std::array<uint8_t, 64> hash = ComputeHash8x8(span, width, height);
  const float diff = has_prev_hash_ ? HashDiff(hash, prev_hash_) : 1.f;

  const bool is_cut = has_prev_hash_ && diff > kCutThreshold;
  const bool due_keyframe =
      !has_prev_hash_ ||
      (media_time - last_keyframe_ts_) >=
          base::Milliseconds(kKeyframeIntervalMs);

  if (is_cut) {
    // Frontière de cut : la DERNIÈRE frame de l'ancienne scène (n-1, gardée) PUIS
    // la première de la nouvelle (n). L'overlay interpole l'ancienne scène
    // jusqu'à n-1 puis snap à n → pas de flash full-blur au cut.
    if (has_prev_frame_) {
      ForwardForAnalysis(base::span<const uint8_t>(prev_bgra_), prev_width_,
                         prev_height_, prev_media_time_, FrameKind::kCutBefore);
    }
    ForwardForAnalysis(span, width, height, media_time, FrameKind::kCutAfter);
    last_keyframe_ts_ = media_time;  // le cut réarme la cadence keyframe
  } else if (due_keyframe) {
    ForwardForAnalysis(span, width, height, media_time, FrameKind::kKeyframe);
    last_keyframe_ts_ = media_time;
  }
  // Sinon : drop (interpolation overlay entre keyframes).

  // Mémorise la frame courante comme "précédente" (candidate n-1 d'un futur cut).
  // Le hash/forward ci-dessus n'ont pas consommé |bgra| (BigBuffer copie depuis
  // le span) → on peut le move ici.
  prev_hash_ = hash;
  has_prev_hash_ = true;
  prev_bgra_ = std::move(bgra);
  prev_width_ = width;
  prev_height_ = height;
  prev_media_time_ = media_time;
  has_prev_frame_ = true;
}

void BasarunaaRenderFrameObserver::OnAnalyzed(
    base::TimeDelta media_time,
    int width,
    int height,
    FrameKind kind,
    std::vector<mojom::AnalyzedPersonPtr> persons,
    const std::string& debug_mode,
    bool blur_enabled) {
  // ④a : pousse le verdict au JS de la page. Coords normalisées [0,1] (le JS
  // scale à l'affichage). detail = string JSON. Chaque personne : [nx, ny, nw,
  // nh, score, gender(-1|0|1), gender_conf, blur, gender_source]. `k` = nature de
  // la frame (0 keyframe | 1 avant-cut | 2 après-cut) → l'overlay borne
  // l'interpolation et snap au cut.
  const double w = width > 0 ? width : 1;
  const double h = height > 0 ? height : 1;
  base::ListValue boxes;
  for (const auto& p : persons) {
    base::ListValue box;
    box.Append(p->x / w);
    box.Append(p->y / h);
    box.Append(p->w / w);
    box.Append(p->h / h);
    box.Append(static_cast<double>(p->score));
    box.Append(static_cast<int>(p->gender));
    box.Append(static_cast<double>(p->gender_conf));
    box.Append(p->blur);
    box.Append(static_cast<int>(p->gender_source));
    boxes.Append(std::move(box));
  }
  base::DictValue dict;
  dict.Set("t", static_cast<double>(media_time.InMilliseconds()));
  dict.Set("debug", debug_mode);
  dict.Set("be", blur_enabled);
  dict.Set("k", static_cast<int>(kind));
  dict.Set("p", std::move(boxes));

  std::optional<std::string> json = base::WriteJson(dict);
  if (!json) {
    return;
  }
  // JSON-encode la string une 2e fois -> littéral JS échappé pour |detail|.
  std::optional<std::string> js_literal = base::WriteJson(base::Value(*json));
  if (!js_literal) {
    return;
  }
  std::string script =
      "document.dispatchEvent(new CustomEvent('bsr-native-result',{detail:" +
      *js_literal + "}))";
  content::RenderFrame* rf = render_frame();
  if (!rf) {
    return;
  }
  // ⚠️ NE PAS ExecuteScript ici (callback Mojo) : on poste une tâche fraîche.
  rf->GetTaskRunner(blink::TaskType::kInternalDefault)
      ->PostTask(
          FROM_HERE,
          base::BindOnce(&BasarunaaRenderFrameObserver::DispatchResultToPage,
                         weak_ptr_factory_.GetWeakPtr(), std::move(script)));
}

void BasarunaaRenderFrameObserver::DispatchResultToPage(std::string script) {
  content::RenderFrame* rf = render_frame();
  if (!rf) {
    return;
  }
  blink::WebLocalFrame* web_frame = rf->GetWebFrame();
  if (!web_frame || web_frame->IsProvisional()) {
    return;
  }
  // Main world : le content script (monde isolé) reçoit l'event DOM.
  web_frame->ExecuteScript(
      blink::WebScriptSource(blink::WebString::FromUTF8(script)));
}

void BasarunaaRenderFrameObserver::OnDestruct() {
  delete this;
}

}  // namespace basarunaa
