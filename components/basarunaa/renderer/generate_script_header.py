#!/usr/bin/env python3
"""Generate a C++ header from basarunaa_script_android.js as a raw string literal.

Pattern dupliqué de Sawtunaa (cf. components/sawtunaa/renderer/generate_script_header.py).
Wrap le .js dans une constante `kBasarunaaScriptAndroid[]` que C++ peut
directement ExecuteScript() au DidClearWindowObject.

Usage:
  generate_script_header.py <basarunaa_script_android.js> <output.h>
"""
import sys


def main():
    if len(sys.argv) != 3:
        sys.stderr.write(
            "Usage: generate_script_header.py <script.js> <output.h>\n"
        )
        return 1

    script_path, output_path = sys.argv[1], sys.argv[2]

    with open(script_path, encoding="utf-8") as f:
        script_js = f.read()

    # Raw-string delimiters maxent à 16 chars (C++ standard). `BASARUNAA_JS_BLOB`
    # = 17 → compile error. On raccourcit.
    delim = "BASARUNAA_BLOB"
    if delim in script_js:
        sys.stderr.write(
            "Error: delimiter {!r} unexpectedly present in source\n".format(delim)
        )
        return 1

    header = (
        "// Copyright (c) 2026 The Browther Authors. All rights reserved.\n"
        "// This Source Code Form is subject to the terms of the Mozilla Public\n"
        "// License, v. 2.0. If a copy of the MPL was not distributed with this file,\n"
        "// you can obtain one at https://mozilla.org/MPL/2.0/.\n"
        "//\n"
        "// AUTO-GENERATED from basarunaa_script_android.js by generate_script_header.py.\n"
        "// DO NOT EDIT. Modifier le .js à la place.\n"
        "\n"
        "#ifndef BRAVE_COMPONENTS_BASARUNAA_RENDERER_BASARUNAA_SCRIPT_ANDROID_GENERATED_H_\n"
        "#define BRAVE_COMPONENTS_BASARUNAA_RENDERER_BASARUNAA_SCRIPT_ANDROID_GENERATED_H_\n"
        "\n"
        "namespace basarunaa {\n"
        "namespace android {\n"
        "\n"
        "inline constexpr char kBasarunaaScriptAndroid[] = R\"" + delim + "(\n"
        + script_js +
        ")" + delim + "\";\n"
        "\n"
        "}  // namespace android\n"
        "}  // namespace basarunaa\n"
        "\n"
        "#endif  // BRAVE_COMPONENTS_BASARUNAA_RENDERER_BASARUNAA_SCRIPT_ANDROID_GENERATED_H_\n"
    )

    with open(output_path, "w", encoding="utf-8") as f:
        f.write(header)

    return 0


if __name__ == "__main__":
    sys.exit(main())
