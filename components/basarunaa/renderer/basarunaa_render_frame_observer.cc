// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/components/basarunaa/renderer/basarunaa_render_frame_observer.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <deque>
#include <iterator>
#include <map>
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

// DÉTECTION v2 — dichotomie keyframe-guidée (2026-07-15, remplace le hash
// dense de Phase A). Le renderer NOTIFIE chaque frame décodée-en-avance
// (métadonnées seulement, pas de pixels) et fournit un handle « readback à la
// demande ». Politique du RFO :
//   - CHECKPOINT à cadence bornée (CheckpointInterval() = min(cadence ML,
//     1000 ms)) : readback + hash de kf_cur ET de 2 probes de couverture à
//     ⅓/⅔ de l'intervalle. kf_cur part au ML (kKeyframe) si la cadence ML
//     adaptative est due (INCHANGÉE) ; les probes sont hash-only. Les probes
//     couvrent les flash-cuts A→B→A′ (cutaway court revenant à la même
//     scène) : invisibles au diff kf↔kf, ils seraient une FUITE (personne du
//     flash non floutée). Tout cutaway ≥ ⅓ d'intervalle est garanti détecté.
//   - Chaque saut adjacent de l'échelle {ancre, p⅓, p⅔, kf} dont le diff
//     dépasse kScanThreshold → DICHOTOMIE sur l'échelle EXACTE des ts notifiés
//     (~log₂ N readbacks) jusqu'à la paire ADJACENTE (n-1, n).
//   - Classification à convergence : diff(n-1,n) > kCutThreshold = CUT (mêmes
//     seuil et sémantique que le hash dense de Phase A) → paire kCutBefore /
//     kCutAfter au ML, frames EXACTES. Diff petit = pan/zoom (drift graduel)
//     → rien, l'overlay interpole.
//   - MULTI-CUTS : si un côté de la paire ne ressemble pas à sa borne du saut
//     (diff > kScanThreshold, hash-compare pur), un autre cut s'y cache →
//     récursion sur ce côté. Cap dur kMaxScanProbes par checkpoint ; au cap ou
//     sur échec de readback → abandon PROPRE (l'overlay retombe sur
//     l'interpolation-union symétrique : sur-flou, jamais de fuite).
// Coût : ~3 readbacks/s sans cut (vs ~30/s Phase A), +3-6 par cut.
// L'overlay confirme toujours par la continuité des PERSONNES (défense en
// profondeur), cf. video-native/main.ts.
//
// Intervalle keyframe ML ADAPTATIF (INCHANGÉ) : c'est la cadence de l'analyse
// ML (coûteuse), = round-trip mesuré × facteur, borné [MIN, MAX]. Bon PC →
// plancher MIN ; PC lent → plafond MAX (pas de backlog). NB : ceci ≠ la
// cadence des checkpoints (hash, bon marché) qui sert la détection de cut.
constexpr double kKeyframeMinMs = 400.0;
constexpr double kKeyframeMaxMs = 1200.0;
constexpr double kKeyframeDefaultMs = 700.0;
constexpr double kKeyframeLatencyFactor = 3.0;  // intervalle ≈ 3× coût d'analyse
// Plafond de la cadence des CHECKPOINTS : garantit que le scan d'un intervalle
// finit largement avant que ses frames n'atteignent l'affichage (lead 2 s) —
// budget pire cas ≈ 1000 (checkpoint) + ~600 (scan p90) + ~100 (analyse paire)
// ≪ 2000 ms. Sans ce plafond, le safe-state (2500 ms) ferait afficher des
// frames avant leur scan.
constexpr double kCheckpointMaxMs = 1000.0;
// Détection de cut : seuil ABSOLU sur le diff hash de deux frames ADJACENTES
// (à convergence de la dichotomie). Même sémantique/valeur que le hash dense
// de Phase A : un vrai cut est bien au-dessus, un pan/zoom bien en-dessous.
constexpr float kCutThreshold = 0.12f;
// Déclencheur de scan : diff d'un saut de l'échelle de checkpoint (≈ ⅓
// d'intervalle). PLUS BAS que kCutThreshold : deux scènes peuvent se
// ressembler en 8×8 (le diff kf↔kf minore le diff adjacent au cut), et un pan
// n'accumule sur ⅓ d'intervalle que ~⅓ de sa dérive. Un scan déclenché pour
// rien est bon marché (~log₂ N readbacks) et conclut « pan ».
constexpr float kScanThreshold = 0.06f;
// Cap dur de readbacks de dichotomie par checkpoint (multi-cuts compris) :
// ~log₂(30) ≈ 5 par cut, 16 couvre ≥ 2 cuts + marge. Au-delà = montage
// pathologique → abandon propre (interpolation-union côté overlay).
constexpr int kMaxScanProbes = 16;
// Garde-fou mémoire de l'échelle des ts (2 s @ 60 fps = 120 ; large marge).
constexpr size_t kLadderCap = 256;
// Hygiène de la map des players : au-delà, prune ceux muets depuis > 30 s.
constexpr size_t kMaxPlayers = 4;
constexpr base::TimeDelta kStalePlayerAfter = base::Seconds(30);
// Réveil safe-state : un changement notable (personne qui entre une scène vide)
// dépasse ce petit seuil sans être un cut → réveille la cadence keyframe ralentie.
constexpr float kSceneWakeThreshold = 0.02f;
// Cadence du check NSFW (Marqo ~120ms) : ~1/s + sur chaque cut. Le NSFW ne change
// pas d'une frame à l'autre → inutile de le payer à chaque keyframe.
constexpr double kNsfwIntervalMs = 1000.0;

