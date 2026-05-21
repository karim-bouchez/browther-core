// Copyright (c) 2026 The Browther Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/components/sawtunaa/renderer/sawtunaa_render_frame_observer.h"

#include "base/strings/strcat.h"
#include "content/public/renderer/render_frame.h"
#include "third_party/blink/public/platform/browser_interface_broker_proxy.h"
#include "third_party/blink/public/web/web_document.h"
#include "third_party/blink/public/web/web_local_frame.h"

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
  // Ping minimal — l'URL committée. Côté browser ce sera loggé en
  // LOG(INFO) "[Sawtunaa/JS] hello from <url>".
  const auto url = render_frame->GetWebFrame()->GetDocument().Url();
  sawtunaa_->LogJs(
      base::StrCat({"hello from ", url.GetString().Utf8()}));
}

void SawtunaaRenderFrameObserver::OnDestruct() {
  delete this;
}

}  // namespace sawtunaa
