// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/components/basarunaa/renderer/basarunaa_renderer_installer.h"

#include <string>

#include "base/logging.h"
#include "brave/components/basarunaa/renderer/basarunaa_js_handler.h"
#include "content/public/renderer/render_frame.h"
#include "third_party/blink/public/platform/web_security_origin.h"
#include "third_party/blink/public/platform/web_string.h"
#include "third_party/blink/public/web/web_local_frame.h"

namespace basarunaa {

namespace {

// Garder en sync avec
// chromium_src/.../component_extensions_allowlist/allowlist.cc.
constexpr char kBasarunaaExtensionId[] =
    "hfgccmcaagdjpfkmjefgilngheecaapb";

}  // namespace

BasarunaaRendererInstaller::BasarunaaRendererInstaller(
    content::RenderFrame* render_frame)
    : content::RenderFrameObserver(render_frame) {}

BasarunaaRendererInstaller::~BasarunaaRendererInstaller() = default;

void BasarunaaRendererInstaller::OnDestruct() {
  delete this;
}

void BasarunaaRendererInstaller::DidCreateScriptContext(
    v8::Local<v8::Context> context,
    int32_t world_id) {
  constexpr int32_t kMainWorldId = 0;
  if (world_id != kMainWorldId) {
    return;
  }
  blink::WebLocalFrame* web_frame =
      render_frame() ? render_frame()->GetWebFrame() : nullptr;
  if (!web_frame) {
    return;
  }
  if (web_frame->GetSecurityOrigin().Host().Utf8() != kBasarunaaExtensionId) {
    return;
  }
  BasarunaaJSHandler::Install(render_frame(), context);
}

}  // namespace basarunaa