// Safe-state (#10) : quand N keyframes consécutifs ne trouvent AUCUNE personne
// (scène vide confirmée), on RALENTIT la cadence keyframe (× facteur, cap dur)
// pour ne pas gâcher du calcul sur une scène sans personne. Réveil immédiat :
// un cut (une personne qui entre une scène statique EN EST un → capté frame à
// frame) OU un pic pixel en safe-state force une analyse malgré la cadence
// ralentie → borne la latence de détection d'une personne qui apparaît.
constexpr int kSafeEmptyFrames = 3;
constexpr double kSafeStateFactor = 2.5;
constexpr double kKeyframeSafeMaxMs = 2500.0;

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

// Snap d'un ts cible sur l'échelle EXACTE des ts notifiés (le plus proche).
base::TimeDelta NearestLadderTs(const std::deque<base::TimeDelta>& ladder,
                                base::TimeDelta target) {
  DCHECK(!ladder.empty());
  const auto it = std::lower_bound(ladder.begin(), ladder.end(), target);
  if (it == ladder.end()) {
    return ladder.back();
  }
  if (it == ladder.begin()) {
    return *it;
  }
  return (*it - target <= target - *std::prev(it)) ? *it : *std::prev(it);
}

}  // namespace

// Out-of-line (chromium-style : structs complexes).
BasarunaaRenderFrameObserver::LeadFrame::LeadFrame() = default;
BasarunaaRenderFrameObserver::LeadFrame::LeadFrame(LeadFrame&&) = default;
BasarunaaRenderFrameObserver::LeadFrame&
BasarunaaRenderFrameObserver::LeadFrame::operator=(LeadFrame&&) = default;
BasarunaaRenderFrameObserver::LeadFrame::LeadFrame(const LeadFrame&) = default;
BasarunaaRenderFrameObserver::LeadFrame&
BasarunaaRenderFrameObserver::LeadFrame::operator=(const LeadFrame&) = default;
BasarunaaRenderFrameObserver::LeadFrame::~LeadFrame() = default;
BasarunaaRenderFrameObserver::PlayerDetector::PlayerDetector() = default;
BasarunaaRenderFrameObserver::PlayerDetector::~PlayerDetector() = default;

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

content::ContentRendererClient::VideoLeadFrameSink
BasarunaaRenderFrameObserver::GetVideoLeadFrameSink() {
  return base::BindRepeating(
      &BasarunaaRenderFrameObserver::OnLeadFrameNotified,
      weak_ptr_factory_.GetWeakPtr());
}

