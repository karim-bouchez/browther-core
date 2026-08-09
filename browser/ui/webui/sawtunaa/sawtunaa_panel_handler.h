// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_BROWSER_UI_WEBUI_SAWTUNAA_SAWTUNAA_PANEL_HANDLER_H_
#define BRAVE_BROWSER_UI_WEBUI_SAWTUNAA_SAWTUNAA_PANEL_HANDLER_H_

#include "base/memory/raw_ptr.h"
#include "brave/components/sawtunaa/common/mojom/sawtunaa_panel.mojom.h"
#include "chrome/browser/profiles/profile.h"
#include "mojo/public/cpp/bindings/pending_receiver.h"
#include "mojo/public/cpp/bindings/receiver.h"

namespace content {
class WebContents;
}  // namespace content

class BrowserWindowInterface;
class SawtunaaPanelUI;

// Browther: jumeau de BasarunaaPanelHandler. Le handshake `ShowUI` / `CloseUI`
// avec l'embedder est ce qui débloque la visibilité de la bulle aux
// réouvertures — ne pas le retirer (cf. sawtunaa_panel.mojom).
//
// ⚠️ Le handler NE MÉMORISE PAS la fenêtre ni l'onglet : la WebContents du
// panel est mise en cache et réutilisée d'une ouverture à l'autre (c'est même
// pour ça que le handler n'est construit qu'une fois), et elle peut être
// rattachée à une autre fenêtre entre-temps. Tout ce qui dépend de la fenêtre
// est donc résolu À CHAQUE APPEL via `webui::GetBrowserWindowInterface`.
class SawtunaaPanelHandler : public sawtunaa::mojom::PanelHandler {
 public:
  SawtunaaPanelHandler(
      mojo::PendingReceiver<sawtunaa::mojom::PanelHandler> receiver,
      SawtunaaPanelUI* panel_controller,
      Profile* profile);
  SawtunaaPanelHandler(const SawtunaaPanelHandler&) = delete;
  SawtunaaPanelHandler& operator=(const SawtunaaPanelHandler&) = delete;
  ~SawtunaaPanelHandler() override;

  // sawtunaa::mojom::PanelHandler:
  void ShowUI() override;
  void CloseUI() override;
  void GetState(GetStateCallback callback) override;
  void SetEnabled(bool enabled) override;
  void ReloadActiveTab() override;
  void OpenSawtunaaAppPage() override;
  void ReportSite(ReportSiteCallback callback) override;

 private:
  // Fenêtre qui héberge la bulle, ou nullptr. À rappeler à chaque usage.
  BrowserWindowInterface* GetBrowserWindowInterface();
  // Onglet actif de cette fenêtre, ou nullptr.
  content::WebContents* GetActiveWebContents();

  // « Un média joue dans l'onglet, le toggle ON n'aura d'effet qu'au reload ».
  bool ShouldShowReloadHint();
  // Cause du badge ambre pour l'onglet actif, déjà gatée.
  sawtunaa::mojom::ProtectedContentState GetProtectedContentState();

  mojo::Receiver<sawtunaa::mojom::PanelHandler> receiver_;
  raw_ptr<SawtunaaPanelUI> const panel_controller_;
  raw_ptr<Profile> profile_;
};

#endif  // BRAVE_BROWSER_UI_WEBUI_SAWTUNAA_SAWTUNAA_PANEL_HANDLER_H_
