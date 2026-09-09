#!/usr/bin/env python3
# Copyright (c) 2026 dev&din. All rights reserved.
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0.
#
# Browther — pré-signature : préparer le .app unsigned avant sign_chrome.py.
#
# 1) Patch install_names libonnxruntime
#    libonnxruntime.1.17.3.dylib (Microsoft pre-built, install_name `@rpath/`)
#    est bundlée dans Frameworks/Browther Framework.framework/.../Libraries/.
#    Les binaires consommateurs (launcher `MacOS/Browther` + `Browther
#    Framework`) n'ont pas de LC_RPATH qui pointe vers Libraries/ → dyld crash.
#    Fix : install_name_tool -change @rpath/... → @loader_path/... (dylib
#    symlinkée dans MacOS/ pour le launcher).
#
# 2) Re-sign Developer ID du BrowtherUpdater.app
#    Brave livre BrowtherUpdater.app (Keystone Google) pré-signé par Brave
#    (Team KL8N8XSYF4). post-build.sh fait codesign --force --deep --sign -
#    qui écrase tout en ad-hoc. Sign_chrome.py ne re-signe PAS le contenu de
#    BrowtherUpdater.app (considéré pré-signé). Résultat : 3 binaires
#    (BraveSoftwareUpdate, ksinstall, ksadmin) sont en ad-hoc, et Apple
#    refuse la notarisation. On les re-signe ici avec notre Developer ID.
#
# Appelé par l'action GN `:patch_onnx_install_names` dans build/mac/BUILD.gn
# AVANT que sign_chrome.py ne signe l'app. Idempotent.

import argparse
import os
import pathlib
import subprocess
import sys


