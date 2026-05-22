#!/usr/bin/env python3
"""Generate a C++ header from sawtunaa_script.js as a raw string literal.

Le .js reste la source de vérité (éditable, lint, etc.). Cette action GN
wrap le contenu dans `inline constexpr char kSawtunaaScript[]` que C++
peut directement ExecuteScript().

Usage:
  generate_script_header.py <input.js> <output.h>
"""
import sys


def main():
    if len(sys.argv) != 3:
        sys.stderr.write("Usage: generate_script_header.py <input.js> <output.h>\n")
        return 1

    input_path, output_path = sys.argv[1], sys.argv[2]

    with open(input_path, encoding="utf-8") as f:
        js = f.read()

    # Délimiteur raw-string improbable de matcher dans le JS.
    delim = "SAWTUNAA_JS_BLOB"
    if delim in js:
        sys.stderr.write(
            "Error: delimiter {!r} unexpectedly present in JS source\n".format(delim)
        )
        return 1

    header = (
        "// Copyright (c) 2026 The Browther Authors. All rights reserved.\n"
        "// This Source Code Form is subject to the terms of the Mozilla Public\n"
        "// License, v. 2.0. If a copy of the MPL was not distributed with this file,\n"
        "// you can obtain one at https://mozilla.org/MPL/2.0/.\n"
        "//\n"
        "// AUTO-GENERATED from sawtunaa_script.js by generate_script_header.py.\n"
        "// DO NOT EDIT. Modifier sawtunaa_script.js à la place.\n"
        "\n"
        "#ifndef BRAVE_COMPONENTS_SAWTUNAA_RENDERER_SAWTUNAA_SCRIPT_GENERATED_H_\n"
        "#define BRAVE_COMPONENTS_SAWTUNAA_RENDERER_SAWTUNAA_SCRIPT_GENERATED_H_\n"
        "\n"
        "namespace sawtunaa {\n"
        "\n"
        "inline constexpr char kSawtunaaScript[] = R\"" + delim + "(\n"
        + js +
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
