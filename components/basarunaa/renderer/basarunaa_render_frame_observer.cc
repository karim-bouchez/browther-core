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

constexpr int kSpikeImageSize = 128;

}  // namespace

BasarunaaRenderFrameObserver::BasarunaaRenderFrameObserver(
    content::RenderFrame* render_frame)
    : content::RenderFrameObserver(render_frame) {}

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
  if (!EnsureConnected()) {
    return;
  }
  // Dummy buffer 128×128 RGBA noir. Le but est juste de stresser la
  // chaîne Mojo+BigBuffer ; le browser stub renvoie [] direct.
  std::vector<uint8_t> pixels(kSpikeImageSize * kSpikeImageSize * 4, 0u);
  mojo_base::BigBuffer buffer{base::span<const uint8_t>(pixels)};
  LOG(INFO) << "[Basarunaa-spike] sending dummy AnalyzeImage from RFO";
  image_analyzer_->AnalyzeImage(
      std::move(buffer), kSpikeImageSize, kSpikeImageSize,
      mojom::ImageFormat::kRgba8,
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
