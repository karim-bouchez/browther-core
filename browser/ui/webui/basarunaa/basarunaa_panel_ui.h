// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_BROWSER_UI_WEBUI_BASARUNAA_BASARUNAA_PANEL_UI_H_
#define BRAVE_BROWSER_UI_WEBUI_BASARUNAA_BASARUNAA_PANEL_UI_H_

#include <memory>
#include <string>
#include <string_view>

#include "brave/browser/ui/webui/basarunaa/basarunaa_panel_handler.h"
#include "brave/components/basarunaa/common/mojom/basarunaa.mojom.h"
#include "chrome/browser/ui/webui/top_chrome/top_chrome_web_ui_controller.h"
#include "chrome/browser/ui/webui/top_chrome/top_chrome_webui_config.h"
#include "content/public/browser/browser_context.h"
#include "content/public/browser/web_ui.h"
#include "mojo/public/cpp/bindings/pending_receiver.h"
#include "mojo/public/cpp/bindings/receiver.h"
#include "ui/webui/untrusted_web_ui_controller.h"

// Browther: WebUI controller for the Basarunaa panel bubble.
// Mirrors VPNPanelUI 1:1 (UntrustedWebUIController + chrome-untrusted scheme)
// to reproduce the bubble lifecycle behaviour we need.
//
// In the style of TopChromeWebUIController but for UntrustedWebUI instead.
class BasarunaaPanelUI : public ui::UntrustedWebUIController,
                        public basarunaa::mojom::PanelHandlerFactory {
 public:
  using Embedder = TopChromeWebUIController::Embedder;

  explicit BasarunaaPanelUI(content::WebUI* web_ui);
  BasarunaaPanelUI(const BasarunaaPanelUI&) = delete;
  BasarunaaPanelUI& operator=(const BasarunaaPanelUI&) = delete;
  ~BasarunaaPanelUI() override;

  // Instantiates the implementor of the mojom::PanelHandlerFactory mojo
  // interface passing the pending receiver that will be internally bound.
  void BindInterface(
      mojo::PendingReceiver<basarunaa::mojom::PanelHandlerFactory> receiver);

  // From TopChromeWebUIController.
  void set_embedder(base::WeakPtr<Embedder> embedder) { embedder_ = embedder; }
  base::WeakPtr<Embedder> embedder() { return embedder_; }

  static constexpr std::string_view GetWebUIName() { return "BasarunaaPanel"; }

 private:
  // basarunaa::mojom::PanelHandlerFactory:
  void CreatePanelHandler(
      mojo::PendingReceiver<basarunaa::mojom::PanelHandler> panel_receiver)
      override;

  std::unique_ptr<BasarunaaPanelHandler> panel_handler_;

  mojo::Receiver<basarunaa::mojom::PanelHandlerFactory>
      panel_factory_receiver_{this};

  // From TopChromeWebUIController.
  base::WeakPtr<Embedder> embedder_;

  WEB_UI_CONTROLLER_TYPE_DECL();
};

class UntrustedBasarunaaPanelUIConfig
    : public DefaultTopChromeWebUIConfig<BasarunaaPanelUI> {
 public:
  UntrustedBasarunaaPanelUIConfig();
  ~UntrustedBasarunaaPanelUIConfig() override = default;

  bool IsWebUIEnabled(content::BrowserContext* browser_context) override;
  bool ShouldAutoResizeHost() override;
};

#endif  // BRAVE_BROWSER_UI_WEBUI_BASARUNAA_BASARUNAA_PANEL_UI_H_
