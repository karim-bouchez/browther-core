# Browther

**Browther** is a privacy-focused web browser by **dev&din**, built on top of
[Brave Core](https://github.com/brave/brave-core) (which itself is built on
Chromium). It targets the Muslim community with two distinguishing built-in
features:

- **Sawtunaa** — removes background music from web audio in real time (YouTube
  and more), no extension required.
- **Basarunaa** — blurs out people in images and videos by gender (and full-frame
  blur on NSFW content), with on-device ML.

> The name "Browther" is a contraction of *browser* and *brother*.

## Status

Public beta. macOS builds (Apple Silicon) are distributed signed and notarized
from [browther.devndin.com/download](https://browther.devndin.com/download).
Windows, iOS, and Android are in progress.

## Project structure

This repository (`browther-core`) is the **public**, MPL-2.0-licensed fork of
`brave/brave-core` that builds Browther for **desktop, iOS, and Android**.
Modified upstream files stay public here, as required by MPL-2.0.

The rest of the project lives in private repos:

- `browther-private` — proprietary code: assets (icons, logos, NTP backgrounds),
  Sawtunaa and Basarunaa ML pipelines, build/release scripts, infrastructure
  configs.
- `browther-website` — the marketing site
  [browther.devndin.com](https://browther.devndin.com) (Next.js).

## Build (Browther / macOS)

Build is driven from the parent workspace (not from this directory). After
cloning, the high-level recipe is:

```bash
# from the parent workspace `browther/desktop/`
npm install
npm run init                                     # fetches Chromium (~60 GB)
bash private/scripts/post-init-patches.sh        # Browther-specific patches
pnpm build Release --target=create_dist_mac      # produces Browther.app + DMG
```

Building for Windows / iOS / Android uses the same workspace with platform
flags (`--target_os=android`, `--target_os=ios`, etc.). The orchestrator
scripts that handle the build, signing, and distribution are private — they
live in `browther-private/scripts/`.

If you only want to reproduce a Browther desktop binary from this fork's
sources, the build is the standard Brave Core build with our patches applied;
follow the upstream
[Brave Core build instructions](https://github.com/brave/brave-core/blob/master/docs/README.md)
and replace upstream `brave-core` with this fork.

## Upstream

We sync from [brave/brave-core](https://github.com/brave/brave-core) `master`
at least once a month and try to keep our modifications fork-friendly
(separate files when possible, minimal inline patches otherwise).

## License

MPL-2.0, like the upstream `brave-core` it is forked from.

## Links

- Website & downloads: [browther.devndin.com](https://browther.devndin.com)
- Privacy: [browther.devndin.com/privacy](https://browther.devndin.com/privacy)
- Support: [browther.devndin.com/support](https://browther.devndin.com/support)
- Issues for this fork: [github.com/karim-bouchez/browther-core/issues](https://github.com/karim-bouchez/browther-core/issues)
- Contact: <karim@devndin.com>
