# Sawtunaa iOS — Pipeline & Méthodologie de debug

> Suppression de musique/bruit de fond en temps réel sur YouTube dans Browther iOS.
> Approche : interception MSE WKWebView → décodage Opus WASM → NSNet2 natif Swift → AVAudioEngine.

## Architecture

```
┌─────────────────────────── WKWebView (JS) ───────────────────────────┐
│                                                                       │
│  YouTube ──appendBuffer──► Monkey-patch ──► Parse EBML (timestamps)  │
│                                │                                      │
│                                ▼                                      │
│                        Opus WASM decode                               │
│                                │                                      │
│                                ▼                                      │
│                    Mix stereo → mono Float32                          │
│                                │                                      │
│                                ▼                                      │
│              Chunk 48000 samples (1s) × N                            │
│                                │                                      │
│                    base64 encode + postMessage                        │
│                    ("preprocess" handler)                              │
│                                │                                      │
│  Scheduler (30ms) ────────── playAt(video.currentTime + 100) ────►   │
│  Pause detect ────────────── pauseAudio / resumeAudio ───────────►   │
│                                                                       │
└───────────────────────────────┬───────────────────────────────────────┘
                                │
                    postMessage (WKScriptMessageHandler)
                                │
                                ▼
┌─────────────────────────── Swift (natif) ─────────────────────────────┐
│                                                                       │
│  SawtunaaScriptHandler (action dispatch)                              │
│    "preprocess" → base64 decode → [Float] → preprocessQueue           │
│                                              │                        │
│                                    NSNet2Processor                    │
│                              (STFT vDSP → ONNX → ISTFT)               │
│                                              │                        │
│                                    AVAudioPCMBuffer                   │
│                                              │                        │
│                                    processedChunks[] (timestamped)    │
│                                                                       │
│    "playAt" → playChunksUpTo(upToMs)                                  │
│      pour chaque chunk.timestampMs ≤ upToMs :                         │
│        • trim si chunk en retard                                      │
│        • playerNode.scheduleBuffer()                                  │
│                                                                       │
│  AVAudioEngine ── playerNode ── mainMixerNode ── output (speakers)   │
│  AVAudioSession(.playback, .mixWithOthers)                            │
│                                                                       │
└───────────────────────────────────────────────────────────────────────┘
```

## Comment ça marche concrètement (pipeline temporel)

YouTube envoie l'audio **en avance** (par bursts), on le **traite en avance aussi**, mais l'audio sort des speakers **précisément** quand la vidéo arrive au bon moment.

```
                     Video time réel:    [0s ━━━ 5s ━━━━━━━━━━ 30s]
                                              ↑ user regarde ici

1. YouTube buffer:   [0s ━━━━━━━━━━━━━━━━━━━━━━━ 30s]  ← envoie d'avance
                          ↓ MSE intercept (segments par bursts)

2. JS décode Opus:   [chunks ts=0,1,2,3...30s]
                          ↓ envoie à Swift en base64

3. NSNet2 process:   [chunks filtrés ts=0..30] ← traite ~4× plus vite que temps réel
                          ↓ 1 chunk de 1s en ~250ms

4. Buffer Swift:     [chunks prêts: ts=5,6,7,8,9] ← max 5s d'avance (lookahead cap)
                          ↓ scheduleBuffer au playerNode

5. Player queue:     [chunks attendant: ts=5,6,7,8,9]
                          ↓ joue 1× temps réel

6. Speakers:         [son qui sort] ← actuellement sample ts=5s, video à 5.15s
                                       (decalage 150ms hardware AVAudioEngine)
```

**Points clés :**
- **Pas "fil de l'eau strict"** : on a toujours ~5s d'audio prêt à jouer (sécurité contre les bursts YouTube qui peuvent envoyer 30s d'audio puis rester silencieux 17s)
- **NSNet2 process en avance** : ~4× plus rapide que temps réel, donc on peut buffer
- **Le PlayerNode joue à 1×** : impossible de l'accélérer/ralentir, il consomme à temps réel
- **Sync** : le 1er chunk est trim/aligné sur `video.currentTime`, après ça l'audio joue chunk après chunk en suivant le timestamp source
- **Drift résiduel ~150ms** = latence hardware AVAudioEngine sur iOS (incompressible facilement, sous le seuil de perception)

