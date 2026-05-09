// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/components/basarunaa/renderer/basarunaa_render_frame_observer.h"

#include <utility>

#include "base/compiler_specific.h"
#include "base/containers/span.h"
#include "base/functional/bind.h"
#include "base/logging.h"
#include "brave/components/basarunaa/renderer/basarunaa_js_handler.h"
#include "content/public/renderer/render_frame.h"
#include "mojo/public/cpp/base/big_buffer.h"
#include "third_party/blink/public/common/associated_interfaces/associated_interface_provider.h"
#include "third_party/blink/public/platform/web_string.h"
#include "third_party/blink/public/web/web_document.h"
#include "third_party/blink/public/web/web_element.h"
#include "third_party/blink/public/web/web_element_collection.h"
#include "third_party/blink/public/web/web_local_frame.h"
#include "third_party/blink/public/web/web_script_source.h"
#include "third_party/skia/include/core/SkBitmap.h"

namespace basarunaa {

namespace {

// Skip very small images: icons, sprites, avatars. M2.4 will replace this
// with a proper scheduler (size + LRU + cap concurrent calls).
constexpr int kMinSidePx = 200;

// Soft cap on Mojo calls per page so a malicious / abusive page can't drown
// the browser process with thousands of analysis requests. M2.4 will drop
// this in favor of a real scheduler.
constexpr size_t kMaxImagesPerPage = 20;

// M2.3a — hide-first CSS. Appended to the IMG's existing inline `style`
// while the ML round-trip is in flight; restored on reply. `important` lets
// us beat author CSS `filter` rules without resorting to `!important` in a
// stylesheet (which would still leave a window of unblurred paint).
constexpr char kHideFirstStyleSuffix[] =
    "filter: blur(20px) !important; -webkit-filter: blur(20px) !important;";

// Page-side dedup marker. The renderer's C++ side (this file) reads it via
// `WebElement::HasAttribute` and writes it via `SetAttribute`; the injected
// JS (M2.5) reads it via `el.dataset.basarunaaSeen`.
constexpr char kSeenAttr[] = "data-basarunaa-seen";

// M2.5 — JavaScript installed at DidCreateScriptContext in the main world.
// Sets up a MutationObserver on `document.documentElement` and notifies the
// native side for every newly inserted `<img>` once it has decoded pixels.
// Idempotent: re-execution (eg, after document replacement) is a no-op
// thanks to `window.__basarunaaInstalled`.
constexpr char kBasarunaaObserverScript[] = R"JS(
(() => {
  if (window.__basarunaaInstalled) return;
  window.__basarunaaInstalled = true;
  const native = window.__basarunaa;
  if (!native || typeof native.notify !== 'function') return;
  const seen = new WeakSet();
  function consider(node) {
    if (!node || node.nodeType !== 1) return;
    if (node.tagName === 'IMG') {
      if (seen.has(node) || node.dataset.basarunaaSeen) return;
      seen.add(node);
      const dispatch = () => {
        try { native.notify(node); } catch (_) { /* noop */ }
      };
      if (node.complete && node.naturalWidth > 0) {
        dispatch();
      } else {
        node.addEventListener('load', dispatch, { once: true });
      }
    } else if (node.querySelectorAll) {
      for (const img of node.querySelectorAll('img')) consider(img);
    }
  }
  // Live updates : observe document directly (Document is a Node) so we
  // catch IMG insertions as soon as the parser yields them, even before
  // documentElement is created.
  const obs = new MutationObserver((muts) => {
    for (const m of muts) {
      for (const n of m.addedNodes) consider(n);
    }
  });
  obs.observe(document, { childList: true, subtree: true });
  // Initial pass: run as soon as <body> exists (or now if it already does).
  function initialScan() {
    if (!document || !document.querySelectorAll) return;
    for (const img of document.querySelectorAll('img')) consider(img);
  }
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initialScan, { once: true });
  } else {
    initialScan();
  }
})();
)JS";

}  // namespace

BasarunaaRenderFrameObserver::BasarunaaRenderFrameObserver(
    content::RenderFrame* render_frame)
    : content::RenderFrameObserver(render_frame) {}

BasarunaaRenderFrameObserver::~BasarunaaRenderFrameObserver() = default;

void BasarunaaRenderFrameObserver::OnDestruct() {
  delete this;
}

const mojo::AssociatedRemote<mojom::ImageAnalyzer>&
BasarunaaRenderFrameObserver::GetImageAnalyzer() {
  if (!image_analyzer_.is_bound()) {
    render_frame()->GetRemoteAssociatedInterfaces()->GetInterface(
        &image_analyzer_);
    image_analyzer_.reset_on_disconnect();
  }
  return image_analyzer_;
}

void BasarunaaRenderFrameObserver::DidCreateScriptContext(
    v8::Local<v8::Context> context,
    int32_t world_id) {
  // Install only in the main world (not extension content scripts, not
  // isolated worlds). Page security: any page script can in theory call
  // `__basarunaa.notify(el)` — that just queues the IMG for analysis,
  // which is exactly what we already want to do. No exfiltration possible
  // since the binding has no return value with sensitive data.
  constexpr int32_t kMainWorldId = 0;
  if (world_id != kMainWorldId) {
    return;
  }
  if (!render_frame() || !render_frame()->GetWebFrame()) {
    return;
  }
  BasarunaaJSHandler::Install(render_frame(),
                              weak_ptr_factory_.GetWeakPtr());
  render_frame()->GetWebFrame()->ExecuteScript(blink::WebScriptSource(
      blink::WebString::FromUTF8(kBasarunaaObserverScript)));
}

