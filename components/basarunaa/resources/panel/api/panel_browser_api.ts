// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

import * as BasarunaaMojom from 'gen/brave/components/basarunaa/common/mojom/basarunaa.mojom.m.js'

// Provide access to all the generated types.
export * from 'gen/brave/components/basarunaa/common/mojom/basarunaa.mojom.m.js'

interface API {
  panelHandler: BasarunaaMojom.PanelHandlerInterface
}

let panelBrowserAPIInstance: API

class PanelBrowserAPI implements API {
  panelHandler = new BasarunaaMojom.PanelHandlerRemote()

  constructor() {
    const factory = BasarunaaMojom.PanelHandlerFactory.getRemote()
    factory.createPanelHandler(
      this.panelHandler.$.bindNewPipeAndPassReceiver())
  }
}

export default function getPanelBrowserAPI(): API {
  if (!panelBrowserAPIInstance) {
    panelBrowserAPIInstance = new PanelBrowserAPI()
  }
  return panelBrowserAPIInstance
}