### Mécanismes anti-drift

1. **Lookahead cap (5s)** : ne schedule jamais plus de 5s d'avance dans le playerNode. Évite que le player accumule un burst entier puis joue avec un trou de silence.
2. **Skip + trim** : si un chunk arrive en retard (>200ms vieux), on le skip ; s'il est partiellement en retard, on coupe le début pour resync.
3. **Gap-fill** : si YouTube livre des chunks non-contigus (ts=0..1000 puis ts=1500..2500), on insère 500ms de silence pour ne pas que l'audio "saute" et prenne de l'avance.
4. **Silence-lead** : si le 1er chunk après un reset (init/seek) est légèrement dans le futur (jusqu'à 2s), on insère du silence pour aligner avec video.currentTime.
5. **Drop-during-pause** : pendant la pause, on jette les nouveaux chunks NSNet2 (sinon ils s'accumuleraient et prendraient de l'avance au resume).
6. **Flush au seek + cache LRU** : `seekTo` flush le playerNode mais **garde le cache** (jusqu'à 600 chunks ~10min) pour permettre le seek instantané vers une zone déjà bufferisée.
7. **PageReset au refresh** : à chaque init du script JS (refresh, restore depuis bfcache, navigation), une action `pageReset` est envoyée à Swift, qui drop le cache et flush le playerNode. Sans ça, l'audio de la page précédente continuerait à jouer par-dessus la nouvelle page (le `SawtunaaScriptHandler` Swift est lié au tab, pas au JS context). Idempotent.
8. **PageReset au changement de vidéo SPA** : YouTube utilise `history.pushState` pour passer d'une vidéo à l'autre sans recharger la page. Le JS context survit, donc `script_init` ne se redéclenche pas. On hook `pushState`/`replaceState`/`popstate` + polling 250ms : dès que le `v=` de l'URL change, on envoie `pageReset`. Sans ça, les chunks de la nouvelle vidéo arrivent à des timestamps ~0ms qui chevauchent ceux de la vidéo précédente dans le cache → "début de A puis alternance A/B puis B".
9. **Epoch counter (anti-race)** : `clearChunks()` incrémente un compteur. Tout chunk en cours de preprocess capture l'epoch au moment du dispatch ; à la complétion, si l'epoch a changé, le chunk est dropé (`stale_epoch`) — sinon on insère un chunk de l'ancienne session dans le cache neuf, recréant le bug "audio en double".

### Cache mirror du buffer YouTube (seek instantané)

Le `audioCache` Swift mirror exactement le buffer MSE interne de YouTube :
- **`appendBuffer`** intercepté → ajoute le chunk processé au cache
- **`remove(start, end)`** intercepté → évince la plage du cache (action `evictRange`)
- **`abort()`** intercepté → metric uniquement
- **Sanity check 5s** → JS envoie `sb.buffered` ranges, Swift drop les chunks hors plages (catch les évictions silencieuses du browser quand le quota MSE est atteint)

Au seek :
- Si la cible est dans le cache → audio reprend instantanément (curseur `scheduledCursorTsMs` repositionné, chunks rejoués depuis le cache)
- Si hors cache → comportement YouTube natif (silence pendant que YouTube re-fetch via DASH)

Le curseur strict `scheduledCursorTsMs` (timestampMs du dernier chunk schedulé) garantit qu'un chunk n'est **jamais** scheduled deux fois — sans ça, des chunks courts (<100ms en fin de segment) pouvaient re-matcher en boucle infinie (bug OOM observé : 429063× scheduling).

## Pourquoi cette approche ?

| Approche testée | Verdict |
|---|---|
| `createMediaElementSource` (Web Audio) | ❌ Ne capture pas l'audio MSE sur iOS |
| AVPlayer + MTAudioProcessingTap | ❌ API privée, rejet App Store |
| AVPlayer + extraction URL YouTube | ❌ Non store-compliant (scraping) |
| **WKWebView + MSE intercept + AVAudioEngine** | ✅ Validé end-to-end |

## Spécificités iOS WKWebView (pièges connus)

- `MediaSource` n'existe **pas** sur iOS — uniquement `ManagedMediaSource` (iOS 17+)
- `SourceBuffer` n'est **pas** un global — patcher via `Object.getPrototypeOf(instance)`
- `video.muted = true` tue l'audio session WKWebView mais **AVAudioEngine survit** (session séparée)
- `video.volume` est ignoré par iOS pour MSE (ne contrôle pas le volume réel)
- YouTube utilise `audio/webm; codecs="opus"` (pas AAC)
- YouTube crée de **nouveaux SourceBuffers** lors des navigations SPA → re-init du pipeline
- `postMessage` avec JSON/Array bloque le thread JS pour les gros segments → utiliser **base64**
- Les segments YouTube sont bufferisés ~10-20s à l'avance au démarrage

## Métriques cibles (baseline du POC)

| Métrique | Cible | Source |
|---|---|---|
| NSNet2 1er chunk (warmup) | ~600-700ms | POC |
| NSNet2 chunks suivants | ~170-210ms / 1s d'audio (5x temps réel) | POC |
| Latence 1er son traité | ~700-800ms après activation | POC |
| Buffer pré-traité | 15-30 chunks d'avance | POC |
| Trim 1er chunk | 500-750ms coupés pour sync | POC |
| Latence audio↔vidéo (sync) | < 200ms (cible idéale) | — |
| Gap entre 2 chunks joués | < 50ms (idéal 0) | — |
| Underruns par minute | 0 | — |
| Chunks skippés (trop vieux) | 0% | — |

## Métriques mesurées (état actuel)

| Métrique | Mesuré |
|---|---|
| Activation → 1er son | **~1.3s** (vs cible POC 700-800ms) |
| NSNet2 1er chunk (warmup) | **~400-500ms** (warmup 1s silence appliqué au load) |
| NSNet2 chunks suivants | **~110-220ms / 1s** (4-5× temps réel) |
| Audio coverage | **99.9%** sur tests 60-130s |
| Drift video↔audio | **~150ms** (audio en retard, latence hardware iOS) |
| Underruns vrais | **0** |

## Fixes appliqués (commits)

| Fix | Commit | Effet mesuré |
|---|---|---|
| Eager load + warmup à froid NSNet2 | `cac1aa8323e` | Activation 10318ms → 1261ms (-83%) |
| Lookahead cap 5s + gap-fill silence | `9b643fcafb6` | Plus de silence 15s entre bursts. Coverage 84% → 99.9% |
| Drop-during-pause + flush au seek + métrique drift | `631a7378008` | Pause/resume sans drift, drift mesuré objectivement |
| Cache mirror buffer YouTube + curseur strict | `1646d390c4f` | Seek instantané dans zone bufferisée. Fix bug OOM (chunks courts re-scheduled en boucle). Fix EBML false positive (0xE7 dans Opus → ts ~30min) |
| Reset `lastEstimatedEndMs` au seek lointain | `f8fda3586fb` | Fix zone morte après seek vers une position non bufferisée (>60s). Le validateur jump>60s rejetait à tort les ts post-seek valides |
| `pageReset` action JS→Swift + epoch counter | `58bae2fa91b` | Fix bug "audio en double après refresh" : Swift drop son cache à chaque init du script JS. Epoch counter empêche les chunks en flight d'une ancienne session de polluer le cache neuf |
| `pageReset` au video change SPA (pushState hook) | `6f8d2af303d` | Fix bug "début vidéo A puis alternance A/B puis B" : détection du `v=` qui change → pageReset instantané (pushState/replaceState/popstate hooks) |
| `pageReset` au content change (init_segment hash) | (en cours) | Fix bug "audio de pub continue après Skip Ad" : compare les init_segments consécutifs ; si différents → contenu changé (pre-roll ad → vidéo principale, ou changement de stream) → pageReset |

## Limitations connues

### Drift hardware ~150ms incompressible
Latence intrinsèque AVAudioEngine + iOS audio I/O. Sous le seuil de perception conscious (~250ms). Pour réduire, on peut configurer `AVAudioSession.preferredIOBufferDuration` (au prix d'une consommation CPU plus élevée et risque d'underrun).

### Seek vers zone jamais visitée
Si l'utilisateur seek vers une position que YouTube n'a jamais bufferisée (et qu'on n'a pas dans notre cache non plus), il faut attendre que YouTube re-fetch via DASH (~500ms-2s). Comportement identique à YouTube natif sur iOS.

## Méthodologie de debug

### Étape 1 : Observabilité

Tous les events clés sont logués au format `[METRIC] {json}` :

**Côté Swift :**
- `engine_start` — AVAudioEngine démarre (succès/échec)
- `model_load_done` — NSNet2 ready
- `chunk_preprocess_start` — JS a envoyé un chunk
- `chunk_preprocess_done` — NSNet2 fini, chunk en queue (avec `nsnet2_ms`)
- `chunk_play_full` / `chunk_play_trim` — chunk schedulé pour playback
- `chunk_skip_old` — chunk skippé (trop vieux)
- `play_chunks_call` — playChunksUpTo appelé (état du buffer)
- `engine_state` — poll toutes les 1s : running, queue depth, audio queued ms
- `engine_error` — toute erreur AVAudio

**Côté JS :**
- `script_init` — script chargé (avec URL + isYoutube)
- `page_reset_sent` — pageReset envoyé à Swift (refresh / nouvelle page)
- `pagehide` / `pageshow` / `visibility_change` — lifecycle DOM
- `url_changed` — URL a changé (SPA navigation YouTube)
- `init_segment` — MSE init segment reçu
- `media_segment` — MSE media segment reçu (taille, packets)
- `decoder_ready` — Opus decoder initialisé
- `decode_done` — Segment décodé (samples, durée)
- `chunk_send` — Chunk envoyé à Swift
- `auto_activate` — Pipeline activé
- `seek_detected` — Saut détecté
- `video_paused` / `video_resumed` — détection lecture/pause vidéo (avec video_ms)
- `video_state` — poll toutes les 500ms (currentTime, paused, muted, buffered)

**Côté Swift (lifecycle) :**
- `handler_init` / `handler_deinit` — TabContentScript instancié/détruit
- `handler_create_player` — AVAudioEngine créé (eager init)
- `handler_page_reset` — action pageReset reçue, drop le cache (avec was_active)
- `handler_clear_chunks` — action clearChunks reçue
- `clear_chunks` — cache nettoyé (epoch incrémenté)
- `seek_to` — seek (cache préservé)

### Étape 2 : Scénario de test reproductible

**Vidéo de référence** : (à fixer ensemble — recommandation : un clip court avec musique constante)

**Procédure** :
1. Forcer une fermeture de Browther (swipe up app switcher)
2. Relancer Browther via `xcrun devicectl device process launch ...`
3. Aller sur YouTube, taper la vidéo de référence
4. Lancer la lecture, **ne rien toucher pendant 60s**
5. Capturer tous les logs dans un fichier
6. Lancer `analyze_metrics.py logs.txt` → rapport

### Étape 3 : Rapport baseline

Le script Python sort un rapport comme ça :

```
=== Sawtunaa iOS — Test Report ===
Test duration:        60.0s
Pipeline activated:   T+1.234s
First chunk played:   T+1.890s (latency=656ms)

== Audio coverage ==
Audio scheduled:      57.3s (95.5% of 60s)
Underruns:            3 events (total silence: 1.8s)
Gap durations:        avg=12ms p99=420ms max=620ms

== NSNet2 performance ==
Chunks processed:     58
Processing time:      avg=187ms p50=170ms p99=412ms
First chunk warmup:   704ms

== Sync ==
Latency video→audio:  avg=143ms p50=120ms p99=487ms (target <200ms)
Skipped chunks:       0 (0%)

== Engine state ==
Engine errors:        0
Time engine.isRunning=false: 0ms
Time playerNode.isPlaying=false: 0ms

== Verdict ==
PASS: NSNet2 performance within target
FAIL: Audio gaps > 50ms detected (3 events) — investigate underruns
WARN: Latency p99=487ms > 200ms target — investigate sync drift
```

### Étape 4 : Fix one by one

Pour chaque bug :
1. **Hypothèse** documentée avec la métrique qui la pointe
2. **Fix minimal** ciblé
3. **Re-run** le même scénario
4. **Comparer** les rapports avant/après
5. **Passer au suivant** seulement si la métrique cible est dans la fourchette

Si une métrique se dégrade ailleurs → revert.

### Sortie de l'analyzer

Le script `analyze_sawtunaa_metrics.py` produit :

- **Lifecycle** : timeline de tous les events haut-niveau (script_init, page_reset, init_segment, seek, pause/resume, etc.) avec deltas
- **Sessions** : segmentation automatique par `handler_page_reset` (chaque refresh = nouvelle session). Stats par session : activation, chunks joués, coverage, drift
- **NSNet2 / Playback / Sync / Engine state / JS pipeline** : agrégats classiques
- **Anomalies détectées** : auto-detection de bugs courants
  - `OUT-OF-ORDER scheduling` — un chunk avec ts inférieur a été schedulé après
  - `DISCONTINUITIES in scheduling` — gap >100ms entre chunks consécutifs
  - `BIG JUMP` — saut >5s (typiquement seek lointain mal géré)
  - `STALE AUDIO AFTER RESET` — chunks d'une ancienne session joués après pageReset (= "audio en double")
  - `CACHE SURVIVED RESET` — cache pas vidé après pageReset
  - `STALE EPOCH DROPS` — info : race correctement attrapée par l'epoch counter
  - `RESET STORM` — ≥3 page_resets en <5s (potentiel bug de loop)
  - `CACHE HOLES` — gaps >100ms dans le cache (zones manquantes)
  - `DRIFT TREND` — drift moyen 1/3 fin > 1/3 début (drift cumulatif)

Avec `--lifecycle`, tous les events lifecycle sont imprimés (sans cap par type).

## Fichiers du pipeline

| Fichier | Rôle |
|---|---|
| `Sources/Sawtunaa/NSNet2Processor.swift` | STFT vDSP → ONNX → ISTFT (stateful GRU) |
| `Sources/Sawtunaa/SawtunaaAudioPlayer.swift` | AVAudioEngine + buffer management |
| `Sources/Sawtunaa/SawtunaaPreferences.swift` | `Preferences.Sawtunaa.enabled` |
| `Sources/Sawtunaa/Resources/nsnet2-stateful.onnx` | Modèle ONNX (25 MB) |
| `Sources/Brave/.../SawtunaaScript.js` | Interception MSE + decode Opus + scheduler |
| `Sources/Brave/.../SawtunaaOpusDecoderBundle.js` | Opus decoder WASM (105 KB) |
| `Sources/Brave/.../SawtunaaScriptHandler.swift` | Bridge JS↔Swift (action dispatch) |
| `Sources/Brave/.../BVC+Sawtunaa.swift` | Delegate BVC pour notifications UI |
| `tools/analyze_sawtunaa_metrics.py` | Parser logs + rapport |

## Build & install

```bash
cd browther/desktop/src/brave/ios/brave-ios/App
xcodebuild -project Client.xcodeproj -scheme "Component" \
  -destination 'generic/platform=iOS' -configuration Debug build

xcrun devicectl device install app --device <device_id> \
  ~/Library/Developer/Xcode/DerivedData/Client-*/Build/Products/Debug-iphoneos/Client.app

# Capturer les logs métriques :
xcrun devicectl device process launch --device <device_id> \
  --terminate-existing --console com.devndin.browther.ios.BrowserBeta \
  2>&1 | tee /tmp/sawtunaa_run_$(date +%s).log

# Analyser :
python3 tools/analyze_sawtunaa_metrics.py /tmp/sawtunaa_run_*.log
```
