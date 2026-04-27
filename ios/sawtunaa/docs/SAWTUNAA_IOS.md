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

## Bugs connus

### 1. Audio hachuré les 2 premières secondes (**connu, POC**)
**Cause :** warmup NSNet2 (premier chunk = ~700ms) crée un micro-gap suivi de starvation pendant le rattrapage.
**Fix proposé :** warmup à froid avec un buffer silence au lancement.

### 2. Audio en avance par rapport à la vidéo (**régression Browther**)
**Cause :** offset de timestamp calibré au démarrage shifte l'audio en avance.
**Fix :** retirer l'offset, laisser `chunk.timestampMs <= upToMs` jouer naturellement (comme le POC).

### 3. Stops aléatoires (**à diagnostiquer**)
**Hypothèses :**
- `playerNode` finit tous les buffers schedulés et passe en idle silencieux
- AVAudioEngine erreur non loguée
- Audio session interruption

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
- `init_segment` — MSE init segment reçu
- `media_segment` — MSE media segment reçu (taille, packets)
- `decoder_ready` — Opus decoder initialisé
- `decode_done` — Segment décodé (samples, durée)
- `chunk_send` — Chunk envoyé à Swift
- `auto_activate` — Pipeline activé
- `seek_detected` — Saut détecté
- `pause_audio` / `resume_audio`
- `video_state` — poll toutes les 500ms (currentTime, paused, muted, buffered)

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
