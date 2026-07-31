// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_BROWSER_UI_WEBUI_SAWTUNAA_SAWTUNAA_PANEL_UI_H_
#define BRAVE_BROWSER_UI_WEBUI_SAWTUNAA_SAWTUNAA_PANEL_UI_H_

#include <memory>
#include <string_view>

#include "brave/browser/ui/webui/sawtunaa/sawtunaa_panel_handler.h"
#include "brave/components/sawtunaa/common/mojom/sawtunaa_panel.mojom.h"
#include "chrome/browser/ui/webui/top_chrome/top_chrome_web_ui_controller.h"
#include "chrome/browser/ui/webui/top_chrome/top_chrome_webui_config.h"
#include "content/public/browser/browser_context.h"
#include "content/public/browser/web_ui.h"
#include "mojo/public/cpp/bindings/pending_receiver.h"
#include "mojo/public/cpp/bindings/receiver.h"
#include "ui/webui/untrusted_web_ui_controller.h"

// Browther: WebUI controller de la popup Sawtunaa.
// Jumeau 1:1 de BasarunaaPanelUI (lui-même calqué sur VPNPanelUI) —
// UntrustedWebUIController + scheme chrome-untrusted, ce qui apporte le cycle
// de vie de bulle dont on a besoin (réouvrable indéfiniment).
//
// In the style of TopChromeWebUIController but for UntrustedWebUI instead.
class SawtunaaPanelUI : public ui::UntrustedWebUIController,
                        public sawtunaa::mojom::PanelHandlerFactory {
 public:
  using Embedder = TopChromeWebUIController::Embedder;

  explicit SawtunaaPanelUI(content::WebUI* web_ui);
  SawtunaaPanelUI(const SawtunaaPanelUI&) = delete;
  SawtunaaPanelUI& operator=(const SawtunaaPanelUI&) = delete;
  ~SawtunaaPanelUI() override;

  // Instantiates the implementor of the mojom::PanelHandlerFactory mojo
  // interface passing the pending receiver that will be internally bound.
  void BindInterface(
      mojo::PendingReceiver<sawtunaa::mojom::PanelHandlerFactory> receiver);

  // From TopChromeWebUIController.
  void set_embedder(base::WeakPtr<Embedder> embedder) { embedder_ = embedder; }
  base::WeakPtr<Embedder> embedder() { return embedder_; }

  static constexpr std::string_view GetWebUIName() { return "SawtunaaPanel"; }

 private:
  // sawtunaa::mojom::PanelHandlerFactory:
  void CreatePanelHandler(
      mojo::PendingReceiver<sawtunaa::mojom::PanelHandler> panel_receiver)
      override;

  std::unique_ptr<SawtunaaPanelHandler> panel_handler_;

  mojo::Receiver<sawtunaa::mojom::PanelHandlerFactory> panel_factory_receiver_{
      this};

  // From TopChromeWebUIController.
  base::WeakPtr<Embedder> embedder_;

  WEB_UI_CONTROLLER_TYPE_DECL();
};

class UntrustedSawtunaaPanelUIConfig
    : public DefaultTopChromeWebUIConfig<SawtunaaPanelUI> {
 public:
  UntrustedSawtunaaPanelUIConfig();
  ~UntrustedSawtunaaPanelUIConfig() override = default;

  bool IsWebUIEnabled(content::BrowserContext* browser_context) override;
  bool ShouldAutoResizeHost() override;
};

#endif  // BRAVE_BROWSER_UI_WEBUI_SAWTUNAA_SAWTUNAA_PANEL_UI_H_
