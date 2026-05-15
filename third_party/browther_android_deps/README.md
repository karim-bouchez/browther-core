# Browther Android third-party dependencies

Ce dossier héberge les AAR Maven utilisés par Browther sur Android, hors du
mécanisme Chromium `//third_party/android_deps` (qui demande de modifier un
fichier upstream non versionné dans le fork brave-core, donc non fork-friendly).

## Stratégie

Les AAR sont **téléchargés** depuis Maven Central / Sonatype par
`private/scripts/fetch-android-deps.sh` et placés dans `libs/` (gitignored).
Le fichier `BUILD.gn` de ce dossier déclare un `android_aar_prebuilt` par
dépendance, qui devient référençable en GN via
`//brave/third_party/browther_android_deps:<lib>_java`.

## Dépendances prévues

| Lib | Version | Usage | Batch |
|---|---|---|---|
| `io.sentry:sentry-android` | 7.18.x | Crash reporting Android | 2 |
| `com.posthog:posthog-android` | 3.10.x | Product analytics Android | 3 (optionnel) |

Le service C++ `BrowtherAnalyticsService` gère déjà PostHog HTTP et stats via
`SharedURLLoaderFactory` (cross-plateforme), donc PostHog-Android Java SDK est
optionnel — utile surtout pour `autocapture` UI events Android-spécifiques.
Sentry-Android est obligatoire car Crashpad ne tourne pas sur Android.

## Lifecycle

1. Modifier `private/scripts/fetch-android-deps.sh` (versions / nouveaux AAR)
2. Lancer `./private/scripts/fetch-android-deps.sh` → télécharge dans `libs/`
3. Mettre à jour `BUILD.gn` (ce dossier) pour exposer les nouvelles targets
4. Déclarer la dépendance dans le `BUILD.gn` consommateur
   (typiquement `brave/android/BUILD.gn` ou un nouveau `android_library`)
5. Rebuild OVH

`libs/` est gitignored — chaque dev / chaque CI lance `fetch-android-deps.sh`
avant le build.
