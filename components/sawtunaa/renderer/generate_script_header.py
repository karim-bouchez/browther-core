#!/usr/bin/env python3
"""Generate a C++ header from the Sawtunaa JS bundles as a raw string literal.

Concatène le bundle Opus decoder (définit `OpusDecoderLib` global) et le
SawtunaaScript principal dans une seule constante `kSawtunaaScript[]`.
Pattern reproduit du chargement iOS (SawtunaaScriptHandler.swift) :
    script = opusSource + "\n" + script

Les .js restent sources de vérité (éditables, lint, etc.). Cette action GN
wrap le contenu dans `inline constexpr char kSawtunaaScript[]` que C++
peut directement ExecuteScript() au DidClearWindowObject.

Usage:
  generate_script_header.py <opus.js> <sawtunaa.js> <output.h>
"""
import sys


def main():
    if len(sys.argv) != 4:
        sys.stderr.write(
            "Usage: generate_script_header.py <opus.js> <sawtunaa.js> <output.h>\n"
        )
        return 1

    opus_path, sawtunaa_path, output_path = sys.argv[1], sys.argv[2], sys.argv[3]

    with open(opus_path, encoding="utf-8") as f:
        opus_js = f.read()
    with open(sawtunaa_path, encoding="utf-8") as f:
        sawtunaa_js = f.read()

    # Délimiteur raw-string improbable de matcher dans le JS.
    delim = "SAWTUNAA_JS_BLOB"
    for label, blob in (("opus", opus_js), ("sawtunaa", sawtunaa_js)):
        if delim in blob:
            sys.stderr.write(
                "Error: delimiter {!r} unexpectedly present in {} source\n".format(
                    delim, label
                )
            )
            return 1

    combined = (
        "// === SawtunaaOpusDecoderBundle.js (defines OpusDecoderLib global) ===\n"
        + opus_js
        + "\n// === SawtunaaScript.js (MSE intercept + ML pipeline) ===\n"
        + sawtunaa_js
    )

    header = (
        "// Copyright (c) 2026 The Browther Authors. All rights reserved.\n"
        "// This Source Code Form is subject to the terms of the Mozilla Public\n"
        "// License, v. 2.0. If a copy of the MPL was not distributed with this file,\n"
        "// you can obtain one at https://mozilla.org/MPL/2.0/.\n"
        "//\n"
        "// AUTO-GENERATED from sawtunaa_opus_decoder_bundle.js + sawtunaa_script.js\n"
        "// by generate_script_header.py. DO NOT EDIT. Modifier les .js à la place.\n"
        "\n"
        "#ifndef BRAVE_COMPONENTS_SAWTUNAA_RENDERER_SAWTUNAA_SCRIPT_GENERATED_H_\n"
        "#define BRAVE_COMPONENTS_SAWTUNAA_RENDERER_SAWTUNAA_SCRIPT_GENERATED_H_\n"
        "\n"
        "namespace sawtunaa {\n"
        "\n"
        "inline constexpr char kSawtunaaScript[] = R\"" + delim + "(\n"
        + combined +
        ")" + delim + "\";\n"
        "\n"
        "}  // namespace sawtunaa\n"
        "\n"
        "#endif  // BRAVE_COMPONENTS_SAWTUNAA_RENDERER_SAWTUNAA_SCRIPT_GENERATED_H_\n"
    )

    with open(output_path, "w", encoding="utf-8") as f:
        f.write(header)

    return 0


if __name__ == "__main__":
    sys.exit(main())
