# Copyright (c) 2025 The Brave Authors. All rights reserved.
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this file,
# You can obtain one at https://mozilla.org/MPL/2.0/.

# Upstream's signing and PKG/DMG/ZIP generation logic lets embedders hook into
# the process by providing a module named `signing.internal_config` with a class
# named `InternalCodeSignConfig`. This file provides such code to apply
# customizations that are necessary for Brave. It collaborates with the similar
# hook `internal_invoker.py` in this directory.

import os

from signing.chromium_config import ChromiumCodeSignConfig
from signing.model import Distribution, NotarizeAndStapleLevel

BRAVE_CHANNEL = os.environ.get('BRAVE_CHANNEL')


class InternalCodeSignConfig(ChromiumCodeSignConfig):

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.is_in_sign_chrome = False

    @staticmethod
    def is_chrome_branded():
        # We want to inherit most of upstream's behavior.
        return True

    @property
    def distributions(self):
        # Browther: DMG-only. PKG needs Developer ID Installer cert (separate
        # purchase). ZIP is redundant with DMG for end-user distribution.
        return [
            Distribution(channel=BRAVE_CHANNEL,
                         package_as_dmg=True,
                         package_as_pkg=False,
                         package_as_zip=False)
        ]

    @property
    def provisioning_profile_basename(self):
        return self.invoker.args.provisioning_profile_basename

    @property
    def run_spctl_assess(self):
        # Browther: désactivé. Brave's logique d'origine activait spctl assess
        # dans validate_app() (chrome/installer/mac/signing/signing.py:143)
        # quand notarize == STAPLE, MAIS validate_app tourne AVANT que la
        # notarisation Apple soit effectuée dans le pipeline. Sur macOS moderne
        # (Catalina+), spctl --assess refuse un Developer ID non-notarisé
        # → "rejected, source=Unnotarized Developer ID" → CalledProcessError
        # → bug NameError car `subprocess` n'est pas importé dans signing.py.
        #
        # La vraie validation spctl --assess (post-staple) est faite par notre
        # script private/scripts/sign-release.sh sur le DMG produit.
        return False

    @property
    def app_dir(self):
        app_dir_basename = super().app_dir
        if self.invoker.args.universal and self.is_in_sign_chrome:
            return 'universal/' + app_dir_basename
        return app_dir_basename