DYLIB = "libonnxruntime.1.17.3.dylib"
DEVELOPER_ID = "Developer ID Application: Chaima Addou (MWBMAMYDUD)"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", required=True,
                        help="Chemin vers Browther.app (unsigned)")
    parser.add_argument("--stamp", required=True,
                        help="Fichier stamp à toucher en sortie")
    args = parser.parse_args()

    app = pathlib.Path(args.app)
    if not app.is_dir():
        print(f"❌ {app} introuvable", file=sys.stderr)
        return 1

    macos_dir = app / "Contents" / "MacOS"
    launcher = macos_dir / "Browther"
    fw_versions = app / "Contents" / "Frameworks" / "Browther Framework.framework" / "Versions" / "Current"
    fw_binary = fw_versions / "Browther Framework"
    fw_lib = fw_versions / "Libraries" / DYLIB

    for path in (launcher, fw_binary, fw_lib):
        if not path.exists():
            print(f"❌ Composant introuvable : {path}", file=sys.stderr)
            return 1

    # 1) Symlink relatif de la dylib dans MacOS/ pour @loader_path du launcher
    link = macos_dir / DYLIB
    target = pathlib.PurePosixPath("..") / "Frameworks" / "Browther Framework.framework" / "Versions" / "Current" / "Libraries" / DYLIB
    if link.is_symlink():
        if os.readlink(link) != str(target):
            link.unlink()
            os.symlink(target, link)
    elif not link.exists():
        os.symlink(target, link)

    # 2) Patch install_names (idempotent — -change no-op si déjà bon path)
    #
    # ⚠️ LES HELPERS DU FRAMEWORK EN FONT PARTIE (ajouté 2026-09-09).
    #
    # `all_dependent_configs` (brave/third_party/onnxruntime/BUILD.gn) propage le
    # ldflag ORT à TOUS les dépendants transitifs, y compris de petits
    # exécutables qui n'utilisent jamais ORT. En Component ça passe (rpaths
    # larges), mais en Release aucun LC_RPATH n'est émis → le helper meurt au
    # lancement. Cas vécu le 2026-07-20 : `web_app_shortcut_copier` mort-né,
    # donc impossible d'installer une PWA.
    #
    # Ce trou-là avait été rebouché dans `private/scripts/patch-onnx-install-names.sh`
    # (post-build) mais PAS ici — et c'est ICI que ça compte : ce script tourne
    # avant `sign_chrome.py`, donc c'est lui qui décide de ce qu'il y a dans le
    # DMG distribué. Résultat, vérifié le 2026-09-09 sur les DMG 2026.8.23
    # (publié) et 2026.9.8 : le helper y pointait encore `@rpath/…` alors que
    # l'app locale, elle, était réparée — le bug était donc invisible pour qui
    # teste depuis `install-release.sh`.
    #
    # Détection GÉNÉRIQUE (comme le .sh) : tout exécutable de Helpers/ qui
    # référence encore @rpath/<dylib>, pour ne pas retomber dans le piège si un
    # autre helper hérite du ldflag un jour.
    helpers = []
    helpers_dir = fw_versions / "Helpers"
    if helpers_dir.is_dir():
        for entry in sorted(helpers_dir.iterdir()):
            if not entry.is_file() or not os.access(entry, os.X_OK):
                continue
            otool = subprocess.run(
                ["otool", "-L", str(entry)],
                check=False,
                capture_output=True,
                text=True,
            )
            if f"@rpath/{DYLIB}" in otool.stdout:
                helpers.append(entry)

    patches = [
        (launcher, f"@loader_path/{DYLIB}"),
        (fw_binary, f"@loader_path/Libraries/{DYLIB}"),
    ]
    # Helpers/ est un cran plus bas que le framework → un `..` de plus.
    patches += [(h, f"@loader_path/../Libraries/{DYLIB}") for h in helpers]

    for binary, new_ref in patches:
        binary.chmod(0o755)
        subprocess.run(
            ["install_name_tool", "-change", f"@rpath/{DYLIB}", new_ref, str(binary)],
            check=False,
            stderr=subprocess.DEVNULL,
        )
    for h in helpers:
        print(f"  ↳ helper patché : {h.name}")

    # 3) Re-sign les binaires tiers qui restent à leur signature d'origine
    # après sign_chrome.py. Le launcher Browther a `library-validation`
    # activé (hardened runtime), qui exige que toute dylib chargée soit
    # signée par notre Team (MWBMAMYDUD) ou par Apple. Sans ça, dyld
    # refuse de charger et l'app crashe au lancement (sans message visible).
    #
    # Concrètement :
    #   - libonnxruntime.1.17.3.dylib : pre-built Microsoft, signée par
    #     Microsoft Corporation (UBF8T346G9). sign_chrome.py ne la connaît
    #     pas → reste signée Microsoft → library-validation refuse.
    #   - BrowtherUpdater.app + helpers : pré-signés Brave (KL8N8XSYF4).
    #     Apple notarytool refuse car pas notre Team.
    #
    # Inner-most first pour que les signatures parent incluent les hashes.
    targets = []

    fw_versions = app / "Contents" / "Frameworks" / "Browther Framework.framework" / "Versions" / "Current"
    onnx_lib = fw_versions / "Libraries" / DYLIB
    if onnx_lib.exists():
        targets.append(onnx_lib)

    updater_root = fw_versions / "Helpers" / "BrowtherUpdater.app"
    if updater_root.exists():
        bundle = updater_root / "Contents" / "Helpers" / "BraveSoftwareUpdate.bundle"
        targets.extend([
            bundle / "Contents" / "Helpers" / "ksinstall",
            bundle / "Contents" / "Helpers" / "ksadmin",
            bundle / "Contents" / "MacOS" / "BraveSoftwareUpdate",
            bundle,
            updater_root / "Contents" / "Helpers" / "launcher",
            updater_root,
        ])

    if targets:
        for target in targets:
            if not target.exists():
                continue
            result = subprocess.run(
                ["codesign", "--force", "--sign", DEVELOPER_ID,
                 "--timestamp", "--options", "runtime",
                 str(target)],
                capture_output=True,
                text=True,
            )
            if result.returncode != 0:
                print(f"❌ codesign failed on {target}", file=sys.stderr)
                print(f"   stderr: {result.stderr}", file=sys.stderr)
                return result.returncode

    pathlib.Path(args.stamp).touch()
    return 0


if __name__ == "__main__":
    sys.exit(main())