base::TimeDelta BasarunaaRenderFrameObserver::KeyframeInterval() const {
  double iv = analysis_ema_init_ ? analysis_ema_ms_ * kKeyframeLatencyFactor
                                 : kKeyframeDefaultMs;
  iv = std::clamp(iv, kKeyframeMinMs, kKeyframeMaxMs);
  // Safe-state : scène vide confirmée → cadence ralentie (bornée par cap dur).
  if (consecutive_empty_frames_ >= kSafeEmptyFrames) {
    iv = std::min(iv * kSafeStateFactor, kKeyframeSafeMaxMs);
  }
  return base::Milliseconds(iv);
}

base::TimeDelta BasarunaaRenderFrameObserver::CheckpointInterval() const {
  return std::min(KeyframeInterval(), base::Milliseconds(kCheckpointMaxMs));
}

void BasarunaaRenderFrameObserver::ForwardForAnalysis(
    base::span<const uint8_t> bgra,
    int width,
    int height,
    base::TimeDelta media_time,
    FrameKind kind,
    float diff,
    bool want_nsfw) {
  if (!EnsureConnected()) {
    return;
  }
  mojo_base::BigBuffer buffer{bgra};
  VLOG(1) << "[bsrV2] → ML kind=" << static_cast<int>(kind)
          << " ts=" << media_time.InMilliseconds() << "ms nsfw=" << want_nsfw
          << " iv=" << KeyframeInterval().InMillisecondsF()
          << " ema=" << (analysis_ema_init_ ? analysis_ema_ms_ : -1);
  // Horodatage d'envoi → mesure du round-trip d'analyse dans OnAnalyzed (sert à
  // l'intervalle keyframe adaptatif).
  const base::TimeTicks sent = base::TimeTicks::Now();
  image_analyzer_->AnalyzeImage(
      std::move(buffer), width, height, mojom::ImageFormat::kBgra8, want_nsfw,
      base::BindOnce(&BasarunaaRenderFrameObserver::OnAnalyzed,
                     weak_ptr_factory_.GetWeakPtr(), media_time, width, height,
                     kind, diff, sent, want_nsfw));
}

void BasarunaaRenderFrameObserver::OnLeadFrameNotified(
    int64_t player_id,
    base::TimeDelta media_ts,
    const LeadFrameReadbackCB& readback) {
  // v2 ① : notification légère (pas de pixels) d'une frame décodée-en-avance.
  PlayerDetector& detector = players_[player_id];
  detector.last_seen = base::TimeTicks::Now();
  detector.readback = readback;

  // Hygiène : un WMPI détruit ne prévient pas → prune des players muets.
  if (players_.size() > kMaxPlayers) {
    for (auto it = players_.begin(); it != players_.end();) {
      if (it->first != player_id &&
          detector.last_seen - it->second.last_seen > kStalePlayerAfter) {
        it = players_.erase(it);
      } else {
        ++it;
      }
    }
  }

  // Seek arrière → reset complet (epoch++ invalide les replies en vol).
  if (!detector.ladder.empty() && media_ts < detector.ladder.back()) {
    VLOG(1) << "[bsrV2] p" << player_id << " seek arrière ("
            << media_ts.InMilliseconds() << "ms) → reset";
    ResetDetector(detector);
  }
  if (detector.ladder.empty() || media_ts > detector.ladder.back()) {
    detector.ladder.push_back(media_ts);
    if (detector.ladder.size() > kLadderCap) {
      detector.ladder.pop_front();
    }
  }

  // Un seul checkpoint/scan à la fois par player (la machine se réarme dans
  // FinishCheckpoint/EndScan ; en cas de retard, le prochain checkpoint part
  // dès la notification suivante — rattrapage naturel).
  if (detector.checkpoint_active || detector.scan_active) {
    return;
  }
  if (!detector.anchor) {
    // Bootstrap : 1re frame = keyframe ML immédiat (comme Phase A), pas de
    // probes (pas d'intervalle).
    StartCheckpoint(player_id, media_ts);
    return;
  }
  if (media_ts - detector.anchor->ts >= CheckpointInterval()) {
    StartCheckpoint(player_id, media_ts);
  }
}

