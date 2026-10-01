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

### Synchronisation en boucle fermée (depuis le 2026-09-30)

> ⚠️ Les mécanismes 1-5 ci-dessous décrivent l'**ancien** scheduling « à la suite »
> (blocs enchaînés, avance fixe `+100 ms`, dérive seulement **mesurée**). Karim
> constatait sur iPhone un décalage audio/image visible — parfois l'audio
> **avant** l'image — après un seek ±10 s, une reprise, ou même sans rien toucher,
> alors que macOS est parfait : sur macOS l'audio traité EST l'horloge du
> lecteur, le décalage y est impossible par construction. Causes, toutes
> vérifiées dans le code :
>
> | Cause | Effet |
> |---|---|
> | Vidéo qui **cale** (rebuffering, seek en cours) avec `paused === false` : l'audio continuait | audio en avance d'autant, **jamais rattrapé** |
> | Reprise : `playerNode.play()` instantané, l'image redémarre avec du retard ; pause détectée avec jusqu'à 30 ms de retard | décalage qui **s'accumule** à chaque pause |
> | Avance fixe `+100 ms` sur `currentTime` pour « compenser » une latence supposée de 150 ms | haut-parleur (~10-20 ms réels) → audio **~80 ms en avance** ; AirPods (~200 ms) → en retard |
> | Blocs enchaînés : un underrun décalait toute la suite | dérive silencieuse |
> | `preprocess_drop_paused` : blocs reçus pendant la pause jetés | trous de silence après une longue pause |
> | Seek < 2 s non détecté | décalage résiduel |
>
> **Nouveau modèle** (`SawtunaaAudioPlayer.swift`, doc en tête de classe) :
> - chaque bloc est posé à sa **position explicite** sur la timeline du player
>   (`scheduleBuffer(_:at:)`) ; plus de gap-fill ni de silence-lead ;
> - position **audible** = horloge du player + `AVAudioSession.outputLatency`,
>   comparée à `currentTime` (extrapolé du transit JS→natif) à chaque tick ;
> - **resync** (vidage + ré-ancrage + rejeu depuis le cache) à chaque reprise
>   (pause, calage, seek) et si la dérive dépasse **80 ms pendant ~300 ms**
>   (max 1/s) ; changement de sortie (AirPods…) → moteur redémarré + resync ;
> - JS : l'audio est coupé dès que la vidéo est `paused`, `seeking`, ou que
>   `currentTime` n'a pas bougé depuis **300 ms** (`STALL_MS`) ;
> - les blocs sont traités même en pause ; leur position tient compte de ce que
>   NSNet2 retenait (`start_ms`).
>
> Métriques ajoutées : `anchor`, `resync` (`reason` = resume/seek/drift/
> config_change/clear), `drift_resync`, `video_stalled`, `engine_config_change`.
> `engine_state.drift_ms` > 0 = audio en retard. **Si ça saccade** : chercher des
> `video_stalled` à répétition (STALL_MS trop court pour la fréquence de
> rafraîchissement de `currentTime`) ou des `drift_resync` en rafale.
> **Vitesse ≠ 1×** : l'audio joue toujours à 1× → resync ~1/s (non géré).
>
> ⚠️ **Régression corrigée le 2026-10-01** : la détection de saut (> 2 s) doit
> rester AVANT la coupure « vidéo `seeking`/calée ». Placée après, un curseur
> posé loin (hors tampon YouTube) laissait `lastEstimatedEndMs` sur l'ancienne
> position : les blocs de la nouvelle étaient re-datés comme aberrants →
> silence > 1 min. Les ±10 s (dans le tampon) n'étaient pas touchés.

### Bascule sans rechargement + « seulement 2 min » (2026-10-01)

Avant : chaque bascule de l'interrupteur rechargeait l'onglet (le script
n'était injecté que Sawtunaa allumé, et il doit être en place AVANT que la
page crée son MediaSource) → la vidéo repartait de 0.

- **Script toujours injecté**, en deux variantes figées selon l'état AU
  CHARGEMENT (`$<sawtunaa_enabled>`) : une page chargée allumée coupe la musique
  dès la première image sans attendre le natif.
