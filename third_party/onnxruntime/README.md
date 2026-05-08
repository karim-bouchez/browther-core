# ONNX Runtime — macOS arm64 prebuilt

Phase 3.1.5 — Étape 1 (M1.1) du plan de migration Basarunaa native (cf. `private/extensions/basarunaa/NATIVE_BROWSER.md`).

## Contenu

- `lib/libonnxruntime.1.17.3.dylib` — release officielle Microsoft macOS arm64 (24 MB)
- `lib/libonnxruntime.dylib` → symlink vers la précédente
- `include/*.h` — headers du C/C++ API + CoreML/CPU EP factories

## Source

Téléchargé depuis :
```
https://github.com/microsoft/onnxruntime/releases/download/v1.17.3/onnxruntime-osx-arm64-1.17.3.tgz
```

## Mise à jour

```bash
TMP=$(mktemp -d)
curl -sL -o "$TMP/ort.tgz" \
  "https://github.com/microsoft/onnxruntime/releases/download/vX.Y.Z/onnxruntime-osx-arm64-X.Y.Z.tgz"
tar -xzf "$TMP/ort.tgz" -C "$TMP"
SRC="$TMP/onnxruntime-osx-arm64-X.Y.Z"
cp "$SRC"/lib/libonnxruntime.X.Y.Z.dylib lib/
ln -sf libonnxruntime.X.Y.Z.dylib lib/libonnxruntime.dylib
cp "$SRC"/include/{coreml_provider_factory,cpu_provider_factory,onnxruntime_c_api,onnxruntime_cxx_api,onnxruntime_cxx_inline,onnxruntime_float16,onnxruntime_run_options_config_keys,onnxruntime_session_options_config_keys,provider_options}.h include/
```

Penser à mettre à jour `BUILD.gn` (le `copy()` source/output et le `ldflags` qui réfèrent la version exacte) et à supprimer l'ancien `.dylib`.

## Pourquoi pas le static archive du xcframework iOS ?

Le xcframework iOS (`brave/ios/third_party/OnnxRuntime/onnxruntime.xcframework/macos-arm64_x86_64/`) contient déjà un slice macOS arm64. Tentative de l'utiliser : lld segfaulte en boucle infinie dans `ObjCMethListSection::setUp()` lors du link de `libchrome_dll.dylib`. Vraisemblablement à cause de métadonnées ObjC method-list cuites pour la distribution iOS qui ne plaisent pas à `lld --strict-auto-link`.

La dylib séparée bypasse ce code path (les dylibs ne passent pas par le setup d'archive ObjC à link-time).

À termes (cf. `private/docs/TODO.md` § Phase 3.1.5) on devrait soit :

- promouvoir le xcframework au top-level `desktop/src/brave/third_party/onnxruntime_xcframework/` et trouver un workaround lld (ou rebuild from source un xcframework propre)
- ou conserver la dylib séparée et déduplique avec iOS via DEPS