void BasarunaaRenderFrameObserver::StartCheckpoint(int64_t player_id,
                                                   base::TimeDelta kf_ts) {
  // v2 ② : readback de kf_cur + 2 probes de couverture à ⅓/⅔ de l'intervalle
  // (snappés sur l'échelle EXACTE, dédoublonnés — intervalle court / fps bas).
  PlayerDetector& detector = players_[player_id];
  detector.checkpoint_active = true;
  detector.got_kf = false;
  detector.pending_kf_ts = kf_ts;
  detector.frames.clear();
  detector.hops.clear();
  detector.probes_used = 0;
  detector.readbacks_this_checkpoint = 0;
  detector.ml_forwarded_this_checkpoint = false;
  detector.checkpoint_start_ticks = base::TimeTicks::Now();

  std::vector<base::TimeDelta> targets;
  if (detector.anchor) {
    const base::TimeDelta delta = kf_ts - detector.anchor->ts;
    for (int k = 1; k <= 2; ++k) {
      const base::TimeDelta t =
          NearestLadderTs(detector.ladder, detector.anchor->ts + delta * k / 3);
      if (t > detector.anchor->ts && t < kf_ts &&
          (targets.empty() || t != targets.back())) {
        targets.push_back(t);
      }
    }
  }
  targets.push_back(kf_ts);

  detector.pending_replies = static_cast<int>(targets.size());
  detector.readbacks_this_checkpoint += detector.pending_replies;
  for (const base::TimeDelta target : targets) {
    detector.readback.Run(
        target,
        base::BindOnce(&BasarunaaRenderFrameObserver::OnCheckpointFrame,
                       weak_ptr_factory_.GetWeakPtr(), player_id,
                       detector.epoch, target));
  }
}

void BasarunaaRenderFrameObserver::OnCheckpointFrame(
    int64_t player_id,
    int epoch,
    base::TimeDelta requested_ts,
    std::vector<uint8_t> bgra,
    int width,
    int height,
    base::TimeDelta actual_ts) {
  const auto it = players_.find(player_id);
  if (it == players_.end() || it->second.epoch != epoch ||
      !it->second.checkpoint_active) {
    return;  // reset/prune entre-temps : reply périmé
  }
  PlayerDetector& detector = it->second;
  if (!bgra.empty()) {
    LeadFrame frame;
    frame.hash =
        ComputeHash8x8(base::span<const uint8_t>(bgra), width, height);
    frame.bgra = std::move(bgra);
    frame.width = width;
    frame.height = height;
    frame.ts = actual_ts;
    if (requested_ts == detector.pending_kf_ts) {
      detector.got_kf = true;
    }
    detector.frames[actual_ts.InMicroseconds()] = std::move(frame);
  } else {
    VLOG(1) << "[bsrV2] p" << player_id << " checkpoint probe FAIL req="
            << requested_ts.InMilliseconds() << "ms";
  }
  if (--detector.pending_replies <= 0) {
    FinishCheckpoint(player_id);
  }
}