- **Éteint = veille** : le hook `appendBuffer` analyse chaque segment Opus et
  en garde la copie **compressée** (`standbySegments` : paquets + horodatage,
  10 s derrière la lecture, plafond 4 Mo, miroir des `remove()`), sans
  décodage, sans NSNet2, sans couper le son. Coût : quelques centaines de Ko.
- **Allumage** (`window.__sawtunaaSetEnabled(true)`, appelé par
  `SawtunaaScriptHandler.setEnabled(_:in:)` depuis l'observateur de la pref du
  BVC) : la vidéo qui joue est coupée tout de suite, `activate` part au natif
  (chargement du modèle en parallèle), un décodeur repart du dernier segment
  d'init gardé, et les segments gardés à partir de `currentTime − 500 ms` sont
  décodés puis envoyés comme d'habitude. Le natif s'ancre au premier `playAt`
  (resync normal). Silence attendu ≈ 1 s (décodeur WASM + premier bloc NSNet2,
  + chargement du modèle la toute première fois).
- **Extinction** : timers arrêtés, son d'origine rendu à chaque vidéo coupée
  avec ses valeurs d'avant (`__sawtunaa_saved`, plus de `volume = 1`
  arbitraire), décodeur libéré (compteur de génération contre un `ready`
  tardif), `deactivate` → le natif vide le lecteur et arrête le moteur. Le
  modèle reste chargé (rallumage immédiat).
- **Modèle NSNet2 chargé à la première activation de l'onglet**, plus à la
  création de chaque onglet (~25 Mo + session ORT par onglet auparavant, même
  Sawtunaa éteint).
- La bonne variante est ré-injectée pour les PROCHAINS chargements (`setScripts`
  OFF puis ON, même geste que Basarunaa « Floutage actif »).

**« Seulement 2 min »** (`Brave/Frontend/Browther/SawtunaaTemporarySwitch.swift`,
maquette validée par Karim) : juste après une bascule, le panneau propose
« Réactiver automatiquement dans 2 min » ou « Couper automatiquement dans
2 min » (jusqu'à la fermeture du panneau). Accepté : ligne de compte à rebours
+ « Ne pas réactiver / Ne pas couper », anneau qui se vide sur le bouton rond
de l'interrupteur et autour de l'icône de la barre d'adresse (Core Animation,
aucun travail par image). Revenir plus tôt = rebasculer l'interrupteur, ou
toucher l'icône (sans ouvrir le panneau). Tout le navigateur ; échéance
enregistrée (`Preferences.Sawtunaa.temporaryRevertAt/To`) → app fermée pendant
le compte à rebours = état d'avant au lancement suivant. Pas de rallumage
pendant la pause du parrainage. Events PostHog : `feature_temporary`,
`feature_temporary_end` (`reason` = timer/icon/toggle/keep/relaunch).
Chaînes : `private/assets/sawtunaa-temporary-strings.json` (8 × 66 langues).

### Seek lointain : file NSNet2 prioritaire (2026-10-01)

Mesuré sur iPhone 13 (capture `devicectl --console`) : NSNet2 ≈ **290 ms par
seconde d'audio** (1 thread) et YouTube charge ~35 s d'avance. La file FIFO
finissait l'audio de l'ANCIENNE position (24 blocs ≈ 7 s) avant d'attaquer la
nouvelle, dont les premiers blocs, trop tardifs, étaient sautés → 5 à 10 s de
silence. Désormais `pumpPreprocess()` choisit le prochain bloc : devant la
lecture d'abord (ordre croissant), derrière en dernier ; un bloc qui ne
prolonge pas le précédent (recul, ou saut > 2 s) repart d'un NSNet2 remis à
zéro. Un bloc traité pendant la lecture est planifié aussitôt (sans attendre
le tick JS).

Même capture : le **premier** ancrage (juste après `engine.start()`) était
faux de ~70 ms (audio en avance, mesure oscillant de 48 à 83 ms) alors que
tous les ancrages suivants donnaient 0 ± 1 ms. Le seuil passe à **40 ms sur la
moyenne de 10 ticks** (au lieu de 80 ms sur 10 ticks consécutifs, jamais
atteint en 4 min).

### CPU / chauffe (2026-10-01)

