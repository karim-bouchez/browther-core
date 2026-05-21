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
    for binary, new_ref in (
        (launcher, f"@loader_path/{DYLIB}"),
        (fw_binary, f"@loader_path/Libraries/{DYLIB}"),
    ):
        binary.chmod(0o755)
        subprocess.run(
            ["install_name_tool", "-change", f"@rpath/{DYLIB}", new_ref, str(binary)],
            check=False,
            stderr=subprocess.DEVNULL,
        )

    # 3) Re-sign le contenu du BrowtherUpdater.app avec notre Developer ID
    # (sinon Apple refuse la notarisation — sign_chrome.py ne touche pas
    # ce sous-bundle). Inner-most first pour que les signatures parent
    # incluent les hashes corrects.
    updater_root = (app / "Contents" / "Frameworks"
                    / "Browther Framework.framework" / "Versions" / "Current"
                    / "Helpers" / "BrowtherUpdater.app")
    if updater_root.exists():
        bundle = updater_root / "Contents" / "Helpers" / "BraveSoftwareUpdate.bundle"
        targets = [
            bundle / "Contents" / "Helpers" / "ksinstall",
            bundle / "Contents" / "Helpers" / "ksadmin",
            bundle / "Contents" / "MacOS" / "BraveSoftwareUpdate",
            bundle,
            updater_root / "Contents" / "Helpers" / "launcher",
            updater_root,
        ]
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