void BasarunaaRenderFrameObserver::FinishCheckpoint(int64_t player_id) {
  // v2 ③ : diffs de l'échelle {ancre, p⅓, p⅔, kf} → keyframe ML (cadence
  // adaptative inchangée), sauts suspects → scans, nouvelle ancre = kf.
  PlayerDetector& detector = players_[player_id];
  detector.checkpoint_active = false;
  if (!detector.got_kf || detector.frames.empty()) {
    // kf raté (éviction/seek/teardown) : on garde l'ancre ; l'intervalle étant
    // déjà écoulé, la prochaine notification relance immédiatement.
    VLOG(1) << "[bsrV2] p" << player_id << " checkpoint ABORT (kf manquant)";
    detector.frames.clear();
    return;
  }

  if (detector.anchor) {
    // L'ancre entre dans |frames| : borne gauche des sauts (et candidate
    // kCutBefore si un cut converge dessus).
    detector.frames[detector.anchor->ts.InMicroseconds()] = *detector.anchor;
  }
  std::vector<const LeadFrame*> points;
  points.reserve(detector.frames.size());
  for (const auto& [ts_us, frame] : detector.frames) {
    points.push_back(&frame);
  }
  const LeadFrame& kf = *points.back();

  bool wake = false;
  for (size_t i = 1; i < points.size(); ++i) {
    const float diff = HashDiff(points[i - 1]->hash, points[i]->hash);
    if (diff > kSceneWakeThreshold) {
      wake = true;
    }
    if (diff > kScanThreshold) {
      detector.hops.push_back({points[i - 1]->ts, points[i]->ts});
    }
  }
  const float overall =
      detector.anchor ? HashDiff(detector.anchor->hash, kf.hash) : 1.f;

  // Keyframe ML si la cadence ADAPTATIVE (inchangée) est due — ou réveil
  // safe-state (Phase A : analyse forcée sur changement en scène vide).
  // ⚠️ LOOKAHEAD : la décision n'est évaluée qu'aux checkpoints → sans
  // lookahead, un intervalle ML dans (checkpoint, 2×checkpoint] serait arrondi
  // AU CHECKPOINT SUIVANT (cadence effective ~2× l'intervalle → trous >
  // STALE_MS → full-blur overlay). On forwarde au checkpoint le PLUS PROCHE de
  // l'échéance : si attendre le prochain rendrait la keyframe en retard, elle
  // part maintenant (arrondi vers le bas — jamais d'affamement du store).
  const base::TimeDelta since_ml = kf.ts - detector.last_ml_keyframe_ts;
  const bool due_keyframe =
      !detector.has_ml_keyframe ||
      since_ml + CheckpointInterval() >= KeyframeInterval();
  const bool safe_wake =
      consecutive_empty_frames_ >= kSafeEmptyFrames && wake;
  // Throttle NSFW (Marqo, ~120ms) : cuts (nouvelle scène) + cadence lâche
  // ~1/s ailleurs. Entre deux, l'overlay gèle le verdict.
  const bool due_nsfw =
      !detector.nsfw_ts_init ||
      (kf.ts - detector.last_nsfw_ts) >= base::Milliseconds(kNsfwIntervalMs);
  if (due_keyframe || safe_wake) {
    ForwardForAnalysis(base::span<const uint8_t>(kf.bgra), kf.width, kf.height,
                       kf.ts, FrameKind::kKeyframe, overall, due_nsfw);
    detector.last_ml_keyframe_ts = kf.ts;
    detector.has_ml_keyframe = true;
    detector.ml_forwarded_this_checkpoint = true;
    if (due_nsfw) {
      detector.last_nsfw_ts = kf.ts;
      detector.nsfw_ts_init = true;
    }
  }

  // Nouvelle ancre = kf (copie : |frames| garde son exemplaire pour les scans).
  detector.anchor = kf;

  if (detector.hops.empty()) {
    EndScan(player_id, /*aborted=*/false, "sans scan");
    return;
  }
  detector.scan_active = true;
  PumpScan(player_id);
}

void BasarunaaRenderFrameObserver::PumpScan(int64_t player_id) {
  PlayerDetector& detector = players_[player_id];
  if (detector.hops.empty()) {
    EndScan(player_id, /*aborted=*/false, "scans finis");
    return;
  }
  const PendingHop hop = detector.hops.front();
  detector.hops.pop_front();
  detector.scan_lo = detector.hop_lo = hop.lo;
  detector.scan_hi = detector.hop_hi = hop.hi;
  ScanStep(player_id);
}