Session ORT créée avec les défauts = un thread par cœur **en attente active**
entre deux `run` (un par frame de 10,7 ms). Bench Mac du vrai
`NSNet2Processor.swift` (60 s d'audio stéréo en blocs d'1 s) : **6,3 s CPU pour
1,26 s de travail** → avec `intraOpNumThreads = 1` + `allow_spinning = 0`
(= réglage macOS, `kOrtIntraOpThreads`) : **2,1 s CPU (−67 %)**, toujours 30×
plus rapide que le temps réel, parité golden OK.

**Suite du même jour — les pistes restantes, mesurées.** Banc :
`private/tools/sawtunaa-swift-golden/bench.sh` (vrai `NSNet2Processor.swift`,
60 s stéréo en blocs d'1 s planar, comme le JS). ⚠️ Le Mac étant partagé
(simulateurs, builds), le temps CPU y varie de ±40 % d'une passe à l'autre :
le juge est le nombre d'**instructions retirées** (`proc_pid_rusage`,
indépendant de la charge), A/B de deux binaires alternés.

| Piste | Instructions (60 s) | CPU (passe calme) | Verdict |
|---|---|---|---|
| Avant | 19,65 G | 2,18 s | — |
| `removeFirst(N_HOP)` par frame → indice de lecture, compactage 1×/bloc | −0,8 % | ~−1 % | gardé (trivial) |
| `Data`/`NSMutableData`/`ORTValue` ×3 + sorties allouées par ORT, à chaque frame → tenseurs créés une fois, `run(withInputs:outputs:)` | −2,6 % | ~−3 % | gardé |
| **Les deux** | **19,00 G (−3,3 %)** | **~2,10 s** | |
| Tout ce qui n'est pas ORT (STFT, masque, OLA, copies) — mesuré en sautant `session.run` | — | **0,10 s ≈ 4-5 %** | plafond de toute optim DSP restante : **arrêté là** |
| Pont JS→Swift, côté natif : `Data(base64Encoded:)` + `[Float]`, 1 s stéréo (512 000 car.) | — | 0,10 ms / s d'audio | négligeable |
| Pont JS→Swift, côté JS : `bytesToBase64` (même code), 1 s stéréo, V8/node | — | ~1 ms / s d'audio (≈ 3 % de NSNet2) | **écarté**, pas touché au JS |

Conclusion : **~95 % du CPU est l'inférence ORT elle-même** (GRU 2×600). Les
gaspillages autour étaient réels mais petits ; ce qui reste à gagner passe par
le modèle ou l'exécution (EP CoreML/ANE, quantification), pas par le code
Swift/JS. Non mesurés ici : le coût WebKit du `postMessage` d'une chaîne de
512 Ko (IPC, pas JS), et JavaScriptCore (iPhone) vs V8 pour `btoa`.

**Audio derrière la lecture : volontairement laissé tel quel.** Après un seek
lointain, les blocs derrière la lecture sont encore traités (en dernier). Ne
plus les traiter a été codé puis **retiré le jour même** (consigne Karim : pas
de changement de comportement de la synchro qu'on vient de stabiliser, pour un
gain faible). À noter pour plus tard : un recul de ±10 s en lecture normale ne
serait pas concerné (cet audio est déjà traité et en cache) — seul l'audio
jamais traité derrière la lecture juste après un grand saut l'est.

Les deux optimisations gardées produisent une sortie **identique octet pour
octet** à l'ancienne (`bench.sh --runs=1 --dump=<f32>`, 60 s, `cmp`).

### Mécanismes anti-drift (historique, avant le 2026-09-30)

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
| `createMediaElementSource` (Web Audio) | ❌ Ne capture pas l'audio MSE sur iOS (re-testé sur iOS 18.7) |
| AVPlayer + MTAudioProcessingTap | ❌ API privée, rejet App Store |
| AVPlayer + extraction URL YouTube | ❌ Non store-compliant (scraping) |
| **WKWebView + MSE intercept + AVAudioEngine** | ✅ Validé end-to-end |

### Pourquoi Web Audio API ne marche pas sur iOS — analyse approfondie

Sur Desktop (Chrome/Firefox/Edge) et même Safari macOS, la voie évidente serait :

