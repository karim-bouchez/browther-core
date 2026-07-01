// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/components/basarunaa/renderer/basarunaa_render_frame_observer.h"

#include <utility>
#include <vector>

#include "base/compiler_specific.h"
#include "base/containers/span.h"
#include "base/functional/bind.h"
#include "base/logging.h"
#include "content/public/renderer/render_frame.h"
#include "mojo/public/cpp/base/big_buffer.h"
#include "third_party/blink/public/platform/browser_interface_broker_proxy.h"

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
  image_analyzer_->AnalyzeImage(
      std::move(buffer), width, height, mojom::ImageFormat::kBgra8,
      base::BindOnce(&BasarunaaRenderFrameObserver::OnAnalyzed,
                     weak_ptr_factory_.GetWeakPtr()));
}

void BasarunaaRenderFrameObserver::OnAnalyzed(
    std::vector<mojom::AnalyzedPersonPtr> persons) {
  LOG(INFO) << "[Basarunaa-spike] AnalyzeImage reply: " << persons.size()
            << " persons";
}

void BasarunaaRenderFrameObserver::OnDestruct() {
  delete this;
}

}  // namespace basarunaa