void BasarunaaRenderFrameObserver::ScanStep(int64_t player_id) {
  // v2 ④ : un pas de dichotomie sur [scan_lo, scan_hi] (échelle exacte).
  PlayerDetector& detector = players_[player_id];
  const auto lo_it = std::lower_bound(detector.ladder.begin(),
                                      detector.ladder.end(), detector.scan_lo);
  const auto hi_it = std::lower_bound(detector.ladder.begin(),
                                      detector.ladder.end(), detector.scan_hi);
  if (lo_it == detector.ladder.end() || hi_it == detector.ladder.end()) {
    EndScan(player_id, /*aborted=*/true, "borne hors échelle");
    return;
  }
  const size_t lo_idx = static_cast<size_t>(lo_it - detector.ladder.begin());
  const size_t hi_idx = static_cast<size_t>(hi_it - detector.ladder.begin());

  if (hi_idx <= lo_idx + 1) {
    // CONVERGÉ : paire ADJACENTE (n-1, n) → classification cut vs pan.
    const auto lo_frame = detector.frames.find(detector.scan_lo.InMicroseconds());
    const auto hi_frame = detector.frames.find(detector.scan_hi.InMicroseconds());
    if (lo_frame == detector.frames.end() ||
        hi_frame == detector.frames.end()) {
      EndScan(player_id, /*aborted=*/true, "borne sans frame");
      return;
    }
    const LeadFrame& before = lo_frame->second;
    const LeadFrame& after = hi_frame->second;
    const float adjacent = HashDiff(before.hash, after.hash);
    if (adjacent > kCutThreshold) {
      // CUT EXACT : paire n-1/n au ML (buffers déjà en main — zéro readback
      // en plus). NSFW re-checké sur la nouvelle scène ; réarme la cadence
      // keyframe + reset safe-state (comme Phase A).
      VLOG(1) << "[bsrV2] p" << player_id << " ✂ CUT @"
              << after.ts.InMilliseconds() << "ms (adj=" << adjacent
              << " probes=" << detector.probes_used << ")";
      ForwardForAnalysis(base::span<const uint8_t>(before.bgra), before.width,
                         before.height, before.ts, FrameKind::kCutBefore, 0.f,
                         /*want_nsfw=*/false);
      ForwardForAnalysis(base::span<const uint8_t>(after.bgra), after.width,
                         after.height, after.ts, FrameKind::kCutAfter, adjacent,
                         /*want_nsfw=*/true);
      detector.last_ml_keyframe_ts = after.ts;
      detector.has_ml_keyframe = true;
      detector.last_nsfw_ts = after.ts;
      detector.nsfw_ts_init = true;
      detector.ml_forwarded_this_checkpoint = true;
      consecutive_empty_frames_ = 0;
    } else {
      VLOG(1) << "[bsrV2] p" << player_id << " ↔ pan @"
              << after.ts.InMilliseconds() << "ms (adj=" << adjacent << ")";
    }
    // MULTI-CUTS : un côté qui ne ressemble pas à sa borne d'origine du saut
    // cache un AUTRE cut → récursion sur ce côté (hash-compare pur, 0
    // readback ici). Terminaison : chaque récursion rétrécit strictement, cap
    // kMaxScanProbes en backstop.
    const auto hop_lo_frame =
        detector.frames.find(detector.hop_lo.InMicroseconds());
    const auto hop_hi_frame =
        detector.frames.find(detector.hop_hi.InMicroseconds());
    if (hop_lo_frame != detector.frames.end() &&
        detector.scan_lo > detector.hop_lo &&
        HashDiff(hop_lo_frame->second.hash, before.hash) > kScanThreshold) {
      detector.hops.push_back({detector.hop_lo, detector.scan_lo});
    }
    if (hop_hi_frame != detector.frames.end() &&
        detector.scan_hi < detector.hop_hi &&
        HashDiff(after.hash, hop_hi_frame->second.hash) > kScanThreshold) {
      detector.hops.push_back({detector.scan_hi, detector.hop_hi});
    }
    PumpScan(player_id);
    return;
  }

  const base::TimeDelta mid = detector.ladder[lo_idx + (hi_idx - lo_idx) / 2];
  const auto cached = detector.frames.find(mid.InMicroseconds());
  if (cached != detector.frames.end()) {
    // Déjà lue (probe de couverture / scan précédent) → descente gratuite.
    DescendScan(detector, cached->second);
    ScanStep(player_id);
    return;
  }
  if (detector.probes_used >= kMaxScanProbes) {
    EndScan(player_id, /*aborted=*/true, "cap probes");
    return;
  }
  ++detector.probes_used;
  ++detector.readbacks_this_checkpoint;
  detector.readback.Run(
      mid, base::BindOnce(&BasarunaaRenderFrameObserver::OnScanProbe,
                          weak_ptr_factory_.GetWeakPtr(), player_id,
                          detector.epoch, mid));
}

