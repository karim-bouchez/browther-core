// Copyright (c) 2026 The Browther Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/components/sawtunaa/renderer/sawtunaa_render_frame_observer.h"

#include <optional>
#include <string_view>

#include "base/containers/span.h"
#include "base/functional/bind.h"
#include "base/functional/callback_helpers.h"
#include "base/logging.h"
#include "base/strings/strcat.h"
#include "base/values.h"
#include "brave/components/sawtunaa/renderer/sawtunaa_js_handler.h"
#include "brave/components/sawtunaa/renderer/sawtunaa_script_generated.h"
#include "content/public/renderer/render_frame.h"
#include "third_party/blink/public/common/associated_interfaces/associated_interface_registry.h"
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
    : content::RenderFrameObserver(render_frame) {
  // Register la receiver pour SawtunaaConfig (browser → renderer). Le browser
  // push `SetEnabled(...)` à `RenderFrameCreated` puis à chaque pref change.
  render_frame->GetAssociatedInterfaceRegistry()
      ->AddInterface<mojom::SawtunaaConfig>(base::BindRepeating(
          &SawtunaaRenderFrameObserver::BindConfigReceiver,
          weak_factory_.GetWeakPtr()));
}

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

void SawtunaaRenderFrameObserver::BindConfigReceiver(
    mojo::PendingAssociatedReceiver<mojom::SawtunaaConfig> pending) {
  config_receivers_.Add(this, std::move(pending));
}

void SawtunaaRenderFrameObserver::SetEnabled(bool enabled) {
  const bool was_enabled = enabled_;
  enabled_ = enabled;
  LOG(INFO) << "[Sawtunaa/RFO] SetEnabled(" << (enabled ? "true" : "false")
            << ") was=" << (was_enabled ? "true" : "false");
  if (was_enabled == enabled) {
    return;
  }
  auto* render_frame = SawtunaaRenderFrameObserver::render_frame();
  if (!render_frame || !render_frame->IsMainFrame()) {
    return;
  }
  if (enabled) {
    // OFF → ON live. Le window object est déjà cleared depuis longtemps. On
    // installe le binding + injecte le script maintenant. Le script JS
    // détectera isEnabled()==true à son démarrage.
    InstallBindingAndInjectScript();
  } else {
    // ON → OFF live. Le script JS est en train de tourner. On lui demande de
    // restaurer le mute natif et de s'arrêter via l'event `sawtunaa-disable`.
    DispatchDisableEvent();
  }
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
  const auto url = render_frame->GetWebFrame()->GetDocument().Url();
  sawtunaa_->LogJs(
      base::StrCat({"[from C++] ", url.GetString().Utf8()}));
}

void SawtunaaRenderFrameObserver::DidClearWindowObject() {
  auto* render_frame = SawtunaaRenderFrameObserver::render_frame();
  if (!render_frame || !render_frame->IsMainFrame()) {
    return;
  }
  // Nouvelle Window = nouveau contexte V8 = nouveau script à installer.
  script_injected_ = false;

  // Gating sur la pref : si OFF, on ne touche PAS la page. Pas de
  // `window.__sawtunaa`, pas de script JS, pas de force-mute. Browther se
  // comporte exactement comme Chromium standard pour les `<video>`.
  if (!enabled_) {
    LOG(INFO) << "[Sawtunaa/RFO] DidClearWindowObject — pref OFF, skipping "
                 "script injection";
    return;
  }
  InstallBindingAndInjectScript();
}

void SawtunaaRenderFrameObserver::InstallBindingAndInjectScript() {
  auto* render_frame = SawtunaaRenderFrameObserver::render_frame();
  if (!render_frame || !render_frame->IsMainFrame()) {
    return;
  }
  if (script_injected_) {
    return;
  }
  script_injected_ = true;

  // Installe `window.__sawtunaa.send/isEnabled` dans le main world (V8
  // binding). Doit être fait avant exécution du script Sawtunaa pour que
  // `isEnabled()` soit dispo dès son entrée.
  SawtunaaJsHandler::Install(render_frame, this);

  // Injection du bundle complet (Opus decoder ~105 KB + SawtunaaScript ~33 KB,
  // ~1730 lignes total).
  //
  // ATTENTION : le bundle Opus (~888 null bytes \x00 dans les tables binaires)
  // faisait stopper FromUTF8(const char*) au premier \0 → script tronqué à
  // 21 KB. On passe par std::string_view avec longueur explicite. Fix 2026-05-24.
  constexpr std::string_view script_view(
      kSawtunaaScript, sizeof(kSawtunaaScript) - 1);
  LOG(INFO) << "[Sawtunaa/RFO] InstallBindingAndInjectScript, script size="
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
}

void SawtunaaRenderFrameObserver::DispatchDisableEvent() {
  auto* render_frame = SawtunaaRenderFrameObserver::render_frame();
  if (!render_frame || !render_frame->IsMainFrame()) {
    return;
  }
  if (!script_injected_) {
    // Pas de script à informer (jamais injecté sur cette window).
    return;
  }
  // dispatchEvent + remove notre flag actif. Le script JS écoute sur
  // `window` et fait son cleanup (restaure descriptors, stop scheduler).
  constexpr std::string_view kDisableScript =
      "try {"
      "  window.__sawtunaa_disabled = true;"
      "  window.dispatchEvent(new Event('sawtunaa-disable'));"
      "} catch(e) {}";
  blink::WebScriptSource source(
      blink::WebString::FromUTF8(kDisableScript));
  LOG(INFO) << "[Sawtunaa/RFO] Dispatching sawtunaa-disable";
  render_frame->GetWebFrame()->RequestExecuteScript(
      blink::kMainDOMWorldId, base::span_from_ref(source),
      blink::mojom::UserActivationOption::kDoNotActivate,
      blink::mojom::EvaluationTiming::kSynchronous,
      blink::mojom::LoadEventBlockingOption::kDoNotBlock, base::DoNothing(),
      blink::BackForwardCacheAware::kAllow,
      blink::mojom::WantResultOption::kNoResult,
      blink::mojom::PromiseResultOption::kDoNotWait);
}

void SawtunaaRenderFrameObserver::OnDestruct() {
  delete this;
}

}  // namespace sawtunaa
