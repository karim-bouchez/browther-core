// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// Basarunaa V1 (étape A) : flou CSS naïf sur toutes les <img>.
// Pas de ML — c'est juste le PoC du pipeline d'interception (script handler,
// lifecycle tab, MutationObserver). L'étape B branchera l'analyse ML par image.

window.__firefox__.includeOnce("BasarunaaScript", function($) {
  'use strict';

  // ─── Bridge to Swift ───
  function send(action, data) {
    try {
      $.postNativeMessage('$<message_handler>', {
        securityToken: SECURITY_TOKEN,
        action: action,
        data: data || ''
      });
    } catch (e) {}
  }

  var sessionStart = (typeof performance !== 'undefined' && performance.now)
    ? performance.now()
    : Date.now();
  function metric(event, kvs) {
    var now = (typeof performance !== 'undefined' && performance.now)
      ? performance.now() : Date.now();
    var obj = { t: Math.round(now - sessionStart), event: event, src: 'js' };
    if (kvs) for (var k in kvs) if (Object.prototype.hasOwnProperty.call(kvs, k)) obj[k] = kvs[k];
    try { send('metric', JSON.stringify(obj)); } catch (e) {}
  }

  // ─── Video (pivot E, 2026-05-17) : canvas-as-display ──────────────────────
  //
  // Architecture finale après les pivots D→E :
  //   - VTDecompressionSession+VP9 bloqué par entitlement Apple (cf. memory)
  //   - Overlay HTML backdrop-filter (pivot D) marche mais ne survit pas au
  //     fullscreen iOS natif → bypass trivial
  //   - **Pivot E** : un <canvas> par <video> wiré, posé par-dessus avec le
  //     <video> à `opacity:0` derrière. À chaque `requestVideoFrameCallback`,
  //     drawImage(video) sur le canvas puis blur 2-pass downsample-upsample
  //     sur les bboxes courantes → le pixel rendu inclut déjà le flou. En
  //     fullscreen, c'est le canvas qui passe en fullscreen (Web API
  //     requestFullscreen sur iOS 16.4+) → blur reste actif.
  //
  // ML pipeline (V4 two-tier, parité POC macOS) :
  //   • YOLO heavy via `videoFrame` (320 px max, JPEG q=0.5) — cadence
  //     adaptative 1s en tracking / 5s en safe + trigger event-driven
  //     quand le sentinel détecte une nouvelle personne (2 sightings).
  //   • NanoDet sentinel via `videoSentinel` (480 px, JPEG q=0.6) toutes
  //     les ~100ms entre 2 YOLO → smooth-track les bboxes (EMA) +
  //     déclenche un YOLO immédiat si une bbox sentinel ne matche
  //     aucune bbox YOLO connue (IoU < SENTINEL_IOU_MATCH).
  //   • Swift push les bboxes via `__basarunaaApplyVideo` (YOLO complet
  //     post-mode filter) et `__basarunaaApplyVideoSentinel` (bboxes
  //     bruts NanoDet à utiliser pour smooth tracking).
  (function() {
    var hasVRC = typeof HTMLVideoElement !== 'undefined'
      && typeof HTMLVideoElement.prototype.requestVideoFrameCallback === 'function';
    if (!hasVRC) {
      metric('video_pivot_abort', { reason: 'no_requestVideoFrameCallback' });
      return;
    }

    var nextVideoId = 1;
    var wired = new WeakSet();
    var taintedVideos = new WeakSet();
    var videosById = {};                // videoId → <video>
    var displayCanvasById = {};         // videoId → <canvas> overlay display
    // Bboxes courantes à flouter, partagées entre le tick render (rVFC) et
    // les updates Swift via `__basarunaaApplyVideo`. La key NSFW remplace
    // toutes les bboxes par un full-frame blur.
    var currentBboxesById = {};         // videoId → [[x1,y1,x2,y2], ...]
    var currentBboxMetaById = {};       // videoId → { analyseW, analyseH }

    // ─── Sentinel two-tier state (per videoId) ─────────────────────────────
    // Tout dans des maps par videoId pour gérer plusieurs <video> en parallèle
    // sans collision (multi-onglets / multi-players sur une page).
    var lastYoloTimeById = {};          // videoId → ms du dernier YOLO send
    var lastSentinelTimeById = {};      // videoId → ms du dernier sentinel send
    var yoloInFlightById = {};          // videoId → bool (true entre send et apply)
    var sentinelInFlightById = {};      // videoId → bool
    var sentinelTracksById = {};        // videoId → [{ bbox:[x1,y1,x2,y2], confidence, missCount, vx, vy, yoloW, yoloH }]
    var lastYoloBboxesById = {};        // videoId → [[x1,y1,x2,y2], ...] (raw YOLO output, sans pad sentinel)
    var pendingNewPersonsById = {};     // videoId → [{ bbox, confidence }] vus à la run précédente, en attente du 2e sighting
    var yoloTriggeredBySentinelById = {}; // videoId → bool (consommé au prochain tick YOLO)
    var yoloTriggeredBySceneById = {};    // videoId → bool (scene change cut détecté)
    var videoStateById = {};            // videoId → 'safe' | 'tracking' (cadence YOLO adaptative)
    var videoDebugModeById = {};        // videoId → 'none'|'boxes'|'debug' (memoïsé entre 2 YOLO)
    var videoNsfwById = {};             // videoId → bool (full-frame blur, bypass sentinel reposition)
    // Debug overlay state (parité macOS POC `renderBlur` debug branch + `_drawHUD`)
    var videoAllPersonsById = {};       // videoId → [{bbox, keypoints, gender, genderConfidence, shouldBlur, ...}]
    var videoSentinelPersonsById = {};  // videoId → [{bbox: [x,y,x,y], confidence}] (last sentinel snapshot, en coords analyse)
    var videoLastTimingById = {};       // videoId → {poseLatencyMs, classifyLatencyMs}
    var yoloCountPeriodicById = {};     // videoId → int (YOLO trigerés par cadence)
    var yoloCountSentinelById = {};     // videoId → int (YOLO trigerés par new-person sentinel)
    var yoloCountSceneById = {};        // videoId → int (YOLO trigerés par scene change)
    var sentinelCountById = {};         // videoId → int (sentinel inferences cumulées)
    var framesSinceYoloById = {};       // videoId → int (= frames rVFC depuis dernier YOLO apply)
    var sceneHashById = {};             // videoId → Uint8Array (HASH_SIZE * HASH_SIZE) du dernier hash, ou null
    var sentinelLostCountById = {};     // videoId → nb de sentinels consécutifs avec raw=0 alors qu'on trackait
    var SENTINEL_LOST_THRESHOLD = 1;    // après N sentinels vides → clear blur + trigger YOLO (réactivité 1→0)
    // YOLO↔sentinel offset par bbox YOLO (parité POC). À chaque YOLO apply,
    // on calcule le décalage moyen entre la position YOLO et la position
    // NanoDet sur la MÊME personne (matching centre-distance). On utilise
    // cet offset dans `_updateBlurFromSentinel` pour corriger les positions
    // sentinel et obtenir la vraie position YOLO-équivalente → tracking
    // stable malgré le bias de localisation de NanoDet (qui peut centrer
    // sur le torse alors que YOLO centre différemment).
    var yoloOffsetsById = {};           // videoId → [{ offsetX, offsetY, yoloW, yoloH }] aligné avec currentBboxes
    // Canvas pour le hash 8×8 (parité POC `FrameDiffDetector`). On passe
    // d'abord par un canvas intermédiaire taille raisonnable parce que
    // WebKit iOS ne décode pas les pixels d'un `<video>` hardware sur un
    // canvas trop petit (8×8 ou 64×64 → reste tout noir). 256×256 est
    // au-dessus du seuil observé (sampleCanvas à 480 marche en routine,
    // 64 ne marche pas — testé empiriquement 2026-05-20). On downsample
    // ensuite à 8×8 via un 2e drawImage qui marche normalement entre
    // 2 canvas.
    var SCENE_INTERMEDIATE_SIZE = 256;
    var sceneIntermediateCanvas = document.createElement('canvas');
    sceneIntermediateCanvas.width = SCENE_INTERMEDIATE_SIZE;
    sceneIntermediateCanvas.height = SCENE_INTERMEDIATE_SIZE;
    var sceneIntermediateCtx = sceneIntermediateCanvas.getContext('2d');
    var sceneHashCanvas = document.createElement('canvas');
    sceneHashCanvas.width = SCENE_DIFF_HASH_SIZE;
    sceneHashCanvas.height = SCENE_DIFF_HASH_SIZE;
    var sceneHashCtx = sceneHashCanvas.getContext('2d', { willReadFrequently: true });

    // Compute 8×8 grayscale hash + diff vs precedent. Returns ratio 0..1.
    // Première frame retourne 1 (full change) — caller doit ignorer le 1er
    // appel. Le hash courant est stocké en interne pour la prochaine
    // comparaison. Parité POC `private/extensions/basarunaa/src/utils/frame_diff.js`.
    //
    // Sur iOS WebKit, drawImage(video, 0,0, 8, 8) direct ne dessine RIEN
    // (le video est en hardware overlay, downsample extrême non supporté).
    // On passe par un canvas intermédiaire 64×64 d'abord, puis on
    // downsample à 8×8 via un 2e drawImage.
    function _computeSceneDiff(videoId, video) {
      var n = SCENE_DIFF_HASH_SIZE;
      var mid = SCENE_INTERMEDIATE_SIZE;
      var size = n * n;
      try {
        // WebKit iOS quirk — un canvas réutilisé pour drawImage(<video>)
        // ne reçoit PAS les pixels du video decoder (canvas reste tout
        // noir, observé 2026-05-20 hashSum=0 sur des centaines de samples).
        // Le sampleCanvas marche parce qu'il est resized à chaque sample
        // (canvas.width = X clear et "refresh" le canvas pour le decoder).
        // On reproduit ce trick ici : force resize à chaque appel même
        // si la dimension n'a pas changé.
        sceneIntermediateCanvas.width = mid;
        sceneIntermediateCanvas.height = mid;
        sceneHashCanvas.width = n;
        sceneHashCanvas.height = n;
        sceneIntermediateCtx.drawImage(video, 0, 0, mid, mid);
        sceneHashCtx.imageSmoothingEnabled = true;
        sceneHashCtx.imageSmoothingQuality = 'high';
        sceneHashCtx.drawImage(sceneIntermediateCanvas, 0, 0, mid, mid, 0, 0, n, n);
      } catch (e) {
        // CORS taint ou video pas prêt — ignore
        return 0;
      }
      var data = sceneHashCtx.getImageData(0, 0, n, n).data;
      var hash = new Uint8Array(size);
      for (var i = 0; i < size; i++) {
        var off = i * 4;
        hash[i] = (data[off] * 2 + data[off + 1] * 3 + data[off + 2]) / 6;
      }
      var last = sceneHashById[videoId];
      sceneHashById[videoId] = hash;
      if (!last) return 1;
      var total = 0;
      for (var j = 0; j < size; j++) {
        var d = hash[j] - last[j];
        total += d < 0 ? -d : d;
      }
      return total / (size * 255);
    }

    // ─── Sentinel helpers (parité POC video_processor.js) ─────────────────
    function _bboxIoU(a, b) {
      var x1 = Math.max(a[0], b[0]);
      var y1 = Math.max(a[1], b[1]);
      var x2 = Math.min(a[2], b[2]);
      var y2 = Math.min(a[3], b[3]);
      var inter = Math.max(0, x2 - x1) * Math.max(0, y2 - y1);
      if (inter === 0) return 0;
      var areaA = (a[2] - a[0]) * (a[3] - a[1]);
      var areaB = (b[2] - b[0]) * (b[3] - b[1]);
      return inter / (areaA + areaB - inter);
    }

    function _padBbox(bbox, pad, maxW, maxH) {
      var x1 = bbox[0], y1 = bbox[1], x2 = bbox[2], y2 = bbox[3];
      var w = x2 - x1, h = y2 - y1;
      var px = w * pad, py = h * pad;
      return [
        Math.max(0, x1 - px),
        Math.max(0, y1 - py),
        Math.min(maxW, x2 + px),
        Math.min(maxH, y2 + py),
      ];
    }

    // EMA-smoothed sentinel track update. Matches incoming raw bboxes to
    // existing tracks by IoU, blends positions with adaptive alpha (faster
    // when motion is coherent — cosine similarity with smoothed velocity).
    // Ports `_smoothSentinelTracks` from the POC (1:1).
    function _smoothSentinelTracks(videoId, rawPersons, vw, vh) {
      var tracks = sentinelTracksById[videoId] || [];
      var used = {};
      for (var ti = 0; ti < tracks.length; ti++) {
        var track = tracks[ti];
        var bestIoU = 0, bestIdx = -1;
        for (var ri = 0; ri < rawPersons.length; ri++) {
          if (used[ri]) continue;
          var iou = _bboxIoU(track.bbox, rawPersons[ri].bbox);
          if (iou > bestIoU) { bestIoU = iou; bestIdx = ri; }
        }
        if (bestIdx >= 0 && bestIoU > 0.2) {
          used[bestIdx] = true;
          var newBbox = rawPersons[bestIdx].bbox;
          var oldCx = (track.bbox[0] + track.bbox[2]) / 2;
          var oldCy = (track.bbox[1] + track.bbox[3]) / 2;
          var newCx = (newBbox[0] + newBbox[2]) / 2;
          var newCy = (newBbox[1] + newBbox[3]) / 2;
          var trackH = (track.bbox[3] - track.bbox[1]) || 1;
          var dx = newCx - oldCx;
          var dy = newCy - oldCy;
          var displacement = Math.sqrt(dx * dx + dy * dy) / trackH;
          track.vx = (track.vx || 0) * 0.7 + dx * 0.3;
          track.vy = (track.vy || 0) * 0.7 + dy * 0.3;
          if (displacement < SENTINEL_DEAD_ZONE) {
            track.missCount = 0;
          } else if (displacement > 0.3) {
            track.bbox = newBbox.slice();
            track.yoloW = null;
            track.yoloH = null;
            track.vx = 0;
            track.vy = 0;
          } else {
            var velMag = Math.sqrt(track.vx * track.vx + track.vy * track.vy);
            var movMag = Math.sqrt(dx * dx + dy * dy);
            var alpha = SENTINEL_SMOOTH_ALPHA;
            if (velMag > 1 && movMag > 1) {
              var cosine = (track.vx * dx + track.vy * dy) / (velMag * movMag);
              if (cosine > 0.3) {
                alpha = Math.min(0.85, SENTINEL_SMOOTH_ALPHA + cosine * 0.6);
              }
            }
            var w = track.yoloW || (newBbox[2] - newBbox[0]);
            var h = track.yoloH || (newBbox[3] - newBbox[1]);
            var smoothCx = oldCx + dx * alpha;
            var smoothCy = oldCy + dy * alpha;
            track.bbox = [smoothCx - w / 2, smoothCy - h / 2, smoothCx + w / 2, smoothCy + h / 2];
          }
          track.confidence = rawPersons[bestIdx].confidence;
          track.missCount = 0;
        } else {
          track.missCount = (track.missCount || 0) + 1;
        }
      }
      tracks = tracks.filter(function(t) { return t.missCount < SENTINEL_TRACK_MAX_MISS; });
      for (var ri2 = 0; ri2 < rawPersons.length; ri2++) {
        if (used[ri2]) continue;
        tracks.push({
          bbox: rawPersons[ri2].bbox.slice(),
          confidence: rawPersons[ri2].confidence,
          missCount: 0,
        });
      }
      sentinelTracksById[videoId] = tracks;
      return tracks.map(function(t) {
        return { bbox: t.bbox.slice(), confidence: t.confidence };
      });
    }

    // Sentinel bboxes that don't overlap any of the last YOLO bboxes (IoU
    // below threshold) are candidates for "new person" YOLO trigger.
    function _findUnmatchedPersons(sentinelPersons, yoloBboxes) {
      if (!yoloBboxes || yoloBboxes.length === 0) return sentinelPersons.slice();
      var unmatched = [];
      for (var i = 0; i < sentinelPersons.length; i++) {
        var sp = sentinelPersons[i];
        var matched = false;
        for (var j = 0; j < yoloBboxes.length; j++) {
          if (_bboxIoU(sp.bbox, yoloBboxes[j]) > SENTINEL_IOU_MATCH) {
            matched = true;
            break;
          }
        }
        if (!matched) unmatched.push(sp);
      }
      return unmatched;
    }

    // Re-aligns current blur bboxes to fresher sentinel positions (between
    // 2 YOLO runs). Parité POC `_updateBlurPositions` :
    //  - Match sentinel ↔ yoloBbox par centre-distance (tolérance 60% hauteur)
    //  - Position corrigée = sentinelCentre − offset YOLO↔sentinel appris
    //  - Dead zone : skip si le shift est < 4% de la hauteur YOLO (bruit)
    //  - Garde les dimensions YOLO d'origine (pas du sentinel paddé)
    // L'offset retire le bias systématique de NanoDet (centre torse vs
    // centre YOLO différent) → tracking stable, pas de jitter.
    function _updateBlurFromSentinel(videoId, sentinelPersons) {
      // NSFW = full-frame blur figé. Pas de reposition sentinel : la bbox
      // [0, 0, analyseW, analyseH] doit rester intacte jusqu'au prochain
      // YOLO qui ré-évaluera le verdict NSFW.
      if (videoNsfwById[videoId]) return;
      var current = currentBboxesById[videoId];
      if (!current || !current.length) return;
      var offsets = yoloOffsetsById[videoId] || [];
      var updated = current.map(function(yoloBbox, idx) {
        var off = offsets[idx];
        var yoloW = off ? off.yoloW : (yoloBbox[2] - yoloBbox[0]);
        var yoloH = off ? off.yoloH : ((yoloBbox[3] - yoloBbox[1]) || 1);
        var offX = off ? off.offsetX : 0;
        var offY = off ? off.offsetY : 0;
        var ypCx = (yoloBbox[0] + yoloBbox[2]) / 2;
        var ypCy = (yoloBbox[1] + yoloBbox[3]) / 2;
        var maxDist = yoloH * 0.6;
        var bestDist = Infinity, bestBbox = null;
        for (var i = 0; i < sentinelPersons.length; i++) {
          var t = sentinelPersons[i].bbox;
          var tCx = (t[0] + t[2]) / 2;
          var tCy = (t[1] + t[3]) / 2;
          var dx = ypCx - tCx;
          var dy = ypCy - tCy;
          var dist = Math.sqrt(dx * dx + dy * dy);
          if (dist < bestDist) {
            bestDist = dist;
            bestBbox = t;
          }
        }
        if (!bestBbox || bestDist > maxDist) return yoloBbox;
        // Corrige la position sentinel par l'offset appris au dernier YOLO.
        var sentCx = (bestBbox[0] + bestBbox[2]) / 2;
        var sentCy = (bestBbox[1] + bestBbox[3]) / 2;
        var correctedCx = sentCx - offX;
        var correctedCy = sentCy - offY;
        var dCx = correctedCx - ypCx;
        var dCy = correctedCy - ypCy;
        var disp = Math.sqrt(dCx * dCx + dCy * dCy) / yoloH;
        if (disp < SENTINEL_DEAD_ZONE) return yoloBbox;
        return [
          correctedCx - yoloW / 2, correctedCy - yoloH / 2,
          correctedCx + yoloW / 2, correctedCy + yoloH / 2
        ];
      });
      currentBboxesById[videoId] = updated;
    }

    // ─── Sentinel two-tier V4 ──────────────────────────────────────────────
    // Parité macOS POC `private/extensions/basarunaa/src/video/video_processor.js`
    // (lignes 22-32). 3 cadences imbriquées + event-driven :
    //   • Sentinel NanoDet ~100ms → smooth-track les bboxes entre 2 YOLO
    //   • YOLO 1s en tracking (au moins 1 personne à l'écran)
    //   • YOLO 5s en safe (écran vide — économie d'inférence)
    //   • YOLO trigger immédiat si sentinel voit une bbox non-trackée
    //     (avec confirmation 2 sightings consécutifs pour filtrer les FPs).
    var YOLO_INTERVAL_TRACKING_MS = 1000;  // YOLO refresh while at least 1 person on-screen
    var YOLO_INTERVAL_SAFE_MS = 5000;       // YOLO refresh while screen empty
    var YOLO_MIN_COOLDOWN_MS = 300;         // hard floor between YOLO runs
    var SENTINEL_INTERVAL_MS = 100;         // NanoDet sentinel target cadence
    var SENTINEL_MIN_COOLDOWN_MS = 80;      // hard floor between sentinel runs
    var SENTINEL_CAPTURE_SIZE = 480;        // sentinel capture max dim (vs 320 for YOLO)
    var SENTINEL_IOU_MATCH = 0.3;           // IoU threshold to match sentinel↔YOLO bbox
    var SENTINEL_BBOX_PAD = 0.15;           // 15% pad on sentinel bboxes
    var SENTINEL_SMOOTH_ALPHA = 0.2;        // EMA base smoothing (POC adaptive 0.2-0.85)
    var SENTINEL_DEAD_ZONE = 0.04;          // ignore <4% bbox height movement (noise)
    var SENTINEL_TRACK_MAX_MISS = 3;        // drop track after N missed sentinel frames
    var SCENE_CHANGE_THRESHOLD = 0.12;      // 8×8 grayscale diff ratio > 12% = scene cut
    var SCENE_DIFF_HASH_SIZE = 8;           // 8×8 = 64 pixels, <1ms compute

    var MAX_SAMPLE_WIDTH = 320;         // resize avant JPEG pour bridge (YOLO)
    var JPEG_QUALITY = 0.5;
    var SENTINEL_JPEG_QUALITY = 0.6;        // sentinel q=0.6 (POC parity)
    var BLUR_DOWNSAMPLE = 50;           // 50× downsample (était 30 — encore plus opaque)
    var BLUR_PASS2_FACTOR = 3;          // 2e passe re-downsample 3× pour smooth les carrés
    var BLUR_GAUSSIAN_RADIUS_PX = 5;    // gaussian sur tiny canvas (5px ≈ 30% dim → smooth net)
    // Mode blur dynamique — togglable via DevTools / console pour A/B test :
    //   window.__basarunaaBlurMode = 'box'      → 2-pass bilinéaire seul (default actuel)
    //   window.__basarunaaBlurMode = 'gaussian' → ajoute ctx.filter='blur(2px)' sur tiny canvas
    // Le mode est lu à chaque blur. Métrique `blur_perf` log les ms p50/p95
    // par bbox toutes les 60 frames pour qu'on compare data-driven.
    // Feather mask vidéo (port `_drawFeatheredBlurVideo` POC macOS) : étend
    // la zone blur de FEATHER_MARGIN px + composite destination-in avec un
    // mask blanc blurré → bords du blur en dégradé alpha (transition smooth
    // avec le reste de la vidéo). Snap aux bords image si bbox proche du
    // bord (pas de feather sur ce côté — pas de zone à peine floue au bord).
    // Toggle runtime : `window.__basarunaaFeatherDisabled = true` pour off.
    // 50px (vs 15 POC macOS) car le blur via downsample-upsample bilinéaire
    // est moins net qu'un vrai gaussian — il faut une zone plus large pour
    // que le dégradé soit visible. Togglable runtime via :
    //   window.__basarunaaFeatherMarginPx = 30  // override
    var VIDEO_FEATHER_MARGIN_PX_DEFAULT = 50;
    var VIDEO_FEATHER_PAD_PX = VIDEO_FEATHER_MARGIN_PX_DEFAULT + 5;
    // V3-E iter 1 — visualisait les bboxes pendant le dev. Désactivé en
    // prod car le rect rouge net masquait visuellement l'effet feather.
    var DEBUG_BBOX_STROKE = false;
    // Perf measurement — fenêtre glissante sur les derniers blurs pour
    // déduire p50/p95 du temps de rendu d'une bbox (avec mode courant).
    var blurPerfSamples = [];
    var BLUR_PERF_WINDOW = 60;  // ~2s à 30fps

    // ─── V3.5 — Fake fullscreen CSS ─────────────────────────────────────────
    // Sur iPhone, Element.requestFullscreen() Web API n'est PAS supporté
    // (juste iPad 16.4+) ⇒ canvas.requestFullscreen est undefined et la
    // seule fullscreen native est `<video>.webkitEnterFullscreen()` qui
    // ouvre AVKit (intouchable). Solution : on intercepte
    // webkitEnterFullscreen et au lieu d'appeler le natif, on bascule
    // notre canvas en "fake fullscreen" via CSS (position:fixed; 100vw/vh;
    // z-index max). Le blur reste préservé puisque le canvas EST la vidéo
    // affichée. URL bar Safari reste visible — compromis accepté faute de
    // vraie API disponible.
    var fullscreenVideoEl = null;       // <video> actuellement en mode fs
    var fullscreenCanvas = null;        // canvas correspondant
    var savedCanvasCssText = '';        // restore au exit (cas non-YT)
    var savedBodyOverflow = '';         // restore au exit
    var savedCanvasParent = null;       // parent d'origine du canvas (cas non-YT fallback)
    var savedCanvasNextSibling = null;  // sibling de référence pour restore exact
    var fullscreenYTContainer = null;   // #player-container-id grandi (cas YT)
    var savedYTContainerCssText = '';   // cssText d'origine du container YT
    var fullscreenYTPlayer = null;      // #player (parent direct du video) grandi aussi
    var savedYTPlayerCssText = '';      // cssText d'origine de #player
    var fullscreenYTVideoEl = null;     // <video> aussi forcé à taille intrinsèque centrée
    var savedYTVideoCssText = '';       // cssText d'origine du <video>
    var fullscreenYTHiddenEls = [];     // [{el, prevDisplay}] cinematics + thumbnail
    var fullscreenLayoutRAF = 0;        // rAF loop id qui re-pose le layout

    // ─── Floating subtitles (YouTube) ──────────────────────────────────
    // Le `.ytp-caption-window-container` est descendant de `#player` et
    // peut être recouvert par notre canvas blur OU rester visible dans
    // les zones non floues → soit invisible soit doublonné avec le clone.
    //
    // Stratégie : on hide les subtitles YT natifs en CSS (opacity:0) et
    // on rend notre propre clone `.basarunaa-caption-clone` au-dessus
    // du canvas blur (position:fixed, z-index max). On lit les cues
    // directement depuis `video.textTracks` (WebVTT), fallback DOM.
    //
    // On NE touche PAS au DOM YT (pas de move ni d'unmount) : YT JS
    // s'attend à retrouver son container original pour update son state
    // (bouton CC visuellement actif, re-position via `top:Npx` inline).
    var floatingSubInfo = null;
    // { cloneContainer, lastCueText, syncInterval, video, ... }

    // Canvas partagés pour l'encode ML + le scratch blur (recyclés).
    var sampleCanvas = document.createElement('canvas');
    var sctx = sampleCanvas.getContext('2d');
    var blurCanvas = document.createElement('canvas');
    var bctx = blurCanvas.getContext('2d');
    // 2e canvas pour le 2-pass blur (re-downsample du 1er blurCanvas)
    var blurCanvas2 = document.createElement('canvas');
    var bctx2 = blurCanvas2.getContext('2d');
    // Canvas dédiés au feather mask vidéo (recyclés entre bboxes).
    // - featherTemp : blur upscalé à taille bbox étendue puis composite avec mask
    // - featherMask : rect blanc strict de taille bbox au centre
    // - featherMaskSmall / featherMaskBlurred : trick downsample-upsample pour
    //   blurrer le mask (ctx.filter blur est un no-op silencieux sur WebKit iOS)
    var featherTempCanvas = document.createElement('canvas');
    var ftCtx = featherTempCanvas.getContext('2d');
    var featherMaskCanvas = document.createElement('canvas');
    var fmCtx = featherMaskCanvas.getContext('2d');
    var featherMaskSmallCanvas = document.createElement('canvas');
    var fmsCtx = featherMaskSmallCanvas.getContext('2d');
    var featherMaskBlurredCanvas = document.createElement('canvas');
    var fmbCtx = featherMaskBlurredCanvas.getContext('2d');

    // ─── Overlay placement (2026-05-18) ────────────────────────────────────
    // Sur YouTube le `<video>` est probablement en hardware-overlay au-dessus
    // de tout son stacking context (`.html5-video-container` z=10). Mettre
    // le canvas dans ce container le rend invisible (sous la video plane).
    //
    // Solution : remonter au `#player-container-id` (l'ancêtre qui contient
    // À LA FOIS `#player` (avec le video) ET les contrôles YT (.player-
    // controls-background, #player-control-overlay, etc., siblings dans ce
    // container). On insère notre canvas dans `#player-container-id`, **juste
    // après `#player` mais avant les contrôles** dans l'ordre DOM → canvas
    // peint au-dessus du video, contrôles peints au-dessus du canvas.
    //
    // Hors YouTube : fallback body + position:fixed + z-index max (comme avant).
    function findYTOverlayContainer(video) {
      try { return video.closest('#player-container-id'); } catch (e) { return null; }
    }
    function findYTPlayerElement(video) {
      try { return video.closest('#player'); } catch (e) { return null; }
    }
    // ─── Floating subtitle helpers ─────────────────────────────────────
    // YT mobile peut afficher des **messages d'info** dans le même
    // container que les vrais cues (ex: après activation du CC, message
    // type "Anglais Cliquez sur ⚙ pour accéder aux paramètres."). On
    // les filtre par mots-clés (l'idéal serait un sélecteur DOM précis
    // mais YT n'en expose pas). Liste à étendre si on observe d'autres
    // patterns dans d'autres langues.
    function isYtInfoMessage(text) {
      return /Cliquez sur|Tap on|Tap to|Tappez sur|Tippe auf|Toca en|Tocca su|paramètres|settings|Einstellungen|configuración|impostazioni/i.test(text);
    }

    function setupFloatingSubtitles(video) {
      if (floatingSubInfo) {
        if (floatingSubInfo.cloneContainer.isConnected &&
            floatingSubInfo.video === video) {
          startSubtitleSync();
          return;
        }
        teardownFloatingSubtitles();
      }
      // Le CSS porte 2 responsabilités : (1) styler notre clone et
      // (2) cacher les subs natifs YT. Doit être présent dès qu'un
      // video est wired, sans attendre l'entrée FS (bug 2026-05-19 :
      // sans cet appel, subs natifs visibles + clone non stylé tant
      // que le user n'avait pas tapé FS au moins une fois).
      ensureBasarunaaCssInjected();
      // Pipeline de lecture des cues (cf. `startSubtitleSync`) :
      //  1. WebVTT track API (`video.textTracks`) — standard mais YT
      //     mobile ne l'utilise pas, c'est défensif pour d'autres sites.
      //  2. Fallback DOM (`.caption-window` / `.ytm-mobile-captions`) —
      //     chemin principal sur YT mobile, qui rend les cues dans le
      //     DOM normal (pas dans le shadow DOM du <video>).
      // Le texte récupéré est rendu dans un clone <div> positionné
      // au-dessus du canvas blur (z-index max).
      var clone = document.createElement('div');
      clone.className = 'basarunaa-caption-clone ' +
        (fullscreenYTContainer ? 'basarunaa-caption-fs' : 'basarunaa-caption-normal');
      document.body.appendChild(clone);
      floatingSubInfo = {
        cloneContainer: clone,
        lastCueText: '',
        syncInterval: 0,
        video: video
      };
      startSubtitleSync();
    }

    function startSubtitleSync() {
      if (!floatingSubInfo || floatingSubInfo.syncInterval) return;
      floatingSubInfo.syncInterval = setInterval(function() {
        if (!floatingSubInfo) return;
        var clone = floatingSubInfo.cloneContainer;
        var v = floatingSubInfo.video;
        if (!clone || !clone.isConnected) return;
        var isNormal = clone.classList.contains('basarunaa-caption-normal');
        var isFs = clone.classList.contains('basarunaa-caption-fs');
        if (!isNormal && !isFs) return;
        // 1) WebVTT track API (rare sur YT mobile, mais standard).
        var cueText = '';
        if (v && v.textTracks) {
          for (var i = 0; i < v.textTracks.length; i++) {
            var t = v.textTracks[i];
            if (t.mode === 'showing' && t.activeCues) {
              for (var j = 0; j < t.activeCues.length; j++) {
                var ctext = t.activeCues[j].text || '';
                cueText += (cueText ? '\n' : '') + ctext;
              }
            }
          }
        }
        // 2) Fallback DOM — YT mobile a 2 modes de rendu :
        //  - Desktop-like (mode FS, parfois mode normal) : structure
        //    `.caption-window > … > .ytp-caption-segment > #text`.
        //  - Mobile-compact (souvent mode normal) : innerText direct
        //    dans `.caption-window` / `.ytm-mobile-captions`.
        //
        // Le bouton CC peut aussi afficher des messages d'info
        // ("Anglais Cliquez sur ⚙ pour accéder aux paramètres.") dans
        // le même container que les vrais cues — on les filtre par
        // mots-clés (en plusieurs langues) puisqu'on ne peut pas les
        // distinguer par sélecteur.
        if (!cueText) {
          // Pas `.ytp-caption-window-container` : c'est le wrapper parent
          // de `.caption-window`, le sélectionner double les lectures.
          var windows = document.querySelectorAll('.caption-window, .ytm-mobile-captions');
          var lines = [];
          for (var w = 0; w < windows.length; w++) {
            if (windows[w].closest('.basarunaa-caption-clone')) continue;
            var line = '';
            var segs = windows[w].querySelectorAll('.ytp-caption-segment');
            if (segs.length > 0) {
              // Structure desktop-like : concat les segments propres.
              for (var s = 0; s < segs.length; s++) {
                var st = (segs[s].textContent || '').trim();
                if (st) line += (line ? ' ' : '') + st;
              }
            } else {
              // Structure mobile-compact : innerText direct.
              line = (windows[w].innerText || windows[w].textContent || '').trim();
            }
            // Filtre commun aux 2 chemins : YT rend ses messages d'info
            // ("Anglais Cliquez sur ⚙…") via la même structure DOM que
            // les vrais cues, donc on ne peut pas les distinguer par
            // sélecteur — filtre par mots-clés.
            if (line && !isYtInfoMessage(line)) lines.push(line);
          }
          cueText = lines.join('\n');
        }
        if (cueText !== floatingSubInfo.lastCueText) {
          clone.textContent = cueText;
          floatingSubInfo.lastCueText = cueText;
          send('log', 'SUB_CUE len=' + cueText.length + ' preview=' + cueText.slice(0, 80));
        }
        // Sync container coords au rect du <video> (mode normal).
        if (isNormal && v && v.isConnected) {
          var rect = v.getBoundingClientRect();
          if (rect.width > 0 && rect.height > 0) {
            clone.style.setProperty('top', rect.top + 'px', 'important');
            clone.style.setProperty('left', rect.left + 'px', 'important');
            clone.style.setProperty('width', rect.width + 'px', 'important');
            clone.style.setProperty('height', rect.height + 'px', 'important');
          }
        }
      }, 100);
    }

    function stopSubtitleSync() {
      if (!floatingSubInfo) return;
      if (floatingSubInfo.syncInterval) {
        clearInterval(floatingSubInfo.syncInterval);
        floatingSubInfo.syncInterval = 0;
      }
    }

    function setSubtitleFsMode(isFs) {
      if (!floatingSubInfo) return;
      var clone = floatingSubInfo.cloneContainer;
      if (isFs) {
        clone.classList.remove('basarunaa-caption-normal');
        clone.classList.add('basarunaa-caption-fs');
        clone.style.removeProperty('top');
        clone.style.removeProperty('left');
        clone.style.removeProperty('width');
        clone.style.removeProperty('height');
      } else {
        clone.classList.remove('basarunaa-caption-fs');
        clone.classList.add('basarunaa-caption-normal');
      }
    }

    function teardownFloatingSubtitles() {
      if (!floatingSubInfo) return;
      stopSubtitleSync();
      var clone = floatingSubInfo.cloneContainer;
      if (clone && clone.parentElement) {
        clone.parentElement.removeChild(clone);
      }
      floatingSubInfo = null;
    }

    function ensureBasarunaaCssInjected() {
      if (document.getElementById('basarunaa-css')) return;
      var style = document.createElement('style');
      style.id = 'basarunaa-css';
      style.textContent =
        '#player-container-id[data-basarunaa-fs="1"]{' +
          'position:fixed!important;top:0!important;left:0!important;' +
          'right:0!important;bottom:0!important;' +
          'width:100vw!important;height:100vh!important;' +
          // 100dvh override (iOS 15.4+) — viewport visible réelle, sinon
          // 100vh inclut l'espace sous la toolbar iOS et les subtitles YT
          // (positionnés en bottom du container) tombent hors écran.
          'height:100dvh!important;' +
          'z-index:2147483646!important;background:#000!important;' +
          'margin:0!important;padding:0!important;' +
        '}' +
        '#player-container-id[data-basarunaa-fs="1"] #player,' +
        '#player-container-id[data-basarunaa-fs="1"] #movie_player,' +
        '#player-container-id[data-basarunaa-fs="1"] .html5-video-container{' +
          'position:absolute!important;top:0!important;left:0!important;' +
          'width:100%!important;height:100%!important;' +
          'max-width:none!important;max-height:none!important;' +
          // Empêche le swipe-to-dismiss YT qui scrolle la vidéo native
          // (révèle qu'elle joue à une position différente du canvas).
          // Les contrôles YT sont siblings de #movie_player dans
          // #player-container-id donc restent cliquables.
          'touch-action:none!important;' +
        '}' +
        // Pas de rule CSS pour video.video-stream : on la pose en JS via
        // setProperty('important') + setInterval pour battre YT JS qui
        // override object-fit / object-position (et son hardware overlay
        // iOS qui ignore object-position de toute façon).
        ''+
        '#player-container-id[data-basarunaa-fs="1"] #player-cinematics-container,' +
        '#player-container-id[data-basarunaa-fs="1"] #player-thumbnail-overlay,' +
        // Settings button : son menu casse le layout en fake fs (rect hors
        // viewport + state YT corrompu au close). On le cache plutôt que
        // de tenter de fix le popup positioning.
        '#player-container-id[data-basarunaa-fs="1"] [aria-label*="Settings" i],' +
        '#player-container-id[data-basarunaa-fs="1"] [aria-label*="Paramètres" i],' +
        '#player-container-id[data-basarunaa-fs="1"] .ytmSettingsButtonHost,' +
        '#player-container-id[data-basarunaa-fs="1"] ytm-settings-button,' +
        '#player-container-id[data-basarunaa-fs="1"] .ytp-settings-button{' +
          'display:none!important;' +
        '}' +
        // Hide les subtitles YT natifs : notre clone (basarunaa-caption-clone)
        // affiche le même texte au-dessus du flou. Sans cette rule on aurait
        // un doublon (clone + original visible dans les zones non floues).
        // `.ytp-caption-segment` non listé : descendant de `.caption-window`,
        // déjà caché par propagation visibility:hidden.
        '.ytp-caption-window-container,' +
        '.caption-window,' +
        '.ytm-mobile-captions{' +
          'opacity:0!important;' +
          'visibility:hidden!important;' +
        '}' +
        // Sous-titres : on lit les cues WebVTT du <video>.textTracks et
        // on rend dans un div clone (sortir du stacking context
        // #player-container-id qui masquait sous le canvas). Style mimique
        // les subtitles YT natifs (white text, black bg, drop shadow).
        '.basarunaa-caption-clone{' +
          'position:fixed!important;' +
          'z-index:2147483647!important;' +
          'pointer-events:none!important;' +
          'background:transparent!important;' +
          'display:block!important;' +
          'opacity:1!important;' +
          'color:white!important;' +
          'font-family:sans-serif!important;' +
          'font-size:18px!important;' +
          'font-weight:500!important;' +
          'text-align:center!important;' +
          'text-shadow:1px 1px 2px black,-1px -1px 2px black,1px -1px 2px black,-1px 1px 2px black!important;' +
          'white-space:pre-wrap!important;' +
          'box-sizing:border-box!important;' +
          'padding:0 12px!important;' +
        '}' +
        // Sub container in mode normal : position absolute "row" en bas
        // de la zone <video>. La height inline (set par JS) matche le rect
        // du <video>, donc bottom:8% ≈ 8% du video height au-dessus du
        // bas du video.
        '.basarunaa-caption-clone.basarunaa-caption-normal{' +
          /* JS set top/left/width/height inline. On affiche le text au
             bottom du container via flex bottom alignment. */
          'display:flex!important;' +
          'flex-direction:column!important;' +
          'justify-content:flex-end!important;' +
          'align-items:center!important;' +
          'padding-bottom:8%!important;' +
        '}' +
        // Sub container in fake fs : tout l\'écran, text au bottom.
        '.basarunaa-caption-clone.basarunaa-caption-fs{' +
          'top:0!important;left:0!important;' +
          'right:auto!important;bottom:auto!important;' +
          'width:100vw!important;height:100vh!important;' +
          'display:flex!important;' +
          'flex-direction:column!important;' +
          'justify-content:flex-end!important;' +
          'align-items:center!important;' +
          'padding-bottom:8vh!important;' +
        '}' +
        '#player-container-id[data-basarunaa-fs="1"] .ytp-popup,' +
        '#player-container-id[data-basarunaa-fs="1"] .ytp-panel,' +
        '#player-container-id[data-basarunaa-fs="1"] .ytp-tooltip,' +
        '#player-container-id[data-basarunaa-fs="1"] .ytm-modal-overlay,' +
        '#player-container-id[data-basarunaa-fs="1"] .player-controls-overlay{' +
          'z-index:2147483645!important;' +
          'pointer-events:auto!important;' +
        '}';
      (document.head || document.documentElement).appendChild(style);
    }

    function firstYTControlChild(container) {
      try {
        return container.querySelector(
          ':scope > .player-controls-background,' +
          ':scope > .player-controls-background-container,' +
          ':scope > #player-control-overlay,' +
          ':scope > .player-control-overlay'
        );
      } catch (e) { return null; }
    }

    function wireVideo(video) {
      if (wired.has(video) || taintedVideos.has(video)) return;
      wired.add(video);
      var videoId = nextVideoId++;
      videosById[videoId] = video;
      metric('video_wired', {
        videoId: videoId,
        src: (video.currentSrc || video.src || '').slice(0, 100)
      });

      var display = document.createElement('canvas');
      display.setAttribute('data-basarunaa-display', String(videoId));

      // Sur YouTube : insérer dans `#player-container-id` entre `#player`
      // et les contrôles. Sinon (autres sites) : body + position:fixed +
      // z-index max — comportement historique qui marche partout au prix
      // de masquer les contrôles natifs des autres sites.
      var ytContainer = findYTOverlayContainer(video);
      var ytPlayer = ytContainer ? findYTPlayerElement(video) : null;
      if (ytContainer && ytPlayer && ytPlayer.parentNode === ytContainer) {
        display.style.cssText = [
          'position:absolute',
          'pointer-events:none',
          'left:0', 'top:0', 'width:0', 'height:0',
          // pas de z-index → DOM order ; on insère entre #player et les controls
          'contain:layout style paint'
        ].join(';');
        var firstControl = firstYTControlChild(ytContainer);
        if (firstControl) {
          ytContainer.insertBefore(display, firstControl);
        } else {
          // Pas (encore) de controls : insérer juste après #player ;
          // les controls viendront probablement après.
          var afterPlayer = ytPlayer.nextSibling;
          if (afterPlayer) ytContainer.insertBefore(display, afterPlayer);
          else ytContainer.appendChild(display);
        }
      } else {
        display.style.cssText = [
          'position:fixed',
          'pointer-events:none',
          'left:0', 'top:0', 'width:0', 'height:0',
          'z-index:2147483646',
          'contain:layout style paint'
        ].join(';');
        document.body.appendChild(display);
      }
      displayCanvasById[videoId] = display;

      // (Pas de click→exit ici : on veut que les taps sur le canvas en
      // fake fullscreen passent aux contrôles YouTube en-dessous. L'exit
      // se fait via le bouton × custom uniquement.)

      // Detect quand iOS prend le contrôle (AVKit) sans qu'on ait pu
      // intercepter — `webkitbeginfullscreen` fire au moment où le <video>
      // entre en présentation natif.
      video.addEventListener('webkitbeginfullscreen', function() {
        metric('fs_webkit_begin', { videoId: videoId });
      });
      video.addEventListener('webkitendfullscreen', function() {
        metric('fs_webkit_end', { videoId: videoId });
      });

      var dctx = display.getContext('2d');
      var firstTickLogged = false;
      function tick() {
        if (taintedVideos.has(video)) return;
        var vw = video.videoWidth || 0;
        var vh = video.videoHeight || 0;
        if (vw === 0 || vh === 0 || video.paused || video.ended) {
          video.requestVideoFrameCallback(tick);
          return;
        }
        // Compteur "frames since last YOLO apply" pour le HUD debug.
        framesSinceYoloById[videoId] = (framesSinceYoloById[videoId] || 0) + 1;
        var dpr = window.devicePixelRatio || 1;
        var pw, ph;
        var inFs = (fullscreenVideoEl === video);
        if (inFs) {
          // En fullscreen : canvas remplit le viewport ; le browser gère
          // sa taille CSS (100% du screen). On match juste les pixels
          // physiques à clientWidth × dpr.
          var cw = display.clientWidth || window.innerWidth;
          var ch = display.clientHeight || window.innerHeight;
          pw = Math.max(1, Math.round(cw * dpr));
          ph = Math.max(1, Math.round(ch * dpr));
        } else {
          var rect = video.getBoundingClientRect();
          if (rect.width <= 0 || rect.height <= 0) {
            video.requestVideoFrameCallback(tick);
            return;
          }
          pw = Math.max(1, Math.round(rect.width * dpr));
          ph = Math.max(1, Math.round(rect.height * dpr));
          // Si le canvas est dans un parent positionné (cas YT inside
          // #player-container-id), les coords doivent être relatives à
          // ce parent. Sinon (body+fixed), on est en coords viewport.
          var dp = display.parentElement;
          if (dp && dp !== document.body) {
            var pr = dp.getBoundingClientRect();
            display.style.left = (rect.left - pr.left) + 'px';
            display.style.top = (rect.top - pr.top) + 'px';
          } else {
            display.style.left = rect.left + 'px';
            display.style.top = rect.top + 'px';
          }
          display.style.width = rect.width + 'px';
          display.style.height = rect.height + 'px';
        }
        if (display.width !== pw) display.width = pw;
        if (display.height !== ph) display.height = ph;
        if (!firstTickLogged) {
          metric('video_tick_first', {
            videoId: videoId,
            vw: vw, vh: vh,
            rw: Math.round(rect.width), rh: Math.round(rect.height),
            dpr: dpr
          });
          firstTickLogged = true;
        }
        try {
          // 2 modes :
          //  - Normal (canvas overlay au-dessus du <video>) : transparent
          //    par défaut, on dessine UNIQUEMENT les zones blur.
          //  - Fake-fullscreen (canvas en CSS position:fixed 100vw/vh) :
          //    opaque, letterbox + drawImage full frame puis blur sur bboxes.
          var dispOffX = 0, dispOffY = 0, dispW = pw, dispH = ph;
          if (inFs) {
            // Letterbox manuel : preserve aspect ratio. Bandes noires aux
            // bords si le canvas n'a pas le même ratio que la vidéo source.
            var vAspect = vw / vh;
            var cAspect = pw / ph;
            if (vAspect > cAspect) {
              dispW = pw; dispH = pw / vAspect;
              dispOffX = 0; dispOffY = (ph - dispH) / 2;
            } else {
              dispH = ph; dispW = ph * vAspect;
              dispOffY = 0; dispOffX = (pw - dispW) / 2;
            }
            dctx.fillStyle = '#000';
            dctx.fillRect(0, 0, pw, ph);
            dctx.drawImage(video, 0, 0, vw, vh, dispOffX, dispOffY, dispW, dispH);
          } else {
            dctx.clearRect(0, 0, pw, ph);
          }

          // Sample pour ML — capture brute via un canvas séparé sur le
          // <video> source, indépendant du canvas display.
          //
          // Two-tier scheduling (parité POC macOS) :
          //   • YOLO (heavy) toutes les 1s en tracking / 5s en safe,
          //     ou immédiatement si event-driven par le sentinel.
          //   • Sentinel (lightweight NanoDet) toutes les ~100ms entre
          //     2 YOLO. Si !sentinelInFlight && !yoloInFlight.
          var nowMs = (typeof performance !== 'undefined' && performance.now)
            ? performance.now() : Date.now();

          // Scene change detection — 8×8 grayscale hash vs frame précédente
          // (parité POC `FrameDiffDetector`). Si diff > 12%, reset le state
          // tracking et trigger un YOLO immédiat. Évite le "flou qui reste
          // après un cut" + accélère l'apparition du flou sur changement
          // de plan vs attendre le YOLO périodique (1s).
          var sceneDiff = _computeSceneDiff(videoId, video);
          if (sceneDiff > SCENE_CHANGE_THRESHOLD) {
            sentinelTracksById[videoId] = [];
            pendingNewPersonsById[videoId] = [];
            currentBboxesById[videoId] = [];
            lastYoloBboxesById[videoId] = [];
            yoloTriggeredBySceneById[videoId] = true;
            videoStateById[videoId] = 'safe';
            metric('scene_change', {
              videoId: videoId,
              diff: Math.round(sceneDiff * 1000) / 1000
            });
          }
          // Diagnostic — log la magnitude du diff + signature du hash
          // (sum + 4 premiers pixels) périodiquement pour debug. Si tous
          // les pixels du hash sont 0 → canvas vide (drawImage cassé).
          // Si les pixels sont non-nuls mais identiques entre 2 logs →
          // canvas figé sur même image (video decoder ne refresh pas).
          var lastSceneDiag = window.__basarunaaLastSceneDiag || 0;
          if (nowMs - lastSceneDiag > 1000) {
            window.__basarunaaLastSceneDiag = nowMs;
            var hashDbg = sceneHashById[videoId];
            var hashSum = 0;
            var hashSample = [];
            if (hashDbg) {
              for (var hi = 0; hi < hashDbg.length; hi++) hashSum += hashDbg[hi];
              hashSample = [hashDbg[0], hashDbg[1], hashDbg[hashDbg.length - 2], hashDbg[hashDbg.length - 1]];
            }
            metric('scene_diff_diag', {
              videoId: videoId,
              diff: Math.round(sceneDiff * 10000) / 10000,
              hashSum: hashSum,
              hashSample: hashSample
            });
            // Perf blur — p50/p95 sur fenêtre glissante. Permet de comparer
            // 'box' (default) vs 'gaussian' (toggle window.__basarunaaBlurMode).
            if (blurPerfSamples.length >= 10) {
              var sorted = blurPerfSamples.slice().sort(function(a, b) { return a - b; });
              var p50 = sorted[Math.floor(sorted.length * 0.5)];
              var p95 = sorted[Math.floor(sorted.length * 0.95)];
              var avg = 0;
              for (var bi = 0; bi < sorted.length; bi++) avg += sorted[bi];
              avg /= sorted.length;
              metric('blur_perf', {
                mode: window.__basarunaaBlurMode || 'gaussian',
                n: sorted.length,
                p50_ms: Math.round(p50 * 100) / 100,
                p95_ms: Math.round(p95 * 100) / 100,
                avg_ms: Math.round(avg * 100) / 100
              });
            }
          }

          var state = videoStateById[videoId] || 'safe';
          var yoloInterval = state === 'safe' ? YOLO_INTERVAL_SAFE_MS : YOLO_INTERVAL_TRACKING_MS;
          var lastYoloMs = lastYoloTimeById[videoId] || 0;
          var lastSentinelMs = lastSentinelTimeById[videoId] || 0;
          var yoloDue = (nowMs - lastYoloMs) >= yoloInterval;
          var yoloTriggered = !!yoloTriggeredBySentinelById[videoId] || !!yoloTriggeredBySceneById[videoId];
          var yoloCooldownOk = (nowMs - lastYoloMs) >= YOLO_MIN_COOLDOWN_MS;

          if (!yoloInFlightById[videoId] && yoloCooldownOk && (yoloDue || yoloTriggered)) {
            yoloInFlightById[videoId] = true;
            // Les flags triggered sont consommés dans `__basarunaaApplyVideo`
            // au retour, pour pouvoir comptabiliser par trigger.
            lastYoloTimeById[videoId] = nowMs;
            metric('yolo_send', {
              videoId: videoId, state: state,
              dueAfterMs: Math.round(nowMs - lastYoloMs),
              triggered: yoloTriggered
            });
            sampleForAnalysis(videoId, video);
          } else if (
            !yoloInFlightById[videoId]
            && !sentinelInFlightById[videoId]
            && (nowMs - lastSentinelMs) >= SENTINEL_INTERVAL_MS
            && (nowMs - lastSentinelMs) >= SENTINEL_MIN_COOLDOWN_MS
          ) {
            sentinelInFlightById[videoId] = true;
            lastSentinelTimeById[videoId] = nowMs;
            sampleForSentinel(videoId, video);
          }
          // Diagnostic — log uniquement les VRAIS stucks (>3s sans retour
          // côté JS). Un YOLO normal met 50-100ms à revenir, donc 1s de
          // seuil triggerait des faux positifs à chaque tick suivant un
          // send. >3s signale un vrai problème (drop natif silencieux,
          // crash WebKit, etc.). Rate-limited à 1/s.
          if (yoloInFlightById[videoId] && (nowMs - lastYoloMs) > 3000) {
            var lastDiag = window.__basarunaaLastTickDiag || 0;
            if (nowMs - lastDiag > 1000) {
              window.__basarunaaLastTickDiag = nowMs;
              metric('yolo_stuck_in_flight', {
                videoId: videoId, state: state,
                msSinceLastYolo: Math.round(nowMs - lastYoloMs),
                sentinelInFlight: !!sentinelInFlightById[videoId]
              });
            }
          }

          // Blur bboxes courantes — pour chaque bbox on draw la zone
          // correspondante du <video> downsamplée puis upscalée. En
          // fullscreen, scale + offset par la zone letterboxée (dispW/H,
          // dispOffX/Y) ; en mode normal, dispW=pw, dispH=ph, offsets=0.
          var bboxes = currentBboxesById[videoId];
          var meta = currentBboxMetaById[videoId];
          if (bboxes && bboxes.length && meta) {
            var sx = dispW / meta.analyseW;
            var sy = dispH / meta.analyseH;
            var videoDebug = videoDebugModeById[videoId] || 'none';
            for (var i = 0; i < bboxes.length; i++) {
              drawAndBlurRegion(dctx, video, bboxes[i], sx, sy, vw, vh, dispW, dispH, dispOffX, dispOffY, videoDebug);
            }
            // Overlay debug global (sentinel/all-persons/skeleton/HUD).
            // Dessiné après les drawAndBlurRegion pour rester au-dessus du blur.
            if (videoDebug === 'boxes' || videoDebug === 'debug') {
              _drawVideoDebugOverlay(dctx, videoId, videoDebug, dispW, dispH, dispOffX, dispOffY, meta);
            }
            // En mode debug, badge "NSFW" en haut-gauche du canvas pour
            // distinguer un full-frame blur intentionnel d'un bug. Le
            // badge est dessiné par-dessus le blur car le bbox full-frame
            // couvre tout le canvas (snap → hasFeather=false → pas de
            // rects pointillés dans drawAndBlurRegion).
            if (videoNsfwById[videoId] && (videoDebug === 'boxes' || videoDebug === 'debug')) {
              var dpr = window.devicePixelRatio || 1;
              dctx.save();
              var pad = 8 * dpr;
              var fontPx = Math.max(14, Math.round(14 * dpr));
              dctx.font = 'bold ' + fontPx + 'px -apple-system, system-ui, sans-serif';
              var label = 'NSFW';
              var tw_text = dctx.measureText(label).width;
              var bgW = tw_text + 2 * pad;
              var bgH = fontPx + 2 * pad;
              dctx.fillStyle = 'rgba(220, 30, 30, 0.85)';
              dctx.fillRect(pad, pad, bgW, bgH);
              dctx.fillStyle = '#fff';
              dctx.textBaseline = 'middle';
              dctx.fillText(label, pad * 2, pad + bgH / 2);
              dctx.restore();
            }
          }

        } catch (e) {
          // CORS taint, decoder fail, etc. — on stoppe pour ce <video>.
          taintedVideos.add(video);
          if (display.parentNode) display.parentNode.removeChild(display);
          delete displayCanvasById[videoId];
          metric('video_draw_error', {
            videoId: videoId,
            msg: ('' + e).slice(0, 200)
          });
          return;
        }
        video.requestVideoFrameCallback(tick);
      }
      video.requestVideoFrameCallback(tick);
    }

    function sampleForAnalysis(videoId, video) {
      // Capture brute la frame du <video> source dans sampleCanvas (max
      // 320 px de large) → JPEG q=0.5 → envoie à Swift pour ML analyse.
      // Indépendant du canvas display (qui est notre overlay sélectif).
      var vw = video.videoWidth, vh = video.videoHeight;
      if (vw === 0 || vh === 0) return;
      var sw = Math.min(MAX_SAMPLE_WIDTH, vw);
      var sh = Math.max(1, Math.round(vh * sw / vw));
      if (sampleCanvas.width !== sw) sampleCanvas.width = sw;
      if (sampleCanvas.height !== sh) sampleCanvas.height = sh;
      sctx.drawImage(video, 0, 0, sw, sh);
      var dataUrl = sampleCanvas.toDataURL('image/jpeg', JPEG_QUALITY);
      var comma = dataUrl.indexOf(',');
      if (comma > 0) {
        var b64 = dataUrl.substring(comma + 1);
        var ctMs = Math.round((video.currentTime || 0) * 1000);
        send('videoFrame', videoId + '|' + ctMs + '|' + sw + '|' + sh + '|' + b64);
      }
    }

    // Sentinel sample — capture plus large (480 px vs 320 pour YOLO, parité
    // POC `SENTINEL_CAPTURE_SIZE`) en JPEG q=0.6. NanoDet est plus tolérant
    // au downscale qu'un detector lourd, mais il a aussi besoin d'un peu
    // plus de détail que la YOLO pour repérer des nouveaux entrants petits.
    function sampleForSentinel(videoId, video) {
      var vw = video.videoWidth, vh = video.videoHeight;
      if (vw === 0 || vh === 0) {
        sentinelInFlightById[videoId] = false;
        return;
      }
      var aspect = vw / vh;
      var sw, sh;
      if (aspect > 1) {
        sw = SENTINEL_CAPTURE_SIZE;
        sh = Math.max(1, Math.round(SENTINEL_CAPTURE_SIZE / aspect));
      } else {
        sh = SENTINEL_CAPTURE_SIZE;
        sw = Math.max(1, Math.round(SENTINEL_CAPTURE_SIZE * aspect));
      }
      if (sampleCanvas.width !== sw) sampleCanvas.width = sw;
      if (sampleCanvas.height !== sh) sampleCanvas.height = sh;
      sctx.drawImage(video, 0, 0, sw, sh);
      var dataUrl = sampleCanvas.toDataURL('image/jpeg', SENTINEL_JPEG_QUALITY);
      var comma = dataUrl.indexOf(',');
      if (comma > 0) {
        var b64 = dataUrl.substring(comma + 1);
        var ctMs = Math.round((video.currentTime || 0) * 1000);
        send('videoSentinel', videoId + '|' + ctMs + '|' + sw + '|' + sh + '|' + b64);
      } else {
        sentinelInFlightById[videoId] = false;
      }
    }

    // Pour chaque bbox à flouter, draw la zone correspondante de la
    // source <video> (en coords pixels natifs `videoWidth × videoHeight`)
    // downsamplée vers `blurCanvas` puis upscalée dans le canvas display
    // — résultat : pixel flou dans le canvas, le reste reste transparent.
    // Le `imageSmoothingEnabled:high` + l'aller-retour BLUR_DOWNSAMPLE× fait
    // le flou. Pas de `ctx.filter='blur(...)'` (lent en canvas 2D WebKit).
    //
    // bboxes en coords analyse (= dim JPEG envoyé) → sx, sy rescale vers
    // canvas pixel size (pw, ph). On reconvertit ensuite en source <video>
    // pixel coords pour drawImage(video, srcX, srcY, srcW, srcH, ...).
    function drawAndBlurRegion(dctx, video, bbox, sx, sy, vw, vh, canvasW, canvasH, offX, offY, debugMode) {
      offX = offX || 0;
      offY = offY || 0;
      var bx = offX + bbox[0] * sx;
      var by = offY + bbox[1] * sy;
      var bw = (bbox[2] - bbox[0]) * sx;
      var bh = (bbox[3] - bbox[1]) * sy;
      if (bw <= 0 || bh <= 0) return;
      bx = Math.max(0, Math.floor(bx));
      by = Math.max(0, Math.floor(by));
      bw = Math.min(dctx.canvas.width - bx, Math.ceil(bw));
      bh = Math.min(dctx.canvas.height - by, Math.ceil(bh));
      if (bw <= 0 || bh <= 0) return;
      // Source coords sur le <video> natif (videoWidth × videoHeight).
      // canvasW/H = taille de la zone où la vidéo est rendue (= dispW/H
      // en fullscreen letterbox, = pw/ph en normal).
      var srcSx = vw / canvasW;
      var srcSy = vh / canvasH;

      // ── Feather extend (snap aux bords image) ──────────────────
      // Si bbox proche d'un bord image, on n'étend PAS de ce côté
      // (snap → pas de dégradé visible vers le vide). Le clamp final
      // empêche de sortir du canvas (en cas de coin par ex).
      var dcw = dctx.canvas.width, dch = dctx.canvas.height;
      var snapX = dcw * 0.10, snapY = dch * 0.10;
      var FM = (typeof window.__basarunaaFeatherMarginPx === 'number')
        ? window.__basarunaaFeatherMarginPx
        : VIDEO_FEATHER_MARGIN_PX_DEFAULT;
      var featherEnabled = (window.__basarunaaFeatherDisabled !== true);
      var exL = (featherEnabled && bx >= snapX) ? FM : 0;
      var exT = (featherEnabled && by >= snapY) ? FM : 0;
      var exR = (featherEnabled && (dcw - (bx + bw)) >= snapX) ? FM : 0;
      var exB = (featherEnabled && (dch - (by + bh)) >= snapY) ? FM : 0;
      exL = Math.min(exL, bx);
      exT = Math.min(exT, by);
      exR = Math.min(exR, dcw - (bx + bw));
      exB = Math.min(exB, dch - (by + bh));
      var bxe = bx - exL, bye = by - exT;
      var bwe = bw + exL + exR, bhe = bh + exT + exB;
      var hasFeather = (exL + exT + exR + exB) > 0;

      // 2-pass blur — l'aller-retour downsample-upsample fait une moyenne
      // bilinéaire de pixels (~box filter). Avec 2 passes successives, on
      // approxime un gaussian blur smooth. Mode 'gaussian' add `ctx.filter`
      // sur le tiny canvas pour un vrai gaussian (potentiellement plus lent
      // sur WebKit, à vérifier via `blur_perf` métric).
      var blurStart = (typeof performance !== 'undefined' && performance.now)
        ? performance.now() : Date.now();
      // Mode default = 'gaussian' depuis la mesure 2026-05-20 : box perf
      // p50=0ms, avg=0.05ms → coût du gaussian négligeable (~0.5-1ms
      // attendu sur tiny canvas), qualité supérieure.
      var blurMode = window.__basarunaaBlurMode || 'gaussian';
      // Coords source vidéo pour la zone étendue (clampé aux bords vidéo).
      var srcX_e = (bxe - offX) * srcSx;
      var srcY_e = (bye - offY) * srcSy;
      var srcW_e = bwe * srcSx;
      var srcH_e = bhe * srcSy;
      if (srcX_e < 0) { srcW_e += srcX_e; srcX_e = 0; }
      if (srcY_e < 0) { srcH_e += srcY_e; srcY_e = 0; }
      if (srcX_e + srcW_e > vw) srcW_e = vw - srcX_e;
      if (srcY_e + srcH_e > vh) srcH_e = vh - srcY_e;
      // Pass 1: video → blurCanvas (downsample fort, BLUR_DOWNSAMPLE×)
      var tw = Math.max(1, Math.round(bwe / BLUR_DOWNSAMPLE));
      var th = Math.max(1, Math.round(bhe / BLUR_DOWNSAMPLE));
      if (blurCanvas.width !== tw) blurCanvas.width = tw;
      if (blurCanvas.height !== th) blurCanvas.height = th;
      bctx.imageSmoothingEnabled = true;
      bctx.imageSmoothingQuality = 'high';
      if (blurMode === 'gaussian') {
        // Gaussian filter sur le tiny canvas — coût ~constant à cette taille.
        bctx.filter = 'blur(' + BLUR_GAUSSIAN_RADIUS_PX + 'px)';
      }
      bctx.drawImage(video, srcX_e, srcY_e, srcW_e, srcH_e, 0, 0, tw, th);
      if (blurMode === 'gaussian') {
        bctx.filter = 'none';
      }
      // Pass 2: blurCanvas → blurCanvas2 (re-downsample 2× pour lisser)
      var tw2 = Math.max(1, Math.round(tw / BLUR_PASS2_FACTOR));
      var th2 = Math.max(1, Math.round(th / BLUR_PASS2_FACTOR));
      if (blurCanvas2.width !== tw2) blurCanvas2.width = tw2;
      if (blurCanvas2.height !== th2) blurCanvas2.height = th2;
      bctx2.imageSmoothingEnabled = true;
      bctx2.imageSmoothingQuality = 'high';
      bctx2.drawImage(blurCanvas, 0, 0, tw, th, 0, 0, tw2, th2);

      if (!hasFeather) {
        // Pas de feather (toggle off ou bbox plaqué aux 4 bords) :
        // Pass 3 directe — upscale blur vers dctx aux coords étendues
        // (= coords originales puisque exL/T/R/B = 0).
        dctx.imageSmoothingEnabled = true;
        dctx.imageSmoothingQuality = 'high';
        dctx.drawImage(blurCanvas2, 0, 0, tw2, th2, bxe, bye, bwe, bhe);
      } else {
        // ── Feather composite ─────────────────────────────────────
        // Pass 3a : upscale blur → featherTemp (taille bbox étendue).
        if (featherTempCanvas.width !== bwe) featherTempCanvas.width = bwe;
        if (featherTempCanvas.height !== bhe) featherTempCanvas.height = bhe;
        ftCtx.clearRect(0, 0, bwe, bhe);
        ftCtx.imageSmoothingEnabled = true;
        ftCtx.imageSmoothingQuality = 'high';
        ftCtx.drawImage(blurCanvas2, 0, 0, tw2, th2, 0, 0, bwe, bhe);
        // Pass 3b : mask blanc strict bbox au centre de l'extended. Le
        // blur du mask via downsample-upsample par maskFactor = FM donne
        // un dégradé centré sur le bord du rect (= bord du bbox d'origine).
        // Donc à la position du bbox d'origine, alpha ≈ 50%, et le
        // dégradé s'étend de ~FM/2 de chaque côté (intérieur + extérieur).
        if (featherMaskCanvas.width !== bwe) featherMaskCanvas.width = bwe;
        if (featherMaskCanvas.height !== bhe) featherMaskCanvas.height = bhe;
        fmCtx.clearRect(0, 0, bwe, bhe);
        fmCtx.fillStyle = '#fff';
        fmCtx.fillRect(exL, exT, bw, bh);
        // Pass 3c : blur le mask (downsample-upsample, factor ~= FM).
        // POC macOS utilise `ctx.filter='blur(15px)'` mais c'est un no-op
        // sur WebKit iOS — on émule via aller-retour bilinéaire. Factor
        // ~= FM donne un dégradé proche du blur natif macOS (testé 2026-05-20).
        var maskFactor = Math.max(8, FM);
        var msW = Math.max(1, Math.floor(bwe / maskFactor));
        var msH = Math.max(1, Math.floor(bhe / maskFactor));
        if (featherMaskSmallCanvas.width !== msW) featherMaskSmallCanvas.width = msW;
        if (featherMaskSmallCanvas.height !== msH) featherMaskSmallCanvas.height = msH;
        fmsCtx.clearRect(0, 0, msW, msH);
        fmsCtx.imageSmoothingEnabled = true;
        fmsCtx.imageSmoothingQuality = 'high';
        fmsCtx.drawImage(featherMaskCanvas, 0, 0, bwe, bhe, 0, 0, msW, msH);
        if (featherMaskBlurredCanvas.width !== bwe) featherMaskBlurredCanvas.width = bwe;
        if (featherMaskBlurredCanvas.height !== bhe) featherMaskBlurredCanvas.height = bhe;
        fmbCtx.clearRect(0, 0, bwe, bhe);
        fmbCtx.imageSmoothingEnabled = true;
        fmbCtx.imageSmoothingQuality = 'high';
        fmbCtx.drawImage(featherMaskSmallCanvas, 0, 0, msW, msH, 0, 0, bwe, bhe);
        // Pass 3d : composite mask → bords feathered.
        ftCtx.globalCompositeOperation = 'destination-in';
        ftCtx.drawImage(featherMaskBlurredCanvas, 0, 0);
        ftCtx.globalCompositeOperation = 'source-over';
        // Pass 3e : draw final sur dctx.
        dctx.imageSmoothingEnabled = true;
        dctx.imageSmoothingQuality = 'high';
        dctx.drawImage(featherTempCanvas, 0, 0, bwe, bhe, bxe, bye, bwe, bhe);
      }
      // Mesure perf (en ms par bbox) — fenêtre glissante 60 samples.
      var blurEnd = (typeof performance !== 'undefined' && performance.now)
        ? performance.now() : Date.now();
      blurPerfSamples.push(blurEnd - blurStart);
      if (blurPerfSamples.length > BLUR_PERF_WINDOW) blurPerfSamples.shift();
      if (DEBUG_BBOX_STROKE) {
        dctx.strokeStyle = 'rgba(255, 80, 80, 0.9)';
        dctx.lineWidth = Math.max(2, Math.round(2 * (window.devicePixelRatio || 1)));
        dctx.strokeRect(bx, by, bw, bh);
      }
      // En mode debug "boxes" ou "debug" — affiche 2 rects pointillés :
      // - intérieur (cyan) : zone du blur 100% (= bbox d'origine rétréci
      //   de FM/2 sur chaque côté feathered, car le dégradé alpha est
      //   centré sur le bord du bbox d'origine où alpha ≈ 50%)
      // - extérieur (jaune) : fin du dégradé alpha (= bbox étendue de FM)
      if ((debugMode === 'boxes' || debugMode === 'debug') && hasFeather) {
        dctx.save();
        var dpr = window.devicePixelRatio || 1;
        dctx.lineWidth = Math.max(1.5, Math.round(1.5 * dpr));
        dctx.setLineDash([6 * dpr, 4 * dpr]);
        var halfFM_cyan = Math.floor(FM / 2);
        var cyanX = bx + (exL > 0 ? halfFM_cyan : 0);
        var cyanY = by + (exT > 0 ? halfFM_cyan : 0);
        var cyanW = bw - (exL > 0 ? halfFM_cyan : 0) - (exR > 0 ? halfFM_cyan : 0);
        var cyanH = bh - (exT > 0 ? halfFM_cyan : 0) - (exB > 0 ? halfFM_cyan : 0);
        dctx.strokeStyle = 'rgba(80, 220, 255, 0.95)';
        if (cyanW > 0 && cyanH > 0) dctx.strokeRect(cyanX, cyanY, cyanW, cyanH);
        dctx.strokeStyle = 'rgba(255, 230, 80, 0.95)';
        dctx.strokeRect(bxe, bye, bwe, bhe);
        dctx.restore();
      }
    }

    // Overlay debug vidéo — parité macOS POC `renderBlur` debug branch +
    // `_drawHUD`. Appelé 1× par tick après les drawAndBlurRegion. Dessine :
    //  - Sentinel bboxes (vert dashed) — ce que NanoDet voit
    //  - All persons bboxes (rose/bleu/jaune par gender) — toutes les
    //    persons YOLO (pas juste celles à flouter). Label F/M + conf%.
    //  - Skeleton COCO (mode 'debug' only) — limbs colorés
    //  - Keypoints (mode 'debug' only) — dots blancs
    //  - HUD bottom-left : state, blur count, YOLO counters par trigger,
    //    sentinel count, frames depuis dernier YOLO, latency
    function _drawVideoDebugOverlay(dctx, videoId, debugMode, dispW, dispH, dispOffX, dispOffY, meta) {
      if (!meta) return;
      var sx = dispW / meta.analyseW;
      var sy = dispH / meta.analyseH;

      // ── Sentinel bboxes (dashed vert) ──
      var sentinelPersons = videoSentinelPersonsById[videoId] || [];
      if (sentinelPersons.length > 0) {
        dctx.save();
        dctx.strokeStyle = '#00FF00';
        dctx.lineWidth = 1;
        dctx.setLineDash([4, 4]);
        dctx.font = 'bold 10px monospace';
        for (var i = 0; i < sentinelPersons.length; i++) {
          var sp = sentinelPersons[i];
          var sb = sp.bbox;
          var rx = dispOffX + sb[0] * sx;
          var ry = dispOffY + sb[1] * sy;
          var rw = (sb[2] - sb[0]) * sx;
          var rh = (sb[3] - sb[1]) * sy;
          dctx.strokeRect(rx, ry, rw, rh);
          dctx.fillStyle = '#00FF00';
          var labelY = ry >= 12 ? ry - 3 : ry + 10;
          dctx.fillText('S ' + Math.round((sp.confidence || 0) * 100) + '%', rx, labelY);
        }
        dctx.restore();
      }

      // ── All persons bboxes (H/F colored) + skeleton (mode 'debug') ──
      var allPersons = videoAllPersonsById[videoId] || [];
      var COCO_SKELETON = [
        [0,1],[0,2],[1,3],[2,4],[5,6],
        [5,7],[7,9],[6,8],[8,10],
        [5,11],[6,12],[11,12],
        [11,13],[13,15],[12,14],[14,16]
      ];
      var LIMB_COLORS = [
        '#FF6B6B','#FF6B6B','#FF6B6B','#FF6B6B','#FFD93D',
        '#6BCB77','#6BCB77','#4D96FF','#4D96FF',
        '#FFD93D','#FFD93D','#FFD93D',
        '#6BCB77','#6BCB77','#4D96FF','#4D96FF'
      ];
      var KP_CONF_THRESHOLD = 0.3;
      for (var pi = 0; pi < allPersons.length; pi++) {
        var p = allPersons[pi];
        var pb = p.bbox || [0, 0, 0, 0];
        var dx = dispOffX + pb[0] * sx;
        var dy = dispOffY + pb[1] * sy;
        var dw = (pb[2] - pb[0]) * sx;
        var dh = (pb[3] - pb[1]) * sy;
        if (dw <= 0 || dh <= 0) continue;
        var color = (p.gender === 'female') ? '#FF69B4'
                  : (p.gender === 'male')   ? '#4169E1'
                                            : '#FFCC00';
        dctx.save();
        dctx.strokeStyle = color;
        dctx.lineWidth = 2;
        dctx.strokeRect(dx, dy, dw, dh);
        var labelTxt = (p.gender === 'female') ? 'F'
                     : (p.gender === 'male')   ? 'M'
                                               : '?';
        if (typeof p.genderConfidence === 'number') {
          labelTxt += ' ' + Math.round(p.genderConfidence * 100) + '%';
        }
        if (p.classifierUsed) labelTxt += ' [' + p.classifierUsed + ']';
        dctx.fillStyle = color;
        dctx.font = 'bold 11px monospace';
        var labelLY = dy >= 14 ? dy - 4 : dy + 14;
        dctx.fillText(labelTxt, dx, labelLY);
        if (debugMode === 'debug' && Array.isArray(p.keypoints) && p.keypoints.length >= 17) {
          var kps = p.keypoints;  // [[x, y, conf], ...]
          dctx.lineWidth = Math.max(1, Math.round(dw * 0.015));
          for (var si = 0; si < COCO_SKELETON.length; si++) {
            var ai = COCO_SKELETON[si][0], bi = COCO_SKELETON[si][1];
            var ka = kps[ai], kb = kps[bi];
            if (!ka || !kb) continue;
            if (ka[2] > KP_CONF_THRESHOLD && kb[2] > KP_CONF_THRESHOLD) {
              dctx.strokeStyle = LIMB_COLORS[si];
              dctx.beginPath();
              dctx.moveTo(dispOffX + ka[0] * sx, dispOffY + ka[1] * sy);
              dctx.lineTo(dispOffX + kb[0] * sx, dispOffY + kb[1] * sy);
              dctx.stroke();
            }
          }
          dctx.fillStyle = '#FFFFFF';
          for (var ki = 0; ki < kps.length; ki++) {
            if (kps[ki][2] > KP_CONF_THRESHOLD) {
              dctx.beginPath();
              dctx.arc(dispOffX + kps[ki][0] * sx, dispOffY + kps[ki][1] * sy, 2.5, 0, Math.PI * 2);
              dctx.fill();
            }
          }
        }
        dctx.restore();
      }

      // ── HUD bottom-left (parité macOS `_drawHUD`) ──
      var state = videoStateById[videoId] || 'safe';
      var timing = videoLastTimingById[videoId];
      var mode = (timing && timing.mode) ? timing.mode : '?';
      var nBlur = (currentBboxesById[videoId] || []).length;
      var yp = yoloCountPeriodicById[videoId] || 0;
      var ys = yoloCountSentinelById[videoId] || 0;
      var yc = yoloCountSceneById[videoId] || 0;
      var yTotal = yp + ys + yc;
      var sc = sentinelCountById[videoId] || 0;
      var nSentinel = sentinelPersons.length;
      var fsy = framesSinceYoloById[videoId] || 0;
      var inFlight = !!yoloInFlightById[videoId];
      var lines = [
        state + ' | ' + nBlur + ' blur | ' + mode,
        'YOLO: ' + yTotal + ' (p:' + yp + ' s:' + ys + ' c:' + yc + ')' + (inFlight ? ' ...' : ''),
        'Sentinel: ' + sc + ' runs | ' + nSentinel + 'p | ' + fsy + 'f since YOLO'
      ];
      if (timing) {
        var pose = Math.round(timing.poseLatencyMs || 0);
        var cls = Math.round(timing.classifyLatencyMs || 0);
        lines.push('det: ' + pose + 'ms cls: ' + cls + 'ms');
      }
      var fontPx = 11;
      var lineH = fontPx + 3;
      var pad = 5;
      dctx.save();
      dctx.font = 'bold ' + fontPx + 'px monospace';
      var boxW = 0;
      for (var li = 0; li < lines.length; li++) {
        var lw = dctx.measureText(lines[li]).width;
        if (lw > boxW) boxW = lw;
      }
      boxW += pad * 2;
      var boxH = lines.length * lineH + pad * 2;
      var boxY = dctx.canvas.height - boxH;
      dctx.fillStyle = 'rgba(0, 0, 0, 0.75)';
      dctx.fillRect(0, boxY, boxW, boxH);
      dctx.fillStyle = '#0f0';
      dctx.textBaseline = 'alphabetic';
      for (var li2 = 0; li2 < lines.length; li2++) {
        dctx.fillText(lines[li2], pad, boxY + pad + (li2 + 1) * lineH - 3);
      }
      dctx.restore();
    }

    function scanAndWire() {
      var videos = document.getElementsByTagName('video');
      for (var i = 0; i < videos.length; i++) {
        wireVideo(videos[i]);
      }
      // Try to setup floating subtitles (idempotent — no-op if déjà fait).
      // Le subtitle container peut être créé après le wireVideo initial
      // (lazy YT), donc on retry à chaque MutationObserver tick.
      if (!floatingSubInfo) {
        for (var v in videosById) {
          if (videosById[v]) {
            setupFloatingSubtitles(videosById[v]);
            if (floatingSubInfo) break;
          }
        }
      }
    }

    // Appelée par Swift via `tab.evaluateJavaScript` à chaque résultat
    // d'analyse. On stocke les bboxes globalement ; le render loop les
    // applique à chaque rVFC (~30 fps). Si NSFW, on remplace les bboxes
    // par un full-frame blur (1 seule bbox couvrant la totale).
    window.__basarunaaApplyVideo = function(videoId, ctMs, analyseW, analyseH, bboxes, isNsfw, debugMode, fullPersons, timing) {
      try {
        // Libère le flag in-flight quoiqu'il arrive — sinon un display
        // canvas removed pendant l'analyse fige la state machine sur
        // "YOLO occupe le slot" et le sentinel ne fire plus jamais.
        yoloInFlightById[videoId] = false;
        if (!displayCanvasById[videoId]) {
          metric('video_apply_no_canvas', { videoId: videoId });
          return;
        }
        var safeBboxes = bboxes || [];
        videoNsfwById[videoId] = !!isNsfw;
        if (isNsfw) {
          currentBboxesById[videoId] = [[0, 0, analyseW, analyseH]];
        } else {
          currentBboxesById[videoId] = safeBboxes;
        }
        currentBboxMetaById[videoId] = { analyseW: analyseW, analyseH: analyseH };
        // Snapshot des bboxes YOLO (en coords analyse) pour matcher les
        // détections sentinel. Sentinel travaille dans son propre espace
        // de capture (SENTINEL_CAPTURE_SIZE) → on doit rescaler côté JS
        // au moment du `__basarunaaApplyVideoSentinel` pour comparer.
        lastYoloBboxesById[videoId] = safeBboxes.map(function(b) { return b.slice(); });
        // Calcule les offsets YOLO↔sentinel AVANT de reset les tracks
        // (parité POC `runDetection` lignes 715-740). Pour chaque bbox
        // YOLO, on cherche le track sentinel le plus proche par centre,
        // dans une tolérance de 60% de la hauteur YOLO. On stocke le
        // décalage (= bias systématique de NanoDet vs YOLO) + les
        // dimensions YOLO d'origine. Utilisé par `_updateBlurFromSentinel`
        // pour corriger les positions sentinel suivantes.
        var existingTracks = sentinelTracksById[videoId] || [];
        yoloOffsetsById[videoId] = safeBboxes.map(function(yoloBbox) {
          var yoloCx = (yoloBbox[0] + yoloBbox[2]) / 2;
          var yoloCy = (yoloBbox[1] + yoloBbox[3]) / 2;
          var yoloW = yoloBbox[2] - yoloBbox[0];
          var yoloH = (yoloBbox[3] - yoloBbox[1]) || 1;
          var bestDist = Infinity, bestTrack = null;
          for (var ti = 0; ti < existingTracks.length; ti++) {
            var t = existingTracks[ti].bbox;
            var tCx = (t[0] + t[2]) / 2;
            var tCy = (t[1] + t[3]) / 2;
            var dx = yoloCx - tCx;
            var dy = yoloCy - tCy;
            var d = Math.sqrt(dx * dx + dy * dy);
            if (d < bestDist) { bestDist = d; bestTrack = t; }
          }
          var offX = 0, offY = 0;
          if (bestTrack && bestDist < yoloH * 0.6) {
            var stCx = (bestTrack[0] + bestTrack[2]) / 2;
            var stCy = (bestTrack[1] + bestTrack[3]) / 2;
            offX = stCx - yoloCx;
            offY = stCy - yoloCy;
          }
          return { offsetX: offX, offsetY: offY, yoloW: yoloW, yoloH: yoloH };
        });
        // Memoïse le debugMode pour ce videoId — sentinels & ticks suivants
        // l'utilisent pour décider de l'overlay (boxes/debug).
        videoDebugModeById[videoId] = debugMode || 'none';
        // Stocke les persons riches (mode debug) + timing pour HUD.
        videoAllPersonsById[videoId] = Array.isArray(fullPersons) ? fullPersons : [];
        videoLastTimingById[videoId] = timing || null;
        // Reset framesSinceYolo — incrémenté à chaque tick rVFC.
        framesSinceYoloById[videoId] = 0;
        // Comptabilise le YOLO selon son trigger (cadence vs sentinel vs scene).
        // Les flags sont posés en amont par le scheduler ; `__basarunaaApplyVideo`
        // est la première occasion sûre de les lire car appelé strictement
        // après le retour natif.
        var triggeredBySentinel = !!yoloTriggeredBySentinelById[videoId];
        var triggeredByScene = !!yoloTriggeredBySceneById[videoId];
        if (triggeredBySentinel) {
          yoloCountSentinelById[videoId] = (yoloCountSentinelById[videoId] || 0) + 1;
          yoloTriggeredBySentinelById[videoId] = false;
        } else if (triggeredByScene) {
          yoloCountSceneById[videoId] = (yoloCountSceneById[videoId] || 0) + 1;
          yoloTriggeredBySceneById[videoId] = false;
        } else {
          yoloCountPeriodicById[videoId] = (yoloCountPeriodicById[videoId] || 0) + 1;
        }
        // State machine cadence : tracking si au moins 1 personne à
        // flouter OU si NSFW (= re-évaluer rapidement la sortie du NSFW
        // pour ne pas garder un full-frame blur stale). Safe sinon.
        // Pas de gender info — le natif a déjà filtré par mode (cf.
        // `decide()` côté Swift).
        videoStateById[videoId] = (safeBboxes.length > 0 || isNsfw) ? 'tracking' : 'safe';
        // Reset des tracks sentinel sur full YOLO refresh (le YOLO refait
        // la vérité de base, le tracking sentinel reprend à partir de là).
        sentinelTracksById[videoId] = [];
        pendingNewPersonsById[videoId] = [];
        metric('video_apply', {
          videoId: videoId, ct_ms: ctMs,
          nsfw: !!isNsfw, n: safeBboxes.length,
          state: videoStateById[videoId]
        });
      } catch (e) {
        yoloInFlightById[videoId] = false;
        metric('video_apply_error', {
          videoId: videoId, msg: ('' + e).slice(0, 200)
        });
      }
    };

    // Sentinel payload — `bboxes` are `[x1, y1, x2, y2, confidence]` in
    // capture coords (SENTINEL_CAPTURE_SIZE space). Rescale to last-YOLO
    // analyse coords for matching (so we can compare against lastYoloBboxes
    // which live in that space). EMA-smooth, find unmatched, trigger YOLO
    // if confirmed (2 consecutive sightings), and update blur positions.
    window.__basarunaaApplyVideoSentinel = function(videoId, ctMs, sentinelW, sentinelH, payload) {
      try {
        sentinelInFlightById[videoId] = false;
        if (!displayCanvasById[videoId]) return;
        // NSFW = full-frame blur figé jusqu'au prochain YOLO. On skip toute
        // la logique sentinel (reposition, sentinel-lost, new-person trigger)
        // pour ne pas casser la bbox full-frame. Le scheduler ré-évaluera
        // NSFW au prochain YOLO périodique.
        if (videoNsfwById[videoId]) {
          metric('video_sentinel_skip_nsfw', { videoId: videoId });
          return;
        }
        var meta = currentBboxMetaById[videoId];
        var analyseW = meta ? meta.analyseW : sentinelW;
        var analyseH = meta ? meta.analyseH : sentinelH;
        var sx = analyseW / sentinelW;
        var sy = analyseH / sentinelH;
        var rawPersons = [];
        var raw = payload || [];
        for (var i = 0; i < raw.length; i++) {
          var b = raw[i];
          var padded = _padBbox(
            [b[0] * sx, b[1] * sy, b[2] * sx, b[3] * sy],
            SENTINEL_BBOX_PAD, analyseW, analyseH
          );
          rawPersons.push({ bbox: padded, confidence: b[4] || 0 });
        }
        var sentinelPersons = _smoothSentinelTracks(videoId, rawPersons, analyseW, analyseH);
        // Stocke pour overlay debug (parité macOS `lastSentinelPersons`).
        videoSentinelPersonsById[videoId] = sentinelPersons;
        sentinelCountById[videoId] = (sentinelCountById[videoId] || 0) + 1;

        // Perte de sentinel — si on trackait au moins 1 personne et que
        // sentinel retourne raw=0, on assume la disparition (cut, perte
        // de cadre). On fait 2 choses :
        //   1. Clear le blur immédiatement (currentBboxesById = []) →
        //      perçu très rapidement vs attendre le YOLO.
        //   2. Trigger YOLO immédiat pour confirmer / récupérer si FP.
        // Si YOLO retrouve la personne (sentinel rate ~100ms), il re-apply
        // le blur. Le risque de flash bref est minime (perte rare en
        // pratique) et le gain de réactivité est important.
        var yoloBboxes = lastYoloBboxesById[videoId] || [];
        var hadTracks = yoloBboxes.length > 0;
        if (raw.length === 0 && hadTracks) {
          sentinelLostCountById[videoId] = (sentinelLostCountById[videoId] || 0) + 1;
          if (sentinelLostCountById[videoId] >= SENTINEL_LOST_THRESHOLD) {
            yoloTriggeredBySentinelById[videoId] = true;
            currentBboxesById[videoId] = [];
            lastYoloBboxesById[videoId] = [];
          }
        } else {
          sentinelLostCountById[videoId] = 0;
        }

        // Find sentinel bboxes that don't match any current YOLO bbox.
        var unmatched = _findUnmatchedPersons(sentinelPersons, yoloBboxes);

        // Require 2 consecutive sightings before triggering a YOLO refresh
        // (filter sentinel false-positives, same as POC).
        var prevPending = pendingNewPersonsById[videoId] || [];
        var confirmed = [];
        for (var u = 0; u < unmatched.length; u++) {
          var found = false;
          for (var p = 0; p < prevPending.length; p++) {
            if (_bboxIoU(prevPending[p].bbox, unmatched[u].bbox) > 0.2) {
              found = true;
              break;
            }
          }
          if (found) confirmed.push(unmatched[u]);
        }
        pendingNewPersonsById[videoId] = unmatched;

        if (confirmed.length > 0) {
          yoloTriggeredBySentinelById[videoId] = true;
        }

        // Smooth-update the current blur bboxes with fresher sentinel
        // positions (so the per-person blur tracks people 30fps between
        // 2 YOLO runs even though the gender label was set 800ms ago).
        _updateBlurFromSentinel(videoId, sentinelPersons);

        // Bbox snapshot pour debug visuel — coords compactes après
        // _updateBlurFromSentinel donc on voit la vraie position rendue
        // (pas la bbox YOLO d'origine).
        var bboxesNow = (currentBboxesById[videoId] || []).map(function(b) {
          return [Math.round(b[0]), Math.round(b[1]), Math.round(b[2]), Math.round(b[3])];
        });
        metric('video_sentinel_apply', {
          videoId: videoId, ct_ms: ctMs,
          raw: raw.length, tracks: sentinelPersons.length,
          unmatched: unmatched.length, confirmed: confirmed.length,
          lost: sentinelLostCountById[videoId] || 0,
          state: videoStateById[videoId] || 'safe',
          bboxes: bboxesNow
        });
      } catch (e) {
        sentinelInFlightById[videoId] = false;
        metric('video_sentinel_apply_error', {
          videoId: videoId, msg: ('' + e).slice(0, 200)
        });
      }
    };

    // Monkey-patches pour intercepter toutes les voies de fullscreen. On
    // logge TOUT pour identifier ce que YouTube utilise réellement.
    (function() {
      if (typeof HTMLVideoElement === 'undefined') return;

      // 1) <video>.webkitEnterFullscreen — chemin iOS natif AVKit
      var protoFs = HTMLVideoElement.prototype.webkitEnterFullscreen;
      if (typeof protoFs === 'function') {
        HTMLVideoElement.prototype.webkitEnterFullscreen = function() {
          metric('fs_webkit_enter_called', { wired: wired.has(this) });
          if (wired.has(this)) {
            if (redirectToCanvasFullscreen(this)) return;
          }
          return protoFs.apply(this, arguments);
        };
      } else {
        metric('fs_no_webkitEnterFullscreen', {});
      }

      // 2) Element.requestFullscreen — chemin Web API standard
      var elProto = Element.prototype;
      var origReq = elProto.requestFullscreen;
      if (typeof origReq === 'function') {
        elProto.requestFullscreen = function() {
          var isVideo = this.tagName === 'VIDEO';
          metric('fs_request_called', {
            tag: this.tagName, isVideo: isVideo,
            wired: isVideo && wired.has(this)
          });
          if (isVideo && wired.has(this) && redirectToCanvasFullscreen(this)) {
            return Promise.resolve();
          }
          return origReq.apply(this, arguments);
        };
      }
      var origWebkitReq = elProto.webkitRequestFullscreen;
      if (typeof origWebkitReq === 'function') {
        elProto.webkitRequestFullscreen = function() {
          var isVideo = this.tagName === 'VIDEO';
          metric('fs_webkit_request_called', {
            tag: this.tagName, isVideo: isVideo,
            wired: isVideo && wired.has(this)
          });
          if (isVideo && wired.has(this) && redirectToCanvasFullscreen(this)) return;
          return origWebkitReq.apply(this, arguments);
        };
      }
    })();

    function redirectToCanvasFullscreen(video) {
      var videoId = null;
      for (var id in videosById) {
        if (videosById[id] === video) { videoId = parseInt(id, 10); break; }
      }
      if (!videoId) return false;
      var canvas = displayCanvasById[videoId];
      if (!canvas) return false;

      // Toggle : YouTube ne sait pas qu'on est en fake fullscreen, donc
      // son bouton fullscreen affiche toujours "entrer" et re-appelle
      // `webkitEnterFullscreen` à chaque tap. Si on est déjà en fake fs
      // pour ce video, on sort (au lieu d'entrer une 2e fois et corrompre
      // l'état — savedYTVideoCssText perdrait l'original).
      if (fullscreenVideoEl === video) {
        exitFakeFullscreen('yt_fs_button_toggle');
        return true;
      }

      // Bascule en fake fullscreen CSS (iPhone n'a pas
      // Element.requestFullscreen).
      //
      // Cas YouTube : on grandit `#player-container-id` lui-même à
      // 100vw/100vh → tout son contenu (video, canvas overlay, contrôles
      // YT) grandit naturellement, l'empilement DOM reste cohérent
      // (canvas au-dessus du video, contrôles au-dessus du canvas).
      //
      // Cas autres sites : on re-parente le canvas sur `body` en
      // position:fixed + z-index max (perd les contrôles natifs du site,
      // à traiter au cas par cas plus tard).
      fullscreenVideoEl = video;
      fullscreenCanvas = canvas;
      savedBodyOverflow = document.body.style.overflow;
      var ytContainer = findYTOverlayContainer(video);
      if (ytContainer && canvas.parentElement === ytContainer) {
        fullscreenYTContainer = ytContainer;
        // Subtitles : swap vers le mode fake fs (position:fixed bottom:80px).
        // Le subtitle container a déjà été déplacé vers `body` au wireVideo.
        setSubtitleFsMode(true);
        // Stratégie : utiliser un `<style>` injecté avec `!important` au
        // lieu de modifier `.style.cssText` inline. Raison : YouTube JS
        // re-écrase régulièrement le style inline du `<video>` (probablement
        // via setAttribute('style', ...) qui shoot toutes nos propriétés
        // y compris !important). Avec un `<style>` tag externe + selector
        // attribut + !important, on bat l'inline overwrite.
        ensureBasarunaaCssInjected();
        ytContainer.setAttribute('data-basarunaa-fs', '1');
        // Layout du <video> + canvas calculé en JS depuis l'intrinsic
        // ratio (video.videoWidth × video.videoHeight) et viewport size.
        // Raison : object-fit:contain + object-position:center via CSS
        // ne marche pas correctement sur iOS Safari pour le hardware
        // overlay video (rendu décalé). On positionne le `<video>` à la
        // bonne taille (aspect-correct, centered) directement en inline
        // style, et le canvas suit exactement le même rect.
        //
        // YT JS peut overwriter notre inline style → setInterval 100ms
        // pour ré-appliquer en boucle pendant tout le fake fullscreen.
        fullscreenYTVideoEl = video;
        savedYTVideoCssText = video.style.cssText;
        var applyVideoFsLayout = function(skipDraw) {
          var vw = video.videoWidth || 1920;
          var vh = video.videoHeight || 1080;
          var vpW = window.innerWidth;
          var vpH = window.innerHeight;
          var ratio = vw / vh;
          var vpRatio = vpW / vpH;
          var w, h, x, y;
          if (ratio > vpRatio) {
            // video plus large que viewport → fit width, letterbox vertical
            w = vpW; h = vpW / ratio;
            x = 0;   y = (vpH - h) / 2;
          } else {
            // video plus haute → fit height, letterbox horizontal
            h = vpH; w = vpH * ratio;
            y = 0;   x = (vpW - w) / 2;
          }
          // <video> à la taille intrinsèque centrée (object-fit:fill car
          // on a calculé pile-poil la bonne taille → pas de letterbox
          // CSS nécessaire)
          video.style.setProperty('position', 'absolute', 'important');
          video.style.setProperty('top', y + 'px', 'important');
          video.style.setProperty('left', x + 'px', 'important');
          video.style.setProperty('width', w + 'px', 'important');
          video.style.setProperty('height', h + 'px', 'important');
          video.style.setProperty('object-fit', 'fill', 'important');
          video.style.setProperty('max-width', 'none', 'important');
          video.style.setProperty('max-height', 'none', 'important');
          video.style.setProperty('transform', 'none', 'important');
          video.style.setProperty('margin', '0', 'important');
          // Canvas pile au-dessus du video (parent = #player-container-id
          // qui est maintenant pos:fixed 100vw/100vh, donc coords directes)
          var parent = canvas.parentElement;
          if (parent) {
            var parentRect = parent.getBoundingClientRect();
            canvas.style.left = (x - parentRect.left) + 'px';
            canvas.style.top = (y - parentRect.top) + 'px';
          } else {
            canvas.style.left = x + 'px';
            canvas.style.top = y + 'px';
          }
          canvas.style.width = w + 'px';
          canvas.style.height = h + 'px';
          // canvas.width/height (px backing store) ET drawImage : seulement
          // au premier call (init). Le rAF loop skip pour ne pas effacer
          // le blur que le tick rVFC vient de dessiner à chaque frame
          // (rAF s'exécute à 60fps, vs tick rVFC ~30fps → 2 erase/draw
          // entre 2 rVFC = blur invisible).
          //
          // Si paused/ended : SKIP le draw aussi. Sinon on écrirait la
          // frame brute (sans flou) dans le backing store, et comme le
          // tick rVFC ne fire pas en pause, cette frame brute resterait
          // visible → exposition d'une personne à flouter. On préserve
          // le backing store mode normal (frame floue) qui sera stretché
          // CSS-side jusqu'au prochain play. Symétrique avec
          // `exitFakeFullscreen`.
          if (!skipDraw && !video.paused && !video.ended) {
            var dpr = window.devicePixelRatio || 1;
            var pw = Math.max(1, Math.round(w * dpr));
            var ph = Math.max(1, Math.round(h * dpr));
            if (canvas.width !== pw) canvas.width = pw;
            if (canvas.height !== ph) canvas.height = ph;
            try {
              var ctx = canvas.getContext('2d');
              if (ctx) {
                ctx.fillStyle = '#000';
                ctx.fillRect(0, 0, canvas.width, canvas.height);
                ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
              }
            } catch (e) {}
          }
        };
        void ytContainer.offsetHeight;
        applyVideoFsLayout();          // 1er call : avec drawImage initial
        // rAF loop : `skipDraw=true` → laisse le tick rVFC normal gérer
        // le rendering (video + blur). Sinon on écraserait le blur dessiné
        // par rVFC à 60fps.
        var loopApply = function() {
          if (!fullscreenYTContainer) { fullscreenLayoutRAF = 0; return; }
          applyVideoFsLayout(true);
          fullscreenLayoutRAF = requestAnimationFrame(loopApply);
        };
        fullscreenLayoutRAF = requestAnimationFrame(loopApply);
      } else {
        savedCanvasCssText = canvas.style.cssText;
        savedCanvasParent = canvas.parentElement;
        savedCanvasNextSibling = canvas.nextSibling;
        if (canvas.parentElement !== document.body) {
          document.body.appendChild(canvas);
        }
        canvas.style.cssText = [
          'position:fixed',
          'top:0', 'left:0',
          'width:100vw', 'height:100vh',
          'z-index:2147483646',
          'background:#000',
          'pointer-events:auto',
          'object-fit:contain',
          'margin:0', 'padding:0'
        ].join(' !important;') + ' !important;';
      }
      document.body.style.overflow = 'hidden';

      // Pas de bouton × custom : sur YouTube le bouton fullscreen natif
      // (visible dans les contrôles YT) sert maintenant aussi de toggle
      // exit grâce à la guarde en début de cette fonction.

      metric('fs_entered_canvas', { videoId: videoId, mode: 'fakeCss' });
      try { send('fullscreenEnter'); } catch (e) {}
      return true;
    }

    function exitFakeFullscreen(reason) {
      if (!fullscreenCanvas) return;
      // Stack trace pour identifier d'où vient l'appel (debug "sort tout
      // seul après quelques secondes" reporté 2026-05-17 22:35).
      var stack = '';
      try { stack = (new Error()).stack || ''; } catch (e) {}
      metric('fs_exited', {
        reason: reason || 'unknown',
        stack: stack.slice(0, 300)
      });
      document.body.style.overflow = savedBodyOverflow;
      // Capture du canvas+video AVANT de null-er les state refs, pour
      // pouvoir forcer un re-layout du canvas en bas de cette fonction
      // (le `tick()` rVFC ne fire pas si la vidéo est en pause → sans
      // ce re-layout, le canvas garderait ses dimensions FS et déborde
      // visuellement par-dessus le contenu de la page jusqu'au prochain
      // play).
      var canvasToRelayout = fullscreenCanvas;
      var videoToRelayout = fullscreenVideoEl;
      if (fullscreenYTContainer) {
        // Stop le re-apply loop + retire l'attribut + restore inline style
        // du <video> (CSS injecté ne s'applique plus tout seul).
        if (fullscreenLayoutRAF) {
          cancelAnimationFrame(fullscreenLayoutRAF);
          fullscreenLayoutRAF = 0;
        }
        if (fullscreenYTVideoEl) {
          fullscreenYTVideoEl.style.cssText = savedYTVideoCssText;
          fullscreenYTVideoEl = null;
          savedYTVideoCssText = '';
        }
        // Subtitles : swap back to mode normal (sync au rect du <video>).
        setSubtitleFsMode(false);
        fullscreenYTContainer.removeAttribute('data-basarunaa-fs');
        fullscreenYTContainer = null;
      } else {
        // Cas non-YT : restaurer le canvas (cssText + parent d'origine).
        fullscreenCanvas.style.cssText = savedCanvasCssText;
        if (savedCanvasParent && savedCanvasParent.isConnected) {
          if (savedCanvasNextSibling && savedCanvasNextSibling.parentNode === savedCanvasParent) {
            savedCanvasParent.insertBefore(fullscreenCanvas, savedCanvasNextSibling);
          } else {
            savedCanvasParent.appendChild(fullscreenCanvas);
          }
        }
        savedCanvasParent = null;
        savedCanvasNextSibling = null;
      }
      fullscreenVideoEl = null;
      fullscreenCanvas = null;
      // Force le re-layout CSS du canvas si la vidéo est en pause (sinon
      // `tick()` ne fire pas → canvas garde ses dimensions FS et déborde
      // visuellement par-dessus la page). On NE reset PAS le backing
      // store (`canvas.width/height`) : on conserve la frame floue
      // dessinée pendant le FS, juste shrinkée CSS-side. La frame est
      // un peu déformée pendant la pause mais le flou reste appliqué
      // (pas d'exposition de la frame brute). Le prochain `tick()` au
      // play reset proprement le backing store.
      if (canvasToRelayout && videoToRelayout && videoToRelayout.isConnected) {
        try {
          var rect = videoToRelayout.getBoundingClientRect();
          if (rect.width > 0 && rect.height > 0) {
            var dp = canvasToRelayout.parentElement;
            if (dp && dp !== document.body) {
              var pr = dp.getBoundingClientRect();
              canvasToRelayout.style.left = (rect.left - pr.left) + 'px';
              canvasToRelayout.style.top = (rect.top - pr.top) + 'px';
            } else {
              canvasToRelayout.style.left = rect.left + 'px';
              canvasToRelayout.style.top = rect.top + 'px';
            }
            canvasToRelayout.style.width = rect.width + 'px';
            canvasToRelayout.style.height = rect.height + 'px';
          }
        } catch (e) {}
      }
      try { send('fullscreenExit'); } catch (e) {}
    }

    // GC périodique : si un <video> a été retiré du DOM par YouTube SPA,
    // on nettoie son canvas display + son state.
    setInterval(function() {
      for (var idStr in displayCanvasById) {
        var id = parseInt(idStr, 10);
        var v = videosById[id];
        var c = displayCanvasById[id];
        if (!v || !document.body.contains(v)) {
          if (c && c.parentNode) c.parentNode.removeChild(c);
          delete displayCanvasById[id];
          delete videosById[id];
          delete currentBboxesById[id];
          delete currentBboxMetaById[id];
          delete videoNsfwById[id];
          delete videoDebugModeById[id];
          delete videoAllPersonsById[id];
          delete videoSentinelPersonsById[id];
          delete videoLastTimingById[id];
          delete yoloCountPeriodicById[id];
          delete yoloCountSentinelById[id];
          delete yoloCountSceneById[id];
          delete sentinelCountById[id];
          delete framesSinceYoloById[id];
        }
      }
    }, 1000);

    // Scan immédiat + observer pour les <video> ajoutés dynamiquement
    // (YouTube SPA recrée l'élément à chaque navigation interne).
    function init() {
      scanAndWire();
      try {
        var mo = new MutationObserver(scanAndWire);
        mo.observe(document.documentElement || document.body, {
          childList: true,
          subtree: true
        });
      } catch (e) {
        metric('video_observer_error', { msg: '' + e });
      }
    }
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', init, { once: true });
    } else {
      init();
    }

    metric('video_pivot_init', {
      url: location.href,
      isYoutube: /(?:youtube\.com|youtu\.be)/.test(location.host)
    });
  })();
  // ─── End video pivot D ────────────────────────────────────────────────────

  // ─── Config ───
  // V1: hard-coded blur intensity. V2 will read Preferences.Basarunaa.blurStrength
  // from Swift via an initial postMessage round-trip.
  var BLUR_RADIUS_PX = 20;
  var BLUR_MARKER = 'data-basarunaa-blurred';
  var ID_ATTR = 'data-basarunaa-id';
  var STATE_ATTR = 'data-basarunaa-state';
  var MAX_DIM = 800;
  var MIN_DIM = 64;

  var nextId = 1;

  // ─── Decision cache (URL → 'keep' | 'remove') ───
  //
  // Sites with infinite scroll / lazy reload (Google Images, social feeds)
  // create + destroy many <img> elements that share the same URL. Without a
  // cache we'd re-analyse the same bytes every time. With one, the second
  // appearance skips the Swift roundtrip entirely.
  //
  // Map iteration order = insertion order in JS, so we can use it as a
  // simple LRU-ish bound: drop the oldest entry when we hit the cap.
  var DECISION_CACHE_MAX = 500;
  var decisionCache = new Map();

  function imgUrl(img) {
    return img.currentSrc || img.src || '';
  }

  function getCachedDecision(url) {
    return url ? decisionCache.get(url) : undefined;
  }

  function setCachedDecision(url, decision) {
    if (!url) return;
    if (decisionCache.has(url)) {
      decisionCache.delete(url);  // re-insert to refresh LRU position
    } else if (decisionCache.size >= DECISION_CACHE_MAX) {
      var firstKey = decisionCache.keys().next().value;
      decisionCache.delete(firstKey);
    }
    decisionCache.set(url, decision);
  }

  // ─── Blur application ───
  // We use inline `style.setProperty(..., 'important')` because:
  //   1. `!important` on inline style beats virtually any page-level CSS.
  //   2. Some sites (Google Images, social feeds) mutate the DOM aggressively;
  //      we track STATE_ATTR so any analyzed image (keep with per-person
  //      composite, or remove = safe) is never re-blurred when DOM mutates.
  function applyBlurTo(img) {
    if (!img || img.nodeType !== 1 || img.tagName !== 'IMG') return false;
    var state = img.getAttribute(STATE_ATTR);
    if (state === 'remove' || state === 'keep') return false;
    if (img.getAttribute(BLUR_MARKER) === '1') return false;
    try {
      img.style.setProperty('filter', 'blur(' + BLUR_RADIUS_PX + 'px)', 'important');
      img.setAttribute(BLUR_MARKER, '1');
      return true;
    } catch (e) {
      return false;
    }
  }

  function removeBlurFrom(img) {
    try {
      img.style.setProperty('filter', 'none', 'important');
      img.removeAttribute(BLUR_MARKER);
    } catch (e) {}
  }

  function scanAndBlur(root) {
    var imgs = (root || document).querySelectorAll('img');
    var n = 0;
    for (var i = 0; i < imgs.length; i++) {
      if (applyBlurTo(imgs[i])) n++;
    }
    return n;
  }

  // ─── Image → base64 (async) ───
  //
  // Strategy:
  //   1. Try `fetch(img.src, { mode: 'cors' })` first. This is served by the
  //      browser's HTTP cache (no double download), bypasses canvas taint, and
  //      works for any URL whose server returns Access-Control-Allow-Origin
  //      (Wikipedia, most CDNs, Google Images).
  //   2. Fallback to canvas.toDataURL for data: / blob: URLs, or same-origin
  //      images whose servers don't send CORS headers.
  function bytesToBase64(bytes) {
    // chunked to avoid `String.fromCharCode.apply` stack overflows on big arrays
    var binary = '';
    var chunk = 0x8000;
    for (var i = 0; i < bytes.length; i += chunk) {
      binary += String.fromCharCode.apply(null, bytes.subarray(i, i + chunk));
    }
    return btoa(binary);
  }

  // Per-image cached ArrayBuffer (the fetched CORS blob). Reused by the
  // compositing step so it doesn't have to fight cross-origin canvas taint.
  // WeakMap so entries get GC'd when the <img> element is removed from DOM.
  var imageBytesByImg = new WeakMap();

  function encodeImage(img) {
    return new Promise(function(resolve) {
      var src = img.currentSrc || img.src;
      if (!src) {
        metric('encode_no_src', { id: img.getAttribute(ID_ATTR) });
        resolve(null);
        return;
      }
      // data: / blob: URLs go straight to canvas
      if (/^(data|blob):/.test(src)) {
        resolve(encodeImageViaCanvas(img));
        return;
      }
      // Try CORS fetch (uses HTTP cache, no double network call)
      var aborted = false;
      var timeout = setTimeout(function() {
        aborted = true;
        metric('encode_fetch_timeout', { id: img.getAttribute(ID_ATTR), src: src.slice(0, 80) });
        resolve(encodeImageViaCanvas(img));
      }, 5000);
      fetch(src, { mode: 'cors', credentials: 'omit', cache: 'force-cache' })
        .then(function(r) {
          if (!r.ok) throw new Error('http_' + r.status);
          return r.arrayBuffer();
        })
        .then(function(buf) {
          if (aborted) return;
          clearTimeout(timeout);
          // Stash the CORS-fetched bytes so the compositing step can build a
          // non-tainted ImageBitmap from them when Swift returns persons-to-blur.
          imageBytesByImg.set(img, buf);
          resolve(bytesToBase64(new Uint8Array(buf)));
        })
        .catch(function(e) {
          if (aborted) return;
          clearTimeout(timeout);
          metric('encode_fetch_failed', {
            id: img.getAttribute(ID_ATTR),
            src: src.slice(0, 80),
            err: ('' + e).slice(0, 120)
          });
          resolve(encodeImageViaCanvas(img));
        });
    });
  }

  function encodeImageViaCanvas(img) {
    try {
      var w = img.naturalWidth || img.width;
      var h = img.naturalHeight || img.height;
      if (!w || !h) return null;
      var scale = Math.min(1, MAX_DIM / Math.max(w, h));
      var cw = Math.max(1, Math.round(w * scale));
      var ch = Math.max(1, Math.round(h * scale));
      var canvas = document.createElement('canvas');
      canvas.width = cw;
      canvas.height = ch;
      var ctx = canvas.getContext('2d');
      if (!ctx) return null;
      ctx.drawImage(img, 0, 0, cw, ch);
      var dataUrl = canvas.toDataURL('image/jpeg', 0.85);
      var commaIdx = dataUrl.indexOf(',');
      if (commaIdx < 0) return null;
      return dataUrl.slice(commaIdx + 1);
    } catch (e) {
      metric('encode_canvas_failed', { msg: ('' + e).slice(0, 120) });
      return null;
    }
  }

  // ─── Analysis queue (concurrency 1) ───
  var queue = [];
  var analyzing = false;
  function enqueueAnalyze(img) {
    if (!img || img.tagName !== 'IMG') return;
    if (img.hasAttribute(ID_ATTR)) return;  // already queued/analyzed
    var w = img.naturalWidth || img.width;
    var h = img.naturalHeight || img.height;
    if (w < MIN_DIM || h < MIN_DIM) return;  // skip tiny icons
    if (!img.complete || w === 0 || h === 0) {
      img.addEventListener('load', function() { enqueueAnalyze(img); }, { once: true });
      return;
    }
    // URL cache fast-path: same bytes were classified before → skip Swift.
    var url = imgUrl(img);
    var cached = getCachedDecision(url);
    if (cached) {
      var id = nextId++;
      img.setAttribute(ID_ATTR, String(id));
      img.setAttribute(STATE_ATTR, cached);
      if (cached === 'remove') removeBlurFrom(img);
      metric('analyze_cache_hit', { id: id, decision: cached });
      return;
    }
    var id = nextId++;
    img.setAttribute(ID_ATTR, String(id));
    img.setAttribute(STATE_ATTR, 'pending');
    queue.push({ id: id, img: img, url: url });
    drain();
  }

  function drain() {
    if (analyzing) return;
    var job = queue.shift();
    if (!job) return;
    analyzing = true;
    encodeImage(job.img).then(function(b64) {
      if (!b64) {
        // could not encode (broken img, opaque server) — keep default blur
        job.img.setAttribute(STATE_ATTR, 'keep');
        analyzing = false;
        drain();
        return;
      }
      metric('analyze_send', {
        id: job.id,
        w: job.img.naturalWidth,
        h: job.img.naturalHeight,
        bytes: b64.length
      });
      send('analyzeImage', job.id + '|' + b64);
      // Swift will call window.__basarunaaApply(id, decision) when done.
      // drain() resumes inside __basarunaaApply.
    }).catch(function(e) {
      metric('encode_unexpected_error', { msg: ('' + e).slice(0, 120) });
      job.img.setAttribute(STATE_ATTR, 'keep');
      analyzing = false;
      drain();
    });
  }

  function findById(id) {
    return document.querySelector('[' + ID_ATTR + '="' + id + '"]');
  }

  // ─── Per-person blur compositing (port du POC macOS) ───
  //
  // Stratégie choisie (voir aussi le commit message) : on reproduit le
  // POC `private/extensions/basarunaa/src/content.js#applyBlur` :
  //   1. Dessiner l'image originale dans un canvas
  //   2. Pré-calculer une version floutée edge-clampée (`_createEdgeClampedBlur`)
  //   3. Pour chaque personne à flouter, copier la zone floutée masquée par
  //      le body polygon (depuis les keypoints COCO) avec bords adoucis
  //      (FEATHER_EXPAND + FEATHER_BLUR) → `_drawFeatheredBlur`
  //   4. Remplacer le rendu de l'<img> via `style.content = url(<dataURL>)`
  //      — l'attribut `src` reste intact (pas de re-fetch, pas de mutation
  //      observer en boucle).
  //
  // Trade-off vs DOM overlays : ~50-100 ms compute canvas par image en plus
  // du ML, mais qualité polygon body-shaped + bords adoucis. Si la perf
  // devient un problème (Reels/scroll long), on pourra passer à des overlays
  // CSS rectangulaires en V2.

  var KP_CONFIDENCE = 0.3;
  var BODY_WIDTH_FACTOR = 0.55;
  var HAND_EXTEND = 0.3;
  var FOOT_EXTEND = 0.08;
  var EDGE_SNAP_THRESHOLD = 0.05;
  var FEATHER_EXPAND = 20;
  var FEATHER_BLUR = 10;
  var FEATHER_PAD = FEATHER_EXPAND + FEATHER_BLUR + 5;
  var REGION_SCALE = {
    head: 0.8, shoulder: 1.0, elbow: 0.7, wrist: 0.6,
    hip: 1.1, knee: 0.8, ankle: 0.7,
  };

  function getRegionScale(idx) {
    if (idx <= 4) return REGION_SCALE.head;
    if (idx <= 6) return REGION_SCALE.shoulder;
    if (idx <= 8) return REGION_SCALE.elbow;
    if (idx <= 10) return REGION_SCALE.wrist;
    if (idx <= 12) return REGION_SCALE.hip;
    if (idx <= 14) return REGION_SCALE.knee;
    return REGION_SCALE.ankle;
  }

  // keypoints: [[x, y, conf], ...] (17 COCO) | bbox: [x1, y1, x2, y2]
  function buildBodyPolygon(keypoints, bbox, imgW, imgH) {
    var bx1 = bbox[0], by1 = bbox[1], bx2 = bbox[2], by2 = bbox[3];
    var bw = bx2 - bx1;
    var bh = by2 - by1;

    var fallback = function() {
      return {
        points: [
          { x: bx1, y: by1 }, { x: bx2, y: by1 },
          { x: bx2, y: by2 }, { x: bx1, y: by2 },
        ],
        isBodyShaped: false,
      };
    };

    if (!keypoints || keypoints.length === 0) return fallback();
    var confident = [];
    for (var i = 0; i < keypoints.length; i++) {
      if (keypoints[i][2] >= KP_CONFIDENCE) confident.push(i);
    }
    if (confident.length < 4) return fallback();

    var lSh = keypoints[5], rSh = keypoints[6];
    var halfWidth;
    if (lSh && rSh && lSh[2] >= KP_CONFIDENCE && rSh[2] >= KP_CONFIDENCE) {
      halfWidth = Math.abs(rSh[0] - lSh[0]) * BODY_WIDTH_FACTOR;
    } else {
      halfWidth = bw * 0.25;
    }
    halfWidth = Math.max(halfWidth, bw * 0.2);

    var widened = [];
    for (var c = 0; c < confident.length; c++) {
      var idx = confident[c];
      var k = keypoints[idx];
      var w = halfWidth * getRegionScale(idx);
      widened.push({ x: k[0] - w, y: k[1] });
      widened.push({ x: k[0] + w, y: k[1] });
    }

    // Head padding
    var headIdx = [0, 1, 2, 3, 4].filter(function(i) {
      return keypoints[i] && keypoints[i][2] >= KP_CONFIDENCE;
    });
    if (headIdx.length > 0) {
      var topY = Infinity;
      var headCx = 0;
      for (var hi = 0; hi < headIdx.length; hi++) {
        var hkp = keypoints[headIdx[hi]];
        if (hkp[1] < topY) topY = hkp[1];
        headCx += hkp[0];
      }
      headCx /= headIdx.length;
      var headPadY = Math.max(halfWidth * 0.6, bh * 0.08);
      var headPadX = Math.max(halfWidth * 0.9, bw * 0.25);
      widened.push({ x: headCx - headPadX, y: topY - headPadY });
      widened.push({ x: headCx + headPadX, y: topY - headPadY });
    }

    extendHand(keypoints, 7, 9, halfWidth, widened);
    extendHand(keypoints, 8, 10, halfWidth, widened);

    var footExtend = bh * FOOT_EXTEND;
    [15, 16].forEach(function(aIdx) {
      var a = keypoints[aIdx];
      if (!a || a[2] < KP_CONFIDENCE) return;
      var wA = halfWidth * REGION_SCALE.ankle;
      widened.push({ x: a[0] - wA, y: a[1] + footExtend });
      widened.push({ x: a[0] + wA, y: a[1] + footExtend });
    });

    var hull = convexHull(widened);
    var polyMinX = Infinity, polyMaxX = -Infinity;
    var polyMinY = Infinity, polyMaxY = -Infinity;
    for (var h2 = 0; h2 < hull.length; h2++) {
      var p = hull[h2];
      if (p.x < polyMinX) polyMinX = p.x;
      if (p.x > polyMaxX) polyMaxX = p.x;
      if (p.y < polyMinY) polyMinY = p.y;
      if (p.y > polyMaxY) polyMaxY = p.y;
    }
    var polyCx = (polyMinX + polyMaxX) / 2;
    var polyCy = (polyMinY + polyMaxY) / 2;
    var bboxCx = (bx1 + bx2) / 2;
    var bboxCy = (by1 + by2) / 2;
    var sx = bw / ((polyMaxX - polyMinX) || 1);
    var sy = bh / ((polyMaxY - polyMinY) || 1);
    var scaled = hull.map(function(p) {
      return {
        x: bboxCx + (p.x - polyCx) * sx,
        y: bboxCy + (p.y - polyCy) * sy,
      };
    });

    var snapped = snapToEdges(scaled, bbox, imgW, imgH, keypoints);
    return { points: snapped, isBodyShaped: true };
  }

  function extendHand(kps, elbowIdx, wristIdx, halfWidth, out) {
    var elbow = kps[elbowIdx];
    var wrist = kps[wristIdx];
    if (!elbow || !wrist) return;
    if (elbow[2] < KP_CONFIDENCE || wrist[2] < KP_CONFIDENCE) return;
    var dx = wrist[0] - elbow[0];
    var dy = wrist[1] - elbow[1];
    var hx = wrist[0] + dx * HAND_EXTEND;
    var hy = wrist[1] + dy * HAND_EXTEND;
    var w = halfWidth * 0.6;
    out.push({ x: hx - w, y: hy });
    out.push({ x: hx + w, y: hy });
  }

  function snapToEdges(points, bbox, imgW, imgH, keypoints) {
    var bx1 = bbox[0], by1 = bbox[1], bx2 = bbox[2], by2 = bbox[3];
    var hasAnkles = keypoints &&
      [15, 16].some(function(i) { return keypoints[i] && keypoints[i][2] >= KP_CONFIDENCE; });
    var hasHead = keypoints &&
      [0, 1, 2].some(function(i) { return keypoints[i] && keypoints[i][2] >= KP_CONFIDENCE; });
    var snapBottom = !hasAnkles && by2 / imgH > (1 - EDGE_SNAP_THRESHOLD);
    var snapTop = !hasHead && by1 / imgH < EDGE_SNAP_THRESHOLD;
    var snapLeft = bx1 / imgW < EDGE_SNAP_THRESHOLD;
    var snapRight = bx2 / imgW > (1 - EDGE_SNAP_THRESHOLD);
    if (!snapBottom && !snapTop && !snapLeft && !snapRight) return points;

    var minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
    for (var i = 0; i < points.length; i++) {
      if (points[i].x < minX) minX = points[i].x;
      if (points[i].x > maxX) maxX = points[i].x;
      if (points[i].y < minY) minY = points[i].y;
      if (points[i].y > maxY) maxY = points[i].y;
    }
    var xRange = maxX - minX || 1;
    var yRange = maxY - minY || 1;
    var nearFrac = 0.15;
    return points.map(function(p) {
      var x = p.x, y = p.y;
      if (snapBottom && y > maxY - yRange * nearFrac) y = imgH;
      if (snapTop && y < minY + yRange * nearFrac) y = 0;
      if (snapLeft && x < minX + xRange * nearFrac) x = 0;
      if (snapRight && x > maxX - xRange * nearFrac) x = imgW;
      return { x: x, y: y };
    });
  }

  function convexHull(points) {
    if (points.length < 3) return points;
    var sorted = points.slice().sort(function(a, b) { return a.x - b.x || a.y - b.y; });
    var n = sorted.length;
    var cross = function(o, a, b) {
      return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
    };
    var lower = [];
    for (var i = 0; i < n; i++) {
      while (lower.length >= 2 && cross(lower[lower.length - 2], lower[lower.length - 1], sorted[i]) <= 0) {
        lower.pop();
      }
      lower.push(sorted[i]);
    }
    var upper = [];
    for (var i2 = n - 1; i2 >= 0; i2--) {
      while (upper.length >= 2 && cross(upper[upper.length - 2], upper[upper.length - 1], sorted[i2]) <= 0) {
        upper.pop();
      }
      upper.push(sorted[i2]);
    }
    lower.pop();
    upper.pop();
    return lower.concat(upper);
  }

  // Diagnostic: log canvas filter support once, on first call.
  var canvasFilterChecked = false;
  function checkCanvasFilter() {
    if (canvasFilterChecked) return;
    canvasFilterChecked = true;
    try {
      var c = document.createElement('canvas');
      c.width = 4; c.height = 4;
      var cx = c.getContext('2d');
      cx.filter = 'blur(5px)';
      metric('canvas_filter_check', { set: 'blur(5px)', got: '' + cx.filter });
    } catch (e) {
      metric('canvas_filter_check', { err: '' + e });
    }
  }

  // Downsample-upsample blur — works around iOS WKWebView's silent no-op on
  // `ctx.filter = 'blur(...)'`. We draw the source into a tiny canvas (factor
  // ≈ blur radius) then back into a full-size canvas with bilinear filtering
  // enabled. The interpolation produces a Gaussian-ish blur that visually
  // matches what the POC achieves with `filter: blur(Npx)`.
  function createEdgeClampedBlur(img, w, h, blur) {
    checkCanvasFilter();
    // Two passes give a smoother (more Gaussian-like) result than one.
    var factor = Math.max(8, Math.round(blur / 2));
    var smallW = Math.max(1, Math.floor(w / factor));
    var smallH = Math.max(1, Math.floor(h / factor));
    var passes = 2;

    var src = img;
    var srcW = w, srcH = h;
    for (var p = 0; p < passes; p++) {
      var small = document.createElement('canvas');
      small.width = smallW;
      small.height = smallH;
      var sCtx = small.getContext('2d');
      sCtx.imageSmoothingEnabled = true;
      sCtx.imageSmoothingQuality = 'high';
      sCtx.drawImage(src, 0, 0, srcW, srcH, 0, 0, smallW, smallH);

      var up = document.createElement('canvas');
      up.width = w;
      up.height = h;
      var uCtx = up.getContext('2d');
      uCtx.imageSmoothingEnabled = true;
      uCtx.imageSmoothingQuality = 'high';
      uCtx.drawImage(small, 0, 0, smallW, smallH, 0, 0, w, h);

      src = up;
      srcW = w; srcH = h;
    }
    return src;
  }

  function drawFeatheredBlur(ctx, blurredCanvas, person, w, h, showDebug) {
    var poly = buildBodyPolygon(person.keypoints, person.bbox, w, h);
    var tw = w + 2 * FEATHER_PAD;
    var th = h + 2 * FEATHER_PAD;
    var maskCanvas = document.createElement('canvas');
    maskCanvas.width = tw;
    maskCanvas.height = th;
    var mCtx = maskCanvas.getContext('2d');
    mCtx.fillStyle = '#fff';
    mCtx.beginPath();

    if (poly.isBodyShaped) {
      var cx = 0, cy = 0;
      for (var i = 0; i < poly.points.length; i++) {
        cx += poly.points[i].x; cy += poly.points[i].y;
      }
      cx /= poly.points.length; cy /= poly.points.length;
      for (var i2 = 0; i2 < poly.points.length; i2++) {
        var dx = poly.points[i2].x - cx;
        var dy = poly.points[i2].y - cy;
        var dist = Math.sqrt(dx * dx + dy * dy) || 1;
        var ex = poly.points[i2].x + (dx / dist) * FEATHER_EXPAND + FEATHER_PAD;
        var ey = poly.points[i2].y + (dy / dist) * FEATHER_EXPAND + FEATHER_PAD;
        if (i2 === 0) mCtx.moveTo(ex, ey);
        else mCtx.lineTo(ex, ey);
      }
      mCtx.closePath();
    } else {
      var b = person.bbox;
      var x1 = b[0], y1 = b[1], x2 = b[2], y2 = b[3];
      var snapX = w * 0.10, snapY = h * 0.10;
      if (x1 < snapX) x1 = -FEATHER_PAD; else x1 -= FEATHER_EXPAND;
      if (y1 < snapY) y1 = -FEATHER_PAD; else y1 -= FEATHER_EXPAND;
      if (w - x2 < snapX) x2 = w + FEATHER_PAD; else x2 += FEATHER_EXPAND;
      if (h - y2 < snapY) y2 = h + FEATHER_PAD; else y2 += FEATHER_EXPAND;
      mCtx.rect(x1 + FEATHER_PAD, y1 + FEATHER_PAD, x2 - x1, y2 - y1);
    }
    mCtx.fill();

    // Same downsample-upsample trick on the mask (ctx.filter blur is silent
    // no-op on iOS WKWebView). Gives feathered edges around the polygon.
    var maskFactor = Math.max(4, FEATHER_BLUR);
    var maskSmall = document.createElement('canvas');
    maskSmall.width = Math.max(1, Math.floor(tw / maskFactor));
    maskSmall.height = Math.max(1, Math.floor(th / maskFactor));
    var msCtx = maskSmall.getContext('2d');
    msCtx.imageSmoothingEnabled = true;
    msCtx.imageSmoothingQuality = 'high';
    msCtx.drawImage(maskCanvas, 0, 0, tw, th, 0, 0, maskSmall.width, maskSmall.height);

    var blurredMask = document.createElement('canvas');
    blurredMask.width = tw;
    blurredMask.height = th;
    var bmCtx = blurredMask.getContext('2d');
    bmCtx.imageSmoothingEnabled = true;
    bmCtx.imageSmoothingQuality = 'high';
    bmCtx.drawImage(maskSmall, 0, 0, maskSmall.width, maskSmall.height, 0, 0, tw, th);

    var tempCanvas = document.createElement('canvas');
    tempCanvas.width = w;
    tempCanvas.height = h;
    var tCtx = tempCanvas.getContext('2d');
    tCtx.drawImage(blurredCanvas, 0, 0);
    tCtx.globalCompositeOperation = 'destination-in';
    tCtx.drawImage(blurredMask, FEATHER_PAD, FEATHER_PAD, w, h, 0, 0, w, h);
    ctx.drawImage(tempCanvas, 0, 0);

    // Debug polygons (port direct de _drawFeatheredBlur POC content.js).
    // 4 contours pointillés : polygon YOLO original, début du dégradé,
    // bord du masque blanc, fin du dégradé. Visibles dans les modes
    // debug-mode = "boxes" et "debug".
    if (showDebug) {
      ctx.save();
      ctx.lineWidth = 2;
      var drawExpanded = function(amount) {
        ctx.beginPath();
        if (poly.isBodyShaped) {
          var pcx = 0, pcy = 0;
          for (var i = 0; i < poly.points.length; i++) {
            pcx += poly.points[i].x; pcy += poly.points[i].y;
          }
          pcx /= poly.points.length; pcy /= poly.points.length;
          for (var j = 0; j < poly.points.length; j++) {
            var dxe = poly.points[j].x - pcx;
            var dye = poly.points[j].y - pcy;
            var dist2 = Math.sqrt(dxe * dxe + dye * dye) || 1;
            var ex2 = poly.points[j].x + (dxe / dist2) * amount;
            var ey2 = poly.points[j].y + (dye / dist2) * amount;
            if (j === 0) ctx.moveTo(ex2, ey2);
            else ctx.lineTo(ex2, ey2);
          }
          ctx.closePath();
        } else {
          var bb = person.bbox;
          var rx1 = bb[0], ry1 = bb[1], rx2 = bb[2], ry2 = bb[3];
          ctx.rect(rx1 - amount, ry1 - amount, (rx2 - rx1) + amount * 2, (ry2 - ry1) + amount * 2);
        }
        ctx.stroke();
      };
      // Cyan : polygon original (YOLO body shape)
      ctx.strokeStyle = '#00FFFF';
      ctx.setLineDash([4, 4]);
      drawExpanded(0);
      // Vert : début du dégradé (~expand - blur = 10px)
      ctx.strokeStyle = '#00FF00';
      ctx.setLineDash([3, 3]);
      drawExpanded(FEATHER_EXPAND - FEATHER_BLUR);
      // Orange : bord du masque blanc (expand = 20px)
      ctx.strokeStyle = '#FFA500';
      ctx.setLineDash([6, 3]);
      drawExpanded(FEATHER_EXPAND);
      // Rouge : fin du dégradé (~expand + blur = 30px)
      ctx.strokeStyle = '#FF0000';
      ctx.setLineDash([2, 4]);
      drawExpanded(FEATHER_EXPAND + FEATHER_BLUR);
      ctx.setLineDash([]);
      ctx.restore();
    }
  }

  // Compositing source — prefer the CORS-fetched ArrayBuffer (no canvas taint),
  // fallback to drawing the <img> directly (works only for same-origin or
  // images with crossorigin="anonymous").
  function getCompositingSource(img) {
    return new Promise(function(resolve) {
      var buf = imageBytesByImg.get(img);
      if (buf) {
        try {
          var blob = new Blob([buf]);
          createImageBitmap(blob).then(function(bm) {
            resolve(bm);
          }).catch(function() { resolve(img); });
          return;
        } catch (e) {
          // Fall through to direct img source.
        }
      }
      resolve(img);
    });
  }

  function compositePerPersonBlur(img, persons) {
    if (!persons || persons.length === 0) return Promise.resolve(false);
    var id = img.getAttribute(ID_ATTR);
    // Convert keypoints from [x,y,conf] arrays to {x,y,confidence} objects
    // so `buildBodyPolygon` can read kp.confidence. Without this normalise,
    // the polygon path silently falls back to a bbox rectangle (the blur
    // looks rectangular instead of following the silhouette).
    var normalised = normalisePersons(persons);
    metric('composite_start', {
      id: id,
      naturalW: img.naturalWidth, naturalH: img.naturalHeight,
      persons: normalised.length,
    });
    return getCompositingSource(img).then(function(source) {
      var sourceType = (source && source.constructor) ? source.constructor.name : 'unknown';
      var w = source.naturalWidth != null ? source.naturalWidth : source.width;
      var h = source.naturalHeight != null ? source.naturalHeight : source.height;
      metric('composite_source', { id: id, type: sourceType, w: w, h: h });
      if (!w || !h) {
        metric('composite_nodim', { id: id });
        return false;
      }
      try {
        var canvas = document.createElement('canvas');
        canvas.width = w;
        canvas.height = h;
        var ctx = canvas.getContext('2d');
        ctx.drawImage(source, 0, 0, w, h);
        var blur = Math.max(25, Math.round(Math.max(w, h) * 0.04));
        var blurredCanvas = createEdgeClampedBlur(source, w, h, blur);
        for (var pi = 0; pi < normalised.length; pi++) {
          drawFeatheredBlur(ctx, blurredCanvas, normalised[pi], w, h);
        }
        var srcLower = (img.currentSrc || img.src || '').toLowerCase();
        var needsAlpha = /\.png(\?|$)/.test(srcLower) || /\.webp(\?|$)/.test(srcLower)
          || srcLower.indexOf('data:image/png') === 0;
        var mime = needsAlpha ? 'image/png' : 'image/jpeg';
        var quality = needsAlpha ? undefined : 0.85;
        // Use Blob + createObjectURL (vs toDataURL). Blob URLs are short
        // strings backed by binary in memory — way more reliable than 100+ KB
        // data: URLs on iOS WebKit, where setting img.src to a huge data URL
        // sometimes doesn't trigger a repaint.
        return new Promise(function(resolveBlob) {
          canvas.toBlob(function(blob) { resolveBlob(blob); }, mime, quality);
        }).then(function(blob) {
          if (!blob) {
            metric('composite_no_blob', { id: id });
            return false;
          }
          metric('composite_encoded', { id: id, bytes: blob.size });
          // Strip srcset / <picture><source> so the browser actually uses
          // our new src instead of re-picking a responsive variant.
          if (img.hasAttribute('srcset')) img.removeAttribute('srcset');
          if (img.hasAttribute('sizes')) img.removeAttribute('sizes');
          var pic = img.parentNode;
          if (pic && pic.tagName === 'PICTURE') {
            var sources = pic.querySelectorAll('source');
            for (var si = 0; si < sources.length; si++) {
              sources[si].removeAttribute('srcset');
            }
          }
          if (img.dataset.basarunaaBlobUrl) {
            try { URL.revokeObjectURL(img.dataset.basarunaaBlobUrl); } catch (_) {}
          }
          var blobUrl = URL.createObjectURL(blob);
          img.dataset.basarunaaBlobUrl = blobUrl;
          // Attach diagnostic load/error listeners BEFORE setting src so we
          // know if the browser actually accepts the blob URL.
          img.addEventListener('load', function _onload() {
            img.removeEventListener('load', _onload);
            metric('composite_load_ok', { id: id, w: img.naturalWidth, h: img.naturalHeight });
          });
          img.addEventListener('error', function _onerror(e) {
            img.removeEventListener('error', _onerror);
            metric('composite_load_err', { id: id, msg: '' + (e && e.message || e) });
          });
          // iOS WebKit caches the rendered image after the first load and
          // doesn't always re-render when `img.src` is replaced (especially
          // on ImageDocument pages — direct image URLs like /foo.avif).
          // Workaround: replace the <img> element with a fresh clone that
          // points to our blob URL. This guarantees a new render path.
          var fresh = img.cloneNode(false);
          fresh.removeAttribute('srcset');
          fresh.removeAttribute('sizes');
          fresh.removeAttribute('crossorigin');
          fresh.removeAttribute(BLUR_MARKER);
          fresh.style.removeProperty('filter');
          fresh.dataset.basarunaaBlobUrl = blobUrl;
          fresh.src = blobUrl;
          // Preserve our state so MutationObserver / cache treats it as done.
          fresh.setAttribute(ID_ATTR, img.getAttribute(ID_ATTR) || '');
          fresh.setAttribute(STATE_ATTR, 'keep');
          if (img.parentNode) {
            img.parentNode.replaceChild(fresh, img);
            // Stop observing the old img (it's detached now).
            try { if (intersectionObserver) intersectionObserver.unobserve(img); } catch (_) {}
            metric('composite_applied', { id: id, mode: 'replace', blobUrl: blobUrl.slice(0, 50) });
          } else {
            metric('composite_no_parent', { id: id });
          }
          return true;
        });
      } catch (e) {
        metric('composite_failed', { id: id, msg: ('' + e).slice(0, 120) });
        return false;
      }
    }).catch(function(e) {
      metric('composite_promise_rejected', { id: id, msg: ('' + e).slice(0, 120) });
      return false;
    });
  }

  // ─── Debug overlay — port fidèle du visualizer macOS POC ───
  // (`private/extensions/basarunaa/src/debug/visualizer.js`)
  //
  // Mêmes palettes (5 nuances rose/magenta pour femmes, 5 nuances bleu pour
  // hommes — une nuance distincte par personne via compteur), skeleton COCO,
  // polygon mask (port de `src/utils/body_polygon.js`), keypoints colorés.
  //
  // Coordonnées : on dessine sur un canvas qui *devient* la nouvelle image,
  // donc on travaille en coords pixel originales (le `sx`/`sy` du POC = 1).
  var FEMALE_COLORS = [
    '#FF69B4',  // hot pink
    '#FF1493',  // deep pink
    '#DB7093',  // pale violet red
    '#C71585',  // medium violet red
    '#FF007F',  // rose
  ];
  var MALE_COLORS = [
    '#4169E1',  // royal blue
    '#1E90FF',  // dodger blue
    '#00BFFF',  // deep sky blue
    '#4682B4',  // steel blue
    '#0047AB',  // cobalt
  ];

  var COCO_SKELETON = [
    [0, 1], [0, 2], [1, 3], [2, 4],   // head
    [5, 6],                           // shoulders
    [5, 7], [7, 9],                   // left arm
    [6, 8], [8, 10],                  // right arm
    [5, 11], [6, 12],                 // torso
    [11, 12],                         // hips
    [11, 13], [13, 15],               // left leg
    [12, 14], [14, 16],               // right leg
  ];
  var LIMB_COLORS = [
    '#FF6B6B', '#FF6B6B', '#FF6B6B', '#FF6B6B',   // head: red
    '#FFD93D',                                     // shoulders: yellow
    '#6BCB77', '#6BCB77',                          // left arm: green
    '#4D96FF', '#4D96FF',                          // right arm: blue
    '#FFD93D', '#FFD93D',                          // torso: yellow
    '#FFD93D',                                     // hips: yellow
    '#6BCB77', '#6BCB77',                          // left leg: green
    '#4D96FF', '#4D96FF',                          // right leg: blue
  ];
  var KP_COLORS = [
    '#FF0000', '#00FF00', '#0000FF', '#FFFF00', '#FF00FF',
    '#00FFFF', '#FFA500', '#FF69B4', '#7FFF00', '#DC143C',
    '#00CED1', '#FFD700', '#8A2BE2', '#32CD32', '#FF4500',
    '#1E90FF', '#FF1493',
  ];
  var KP_CONF = 0.3;

  // ─── Body polygon (port de utils/body_polygon.js) ───
  var POLY_KP_CONFIDENCE = 0.3;
  var POLY_BODY_WIDTH_FACTOR = 0.55;
  var POLY_HAND_EXTEND = 0.3;
  var POLY_FOOT_EXTEND = 0.08;
  var POLY_EDGE_SNAP = 0.05;
  var POLY_REGION_SCALE = [
    0.8, 0.8, 0.8, 0.8, 0.8,    // head 0-4
    1.0, 1.0,                   // shoulders 5-6
    0.7, 0.7,                   // elbows 7-8
    0.6, 0.6,                   // wrists 9-10
    1.1, 1.1,                   // hips 11-12
    0.8, 0.8,                   // knees 13-14
    0.7, 0.7,                   // ankles 15-16
  ];

  function _extendHand(kps, elbowIdx, wristIdx, halfWidth, out) {
    var elbow = kps[elbowIdx], wrist = kps[wristIdx];
    if (!elbow || !wrist) return;
    if (elbow.confidence < POLY_KP_CONFIDENCE || wrist.confidence < POLY_KP_CONFIDENCE) return;
    var dx = wrist.x - elbow.x;
    var dy = wrist.y - elbow.y;
    var hx = wrist.x + dx * POLY_HAND_EXTEND;
    var hy = wrist.y + dy * POLY_HAND_EXTEND;
    var w = halfWidth * 0.6;
    out.push({ x: hx - w, y: hy });
    out.push({ x: hx + w, y: hy });
  }

  function _snapToEdges(points, bbox, imgW, imgH, kps) {
    var bx1 = bbox[0], by1 = bbox[1], bx2 = bbox[2], by2 = bbox[3];
    var hasAnkles = kps && [15, 16].some(function(i) {
      return kps[i] && kps[i].confidence >= POLY_KP_CONFIDENCE;
    });
    var hasHead = kps && [0, 1, 2].some(function(i) {
      return kps[i] && kps[i].confidence >= POLY_KP_CONFIDENCE;
    });
    var snapBottom = !hasAnkles && by2 / imgH > (1 - POLY_EDGE_SNAP);
    var snapTop = !hasHead && by1 / imgH < POLY_EDGE_SNAP;
    var snapLeft = bx1 / imgW < POLY_EDGE_SNAP;
    var snapRight = bx2 / imgW > (1 - POLY_EDGE_SNAP);
    if (!snapBottom && !snapTop && !snapLeft && !snapRight) return points;
    var minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
    for (var i = 0; i < points.length; i++) {
      if (points[i].x < minX) minX = points[i].x;
      if (points[i].x > maxX) maxX = points[i].x;
      if (points[i].y < minY) minY = points[i].y;
      if (points[i].y > maxY) maxY = points[i].y;
    }
    var xR = (maxX - minX) || 1;
    var yR = (maxY - minY) || 1;
    var near = 0.15;
    return points.map(function(p) {
      var x = p.x, y = p.y;
      if (snapBottom && y > maxY - yR * near) y = imgH;
      if (snapTop && y < minY + yR * near) y = 0;
      if (snapLeft && x < minX + xR * near) x = 0;
      if (snapRight && x > maxX - xR * near) x = imgW;
      return { x: x, y: y };
    });
  }

  function _bboxFallback(bbox) {
    return {
      points: [
        { x: bbox[0], y: bbox[1] },
        { x: bbox[2], y: bbox[1] },
        { x: bbox[2], y: bbox[3] },
        { x: bbox[0], y: bbox[3] },
      ],
      isBodyShaped: false,
    };
  }

  function _convexHull(points) {
    if (points.length < 3) return points;
    var sorted = points.slice().sort(function(a, b) { return a.x - b.x || a.y - b.y; });
    var n = sorted.length;
    var cross = function(o, a, b) {
      return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
    };
    var lower = [];
    for (var i = 0; i < n; i++) {
      while (lower.length >= 2 && cross(lower[lower.length - 2], lower[lower.length - 1], sorted[i]) <= 0) {
        lower.pop();
      }
      lower.push(sorted[i]);
    }
    var upper = [];
    for (var j = n - 1; j >= 0; j--) {
      while (upper.length >= 2 && cross(upper[upper.length - 2], upper[upper.length - 1], sorted[j]) <= 0) {
        upper.pop();
      }
      upper.push(sorted[j]);
    }
    lower.pop();
    upper.pop();
    return lower.concat(upper);
  }

  function buildBodyPolygon(kps, bbox, imgW, imgH) {
    var bx1 = bbox[0], by1 = bbox[1], bx2 = bbox[2], by2 = bbox[3];
    var bw = bx2 - bx1, bh = by2 - by1;
    if (!kps) return _bboxFallback(bbox);
    var confident = [];
    for (var i = 0; i < kps.length; i++) {
      if (kps[i] && kps[i].confidence >= POLY_KP_CONFIDENCE) {
        confident.push({ idx: i, k: kps[i] });
      }
    }
    if (confident.length < 4) return _bboxFallback(bbox);
    var lSh = kps[5], rSh = kps[6];
    var halfWidth;
    if (lSh && rSh && lSh.confidence >= POLY_KP_CONFIDENCE && rSh.confidence >= POLY_KP_CONFIDENCE) {
      halfWidth = Math.abs(rSh.x - lSh.x) * POLY_BODY_WIDTH_FACTOR;
    } else {
      halfWidth = bw * 0.25;
    }
    halfWidth = Math.max(halfWidth, bw * 0.2);
    var widened = [];
    for (var c = 0; c < confident.length; c++) {
      var entry = confident[c];
      var w = halfWidth * POLY_REGION_SCALE[entry.idx];
      widened.push({ x: entry.k.x - w, y: entry.k.y });
      widened.push({ x: entry.k.x + w, y: entry.k.y });
    }
    var headKps = [];
    for (var hi = 0; hi < 5; hi++) {
      if (kps[hi] && kps[hi].confidence >= POLY_KP_CONFIDENCE) headKps.push(hi);
    }
    if (headKps.length > 0) {
      var topY = Infinity, sumX = 0;
      for (var hh = 0; hh < headKps.length; hh++) {
        var hk = kps[headKps[hh]];
        if (hk.y < topY) topY = hk.y;
        sumX += hk.x;
      }
      var headCx = sumX / headKps.length;
      var headPadY = Math.max(halfWidth * 0.6, bh * 0.08);
      var headPadX = Math.max(halfWidth * 0.9, bw * 0.25);
      widened.push({ x: headCx - headPadX, y: topY - headPadY });
      widened.push({ x: headCx + headPadX, y: topY - headPadY });
    }
    _extendHand(kps, 7, 9, halfWidth, widened);
    _extendHand(kps, 8, 10, halfWidth, widened);
    var footExtend = bh * POLY_FOOT_EXTEND;
    var ankleIndices = [15, 16];
    for (var ai = 0; ai < ankleIndices.length; ai++) {
      var ankle = kps[ankleIndices[ai]];
      if (ankle && ankle.confidence >= POLY_KP_CONFIDENCE) {
        var wA = halfWidth * 0.7;
        widened.push({ x: ankle.x - wA, y: ankle.y + footExtend });
        widened.push({ x: ankle.x + wA, y: ankle.y + footExtend });
      }
    }
    var hull = _convexHull(widened);
    var polyMinX = Infinity, polyMaxX = -Infinity, polyMinY = Infinity, polyMaxY = -Infinity;
    for (var pi = 0; pi < hull.length; pi++) {
      if (hull[pi].x < polyMinX) polyMinX = hull[pi].x;
      if (hull[pi].x > polyMaxX) polyMaxX = hull[pi].x;
      if (hull[pi].y < polyMinY) polyMinY = hull[pi].y;
      if (hull[pi].y > polyMaxY) polyMaxY = hull[pi].y;
    }
    var polyCx = (polyMinX + polyMaxX) / 2;
    var polyCy = (polyMinY + polyMaxY) / 2;
    var bboxCx = (bx1 + bx2) / 2;
    var bboxCy = (by1 + by2) / 2;
    var sX = bw / ((polyMaxX - polyMinX) || 1);
    var sY = bh / ((polyMaxY - polyMinY) || 1);
    var scaled = hull.map(function(p) {
      return { x: bboxCx + (p.x - polyCx) * sX, y: bboxCy + (p.y - polyCy) * sY };
    });
    var snapped = _snapToEdges(scaled, bbox, imgW, imgH, kps);
    return { points: snapped, isBodyShaped: true };
  }

  function polygonToMask(points, imgW, imgH) {
    var data = new Uint8Array(imgW * imgH);
    if (points.length < 3) return { data: data, width: imgW, height: imgH };
    var minY = imgH, maxY = 0;
    for (var i = 0; i < points.length; i++) {
      if (points[i].y < minY) minY = points[i].y;
      if (points[i].y > maxY) maxY = points[i].y;
    }
    minY = Math.max(0, Math.floor(minY));
    maxY = Math.min(imgH - 1, Math.ceil(maxY));
    for (var y = minY; y <= maxY; y++) {
      var inter = [];
      for (var p = 0; p < points.length; p++) {
        var a = points[p];
        var b = points[(p + 1) % points.length];
        if ((a.y <= y && b.y > y) || (b.y <= y && a.y > y)) {
          inter.push(a.x + (y - a.y) / (b.y - a.y) * (b.x - a.x));
        }
      }
      inter.sort(function(u, v) { return u - v; });
      for (var k = 0; k < inter.length - 1; k += 2) {
        var x1 = Math.max(0, Math.floor(inter[k]));
        var x2 = Math.min(imgW - 1, Math.ceil(inter[k + 1]));
        for (var x = x1; x <= x2; x++) {
          data[y * imgW + x] = 1;
        }
      }
    }
    return { data: data, width: imgW, height: imgH };
  }

  // Normalise le payload Swift (keypoints en `[x, y, conf]`) en objets
  // `{x, y, confidence}` que les algos POC consomment.
  function normalisePersons(persons) {
    var out = [];
    for (var i = 0; i < persons.length; i++) {
      var p = persons[i];
      var kps = [];
      if (p.keypoints && p.keypoints.length) {
        for (var k = 0; k < p.keypoints.length; k++) {
          var raw = p.keypoints[k];
          if (raw && raw.length >= 3) {
            kps.push({ x: raw[0], y: raw[1], confidence: raw[2] });
          }
        }
      }
      out.push({
        bbox: p.bbox,
        faceBbox: p.faceBbox || null,
        keypoints: kps,
        bodyConfidence: typeof p.bodyConfidence === 'number' ? p.bodyConfidence : null,
        gender: p.gender || null,
        genderConfidence: typeof p.genderConfidence === 'number' ? p.genderConfidence : null,
        isSyntheticBody: !!p.isSyntheticBody,
        classifierUsed: typeof p.classifierUsed === 'string' ? p.classifierUsed : '',
        facePFemale: typeof p.facePFemale === 'number' ? p.facePFemale : null,
        facePMale: typeof p.facePMale === 'number' ? p.facePMale : null,
        bodyPFemale: typeof p.bodyPFemale === 'number' ? p.bodyPFemale : null,
        bodyPMale: typeof p.bodyPMale === 'number' ? p.bodyPMale : null,
        faceCropDataUrl: typeof p.faceCropDataUrl === 'string' ? p.faceCropDataUrl : null,
        bodyCropDataUrl: typeof p.bodyCropDataUrl === 'string' ? p.bodyCropDataUrl : null,
      });
    }
    return out;
  }

  // Dessine le mask polygone : fill 35% alpha de la couleur de la personne
  // + contour 1px sur les pixels d'arête (port direct de visualizer._drawMask).
  function drawMask(ctx, mask, hexColor) {
    var r = parseInt(hexColor.slice(1, 3), 16);
    var g = parseInt(hexColor.slice(3, 5), 16);
    var b = parseInt(hexColor.slice(5, 7), 16);
    var W = ctx.canvas.width, H = ctx.canvas.height;
    var mw = mask.width, mh = mask.height, d = mask.data;
    var tmp = document.createElement('canvas');
    tmp.width = W; tmp.height = H;
    var tCtx = tmp.getContext('2d');
    var imgData = tCtx.createImageData(W, H);
    for (var y = 0; y < H; y++) {
      var my = y < mh ? y : mh - 1;
      for (var x = 0; x < W; x++) {
        var mx = x < mw ? x : mw - 1;
        if (d[my * mw + mx] > 0) {
          var off = (y * W + x) * 4;
          imgData.data[off] = r;
          imgData.data[off + 1] = g;
          imgData.data[off + 2] = b;
          imgData.data[off + 3] = 255;
        }
      }
    }
    tCtx.putImageData(imgData, 0, 0);
    ctx.save();
    ctx.globalAlpha = 0.35;
    ctx.drawImage(tmp, 0, 0);
    ctx.restore();
    ctx.strokeStyle = hexColor;
    ctx.lineWidth = 2;
    ctx.beginPath();
    for (var ey = 1; ey < mh - 1; ey++) {
      for (var ex = 1; ex < mw - 1; ex++) {
        if (d[ey * mw + ex] === 0) continue;
        var isEdge = d[(ey - 1) * mw + ex] === 0 ||
                     d[(ey + 1) * mw + ex] === 0 ||
                     d[ey * mw + (ex - 1)] === 0 ||
                     d[ey * mw + (ex + 1)] === 0;
        if (isEdge) ctx.rect(ex, ey, 1, 1);
      }
    }
    ctx.stroke();
  }

  // Header timing en haut à gauche : `#<id> XXms` (parité POC visualizer).
  function drawDebugHeader(ctx, id, elapsedMs) {
    var label = '#' + (id || '?');
    if (typeof elapsedMs === 'number' && isFinite(elapsedMs)) {
      label += ' ' + elapsedMs.toFixed(0) + 'ms';
    }
    ctx.font = 'bold 13px monospace';
    var tw = ctx.measureText(label).width + 10;
    ctx.fillStyle = 'rgba(0, 0, 0, 0.75)';
    ctx.fillRect(0, 0, tw, 22);
    ctx.fillStyle = '#00FF00';
    ctx.fillText(label, 5, 16);
  }

  // Dessine le overlay (port direct de visualizer.draw, sx=sy=1).
  function drawDebugDetections(ctx, persons, imgW, imgH, debugMode) {
    var isLite = debugMode === 'boxes';
    var femaleIdx = 0;
    var maleIdx = 0;

    for (var pi = 0; pi < persons.length; pi++) {
      var person = persons[pi];
      var bb = person.bbox;
      if (!bb || bb.length !== 4) continue;
      var x1 = bb[0], y1 = bb[1], x2 = bb[2], y2 = bb[3];
      var dw = x2 - x1, dh = y2 - y1;

      var color;
      if (person.gender === 'female') {
        color = FEMALE_COLORS[femaleIdx % FEMALE_COLORS.length];
        femaleIdx++;
      } else {
        color = MALE_COLORS[maleIdx % MALE_COLORS.length];
        maleIdx++;
      }

      // Polygon mask (debug only) — recalculé à la volée depuis les keypoints.
      if (!isLite && person.keypoints && person.keypoints.length === 17) {
        try {
          var poly = buildBodyPolygon(person.keypoints, bb, imgW, imgH);
          if (poly.isBodyShaped) {
            var mask = polygonToMask(poly.points, imgW, imgH);
            drawMask(ctx, mask, color);
          }
        } catch (_) { /* non-fatal */ }
      }

      // Body bbox
      ctx.strokeStyle = color;
      ctx.lineWidth = isLite ? 2 : 3;
      ctx.strokeRect(x1, y1, dw, dh);

      if (!isLite) {
        // Face bbox (dashed, yellow)
        if (person.faceBbox && person.faceBbox.length === 4) {
          var fx1 = person.faceBbox[0], fy1 = person.faceBbox[1];
          var fx2 = person.faceBbox[2], fy2 = person.faceBbox[3];
          ctx.strokeStyle = '#FFD700';
          ctx.lineWidth = 2;
          ctx.setLineDash([4, 4]);
          ctx.strokeRect(fx1, fy1, fx2 - fx1, fy2 - fy1);
          ctx.setLineDash([]);
        }
        // Skeleton + keypoints
        if (person.keypoints && person.keypoints.length) {
          var kps = person.keypoints;
          var kpRadius = Math.max(1.5, Math.min(4, dw * 0.025));
          ctx.lineWidth = Math.max(1, Math.round(dw * 0.012));
          for (var si = 0; si < COCO_SKELETON.length; si++) {
            var a = COCO_SKELETON[si][0], b = COCO_SKELETON[si][1];
            if (kps[a] && kps[b] && kps[a].confidence > KP_CONF && kps[b].confidence > KP_CONF) {
              ctx.strokeStyle = LIMB_COLORS[si];
              ctx.beginPath();
              ctx.moveTo(kps[a].x, kps[a].y);
              ctx.lineTo(kps[b].x, kps[b].y);
              ctx.stroke();
            }
          }
          for (var ki = 0; ki < kps.length; ki++) {
            var kp = kps[ki];
            if (kp && kp.confidence > KP_CONF) {
              ctx.beginPath();
              ctx.arc(kp.x, kp.y, kpRadius, 0, Math.PI * 2);
              ctx.fillStyle = KP_COLORS[ki % KP_COLORS.length];
              ctx.fill();
              ctx.strokeStyle = '#000';
              ctx.lineWidth = 1;
              ctx.stroke();
            }
          }
        }
      }

      // Label (POC parity)
      var gShort = person.gender === 'female' ? 'F'
                 : person.gender === 'male'   ? 'M'
                 : '?';
      var classLabel = person.classifierUsed ? ' [' + person.classifierUsed + ']' : '';
      if (isLite) {
        // Boxes mode : "F XX%" + classifier label in brackets (macOS POC).
        var confTxt = person.genderConfidence != null
          ? (gShort + ' ' + Math.round(person.genderConfidence * 100) + '%' + classLabel)
          : gShort + classLabel;
        ctx.font = 'bold 13px monospace';
        var tw = ctx.measureText(confTxt).width + 6;
        var lh = 18;
        var ly = y1 >= lh ? y1 - lh : y1;
        ctx.fillStyle = color;
        ctx.fillRect(x1, ly, tw, lh);
        ctx.fillStyle = '#fff';
        ctx.fillText(confTxt, x1 + 3, ly + lh - 4);
      } else {
        // Debug complet : main + body conf + classifier label.
        var confStr = person.genderConfidence != null
          ? (Math.round(person.genderConfidence * 100) + '%')
          : '';
        var bodyStr = person.bodyConfidence != null
          ? ('body ' + Math.round(person.bodyConfidence * 100) + '%')
          : null;
        var mainLabel = gShort + ' ' + confStr + classLabel;
        var extra = bodyStr ? [bodyStr] : [];
        var lineH = 15;
        var totalH = (1 + extra.length) * lineH + 4;
        ctx.font = 'bold 13px monospace';
        var labelW = ctx.measureText(mainLabel).width;
        for (var ei = 0; ei < extra.length; ei++) {
          labelW = Math.max(labelW, ctx.measureText(extra[ei]).width);
        }
        labelW += 8;
        var lyD = y1 >= totalH ? y1 - totalH : y1;
        ctx.fillStyle = color;
        ctx.fillRect(x1, lyD, labelW, totalH);
        ctx.fillStyle = '#FFFFFF';
        ctx.fillText(mainLabel, x1 + 4, lyD + lineH - 2);
        ctx.fillStyle = 'rgba(255,255,255,0.7)';
        for (var el = 0; el < extra.length; el++) {
          ctx.fillText(extra[el], x1 + 4, lyD + (el + 2) * lineH - 2);
        }
      }
    }
  }

  // Decode a `data:image/png;base64,...` URL into an HTMLImageElement.
  // Wrapped in a Promise so we can await the decode before drawing.
  function decodeDataUrl(dataUrl) {
    return new Promise(function(resolve) {
      if (!dataUrl) { resolve(null); return; }
      var im = new Image();
      im.onload = function() { resolve(im); };
      im.onerror = function() { resolve(null); };
      im.src = dataUrl;
    });
  }

  // Draw the bottom black strip — face + body side by side per person, with
  // labels in gender colours like the macOS POC `_drawCropStrip` :
  //
  //   [face 96×96][body 100×133]    ← 4px gap between, yellow border face
  //   [male 95%]  [male 91%]        ← yellow under face, gender colour under body
  //   M 95% [insightface (partial body)]   ← gender colour, classifier suffix
  function drawCropStripAndEncode(canvas, ctx, persons, imgW, imgH, stripH, sourceImg) {
    ctx.fillStyle = '#000';
    ctx.fillRect(0, imgH, imgW, stripH);

    // Decode all crops in parallel.
    var jobs = [];
    for (var i = 0; i < persons.length; i++) {
      jobs.push(decodeDataUrl(persons[i].faceCropDataUrl));
      jobs.push(decodeDataUrl(persons[i].bodyCropDataUrl));
    }
    return Promise.all(jobs).then(function(images) {
      var FACE_DISPLAY = 96;
      var BODY_DISPLAY_W = 100;
      var BODY_DISPLAY_H = 133;
      var INNER_GAP = 4;  // face-body gap inside a column
      var COL_W = FACE_DISPLAY + INNER_GAP + BODY_DISPLAY_W;   // 200
      var COL_GAP = 12;
      var TOP_PAD = 6;
      var x = 6;
      var stripTop = imgH;
      // Female / male palette indices reset per strip — match drawDebugDetections.
      var femaleIdx = 0;
      var maleIdx = 0;

      for (var pi = 0; pi < persons.length; pi++) {
        var person = persons[pi];
        var face = images[pi * 2];
        var body = images[pi * 2 + 1];

        // Person colour from the same palettes as the bbox overlay.
        var personColor;
        if (person.gender === 'female') {
          personColor = FEMALE_COLORS[femaleIdx % FEMALE_COLORS.length];
          femaleIdx++;
        } else {
          personColor = MALE_COLORS[maleIdx % MALE_COLORS.length];
          maleIdx++;
        }

        // Derive per-classifier gender + conf for the labels (POC reports
        // both face and body classifier outputs even when one didn't run).
        var faceGenderLabel = '';
        if (person.facePFemale != null && person.facePMale != null) {
          var faceIsFemale = person.facePFemale >= person.facePMale;
          var faceConf = faceIsFemale ? person.facePFemale : person.facePMale;
          faceGenderLabel = (faceIsFemale ? 'female ' : 'male ')
            + Math.round(faceConf * 100) + '%';
        } else {
          faceGenderLabel = 'face';
        }
        var bodyGenderLabel = '';
        if (person.bodyPFemale != null && person.bodyPMale != null) {
          var bodyIsFemale = person.bodyPFemale >= person.bodyPMale;
          var bodyConf = bodyIsFemale ? person.bodyPFemale : person.bodyPMale;
          bodyGenderLabel = (bodyIsFemale ? 'female ' : 'male ')
            + Math.round(bodyConf * 100) + '%';
        } else {
          bodyGenderLabel = 'body';
        }
        // Final winner label (matches the bbox label format).
        var gShort = person.gender === 'female' ? 'F'
                   : person.gender === 'male'   ? 'M'
                   : '?';
        var winnerConf = person.genderConfidence != null
          ? Math.round(person.genderConfidence * 100) + '%'
          : '';
        // Shorten classifier names so the label fits in the column width
        // (POC uses long labels but desktop has more horizontal space).
        var classSuffix = '';
        if (person.classifierUsed) {
          classSuffix = ' ['
            + person.classifierUsed
              .replace('insightface (partial body)', 'IF (part)')
              .replace('insightface (synth body)', 'IF (synth)')
              .replace('insightface (conflict)', 'IF (cnflct)')
              .replace('insightface (align fail)', 'IF (align)')
              .replace('pplcnet (synth body)', 'PP (synth)')
              .replace('pplcnet (no face)', 'PP (no face)')
              .replace('pplcnet (best)', 'PP (best)')
              .replace('pplcnet (align fail)', 'PP (align)')
              .replace('insightface', 'IF')
              .replace('pplcnet', 'PP')
            + ']';
        }
        var classLabel = gShort + ' ' + winnerConf + classSuffix;

        var y = stripTop + TOP_PAD;
        // 1) Face + body side by side
        if (face) {
          ctx.drawImage(face, x, y, FACE_DISPLAY, FACE_DISPLAY);
          // Yellow border on face (POC parity).
          ctx.strokeStyle = '#FFD700';
          ctx.lineWidth = 2;
          ctx.strokeRect(x, y, FACE_DISPLAY, FACE_DISPLAY);
        } else {
          ctx.fillStyle = '#222';
          ctx.fillRect(x, y, FACE_DISPLAY, FACE_DISPLAY);
        }
        var bx = x + FACE_DISPLAY + INNER_GAP;
        // Center body vertically with face (both bottoms aligned).
        var bodyY = y + (FACE_DISPLAY - BODY_DISPLAY_H);  // negative for taller body
        // If body is taller than face, draw it from y and let it extend below.
        // Otherwise align tops. POC stacks bottoms; we do the same.
        var bodyDrawY = y + Math.max(0, FACE_DISPLAY - BODY_DISPLAY_H);
        if (BODY_DISPLAY_H >= FACE_DISPLAY) bodyDrawY = y;
        if (body) {
          ctx.drawImage(body, bx, bodyDrawY, BODY_DISPLAY_W, BODY_DISPLAY_H);
          // Person-colour border on body.
          ctx.strokeStyle = personColor;
          ctx.lineWidth = 2;
          ctx.strokeRect(bx, bodyDrawY, BODY_DISPLAY_W, BODY_DISPLAY_H);
        } else {
          ctx.fillStyle = '#222';
          ctx.fillRect(bx, bodyDrawY, BODY_DISPLAY_W, BODY_DISPLAY_H);
        }

        // 2) Labels under each vignette
        var labelY = y + Math.max(FACE_DISPLAY, BODY_DISPLAY_H) + 12;
        ctx.font = 'bold 11px monospace';
        ctx.textAlign = 'center';
        ctx.fillStyle = '#FFD700';
        ctx.fillText(faceGenderLabel, x + FACE_DISPLAY / 2, labelY);
        ctx.fillStyle = personColor;
        ctx.fillText(bodyGenderLabel, bx + BODY_DISPLAY_W / 2, labelY);

        // 3) Final winner label (gender colour) centered under the column,
        // clipped to column width so it never overlaps the next person.
        ctx.font = 'bold 11px monospace';
        ctx.textAlign = 'center';
        ctx.fillStyle = personColor;
        var classLabelClipped = classLabel;
        var maxLabelW = COL_W - 4;
        while (classLabelClipped.length > 6
               && ctx.measureText(classLabelClipped).width > maxLabelW) {
          classLabelClipped = classLabelClipped.slice(0, -1);
        }
        ctx.fillText(classLabelClipped, x + COL_W / 2, labelY + 16);

        x += COL_W + COL_GAP;
        if (x + COL_W > imgW) break;
      }
      ctx.textAlign = 'left';  // restore

      var srcLower = (sourceImg.currentSrc || sourceImg.src || '').toLowerCase();
      var needsAlpha = /\.png(\?|$)/.test(srcLower) || /\.webp(\?|$)/.test(srcLower)
        || srcLower.indexOf('data:image/png') === 0;
      var mime = needsAlpha ? 'image/png' : 'image/jpeg';
      var quality = needsAlpha ? undefined : 0.85;
      return new Promise(function(resolveBlob) {
        canvas.toBlob(function(blob) { resolveBlob(blob); }, mime, quality);
      }).then(function(blob) {
        if (!blob) return false;
        return replaceImgWithBlob(sourceImg, blob);
      });
    });
  }

  // Replace the original <img> with a fresh clone pointing to a blob URL —
  // factored out of compositePerPersonBlur for the debug strip path.
  function replaceImgWithBlob(img, blob) {
    if (img.hasAttribute('srcset')) img.removeAttribute('srcset');
    if (img.hasAttribute('sizes')) img.removeAttribute('sizes');
    var pic = img.parentNode;
    if (pic && pic.tagName === 'PICTURE') {
      var sources = pic.querySelectorAll('source');
      for (var si = 0; si < sources.length; si++) {
        sources[si].removeAttribute('srcset');
      }
    }
    if (img.dataset.basarunaaBlobUrl) {
      try { URL.revokeObjectURL(img.dataset.basarunaaBlobUrl); } catch (_) {}
    }
    var blobUrl = URL.createObjectURL(blob);
    img.dataset.basarunaaBlobUrl = blobUrl;
    var fresh = img.cloneNode(false);
    fresh.removeAttribute('srcset');
    fresh.removeAttribute('sizes');
    fresh.removeAttribute('crossorigin');
    fresh.removeAttribute(BLUR_MARKER);
    fresh.style.removeProperty('filter');
    fresh.dataset.basarunaaBlobUrl = blobUrl;
    fresh.src = blobUrl;
    fresh.setAttribute(ID_ATTR, img.getAttribute(ID_ATTR) || '');
    fresh.setAttribute(STATE_ATTR, 'keep');
    if (img.parentNode) {
      img.parentNode.replaceChild(fresh, img);
      try { if (intersectionObserver) intersectionObserver.unobserve(img); } catch (_) {}
    }
    return true;
  }

  function compositeDebugOverlay(img, persons, debugMode, elapsedMs) {
    if (!persons || persons.length === 0) return Promise.resolve(false);
    var id = img.getAttribute(ID_ATTR);
    var normalised = normalisePersons(persons);
    // POC parity: in debug mode, the per-person blur from the active mode
    // is still applied — the overlay just draws on top so the user sees
    // *both* the production behaviour and what the pipeline detected.
    // Pick the normalised entries (objects with kp.confidence) so
    // drawFeatheredBlur's buildBodyPolygon can read keypoints correctly.
    var toBlur = [];
    for (var bi = 0; bi < persons.length; bi++) {
      if (persons[bi].shouldBlur) toBlur.push(normalised[bi]);
    }
    metric('debug_overlay_start', {
      id: id, persons: normalised.length, toBlur: toBlur.length, mode: '' + debugMode,
    });
    return getCompositingSource(img).then(function(source) {
      var w = source.naturalWidth != null ? source.naturalWidth : source.width;
      var h = source.naturalHeight != null ? source.naturalHeight : source.height;
      if (!w || !h) {
        metric('debug_overlay_nodim', { id: id });
        return false;
      }
      try {
        // In "debug" mode (full debug), add a black strip below the image
        // showing the face crop 96×96 + body crop 192×256 that each
        // classifier actually saw. Lets us diagnose visually instead of
        // guessing what the model received.
        var isFullDebug = debugMode === 'debug';
        var stripH = 0;
        if (isFullDebug) {
          // POC parity layout : face 96×96 + body 100×133 side-by-side.
          // top pad + max(face,body) + per-vignette label + winner label + pad
          stripH = 6 + 133 + 12 + 11 + 16 + 12 + 10;  // ≈200
        }
        var canvas = document.createElement('canvas');
        canvas.width = w;
        canvas.height = h + stripH;
        var ctx = canvas.getContext('2d');
        ctx.drawImage(source, 0, 0, w, h);
        // 1) blur the persons the active mode would normally blur, with
        //    the POC's debug contours (cyan/green/orange/red dashed) drawn
        //    around each silhouette so the user sees what the polygon mask
        //    looks like — only in debug mode (`showDebug=true`).
        if (toBlur.length > 0) {
          var blur = Math.max(25, Math.round(Math.max(w, h) * 0.04));
          var blurredCanvas = createEdgeClampedBlur(source, w, h, blur);
          for (var pi = 0; pi < toBlur.length; pi++) {
            drawFeatheredBlur(ctx, blurredCanvas, toBlur[pi], w, h, true);
          }
        }
        // 2) draw the debug overlay on top of the (partially) blurred image.
        drawDebugDetections(ctx, normalised, w, h, debugMode);
        // 3) header in top-left : `#<id> <elapsed>ms` (POC parity).
        drawDebugHeader(ctx, id, elapsedMs);
        // 4) crop strip in the bottom black band (debug mode only).
        if (isFullDebug && stripH > 0) {
          return drawCropStripAndEncode(canvas, ctx, normalised, w, h, stripH, img);
        }
        var srcLower = (img.currentSrc || img.src || '').toLowerCase();
        var needsAlpha = /\.png(\?|$)/.test(srcLower) || /\.webp(\?|$)/.test(srcLower)
          || srcLower.indexOf('data:image/png') === 0;
        var mime = needsAlpha ? 'image/png' : 'image/jpeg';
        var quality = needsAlpha ? undefined : 0.85;
        return new Promise(function(resolveBlob) {
          canvas.toBlob(function(blob) { resolveBlob(blob); }, mime, quality);
        }).then(function(blob) {
          if (!blob) {
            metric('debug_overlay_no_blob', { id: id });
            return false;
          }
          if (img.hasAttribute('srcset')) img.removeAttribute('srcset');
          if (img.hasAttribute('sizes')) img.removeAttribute('sizes');
          var pic = img.parentNode;
          if (pic && pic.tagName === 'PICTURE') {
            var sources = pic.querySelectorAll('source');
            for (var si = 0; si < sources.length; si++) {
              sources[si].removeAttribute('srcset');
            }
          }
          if (img.dataset.basarunaaBlobUrl) {
            try { URL.revokeObjectURL(img.dataset.basarunaaBlobUrl); } catch (_) {}
          }
          var blobUrl = URL.createObjectURL(blob);
          img.dataset.basarunaaBlobUrl = blobUrl;
          var fresh = img.cloneNode(false);
          fresh.removeAttribute('srcset');
          fresh.removeAttribute('sizes');
          fresh.removeAttribute('crossorigin');
          fresh.removeAttribute(BLUR_MARKER);
          fresh.style.removeProperty('filter');
          fresh.dataset.basarunaaBlobUrl = blobUrl;
          fresh.src = blobUrl;
          fresh.setAttribute(ID_ATTR, img.getAttribute(ID_ATTR) || '');
          fresh.setAttribute(STATE_ATTR, 'keep');
          if (img.parentNode) {
            img.parentNode.replaceChild(fresh, img);
            try { if (intersectionObserver) intersectionObserver.unobserve(img); } catch (_) {}
            metric('debug_overlay_applied', { id: id, persons: persons.length });
          }
          return true;
        });
      } catch (e) {
        metric('debug_overlay_failed', { id: id, msg: ('' + e).slice(0, 120) });
        return false;
      }
    }).catch(function(e) {
      metric('debug_overlay_rejected', { id: id, msg: ('' + e).slice(0, 120) });
      return false;
    });
  }

  // ─── Receive decision from Swift ───
  // Swift sends `(id, decision, persons, debugMode, elapsedMs)`.
  // `persons` includes a per-entry `shouldBlur` flag (true for the persons
  // the active mode would normally blur). `debugMode` is one of
  // "none" / "boxes" / "debug" — when not "none", we draw a debug overlay
  // on top of the per-person blur (POC parity), and a `#<id> XXms`
  // header in the top-left corner.
  window.__basarunaaApply = function(id, decision, persons, debugMode, elapsedMs) {
    try {
      var img = findById(id);
      var personCount = (persons && persons.length) || 0;
      var isDebug = debugMode === 'boxes' || debugMode === 'debug';
      metric('analyze_decision', {
        id: id, decision: '' + decision, persons: personCount,
        found: !!img, debug: '' + (debugMode || 'none'),
      });
      if (img) {
        img.setAttribute(STATE_ATTR, decision);
        if (isDebug) {
          // Debug overlay: composite blur (on shouldBlur=true persons) then
          // draw bboxes/labels/skeleton on top. We don't cache the
          // decision in debug mode so the user can toggle modes and reload.
          removeBlurFrom(img);
          if (personCount > 0) {
            compositeDebugOverlay(img, persons, debugMode, elapsedMs);
          }
        } else if (decision === 'remove') {
          removeBlurFrom(img);
          setCachedDecision(imgUrl(img), decision);
        } else if (decision === 'keep' && personCount > 0) {
          // Per-person composite blur (POC method). Async because we need to
          // decode the CORS-fetched blob into an ImageBitmap before drawing.
          // Falls back silently to full-image blur on failure.
          compositePerPersonBlur(img, persons);
          setCachedDecision(imgUrl(img), decision);
        } else {
          // 'keep' without persons (NSFW) → full-image blur already applied.
          setCachedDecision(imgUrl(img), decision);
        }
      }
    } catch (e) {
      metric('apply_error', { msg: '' + e });
    } finally {
      analyzing = false;
      drain();
    }
  };

  // ─── Phase 2 NSFW notification ───
  // Swift fires `window.__basarunaaApplyNsfw(id, score)` *after* the
  // per-person blur is already applied, only when NSFW is positive. POC
  // parity (cf. offscreen.js Phase 2). We force a full-image CSS blur on
  // top of whatever the per-person composite produced — cheap & safe.
  window.__basarunaaApplyNsfw = function(id, score) {
    try {
      var img = findById(id);
      metric('apply_nsfw', {
        id: id, score: score, found: !!img,
      });
      if (img) {
        // Re-apply the default full-image blur with !important. This
        // wins over the blob URL replacement done by the composite path.
        img.style.setProperty(
          'filter',
          'blur(' + BLUR_RADIUS_PX + 'px)',
          'important'
        );
        img.setAttribute(BLUR_MARKER, '1');
        img.setAttribute(STATE_ATTR, 'keep');
        setCachedDecision(imgUrl(img), 'keep');
      }
    } catch (e) {
      metric('apply_nsfw_error', { msg: '' + e });
    }
  };

  // ─── IntersectionObserver — only analyze visible images ───
  //
  // Pages can have 50-100+ images, most below the fold. Analyzing all of them
  // upfront wastes ML cycles on imgs the user may never scroll to. We register
  // an IntersectionObserver and only enqueue analysis when an image enters
  // (or is near) the viewport.
  //
  // The CSS blur is still applied to every <img> at scan time, so off-screen
  // imgs are blurred when they arrive — we just defer the *decision* until
  // they're visible.
  var intersectionObserver = null;
  if (typeof IntersectionObserver !== 'undefined') {
    intersectionObserver = new IntersectionObserver(function(entries) {
      for (var i = 0; i < entries.length; i++) {
        var entry = entries[i];
        if (entry.isIntersecting && entry.target.tagName === 'IMG') {
          var img = entry.target;
          intersectionObserver.unobserve(img);
          enqueueAnalyze(img);
        }
      }
    }, {
      // Trigger 200px before the image actually enters the viewport — gives
      // the pipeline time to analyse + apply the decision before the user
      // scrolls to it.
      rootMargin: '200px 0px',
      threshold: 0,
    });
  }

  function observeForAnalysis(img) {
    if (!img || img.tagName !== 'IMG') return;
    if (img.hasAttribute(ID_ATTR)) return;     // already queued/analyzed
    if (img.getAttribute(STATE_ATTR) === 'remove') return;  // sticky safe
    if (intersectionObserver) {
      intersectionObserver.observe(img);
    } else {
      // Fallback for browsers without IntersectionObserver: analyze immediately.
      enqueueAnalyze(img);
    }
  }

  function observeAll(root) {
    var imgs = (root || document).querySelectorAll('img');
    for (var i = 0; i < imgs.length; i++) observeForAnalysis(imgs[i]);
  }

  // ─── Lifecycle ───
  function onPageHide() {
    metric('page_hide', { url: location.href });
    send('pageReset', location.href);
  }
  window.addEventListener('pagehide', onPageHide);
  window.addEventListener('beforeunload', onPageHide);

  function init() {
    var initialCount = scanAndBlur(document);
    metric('script_init', { url: location.href, initial_imgs: initialCount });
    send('scriptReady', location.href);
    send('blurApplied', String(initialCount));
    observeAll(document);

    try {
      var observer = new MutationObserver(function(mutations) {
        var n = 0;
        for (var m = 0; m < mutations.length; m++) {
          var mut = mutations[m];
          if (mut.type === 'childList') {
            for (var a = 0; a < mut.addedNodes.length; a++) {
              var node = mut.addedNodes[a];
              if (!node || node.nodeType !== 1) continue;
              if (node.tagName === 'IMG') {
                if (applyBlurTo(node)) n++;
                observeForAnalysis(node);
              } else if (node.querySelectorAll) {
                n += scanAndBlur(node);
                observeAll(node);
              }
            }
          }
          // NOTE: we deliberately don't observe `src` changes. Lazy-loaded sites
          // (Google Images, social feeds) update `src` from placeholder → full
          // res, which would otherwise re-trigger analysis and cause a visible
          // "blur → unblur → re-blur → unblur" flash. The first decision is
          // sticky for V1. Trade-off: a server-side image swap with different
          // content (rare on lazy-load) will keep the previous decision.
        }
        if (n > 0) metric('mutation_blur', { added: n });
      });
      observer.observe(document.documentElement || document.body, {
        childList: true,
        subtree: true
      });
    } catch (e) {
      metric('observer_error', { msg: '' + e });
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init, { once: true });
  } else {
    init();
  }
});