void BasarunaaRenderFrameObserver::DescendScan(PlayerDetector& detector,
                                               const LeadFrame& mid) {
  const auto lo_frame = detector.frames.find(detector.scan_lo.InMicroseconds());
  const auto hi_frame = detector.frames.find(detector.scan_hi.InMicroseconds());
  const float diff_lo = lo_frame != detector.frames.end()
                            ? HashDiff(mid.hash, lo_frame->second.hash)
                            : 1.f;
  const float diff_hi = hi_frame != detector.frames.end()
                            ? HashDiff(mid.hash, hi_frame->second.hash)
                            : 1.f;
  // Le milieu appartient à une des deux scènes : le cut est du côté du PLUS
  // GRAND écart.
  if (diff_lo >= diff_hi) {
    detector.scan_hi = mid.ts;
  } else {
    detector.scan_lo = mid.ts;
  }
}

void BasarunaaRenderFrameObserver::OnScanProbe(int64_t player_id,
                                               int epoch,
                                               base::TimeDelta requested_ts,
                                               std::vector<uint8_t> bgra,
                                               int width,
                                               int height,
                                               base::TimeDelta actual_ts) {
  const auto it = players_.find(player_id);
  if (it == players_.end() || it->second.epoch != epoch ||
      !it->second.scan_active) {
    return;  // reset/prune entre-temps : reply périmé
  }
  PlayerDetector& detector = it->second;
  if (bgra.empty()) {
    EndScan(player_id, /*aborted=*/true, "readback échoué");
    return;
  }
  LeadFrame frame;
  frame.hash = ComputeHash8x8(base::span<const uint8_t>(bgra), width, height);
  frame.bgra = std::move(bgra);
  frame.width = width;
  frame.height = height;
  frame.ts = actual_ts;
  const LeadFrame& stored =
      (detector.frames[actual_ts.InMicroseconds()] = std::move(frame));
  DescendScan(detector, stored);
  ScanStep(player_id);
}

void BasarunaaRenderFrameObserver::EndScan(int64_t player_id,
                                           bool aborted,
                                           const char* reason) {
  PlayerDetector& detector = players_[player_id];
  if (aborted && !detector.ml_forwarded_this_checkpoint && detector.anchor) {
    // Filet : rien n'est parti au ML ce checkpoint → forwarde l'ancre (kf) en
    // keyframe. L'overlay a les personnes des deux scènes → interp-union
    // symétrique : sur-flou sûr, jamais de fuite.
    const LeadFrame& anchor = *detector.anchor;
    ForwardForAnalysis(base::span<const uint8_t>(anchor.bgra), anchor.width,
                       anchor.height, anchor.ts, FrameKind::kKeyframe, 1.f,
                       /*want_nsfw=*/false);
    detector.last_ml_keyframe_ts = anchor.ts;
    detector.has_ml_keyframe = true;
  }
  VLOG(1) << "[bsrV2] p" << player_id << " checkpoint fin ("
          << (aborted ? "ABORT: " : "") << reason
          << ") readbacks=" << detector.readbacks_this_checkpoint
          << " probes=" << detector.probes_used << " total="
          << (base::TimeTicks::Now() - detector.checkpoint_start_ticks)
                 .InMillisecondsF()
          << "ms";
  detector.scan_active = false;
  detector.hops.clear();
  detector.frames.clear();
  // Prune de l'échelle : tout ce qui précède l'ancre est scanné/derrière.
  while (!detector.ladder.empty() && detector.anchor &&
         detector.ladder.front() < detector.anchor->ts) {
    detector.ladder.pop_front();
  }
}

void BasarunaaRenderFrameObserver::ResetDetector(PlayerDetector& detector) {
  ++detector.epoch;  // invalide les replies en vol
  detector.ladder.clear();
  detector.frames.clear();
  detector.hops.clear();
  detector.anchor.reset();
  detector.checkpoint_active = false;
  detector.scan_active = false;
  detector.pending_replies = 0;
  detector.got_kf = false;
  detector.probes_used = 0;
  detector.has_ml_keyframe = false;
  detector.nsfw_ts_init = false;
  detector.ml_forwarded_this_checkpoint = false;
  // EMA / safe-state globaux conservés (coût du service ML, pas du player).
}

