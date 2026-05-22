// Copyright (c) 2026 The Browther Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/components/sawtunaa/renderer/sawtunaa_render_frame_observer.h"

#include "base/strings/strcat.h"
#include "brave/components/sawtunaa/renderer/sawtunaa_js_handler.h"
#include "content/public/renderer/render_frame.h"
#include "third_party/blink/public/platform/browser_interface_broker_proxy.h"
#include "third_party/blink/public/platform/web_string.h"
#include "third_party/blink/public/web/web_document.h"
#include "third_party/blink/public/web/web_local_frame.h"
#include "third_party/blink/public/web/web_script_source.h"

namespace sawtunaa {

SawtunaaRenderFrameObserver::SawtunaaRenderFrameObserver(
    content::RenderFrame* render_frame)
    : content::RenderFrameObserver(render_frame) {}

SawtunaaRenderFrameObserver::~SawtunaaRenderFrameObserver() = default;

void SawtunaaRenderFrameObserver::EnsureRemote() {
  if (sawtunaa_.is_bound()) {
    return;
  }
  auto* render_frame = SawtunaaRenderFrameObserver::render_frame();
  if (!render_frame) {
    return;
  }
  render_frame->GetBrowserInterfaceBroker().GetInterface(
      sawtunaa_.BindNewPipeAndPassReceiver());
}

void SawtunaaRenderFrameObserver::DidCommitProvisionalLoad(
    ui::PageTransition transition) {
  auto* render_frame = SawtunaaRenderFrameObserver::render_frame();
  if (!render_frame || !render_frame->IsMainFrame()) {
    return;
  }
  EnsureRemote();
  if (!sawtunaa_.is_bound()) {
    return;
  }
  // Ping C++ — gardé en parallèle du ping JS (Jalon 2.C.1) pour pouvoir
  // discriminer si la V8 binding casse vs. le transport Mojo browser.
  // À retirer au Jalon 2.C.3 quand SawtunaaScript.js prendra le relais.
  const auto url = render_frame->GetWebFrame()->GetDocument().Url();
  sawtunaa_->LogJs(
      base::StrCat({"[from C++] ", url.GetString().Utf8()}));
}

void SawtunaaRenderFrameObserver::DidClearWindowObject() {
  auto* render_frame = SawtunaaRenderFrameObserver::render_frame();
  if (!render_frame || !render_frame->IsMainFrame()) {
    return;
  }
  // Jalon 2.C.1 — installe le V8 binding `window.__sawtunaa.send` dans
  // le main world du frame. Doit être fait avant tout script de la page
  // (DidClearWindowObject est appelé après création du contexte V8
  // mais avant exécution de tout script utilisateur).
  SawtunaaJsHandler::Install(render_frame);

  // Test ping depuis JS pour valider le binding. À retirer au Jalon
  // 2.C.3 quand SawtunaaScript.js prendra le relais.
  render_frame->GetWebFrame()->ExecuteScript(blink::WebScriptSource(
      blink::WebString::FromUTF8(
          "try { window.__sawtunaa && window.__sawtunaa.send && "
          "window.__sawtunaa.send('log', '[from JS] ' + location.href); } "
          "catch(e) {}")));
}

void SawtunaaRenderFrameObserver::OnDestruct() {
  delete this;
}

}  // namespace sawtunaa
