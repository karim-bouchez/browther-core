// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_COMPONENTS_BASARUNAA_RENDERER_BASARUNAA_RENDER_FRAME_OBSERVER_H_
#define BRAVE_COMPONENTS_BASARUNAA_RENDERER_BASARUNAA_RENDER_FRAME_OBSERVER_H_

#include <array>
#include <cstdint>
#include <deque>
#include <map>
#include <optional>
#include <string>
#include <vector>

#include "base/containers/span.h"
#include "base/functional/callback.h"
#include "base/memory/weak_ptr.h"
#include "base/time/time.h"
#include "brave/components/basarunaa/common/mojom/basarunaa.mojom.h"
#include "content/public/renderer/content_renderer_client.h"
#include "content/public/renderer/render_frame_observer.h"
#include "content/public/renderer/render_frame_observer_tracker.h"
#include "mojo/public/cpp/bindings/associated_receiver_set.h"
#include "mojo/public/cpp/bindings/pending_associated_receiver.h"
#include "mojo/public/cpp/bindings/remote.h"

namespace basarunaa {

// Nature de la frame envoyée à l'analyse, décidée par la politique de tap du RFO
// (cf. refonte 2026-07-04). Transmise à l'overlay pour borner l'interpolation.
//  - kKeyframe  : échantillon périodique garanti (~1/s) au sein d'une scène.
//  - kCutBefore : dernière frame de l'ANCIENNE scène (n-1) → borne d'interp fin.
//  - kCutAfter  : première frame de la NOUVELLE scène (n) → snap + nouvelle borne.
enum class FrameKind { kKeyframe = 0, kCutBefore = 1, kCutAfter = 2 };

// RFO C++ pur (pas de V8) du pipeline vidéo decode-ahead Basarunaa —
// DÉTECTION v2 (dichotomie keyframe-guidée, 2026-07-15). WebMediaPlayerImpl
// NOTIFIE chaque frame décodée-en-avance (métadonnées seulement) et fournit un
// handle « readback à la demande ». Le RFO décide QUOI lire : checkpoints à
// cadence bornée (kf + 2 probes de couverture) + dichotomie sur les sauts
// suspects → localisation EXACTE des cuts pour ~0 readback sans cut. Les
// frames retenues (keyframes ML + paires n-1/n de cut) partent au ML browser
// via Mojo AnalyzeImage (kBgra8) ; le verdict est poussé au JS de la page via
// CustomEvent 'bsr-native-result' pour l'overlay de flou.
class BasarunaaRenderFrameObserver final
    : public content::RenderFrameObserver,
      public content::RenderFrameObserverTracker<
          BasarunaaRenderFrameObserver>,
      public mojom::VideoTapConfig {
 public:
  explicit BasarunaaRenderFrameObserver(content::RenderFrame* render_frame);

  BasarunaaRenderFrameObserver(const BasarunaaRenderFrameObserver&) = delete;
  BasarunaaRenderFrameObserver& operator=(
      const BasarunaaRenderFrameObserver&) = delete;

  // [Browther/Basarunaa] decode-ahead ③ (v2, notify+pull) : renvoie le sink de
  // NOTIFICATION (player_id, media_ts, handle readback), borné au cycle de vie
  // de ce RFO (WeakPtr). WebMediaPlayerImpl (blink) l'appelle sur le main
  // thread pour CHAQUE frame décodée-en-avance.
  content::ContentRendererClient::VideoLeadFrameSink GetVideoLeadFrameSink();

  // Décision LIVE par player (lue par GetVideoLeadFrameSink à CHAQUE création
  // de WebMediaPlayer) : capacité native de ce build (switch
  // --basarunaa-video-tap, injecté sur la feature seule) ET pref utilisateur
  // courante (poussée par BasarunaaVideoTapTabHelper). Brancher le sink force
  // le decode-ahead 2 s côté VideoRendererImpl → on ne le pose JAMAIS pour un
  // utilisateur OFF. Toggle ON = pris en compte au prochain player (reload
  // d'onglet suffit, même process) ; OFF = live (gate dans
  // OnLeadFrameNotified, plus aucun readback ni ML).
  bool tap_enabled() const { return native_available_ && pref_enabled_; }

 private:
  using LeadFrameReadbackCB = content::ContentRendererClient::LeadFrameReadbackCB;

  // Frame lue (BGRA 640px issue du readback à la demande) + son hash 8×8.
  // Cachée le temps d'un checkpoint/scan pour (a) comparer, (b) forwarder au
  // ML sans re-readback si elle s'avère keyframe ou frontière de cut.
  struct LeadFrame {
    LeadFrame();
    LeadFrame(LeadFrame&&);
    LeadFrame& operator=(LeadFrame&&);
    LeadFrame(const LeadFrame&);
    LeadFrame& operator=(const LeadFrame&);
    ~LeadFrame();
    std::array<uint8_t, 64> hash = {};
    std::vector<uint8_t> bgra;
    int width = 0;
    int height = 0;
    base::TimeDelta ts;
  };
  // Saut suspect [lo, hi] à scanner par dichotomie (bornes = frames déjà lues,
  // présentes dans |frames|).
  struct PendingHop {
    base::TimeDelta lo;
    base::TimeDelta hi;
  };
  // État de détection PAR PLAYER (une page peut porter plusieurs <video> ;
  // Phase A entrelaçait leurs hash dans un seul flux = détection corrompue).
  struct PlayerDetector {
    PlayerDetector();
    ~PlayerDetector();
    // Échelle des ts décodés notifiés (triée croissante par construction,
    // reset sur seek arrière) : la VRAIE adjacence des frames, indépendante
    // du fps. La dichotomie travaille sur ses indices.
    std::deque<base::TimeDelta> ladder;
    // Handle de readback (rafraîchi à chaque notification).
    LeadFrameReadbackCB readback;
    // Invalidation des replies en vol après un reset (seek) : les callbacks
    // porteurs d'un epoch périmé sont ignorés.
    int epoch = 0;
    // Ancre = frame du checkpoint précédent (kf_prev), hash + bgra gardés
    // (un cut peut converger dessus → kCutBefore sans re-readback).
    std::optional<LeadFrame> anchor;
    // Frames lues du checkpoint courant, clé = ts en µs (bornes des sauts +
    // probes de dichotomie). Vidé en fin de checkpoint/scan.
    std::map<int64_t, LeadFrame> frames;
    // Checkpoint en cours : réponses attendues (kf_cur + probes ⅓/⅔).
    bool checkpoint_active = false;
    int pending_replies = 0;
    base::TimeDelta pending_kf_ts;
    bool got_kf = false;
    // Scan (dichotomie) en cours.
    bool scan_active = false;
    std::deque<PendingHop> hops;
    base::TimeDelta scan_lo;
    base::TimeDelta scan_hi;
    base::TimeDelta hop_lo;
    base::TimeDelta hop_hi;
    int probes_used = 0;
    bool ml_forwarded_this_checkpoint = false;
    // Cadences ML par player (chaque vidéo a son propre espace de ts).
    base::TimeDelta last_ml_keyframe_ts;
    bool has_ml_keyframe = false;
    base::TimeDelta last_nsfw_ts;
    bool nsfw_ts_init = false;
    // Hygiène (prune des players morts).
    base::TimeTicks last_seen;
    // Instrumentation [bsrV2].
    base::TimeTicks checkpoint_start_ticks;
    int readbacks_this_checkpoint = 0;
  };

  ~BasarunaaRenderFrameObserver() override;

  // RenderFrameObserver:
  void OnDestruct() override;

  // mojom::VideoTapConfig (browser → renderer, push du TabHelper) :
  void SetEnabled(bool enabled) override;

  void BindConfigReceiver(
      mojo::PendingAssociatedReceiver<mojom::VideoTapConfig> pending);

  bool EnsureConnected();
  // v2 ①  : notification d'une frame décodée-en-avance (main thread). Alimente
  // l'échelle des ts, gère le reset seek, déclenche les checkpoints.
  void OnLeadFrameNotified(int64_t player_id,
                           base::TimeDelta media_ts,
                           const LeadFrameReadbackCB& readback);
  // v2 ② : lance un checkpoint : readback de kf_cur (=|kf_ts|) + 2 probes de
  // couverture à ⅓/⅔ de l'intervalle depuis l'ancre (flash-cuts A→B→A′
  // invisibles au diff kf↔kf ; tout cutaway ≥ ⅓ d'intervalle est garanti vu).
  void StartCheckpoint(int64_t player_id, base::TimeDelta kf_ts);
  // v2 ② reply : une frame de checkpoint est arrivée (ou a échoué : bgra vide).
  void OnCheckpointFrame(int64_t player_id,
                         int epoch,
                         base::TimeDelta requested_ts,
                         std::vector<uint8_t> bgra,
                         int width,
                         int height,
                         base::TimeDelta actual_ts);
  // v2 ③ : toutes les réponses du checkpoint sont là → diffs de l'échelle
  // {ancre, p⅓, p⅔, kf}, keyframe ML si cadence due (inchangée), sauts
  // suspects → file de scan, nouvelle ancre = kf.
  void FinishCheckpoint(int64_t player_id);
  // v2 ④ : pompe la file des sauts suspects → dichotomie.
  void PumpScan(int64_t player_id);
  // v2 ④ : un pas de dichotomie sur [scan_lo, scan_hi] (readback du milieu ou
  // convergence → classification cut/pan + vérif multi-cut des côtés).
  void ScanStep(int64_t player_id);
  // v2 ④ : descente d'un pas — compare le hash du milieu aux deux bornes,
  // resserre [scan_lo, scan_hi] du côté du plus grand écart.
  void DescendScan(PlayerDetector& detector, const LeadFrame& mid);
  // v2 ④ reply : probe de dichotomie arrivé.
  void OnScanProbe(int64_t player_id,
                   int epoch,
                   base::TimeDelta requested_ts,
                   std::vector<uint8_t> bgra,
                   int width,
                   int height,
                   base::TimeDelta actual_ts);
  // v2 : fin de scan (file vide) ou abandon (échec readback / cap probes) →
  // prune de l'échelle + libération des frames du checkpoint. En cas
  // d'abandon, forwarde l'ancre en keyframe si rien n'est parti au ML ce
  // checkpoint (l'overlay retombe sur l'interpolation-union : sur-flou sûr).
  void EndScan(int64_t player_id, bool aborted, const char* reason);
  // v2 : reset du détecteur d'un player (seek arrière) — epoch++.
  void ResetDetector(PlayerDetector& detector);
  // Cadence des checkpoints : min(KeyframeInterval(), plafond 1000 ms). Le
  // plafond garantit que le scan d'un intervalle finit avant que ses frames
  // n'atteignent l'affichage (lead 2 s), même en safe-state (2500 ms).
  base::TimeDelta CheckpointInterval() const;
  // Intervalle keyframe ML ADAPTATIF (INCHANGÉ) : borné [MIN, MAX], =
  // round-trip d'analyse mesuré × facteur (défaut avant la 1re mesure).
  base::TimeDelta KeyframeInterval() const;
  // Envoie une frame à l'analyse ML (Mojo AnalyzeImage, kBgra8) en taguant sa
  // nature |kind| + le diff hash frame-à-frame |diff| de cette frame (rattaché
  // au résultat via le callback lié → jamais sur le fil ; sert au HUD debug pour
  // VISUALISER la détection de cut, cf. flash cut overlay).
  void ForwardForAnalysis(base::span<const uint8_t> bgra,
                          int width,
                          int height,
                          base::TimeDelta media_time,
                          FrameKind kind,
                          float diff,
                          bool want_nsfw);
  // ④a : reçoit le verdict ML (bboxes en pixels de l'image analysée
  // |width|×|height|) + le temps média + la nature |kind| + le diff hash de la
  // frame, et pousse le résultat au JS de la page (CustomEvent 'bsr-native-result',
  // detail = JSON, coords normalisées).
  void OnAnalyzed(base::TimeDelta media_time,
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
                  bool censor_eyes);
  // Exécute le dispatch JS. Posté en tâche fraîche (pas dans le callback Mojo)
  // pour éviter un ExecuteScript en zone ScriptForbiddenScope.
  void DispatchResultToPage(std::string script);

  mojo::Remote<mojom::ImageAnalyzer> image_analyzer_;
  mojo::AssociatedReceiverSet<mojom::VideoTapConfig> config_receivers_;

  // Capacité native du build (switch, immuable) / pref utilisateur (poussée,
  // défaut false — le push du TabHelper arrive à RenderFrameCreated, bien
  // avant tout media player).
  bool native_available_ = false;
  bool pref_enabled_ = false;

  // Détecteurs v2, un par player (main thread only). Prunés quand un player ne
  // notifie plus (hygiène : un WMPI détruit ne préviendra pas).
  std::map<int64_t, PlayerDetector> players_;
  // Intervalle keyframe adaptatif : EMA du round-trip d'analyse (keyframes).
  // GLOBAL au RFO : mesure le coût du service ML, pas d'un player.
  double analysis_ema_ms_ = 0.0;
  bool analysis_ema_init_ = false;
  // Safe-state (#10) : keyframes/cut-after consécutifs SANS aucune personne. Au
  // seuil kSafeEmptyFrames, KeyframeInterval() ralentit la cadence (scène vide →
  // inutile de recalculer souvent). Reset par un cut ou un résultat ≥1 personne.
  int consecutive_empty_frames_ = 0;

  base::WeakPtrFactory<BasarunaaRenderFrameObserver> weak_ptr_factory_{this};
};

}  // namespace basarunaa

#endif  // BRAVE_COMPONENTS_BASARUNAA_RENDERER_BASARUNAA_RENDER_FRAME_OBSERVER_H_