void BasarunaaRenderFrameObserver::DidFinishLoad() {
  // M2.5 — disabled: the JS MutationObserver installed at
  // DidCreateScriptContext now picks up every IMG (initial pass + live
  // mutations) and routes them through ProcessImageElement via the gin
  // binding. Re-running the scan here just doubles the dispatches, which
  // amplifies a Mojo receiver race we still have on the browser side. If
  // the JS path turns out to miss images on certain pages, we will
  // re-enable this with stricter dedup (URL-based, not just attribute).
}

void BasarunaaRenderFrameObserver::ProcessImageElement(
    const blink::WebElement& element_const) {
  if (element_const.IsNull()) {
    return;
  }

  // WebElement methods we need are non-const, so re-bind locally.
  blink::WebElement element = element_const;

  // Per-page cap; M2.4 will replace with a real scheduler.
  if (images_sent_this_page_ >= kMaxImagesPerPage) {
    return;
  }

  // Dedup: same IMG seen twice (initial scan + JS notification, or 2 JS
  // events for the same node) hits this fast path.
  const blink::WebString kSeen = blink::WebString::FromASCII(kSeenAttr);
  if (element.HasAttribute(kSeen)) {
    return;
  }

  SkBitmap bitmap = element.ImageContents();
  if (bitmap.empty()) {
    return;
  }
  if (bitmap.width() < kMinSidePx || bitmap.height() < kMinSidePx) {
    return;
  }

  mojom::ImageFormat format;
  switch (bitmap.colorType()) {
    case kRGBA_8888_SkColorType:
      format = mojom::ImageFormat::kRgba8;
      break;
    case kBGRA_8888_SkColorType:
      format = mojom::ImageFormat::kBgra8;
      break;
    default:
      return;
  }

  const size_t row_bytes = bitmap.rowBytes();
  const size_t expected_row = static_cast<size_t>(bitmap.width()) * 4u;
  const uint8_t* pixels = static_cast<const uint8_t*>(bitmap.getPixels());
  if (!pixels) {
    return;
  }

  mojo_base::BigBuffer buffer;
  if (row_bytes == expected_row) {
    buffer = mojo_base::BigBuffer(UNSAFE_BUFFERS(
        base::span<const uint8_t>(pixels, expected_row * bitmap.height())));
  } else {
    std::vector<uint8_t> packed(expected_row *
                                static_cast<size_t>(bitmap.height()));
    for (int y = 0; y < bitmap.height(); ++y) {
      const uint8_t* src = static_cast<const uint8_t*>(bitmap.getAddr(0, y));
      UNSAFE_BUFFERS(
          memcpy(packed.data() + y * expected_row, src, expected_row));
    }
    buffer = mojo_base::BigBuffer(packed);
  }

  // Mark seen BEFORE applying the blur or dispatching, so that even if a
  // re-entrant MutationObserver event lands during SetAttribute, the next
  // ProcessImageElement call short-circuits.
  element.SetAttribute(kSeen, blink::WebString::FromASCII("1"));

  blink::WebString original_style =
      element.GetAttribute(blink::WebString::FromASCII("style"));
  std::string blurred_style = original_style.Utf8();
  if (!blurred_style.empty() && blurred_style.back() != ';') {
    blurred_style.push_back(';');
  }
  blurred_style.append(kHideFirstStyleSuffix);
  element.SetAttribute(blink::WebString::FromASCII("style"),
                       blink::WebString::FromUTF8(blurred_style));

  GetImageAnalyzer()->AnalyzeImage(
      std::move(buffer), bitmap.width(), bitmap.height(), format,
      base::BindOnce(&BasarunaaRenderFrameObserver::OnAnalyzed,
                     weak_ptr_factory_.GetWeakPtr(), element,
                     std::move(original_style), bitmap.width(),
                     bitmap.height()));
  ++images_sent_this_page_;
  VLOG(1) << "[Basarunaa-renderer] dispatched " << bitmap.width() << "x"
          << bitmap.height() << " (" << images_sent_this_page_ << "/"
          << kMaxImagesPerPage << ")";
}

void BasarunaaRenderFrameObserver::OnAnalyzed(
    blink::WebElement element,
    blink::WebString original_style,
    int width,
    int height,
    std::vector<mojom::AnalyzedPersonPtr> persons) {
  VLOG(1) << "[Basarunaa-renderer] AnalyzeImage(" << width << "x" << height
          << ") → " << persons.size() << " person(s)";

  if (element.IsNull()) {
    return;
  }
  if (persons.empty()) {
    element.SetAttribute(blink::WebString::FromASCII("style"), original_style);
  }
  // ≥ 1 person → leave the blur in place. M2.3b will replace this with a
  // per-bbox overlay div for surgical blur instead of full-image.
}

}  // namespace basarunaa
