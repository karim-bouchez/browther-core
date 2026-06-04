// Copyright (c) 2026 The Browther Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/components/basarunaa/renderer/basarunaa_render_frame_observer_android.h"

#include <optional>
#include <string_view>
#include <utility>

#include "base/functional/bind.h"
#include "base/functional/callback_helpers.h"
#include "base/json/string_escape.h"
#include "base/logging.h"
#include "base/strings/strcat.h"
#include "base/strings/string_number_conversions.h"
#include "base/task/sequenced_task_runner.h"
#include "base/values.h"
#include "brave/components/basarunaa/renderer/basarunaa_js_handler.h"
#include "brave/components/basarunaa/renderer/basarunaa_script_android_generated.h"
#include "content/public/renderer/render_frame.h"
#include "third_party/blink/public/common/associated_interfaces/associated_interface_registry.h"
#include "third_party/blink/public/mojom/script/script_evaluation_params.mojom.h"
#include "third_party/blink/public/platform/web_string.h"
#include "third_party/blink/public/web/web_local_frame.h"
#include "third_party/blink/public/web/web_script_source.h"

namespace basarunaa {
namespace android {

namespace {

// Helper: échappe une chaîne pour inclusion comme literal JS. Wrap entre
// guillemets simples côté caller. Utilise `base::EscapeJSONString` qui pose
// guillemets doubles + échappe correctement les unicode/control chars.
std::string ToJsString(const std::string& s) {
  std::string out;
  base::EscapeJSONString(s, /*put_in_quotes=*/true, &out);
  return out;
}

// Helper: formatte un double sans suffix scientifique pour l'inclure dans du
// JS. JSON-compatible.
std::string ToJsNumber(double d) {
  return base::NumberToString(d);
}

}  // namespace

BasarunaaRenderFrameObserverAndroid::BasarunaaRenderFrameObserverAndroid(
    content::RenderFrame* render_frame)
    : content::RenderFrameObserver(render_frame) {
  // Receivers AssociatedInterface browser → renderer.
  // BasarunaaConfig pousse l'état pref / mode / sliders.
  render_frame->GetAssociatedInterfaceRegistry()
      ->AddInterface<mojom::BasarunaaConfig>(base::BindRepeating(
          &BasarunaaRenderFrameObserverAndroid::BindConfigReceiver,
          weak_factory_.GetWeakPtr()));
  // BasarunaaApply pousse le verdict ML d'une AnalyzeImage antérieure.
  render_frame->GetAssociatedInterfaceRegistry()
      ->AddInterface<mojom::BasarunaaApply>(base::BindRepeating(
          &BasarunaaRenderFrameObserverAndroid::BindApplyReceiver,
          weak_factory_.GetWeakPtr()));
}

BasarunaaRenderFrameObserverAndroid::~BasarunaaRenderFrameObserverAndroid() =
    default;

void BasarunaaRenderFrameObserverAndroid::BindConfigReceiver(
    mojo::PendingAssociatedReceiver<mojom::BasarunaaConfig> pending) {
  config_receivers_.Add(this, std::move(pending));
}

void BasarunaaRenderFrameObserverAndroid::BindApplyReceiver(
    mojo::PendingAssociatedReceiver<mojom::BasarunaaApply> pending) {
  apply_receivers_.Add(this, std::move(pending));
}

void BasarunaaRenderFrameObserverAndroid::SetConfig(
    mojom::BasarunaaSettingsPtr settings) {
  const bool was_enabled = settings_ && settings_->enabled;
  const bool now_enabled = settings && settings->enabled;
  settings_ = std::move(settings);

  if (!settings_) {
    return;
  }
  LOG(INFO) << "[Basarunaa/RFO] SetConfig(enabled="
            << (now_enabled ? "true" : "false")
            << ", mode=" << settings_->mode << ", was="
            << (was_enabled ? "true" : "false") << ")";

  auto* render_frame = BasarunaaRenderFrameObserverAndroid::render_frame();
  if (!render_frame || !render_frame->IsMainFrame()) {
    return;
  }

  if (was_enabled == now_enabled) {
    // Toggle mode/sliders sans flip enabled → push la nouvelle config aux
    // scripts JS s'ils tournent. Pas de réinjection nécessaire.
    if (script_injected_ && now_enabled) {
      // Le script JS lit `window.__basarunaa.getConfig()` à la demande,
      // donc la nouvelle valeur est déjà disponible. Un dispatch
      // `basarunaa-config-changed` réveille les scanners qui ont besoin de
      // re-scanner avec un nouveau mode (blur-female → blur-all).
      constexpr std::string_view kConfigChangedScript =
          "try { window.dispatchEvent(new Event('basarunaa-config-changed')); }"
          " catch(e) {}";
      blink::WebScriptSource source(
          blink::WebString::FromUTF8(kConfigChangedScript));
      render_frame->GetWebFrame()->RequestExecuteScript(
          blink::kMainDOMWorldId, base::span_from_ref(source),
          blink::mojom::UserActivationOption::kDoNotActivate,
          blink::mojom::EvaluationTiming::kSynchronous,
          blink::mojom::LoadEventBlockingOption::kDoNotBlock,
          base::DoNothing(), blink::BackForwardCacheAware::kAllow,
          blink::mojom::WantResultOption::kNoResult,
          blink::mojom::PromiseResultOption::kDoNotWait);
    }
    return;
  }

  // OFF → ON live : on N'INJECTE PAS le script ici (frame peut être
  // provisional, cf. crash DCHECK ToV8ContextMaybeEmpty). Le panel BottomSheet
  // côté Java déclenche un `tab.reload()` qui produit un
  // `DidClearWindowObject` clean → InstallBindingAndInjectScript.
  if (now_enabled) {
    return;
  }

  // ON → OFF live : script JS tourne, on lui demande de cleanup via event.
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE,
      base::BindOnce(&BasarunaaRenderFrameObserverAndroid::DispatchDisableEvent,
                     weak_factory_.GetWeakPtr()));
}

void BasarunaaRenderFrameObserverAndroid::Apply(
    int32_t image_id,
    const std::string& decision,
    const std::string& persons_json,
    const std::string& debug_mode,
    double elapsed_ms) {
  // persons_json est déjà un JSON valide produit côté Java (BasarunaaResult →
  // BasarunaaPersonJson). On le passe tel quel comme expression JS, après
  // fallback `null` si vide.
  const std::string persons_expr =
      persons_json.empty() ? std::string("null") : persons_json;
  const std::string js = base::StrCat({
      "try { if (window.__basarunaaApply) window.__basarunaaApply(",
      base::NumberToString(image_id), ", ",
      ToJsString(decision), ", ",
      persons_expr, ", ",
      ToJsString(debug_mode), ", ",
      ToJsNumber(elapsed_ms),
      "); } catch(e) {}",
  });
  DispatchApplyToJs(js);
}

void BasarunaaRenderFrameObserverAndroid::ApplyNsfw(int32_t image_id,
                                                    double score) {
  const std::string js = base::StrCat({
      "try { if (window.__basarunaaApplyNsfw) window.__basarunaaApplyNsfw(",
      base::NumberToString(image_id), ", ",
      ToJsNumber(score),
      "); } catch(e) {}",
  });
  DispatchApplyToJs(js);
}

void BasarunaaRenderFrameObserverAndroid::DidClearWindowObject() {
  auto* render_frame = BasarunaaRenderFrameObserverAndroid::render_frame();
  if (!render_frame || !render_frame->IsMainFrame()) {
    return;
  }
  // Nouvelle Window = nouveau contexte V8 = nouveau script à installer.
  script_injected_ = false;

  if (!settings_ || !settings_->enabled) {
    LOG(INFO) << "[Basarunaa/RFO] DidClearWindowObject — pref OFF / no config, "
                 "skipping script injection";
    return;
  }
  InstallBindingAndInjectScript();
}

void BasarunaaRenderFrameObserverAndroid::InstallBindingAndInjectScript() {
  if (!settings_ || !settings_->enabled) {
    return;
  }
  auto* render_frame = BasarunaaRenderFrameObserverAndroid::render_frame();
  if (!render_frame || !render_frame->IsMainFrame()) {
    return;
  }
  if (script_injected_) {
    return;
  }
  script_injected_ = true;

  // V8 binding `window.__basarunaa` — doit être installé avant l'eval du
  // script pour que `getConfig()` / `isEnabled()` soient dispo dès l'entry.
  BasarunaaJsHandler::Install(render_frame, this);

  constexpr std::string_view script_view(kBasarunaaScriptAndroid,
                                         sizeof(kBasarunaaScriptAndroid) - 1);
  LOG(INFO) << "[Basarunaa/RFO] InstallBindingAndInjectScript, script size="
            << script_view.size();
  blink::WebScriptSource source(blink::WebString::FromUTF8(script_view));
  render_frame->GetWebFrame()->RequestExecuteScript(
      blink::kMainDOMWorldId, base::span_from_ref(source),
      blink::mojom::UserActivationOption::kDoNotActivate,
      blink::mojom::EvaluationTiming::kSynchronous,
      blink::mojom::LoadEventBlockingOption::kDoNotBlock,
      base::BindOnce([](std::optional<base::Value> value,
                        base::TimeTicks start_time) {
        if (value.has_value()) {
          LOG(INFO) << "[Basarunaa/RFO] script eval result: "
                    << value->DebugString();
        } else {
          LOG(INFO) << "[Basarunaa/RFO] script eval result: NO VALUE";
        }
      }),
      blink::BackForwardCacheAware::kAllow,
      blink::mojom::WantResultOption::kWantResult,
      blink::mojom::PromiseResultOption::kDoNotWait);
}

void BasarunaaRenderFrameObserverAndroid::DispatchDisableEvent() {
  if (settings_ && settings_->enabled) {
    return;
  }
  auto* render_frame = BasarunaaRenderFrameObserverAndroid::render_frame();
  if (!render_frame || !render_frame->IsMainFrame()) {
    return;
  }
  if (!script_injected_) {
    return;
  }
  constexpr std::string_view kDisableScript =
      "try {"
      "  window.__basarunaa_disabled = true;"
      "  window.dispatchEvent(new Event('basarunaa-disable'));"
      "} catch(e) {}";
  blink::WebScriptSource source(blink::WebString::FromUTF8(kDisableScript));
  LOG(INFO) << "[Basarunaa/RFO] Dispatching basarunaa-disable";
  render_frame->GetWebFrame()->RequestExecuteScript(
      blink::kMainDOMWorldId, base::span_from_ref(source),
      blink::mojom::UserActivationOption::kDoNotActivate,
      blink::mojom::EvaluationTiming::kSynchronous,
      blink::mojom::LoadEventBlockingOption::kDoNotBlock, base::DoNothing(),
      blink::BackForwardCacheAware::kAllow,
      blink::mojom::WantResultOption::kNoResult,
      blink::mojom::PromiseResultOption::kDoNotWait);
}

void BasarunaaRenderFrameObserverAndroid::DispatchApplyToJs(
    const std::string& js) {
  auto* render_frame = BasarunaaRenderFrameObserverAndroid::render_frame();
  if (!render_frame || !render_frame->IsMainFrame()) {
    return;
  }
  if (!script_injected_) {
    // Le script n'est pas encore en place → on drop. Le browser side a
    // déjà loggué le verdict ; le JS doit re-AnalyzeImage si nécessaire.
    return;
  }
  blink::WebScriptSource source(blink::WebString::FromUTF8(js));
  render_frame->GetWebFrame()->RequestExecuteScript(
      blink::kMainDOMWorldId, base::span_from_ref(source),
      blink::mojom::UserActivationOption::kDoNotActivate,
      blink::mojom::EvaluationTiming::kSynchronous,
      blink::mojom::LoadEventBlockingOption::kDoNotBlock, base::DoNothing(),
      blink::BackForwardCacheAware::kAllow,
      blink::mojom::WantResultOption::kNoResult,
      blink::mojom::PromiseResultOption::kDoNotWait);
}

void BasarunaaRenderFrameObserverAndroid::OnDestruct() {
  delete this;
}

}  // namespace android
}  // namespace basarunaa
