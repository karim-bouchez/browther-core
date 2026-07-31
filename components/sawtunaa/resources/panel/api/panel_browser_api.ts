// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

import * as SawtunaaMojom from 'gen/brave/components/sawtunaa/common/mojom/sawtunaa_panel.mojom.m.js'

// Provide access to all the generated types.
export * from 'gen/brave/components/sawtunaa/common/mojom/sawtunaa_panel.mojom.m.js'

interface API {
  panelHandler: SawtunaaMojom.PanelHandlerInterface
}

let panelBrowserAPIInstance: API

class PanelBrowserAPI implements API {
  panelHandler = new SawtunaaMojom.PanelHandlerRemote()

  constructor() {
    const factory = SawtunaaMojom.PanelHandlerFactory.getRemote()
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