```
video.element → createMediaElementSource() → AudioWorklet → NSNet2 → destination
```

C'est élégant : le navigateur fait le décodage audio (Opus, AAC, peu importe), on capture le PCM en sortie, on le filtre, on renvoie. Universel par design.

**Sur iOS WKWebView, ça ne marche pas pour plusieurs raisons cumulées** :

1. **L'audio MSE est traité dans une couche système séparée du JavaScript.** Quand iOS lit un stream MSE (ex: YouTube web), le décodage Opus/AAC + l'envoi au haut-parleur passent par AVPlayer interne en C++, sans exposition au runtime JS. Apple isole pour des raisons de batterie et sécurité.

2. **`createMediaElementSource(v)` détourne le path audio**, mais l'`AudioContext` doit être en état `running` pour que le node fonctionne. L'`AudioContext` démarre toujours en `suspended` sur iOS et nécessite un **user gesture validé** pour passer en `running` via `ctx.resume()`.

3. **iOS impose des règles strictes pour la "user activation"** : un click direct sur un bouton concret est OK, mais un listener global `touchstart` (même en capture phase) ou un `setTimeout` après un click ne sont **pas** considérés comme user gesture valide. Le `ctx.resume()` retourne une promise mais le ctx reste `suspended`.

4. **Pendant qu'on essaie d'ouvrir le ctx, iOS pause le video** qui pipe son audio dans le ctx fermé. L'utilisateur voit la vidéo bloquée à 0:00 sans son. **C'est un effet de bord destructif** observé sur Instagram lors du POC.

5. **Verdict historique** (issu du POC initial sur iOS 16) : même quand le ctx est `running`, la capture du stream MSE retourne du silence (`max_rms == 0`). C'était un bug WebKit. **Re-testé sur iOS 18.7** (octobre 2025) avec `webaudio_test_done: working: false, ctx_state: suspended` — le ctx ne passe même pas en running, donc le test n'est pas concluant, mais pratiquement, **on ne peut pas démarrer le ctx de manière fiable depuis JS**.

**Conséquence** : on est forcés de **décoder l'audio nous-mêmes** côté JS, donc d'avoir un decoder par codec. YouTube utilise Opus → on a un decoder Opus WASM (~105 KB) → marche. Vimeo/Twitch/Facebook/Instagram utilisent AAC → il faut ajouter un decoder AAC.

### Couverture actuelle vs cible

| Plateforme | Mécanisme delivery | Codec | Statut Sawtunaa |
|---|---|---|---|
| YouTube (web mobile) | MSE / ManagedMediaSource | Opus | ✅ marche |
| YouTube Shorts | MSE | Opus | ✅ marche |
| Instagram Reels | **HLS natif iOS** (testé 2026-05-02) | n/a | ❌ pas interceptable |
| Vimeo | HLS natif iOS (probable) | n/a | ❌ pas interceptable |
| Twitch | HLS natif iOS | n/a | ❌ pas interceptable |
| Dailymotion | HLS natif iOS (probable) | n/a | ❌ pas interceptable |
| Facebook web | HLS natif iOS (probable) | n/a | ❌ pas interceptable |
| TikTok web | HLS natif iOS (probable) | n/a | ❌ pas interceptable |
| Sites avec `<video src=...>` direct | Lecture directe | n/a | ❌ pas hookable |

### Pourquoi HLS natif n'est pas interceptable sur iOS

Sur iOS WKWebView (et Safari iOS), `<video src="...m3u8">` ou les Player avec HLS sont gérés **par AVPlayer interne** au browser. Le manifeste m3u8 et les chunks `.ts`/`.aac` sont lus directement par le moteur natif iOS, **sans passer par MSE/MediaSource API**. Donc :

