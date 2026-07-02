// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/components/basarunaa/renderer/basarunaa_render_frame_observer.h"

#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "base/compiler_specific.h"
#include "base/containers/span.h"
#include "base/functional/bind.h"
#include "base/json/json_writer.h"
#include "base/location.h"
#include "base/logging.h"
#include "base/task/single_thread_task_runner.h"
#include "base/values.h"
#include "content/public/renderer/render_frame.h"
#include "mojo/public/cpp/base/big_buffer.h"
#include "third_party/blink/public/platform/browser_interface_broker_proxy.h"
#include "third_party/blink/public/platform/task_type.h"
#include "third_party/blink/public/platform/web_string.h"
#include "third_party/blink/public/web/web_local_frame.h"
#include "third_party/blink/public/web/web_script_source.h"

namespace basarunaa {

namespace {

// Référencée par le code commenté du spike dans `DidFinishLoad`. Préfixé
// `[[maybe_unused]]` plutôt que supprimé pour faciliter la réactivation
// en M2.2.
[[maybe_unused]] constexpr int kSpikeImageSize = 128;

}  // namespace

BasarunaaRenderFrameObserver::BasarunaaRenderFrameObserver(
    content::RenderFrame* render_frame)
    : content::RenderFrameObserver(render_frame),
      content::RenderFrameObserverTracker<BasarunaaRenderFrameObserver>(
          render_frame) {}

BasarunaaRenderFrameObserver::~BasarunaaRenderFrameObserver() = default;

bool BasarunaaRenderFrameObserver::EnsureConnected() {
  if (!image_analyzer_.is_bound()) {
    if (!render_frame()) {
      return false;
    }
    render_frame()->GetBrowserInterfaceBroker().GetInterface(
        image_analyzer_.BindNewPipeAndPassReceiver());
    image_analyzer_.reset_on_disconnect();
  }
  return image_analyzer_.is_bound();
}

void BasarunaaRenderFrameObserver::DidFinishLoad() {
  // Spike validé le 2026-05-10 (cycle dummy IPC OK sous stress Google
  // Images, pas de crash). Désactivé pour éviter du Mojo IPC inutile à
  // chaque page chargée. À réactiver / remplacer en M2.2 par un vrai
  // hook ImageNotifyFinished sur les <img> du document.
  //
  // if (!EnsureConnected()) return;
  // std::vector<uint8_t> pixels(kSpikeImageSize * kSpikeImageSize * 4, 0u);
  // mojo_base::BigBuffer buffer{base::span<const uint8_t>(pixels)};
  // image_analyzer_->AnalyzeImage(
  //     std::move(buffer), kSpikeImageSize, kSpikeImageSize,
  //     mojom::ImageFormat::kRgba8,
  //     base::BindOnce(&BasarunaaRenderFrameObserver::OnAnalyzed,
  //                    weak_ptr_factory_.GetWeakPtr()));
}

base::RepeatingCallback<void(std::vector<uint8_t>, int, int, base::TimeDelta)>
BasarunaaRenderFrameObserver::GetVideoLeadFrameSink() {
  return base::BindRepeating(
      &BasarunaaRenderFrameObserver::OnVideoLeadFrame,
      weak_ptr_factory_.GetWeakPtr());
}

void BasarunaaRenderFrameObserver::OnVideoLeadFrame(std::vector<uint8_t> bgra,
                                                    int width,
                                                    int height,
                                                    base::TimeDelta media_time) {
  // ③a : plomberie renderer→browser. Le buffer vient déjà en BGRA
  // (kN32 Apple, cf. WebMediaPlayerImpl::OnLeadFrame étape ②).
  if (!EnsureConnected()) {
    return;
  }
  mojo_base::BigBuffer buffer{base::span<const uint8_t>(bgra)};
  // ④a : garde media_time + dims analysées pour horodater/normaliser côté JS.
  image_analyzer_->AnalyzeImage(
      std::move(buffer), width, height, mojom::ImageFormat::kBgra8,
      base::BindOnce(&BasarunaaRenderFrameObserver::OnAnalyzed,
                     weak_ptr_factory_.GetWeakPtr(), media_time, width, height));
}

void BasarunaaRenderFrameObserver::OnAnalyzed(
    base::TimeDelta media_time,
    int width,
    int height,
    std::vector<mojom::AnalyzedPersonPtr> persons) {
  // ④a : pousse le verdict au JS de la page. Coords normalisées [0,1] (le JS
  // scale à l'affichage). detail = string JSON (traverse proprement les mondes).
  const double w = width > 0 ? width : 1;
  const double h = height > 0 ? height : 1;
  base::ListValue boxes;
  for (const auto& p : persons) {
    base::ListValue box;
    box.Append(p->x / w);
    box.Append(p->y / h);
    box.Append(p->w / w);
    box.Append(p->h / h);
    box.Append(static_cast<double>(p->score));
    boxes.Append(std::move(box));
  }
  base::DictValue dict;
  dict.Set("t", static_cast<double>(media_time.InMilliseconds()));
  dict.Set("p", std::move(boxes));

  std::optional<std::string> json = base::WriteJson(dict);
  if (!json) {
    return;
  }
  // JSON-encode la string une 2e fois -> littéral JS échappé pour |detail|.
  std::optional<std::string> js_literal = base::WriteJson(base::Value(*json));
  if (!js_literal) {
    return;
  }
  std::string script =
      "document.dispatchEvent(new CustomEvent('bsr-native-result',{detail:" +
      *js_literal + "}))";
  content::RenderFrame* rf = render_frame();
  if (!rf) {
    return;
  }
  // ⚠️ NE PAS ExecuteScript ici (callback Mojo) : on poste une tâche fraîche.
  rf->GetTaskRunner(blink::TaskType::kInternalDefault)
      ->PostTask(
          FROM_HERE,
          base::BindOnce(&BasarunaaRenderFrameObserver::DispatchResultToPage,
                         weak_ptr_factory_.GetWeakPtr(), std::move(script)));
}

void BasarunaaRenderFrameObserver::DispatchResultToPage(std::string script) {
  content::RenderFrame* rf = render_frame();
  if (!rf) {
    return;
  }
  blink::WebLocalFrame* web_frame = rf->GetWebFrame();
  if (!web_frame || web_frame->IsProvisional()) {
    return;
  }
  // Main world : le content script (monde isolé) reçoit l'event DOM.
  web_frame->ExecuteScript(
      blink::WebScriptSource(blink::WebString::FromUTF8(script)));
}

void BasarunaaRenderFrameObserver::OnDestruct() {
  delete this;
}

}  // namespace basarunaa
