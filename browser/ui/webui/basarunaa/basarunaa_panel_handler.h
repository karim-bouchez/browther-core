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

class BrowserWindowInterface;
class BasarunaaPanelUI;

namespace content {
class WebContents;
}

// Browther: minimal mirror of VPNPanelHandler. Kept around because the VPN
// `ShowUI` / `CloseUI` handshake (with the embedder) is what unblocks the
// bubble visibility on the second open.
//
// ⚠️ Le handler NE MÉMORISE PAS la fenêtre : la WebContents du panel est mise
// en cache et réutilisée d'une ouverture à l'autre (le handler n'est donc
// construit qu'une fois), et elle peut être rattachée à une autre fenêtre
// entre-temps. Ce qui dépend de la fenêtre est résolu à chaque appel.
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
  void GetProtectedContent(GetProtectedContentCallback callback) override;
  void GetReportSiteState(GetReportSiteStateCallback callback) override;
  void ReportSite(ReportSiteCallback callback) override;
  void GetMode(GetModeCallback callback) override;
  void SetMode(const std::string& mode) override;
  void GetCensorEyes(GetCensorEyesCallback callback) override;
  void SetCensorEyes(bool enabled) override;
  void GetNsfwEnabled(GetNsfwEnabledCallback callback) override;
  void SetNsfwEnabled(bool enabled) override;
  void GetSliders(GetSlidersCallback callback) override;
  void SetConfBody(double value) override;
  void SetGenderCertainty(double value) override;
  void SetSentinelConf(double value) override;
  void SetMinSkeleton(double value) override;
  void SetNsfwConf(double value) override;
  void SetNudenetConf(double value) override;
  void GetDevSettings(GetDevSettingsCallback callback) override;
  void SetDebugMode(const std::string& mode) override;
  void SetCaptureMode(bool enabled) override;
  void SetBlurEnabled(bool enabled) override;
  void SetCollectEnabled(bool enabled) override;

 private:
  // Fenêtre qui héberge la bulle, ou nullptr. À rappeler à chaque usage.
  BrowserWindowInterface* GetBrowserWindowInterface();
  // Onglet actif de la fenêtre qui porte ce panel, ou null.
  content::WebContents* GetActiveWebContents();

  mojo::Receiver<basarunaa::mojom::PanelHandler> receiver_;
  raw_ptr<BasarunaaPanelUI> const panel_controller_;
  raw_ptr<Profile> profile_;
};

#endif  // BRAVE_BROWSER_UI_WEBUI_BASARUNAA_BASARUNAA_PANEL_HANDLER_H_
