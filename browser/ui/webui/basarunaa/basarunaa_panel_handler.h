// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_BROWSER_UI_WEBUI_BASARUNAA_BASARUNAA_PANEL_HANDLER_H_
#define BRAVE_BROWSER_UI_WEBUI_BASARUNAA_BASARUNAA_PANEL_HANDLER_H_

#include <string>

#include "base/memory/raw_ptr.h"
#include "brave/components/basarunaa/common/mojom/basarunaa.mojom.h"
#include "chrome/browser/profiles/profile.h"
#include "mojo/public/cpp/bindings/pending_receiver.h"
#include "mojo/public/cpp/bindings/receiver.h"

class BasarunaaPanelUI;

// Browther: minimal mirror of VPNPanelHandler. Kept around because the VPN
// `ShowUI` / `CloseUI` handshake (with the embedder) is what unblocks the
// bubble visibility on the second open. No business logic for now.
class BasarunaaPanelHandler : public basarunaa::mojom::PanelHandler {
 public:
  BasarunaaPanelHandler(
      mojo::PendingReceiver<basarunaa::mojom::PanelHandler> receiver,
      BasarunaaPanelUI* panel_controller,
      Profile* profile);
  BasarunaaPanelHandler(const BasarunaaPanelHandler&) = delete;
  BasarunaaPanelHandler& operator=(const BasarunaaPanelHandler&) = delete;
  ~BasarunaaPanelHandler() override;

  // basarunaa::mojom::PanelHandler:
  void ShowUI() override;
  void CloseUI() override;
  void GetEnabled(GetEnabledCallback callback) override;
  void SetEnabled(bool enabled) override;
  void GetMode(GetModeCallback callback) override;
  void SetMode(const std::string& mode) override;

 private:
  mojo::Receiver<basarunaa::mojom::PanelHandler> receiver_;
  raw_ptr<BasarunaaPanelUI> const panel_controller_;
  raw_ptr<Profile> profile_;
};

#endif  // BRAVE_BROWSER_UI_WEBUI_BASARUNAA_BASARUNAA_PANEL_HANDLER_H_
