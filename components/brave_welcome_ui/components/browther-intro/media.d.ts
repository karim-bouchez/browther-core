// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

// Médias de l'introduction importés par `file-loader` (cf. `assets.ts`) : la
// config webpack commune ne connaît ni la vidéo, ni l'audio, ni les polices
// TrueType.
declare module '*.mp4' {
  const url: string
  export default url
}
declare module '*.m4a' {
  const url: string
  export default url
}
declare module '*.ttf' {
  const url: string
  export default url
}