- Pas d'événement `addSourceBuffer` à hooker
- Pas de bytes audio accessibles depuis JavaScript
- Pas de `createMediaElementSource` qui marche (on l'a re-vérifié)

**Test 2026-05-02** : sur Instagram, `mse_hooks_installed` ✓ mais aucun `source_buffer_added` jamais émis pendant que la vidéo joue (currentTime avance bien). Confirmation : Instagram = HLS natif iOS.

**Conclusion pratique** : sur iOS, Sawtunaa est **fondamentalement limité aux sites qui servent du MSE/DASH** (principalement YouTube web). La plupart des autres plateformes vidéo mobile (Instagram, Twitch, Vimeo, Facebook, TikTok, Dailymotion) servent du HLS natif iOS, intouchable depuis JavaScript.

Pour les supporter, il faudrait :
- **AVPlayer Tap natif côté Swift** : APIs privées Apple → rejet App Store
- **Modifier le moteur WebKit** côté Brave iOS : très complexe, casse le diff upstream
- **Solution OS-level (audio loopback)** : pas possible sur iOS sandbox

→ **Verdict** : sur iOS, Sawtunaa restera limité à YouTube et autres sites MSE/DASH. Pas de roadmap d'extension viable identifiée à ce jour.

## Spécificités iOS WKWebView (pièges connus)

- `MediaSource` n'existe **pas** sur iOS — uniquement `ManagedMediaSource` (iOS 17+)
- `SourceBuffer` n'est **pas** un global — patcher via `Object.getPrototypeOf(instance)`
- `video.muted = true` tue l'audio session WKWebView mais **AVAudioEngine survit** (session séparée)
- **Rien d'audio à la création de l'onglet** : un `AVAudioEngine` préparé avant `setCategory(... .mixWithOthers)` prend la sortie en `.soloAmbient` et **met en pause l'audio/PiP des autres apps** (cf. § Fixes, 2026-09-21)
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
| `pageReset` au content change (init_segment hash) | `fb9adcb54f3` | Fix bug "audio de pub continue après Skip Ad" : compare les init_segments consécutifs ; si différents → contenu changé (pre-roll ad → vidéo principale, ou changement de stream) → pageReset |
| Hash plus robuste (24 premiers bytes seulement) + logs réduits | `e586bff5b7d` | Le hash incluait la queue (Track UID variable) → faux positifs à chaque seek, drop de cache injustifié. Restreint aux 24 premiers bytes (EBML header + codec params, stables). Logs : suppression `chunk_send` (JS) + `chunk_preprocess_start` (Swift) + `Avg frame` (NSNet2) ; `video_state` ralenti de 500ms à 2s. Réduction ~280 events/min |
| Drop systématique au init_segment + early-exit epoch | `3b1ef74e975` | Tentative initiale qui cassait les seeks courts dans la zone YouTube-buffered (~20-30s). Repris : voir ligne suivante. Early-exit epoch conservé. |
| Détection content change via `video.duration` | `c8c04a99fea` | Au lieu de drop le cache à chaque init_segment, on observe `video.duration` au moment du init_segment. Si la durée change >2s vs précédente → contenu différent (pub→vidéo, etc.) → pageReset. Sinon → seek dans le même contenu → cache préservé (donc seek instantané dans zone bufferisée préservé) |
| **Sortie 6 dB trop faible (`irfft`)** | 2026-08-29 | `rfft` divisait déjà par 2 pour rendre le vrai spectre (le modèle est nourri avec ça), et `irfft` appliquait quand même la normalisation canonique `1/(2N)` de vDSP — qui suppose qu'on lui repasse la sortie BRUTE du forward. **Tout l'audio iOS sortait à -6 dB de la référence**, sur toutes les vidéos, depuis toujours. Trouvé par mesure (harness golden ci-dessous), pas à l'oreille : gain optimal 2.0000, résidu après ce gain 3e-8 → l'erreur était *purement* d'échelle, le reste du portage vDSP est exact |
| **Reset GRU aveugle à 30 s → comportement macOS** | 2026-08-29 | iOS gardait le périodique 30 s du moteur standalone, que macOS a explicitement **écarté parce qu'il grésille en pleine parole** (cf. `private/docs/sawtunaa/DESKTOP.md` § Port qualité). Remplacé par le port fidèle de `Nsnet2Stream` : reset quand le silence de SORTIE dure ≥ 5 s (peak-hold, seuil 0.02, τ 2 s) + filet forcé à 5 min |
| **Stéréo de bout en bout** | 2026-08-29 | Le JS downmixait `(L+R)*0.5` et le player jouait en `channels: 1` : **la scène stéréo s'effondrait sur chaque vidéo**, ce qui s'entend comme « le son est plat », pas comme un défaut de suppression. Porté sur le modèle macOS : le masque reste calculé **une fois** sur le downmix des spectres (linéarité de la STFT ⇒ **l'inférence ne double pas**) et est **appliqué par canal**. Wire format base64 = float32 **planar** (tout L puis tout R). Effets de bord traités : `music_seconds` compte des frames et non des samples (sinon ×2), le trim de chunk copie **tous** les canaux (il ne copiait que le gauche), warmup sur 1 s planar |
| **Latence STFT rendue honnête** | 2026-08-29 | `process()` complétait sa sortie par des zéros **en tête** jusqu'à la taille du bloc — donc un silence dont la longueur dépendait du découpage (896 sur des chunks d'1 s au lieu de 512), et une sortie qui oscillait entre 47104 et 48128 pour 48000 demandés. Aligné sur `Nsnet2Stream` : on rend ce qui est prêt, la fenêtre retient toujours entre 448 et 959 samples, sortie totale == entrée totale. Vérifié par le harness (le décalage mesuré est passé de {512, 896} à 0 partout) |
| **PiP / musique des autres apps mise en pause à l'ouverture de Browther** | 2026-09-21 | Le `SawtunaaScriptHandler` est installé sur **chaque onglet, Sawtunaa allumé ou non**, et créait son lecteur à l'init : `AVAudioEngine` câblé + `prepare()` alors qu'aucune catégorie n'était encore fixée (défaut `.soloAmbient`, **non mixable**). Chaque nouvel onglet (lien ouvert depuis Mail, nouvel onglet…) interrompait donc l'audio des autres apps — une vidéo en PiP d'un autre navigateur se mettait en pause. Brave n'a pas ce handler, d'où « pas chez Brave ». Diagnostic par lecture de code (seule activité audio de Browther à la création d'un onglet), **validé sur iPhone par Karim le 2026-09-21** (le PiP continue, Sawtunaa intact). Le moteur n'est plus construit qu'au premier `start()` (1er `playAt`), **après** `setCategory(.playback, .mixWithOthers)` ; le modèle NSNet2 reste chargé à l'init (aucun audio). ⛔ Ne rien remettre d'audio (engine, `prepare()`, `setActive`) dans l'init du handler ou du lecteur |
| User mark via 3-finger touch | (en cours) | Pour signaler à l'analyzer un moment précis où l'utilisateur a observé un bug (audio haché, désync). Toucher l'écran à 3 doigts simultanés → `user_mark` event. L'analyzer affiche une section "User marks" avec les events ±3s autour de chaque mark (gap_fill, underrun, drift, etc.) |

## Parité DSP avec macOS — vérifiée depuis le 2026-08-29

Le port **C++** de NSNet2 est validé contre le moteur Python par golden vectors
depuis le 2026-07-25. Le port **Swift** refait le même STFT → GRU → iSTFT en
vDSP et n'avait **jamais** subi ce test : un défaut de fenêtrage, de
normalisation ou d'overlap-add ne crashe pas, il s'entend seulement comme
« c'est moins bon sur iPhone ».

```bash
private/tools/sawtunaa-swift-golden/run.sh   # ~5 s, sans device, sans build iOS
```

Le harness compile le **vrai** `NSNet2Processor.swift` (symlink) sur macOS via
la slice `macos-arm64` du xcframework ORT, rejoue
`private/testdata/sawtunaa-golden/*.f32` et applique les tolérances du harness
C++ — les deux verdicts sont donc comparables. Première exécution : **échec sur
les 4 cas** (l'erreur `irfft` ci-dessus). Après correction, les 4 passent avec
30 à 3000× de marge.

Le harness rejoue aussi un passage **stéréo L==R** qui doit redonner exactement
le mono (même test que le C++) : c'est ce qui garde honnête le downmix des
spectres. Ce qu'il ne couvre PAS : le chunking 1 s, les gaps comblés par du
silence, et `AVAudioEngine` — il faut une mesure end-to-end pour les chiffrer.

### Ce qui diverge encore de macOS, sciemment (audit du 2026-08-30)

Toutes les constantes DSP et tout le comportement de `Nsnet2Stream` sont
alignés : fenêtres, bins, downmix des spectres, masque par canal, `1/N`, et les
quatre seuils de reset GRU (0.02 / 2 s / 5 s / 5 min). Restent quatre écarts
**voulus ou sans effet aujourd'hui** — les connaître évite de croire à une
régression, ou d'oublier de suivre le jour où macOS bougera :

| Écart | Effet réel | Pourquoi on le garde |
|---|---|---|
| **Pas de flush/EOS** — `reset()` jette ce qui reste dans la fenêtre (≤ 959 samples d'entrée + 448 d'overlap) au lieu de le vider comme `ProcessBatch(flush=true)` | ~20 ms perdues, **uniquement au seek / pageReset** | À ces moments-là le player jette tout son cache de toute façon. Le flush C++ existe parce que sur macOS l'EOS arrive en pleine lecture continue |
| **Pas de rate adapter** (`sawtunaa_rate_adapter.cc`) | aucun | L'Opus de YouTube est **48 kHz par définition du codec**. macOS en a besoin parce que son tap voit aussi de l'AAC/MP3 44,1 k |
| **Pas de `kMaskFloor`** (plancher de gain post-inférence) | aucun — il vaut `0.f` sur macOS, donc no-op | ⚠️ **Piège futur** : si le mask floor est un jour activé côté desktop, iOS ne suivra **pas** tout seul |
| **Restitution** : macOS rend dans le pipeline (horloge et lip-sync natifs), iOS rejoue via `AVAudioEngine` avec gap-fill silence | structurel | On n'a pas le moteur sur WKWebView. C'est toute la raison d'être de ce pipeline |

Le **périmètre** diffère aussi, et ce n'est pas un écart de portage : macOS
intercepte le PCM déjà décodé dans le moteur (tous les flux), iOS intercepte
MSE en JS (YouTube seulement — cf. § couverture).

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
- `handler_create_player` — lecteur créé + modèle NSNet2 chargé (eager init) ; l'`AVAudioEngine` n'est construit qu'au premier `playAt` (cf. `engine_start`)
- `handler_page_reset` — action pageReset reçue, drop le cache (avec was_active)
- `handler_clear_chunks` — action clearChunks reçue
- `clear_chunks` — cache nettoyé (epoch incrémenté)
- `seek_to` — seek (cache préservé)

### Marquer un bug observé (geste 3 doigts)

Les bugs aléatoires (audio qui disparaît, hachure soudaine) sont durs à reproduire à la demande. Solution : **3 doigts simultanés sur l'écran** → emit un `user_mark` event dans le log avec `video_ms` et URL. L'analyzer Python affiche une section "User marks" avec les events `gap_fill`, `underrun`, `drift`, etc. dans une fenêtre ±3s autour de chaque mark.

Procédure :
1. Lancer la capture des logs (`xcrun devicectl ... | tee /tmp/sawtunaa.log`)
2. Reproduire (ou attendre) le bug
3. Au moment exact où tu l'entends → 3 doigts sur l'écran (zone non-interactive de la vidéo)
4. Stopper la capture (Ctrl+C)
5. `python3 analyze_sawtunaa_metrics.py /tmp/sawtunaa.log` — la section "User marks" zoome sur tes marks

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

## Roadmap — étendre Sawtunaa au-delà de YouTube ?

**Conclusion (2026-05-02)** : pas viable sur iOS WKWebView. Voir section "Pourquoi HLS natif n'est pas interceptable sur iOS" plus haut.

Le metric `source_buffer_added` reste actif dans le code pour cartographier les sites qui utilisent MSE (au cas où une plateforme bascule depuis HLS vers MSE/DASH dans le futur, on le saura via les logs).

Sur iOS, Sawtunaa = **YouTube only**. Sur Desktop et Android (Chromium), on peut utiliser `chrome.tabCapture` qui capture l'audio de tout onglet indépendamment du mécanisme de delivery — voir [`DESKTOP.md`](../../../private/docs/sawtunaa/DESKTOP.md) et [`ANDROID.md`](../../../private/docs/sawtunaa/ANDROID.md).

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