void BasarunaaRenderFrameObserver::OnAnalyzed(
    base::TimeDelta media_time,
    int width,
    int height,
    FrameKind kind,
    float diff,
    base::TimeTicks sent,
    bool want_nsfw,
    std::vector<mojom::AnalyzedPersonPtr> persons,
    const std::string& debug_mode,
    bool blur_enabled,
    const std::string& mode,
    double gender_certainty,
    double min_skeleton,
    bool nsfw,
    float nsfw_score,
    bool censor_eyes) {
  // Round-trip d'analyse (keyframes seulement : espacés, non queués derrière une
  // paire de cut → coût d'UNE analyse). Alimente l'intervalle keyframe adaptatif.
  // EXCLUT les frames NSFW-checkées (Marqo/NudeNet ~120ms throttlés ~1/s) : l'EMA
  // doit refléter le coût de BASE (pose+visage+genre), pas le pic NSFW ponctuel.
  if (kind == FrameKind::kKeyframe && !want_nsfw) {
    const double rt = (base::TimeTicks::Now() - sent).InMillisecondsF();
    analysis_ema_ms_ =
        analysis_ema_init_ ? analysis_ema_ms_ * 0.9 + rt * 0.1 : rt;
    analysis_ema_init_ = true;
    VLOG(1) << "[bsrV2] ← ML rt=" << rt << "ms ema=" << analysis_ema_ms_
            << " ts=" << media_time.InMilliseconds()
            << "ms persons=" << persons.size();
  }
  // Safe-state (#10) : compte les keyframes / cut-after SANS aucune personne
  // (scène vide, comptage sur les détections BRUTES YOLO — conservateur : le
  // moindre faux positif garde la cadence rapide). ≥1 personne → reset. Un cut
  // reset aussi (OnVideoLeadFrame). Cf. KeyframeInterval().
  if (kind == FrameKind::kKeyframe || kind == FrameKind::kCutAfter) {
    if (persons.empty()) {
      ++consecutive_empty_frames_;
    } else {
      consecutive_empty_frames_ = 0;
    }
  }
  // ④a : pousse le verdict au JS de la page. Coords normalisées [0,1] (le JS
  // scale à l'affichage). detail = string JSON. Chaque personne (single-shot
  // gender-v2n) : [nx, ny, nw, nh, score, gender(-1|0|1|2), gender_conf, blur,
  // keypoints]. gender 2 = enfant (non flouté si confiant). Le vote temporel +
  // le recalcul shouldBlur vivent côté overlay. `k` = nature de la frame
  // (0 keyframe | 1 avant-cut | 2 après-cut) → l'overlay borne l'interpolation
  // et snap au cut. `m`/`gc` = mode + certitude.
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
    // b[8] = keypoints [[x,y,c],…] normalisés (squelette debug + min-squelette +
    // flou polygone côté overlay). Arrondi 3 déc. pour limiter la taille du JSON.
    base::ListValue kps;
    for (const auto& kp : p->keypoints) {
      base::ListValue t;
      t.Append(std::round(kp->x * 1000.0) / 1000.0);
      t.Append(std::round(kp->y * 1000.0) / 1000.0);
      t.Append(std::round(kp->confidence * 100.0) / 100.0);
      kps.Append(std::move(t));
    }
    box.Append(std::move(kps));
    boxes.Append(std::move(box));
  }
  base::DictValue dict;
  dict.Set("t", static_cast<double>(media_time.InMilliseconds()));
  dict.Set("debug", debug_mode);
  dict.Set("be", blur_enabled);
  dict.Set("k", static_cast<int>(kind));
  dict.Set("d", static_cast<double>(diff));  // diff hash frame-à-frame (HUD debug)
  dict.Set("iv", KeyframeInterval().InMillisecondsF());  // intervalle keyframe adaptatif
  dict.Set("lat", analysis_ema_init_ ? analysis_ema_ms_ : -1.0);  // round-trip analyse (ms)
  dict.Set("m", mode);                        // mode flou (recalcul shouldBlur voté)
  dict.Set("gc", gender_certainty);           // certitude genre
  dict.Set("ms", min_skeleton);               // seuil min-squelette (filtre overlay)
  dict.Set("nsfw", nsfw);                      // flou plein cadre NSFW (Marqo)
  dict.Set("nsc", static_cast<double>(nsfw_score));  // score NSFW (HUD debug)
  dict.Set("ce", censor_eyes);                 // censure des yeux (bande floutée overlay)
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
