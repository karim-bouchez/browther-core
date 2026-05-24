// Copyright (c) 2026 The Browther Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/components/sawtunaa/renderer/sawtunaa_render_frame_observer.h"

#include <optional>
#include <string_view>

#include "base/containers/span.h"
#include "base/logging.h"
#include "base/strings/strcat.h"
#include "base/values.h"
#include "brave/components/sawtunaa/renderer/sawtunaa_js_handler.h"
#include "brave/components/sawtunaa/renderer/sawtunaa_script_generated.h"
#include "content/public/renderer/render_frame.h"
#include "third_party/blink/public/mojom/script/script_evaluation_params.mojom.h"
#include "third_party/blink/public/platform/browser_interface_broker_proxy.h"
#include "third_party/blink/public/platform/web_isolated_world_info.h"
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

  // Jalon 2.C.4+5 — injection du bundle complet (Opus decoder ~105 KB
  // + SawtunaaScript ~33 KB, ~1730 lignes total).
  //
  // ATTENTION : le bundle Opus (~888 null bytes \x00 dans les tables
  // binaires) faisait stopper FromUTF8(const char*) au premier \0 →
  // script tronqué à 21 KB. On passe par std::string_view pour avoir
  // une longueur explicite (= sizeof(array) - 1). Fix 2026-05-24.
  constexpr std::string_view script_view(
      kSawtunaaScript, sizeof(kSawtunaaScript) - 1);
  LOG(INFO) << "[Sawtunaa/RFO] DidClearWindowObject called, script size="
            << script_view.size();
  blink::WebScriptSource source(blink::WebString::FromUTF8(script_view));
  render_frame->GetWebFrame()->RequestExecuteScript(
      blink::kMainDOMWorldId,
      base::span_from_ref(source),
      blink::mojom::UserActivationOption::kDoNotActivate,
      blink::mojom::EvaluationTiming::kSynchronous,
      blink::mojom::LoadEventBlockingOption::kDoNotBlock,
      base::BindOnce([](std::optional<base::Value> value,
                        base::TimeTicks start_time) {
        if (value.has_value()) {
          LOG(INFO) << "[Sawtunaa/RFO] script eval result: "
                    << value->DebugString();
        } else {
          LOG(INFO) << "[Sawtunaa/RFO] script eval result: NO VALUE";
        }
      }),
      blink::BackForwardCacheAware::kAllow,
      blink::mojom::WantResultOption::kWantResult,
      blink::mojom::PromiseResultOption::kDoNotWait);
  LOG(INFO) << "[Sawtunaa/RFO] RequestExecuteScript returned (callback async)";
}

void SawtunaaRenderFrameObserver::OnDestruct() {
  delete this;
}

}  // namespace sawtunaa
