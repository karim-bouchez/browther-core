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
#include "content/public/renderer/render_frame.h"
#include "mojo/public/cpp/base/big_buffer.h"
#include "third_party/blink/public/common/associated_interfaces/associated_interface_provider.h"
#include "third_party/blink/public/platform/web_string.h"
#include "third_party/blink/public/web/web_document.h"
#include "third_party/blink/public/web/web_element.h"
#include "third_party/blink/public/web/web_element_collection.h"
#include "third_party/blink/public/web/web_local_frame.h"
#include "third_party/skia/include/core/SkBitmap.h"

namespace basarunaa {

namespace {

// M2.2b smoke test: only forward images that are large enough to plausibly
// contain a person. Below this we skip (icons, sprites, avatars). M2.4 will
// replace this with a proper scheduler (size + LRU + cap concurrent calls).
constexpr int kMinSidePx = 200;

// Hard cap on Mojo calls per page to avoid drowning the browser process. M2.4
// will drop this in favor of the scheduler.
constexpr size_t kMaxImagesPerPage = 4;

// M2.3a — hide-first CSS. Appended to the IMG's existing inline `style`
// while the ML round-trip is in flight; restored on reply. `important` lets
// us beat author CSS `filter` rules without resorting to `!important` in a
// stylesheet (which would still leave a window of unblurred paint).
constexpr char kHideFirstStyleSuffix[] =
    "filter: blur(20px) !important; -webkit-filter: blur(20px) !important;";

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

void BasarunaaRenderFrameObserver::DidFinishLoad() {
  auto* web_frame = render_frame() ? render_frame()->GetWebFrame() : nullptr;
  if (!web_frame) {
    return;
  }
  blink::WebDocument document = web_frame->GetDocument();
  if (document.IsNull()) {
    return;
  }
  blink::WebElementCollection collection = document.All();
  if (collection.IsNull()) {
    return;
  }

  const blink::WebString kImgTag = blink::WebString::FromASCII("img");
  size_t total_imgs = 0;
  size_t with_pixels = 0;
  size_t sent = 0;

  for (blink::WebElement element = collection.FirstItem(); !element.IsNull();
       element = collection.NextItem()) {
    if (!element.HasHTMLTagName(kImgTag)) {
      continue;
    }
    ++total_imgs;
    SkBitmap bitmap = element.ImageContents();
    if (bitmap.empty()) {
      continue;
    }
    ++with_pixels;
    if (sent >= kMaxImagesPerPage) {
      continue;
    }
    if (bitmap.width() < kMinSidePx || bitmap.height() < kMinSidePx) {
      continue;
    }

    // We need 4 bytes/pixel and either RGBA or BGRA byte order. Anything else
    // (565, gray, A8, …) gets skipped — extremely rare for content <img>.
    mojom::ImageFormat format;
    switch (bitmap.colorType()) {
      case kRGBA_8888_SkColorType:
        format = mojom::ImageFormat::kRgba8;
        break;
      case kBGRA_8888_SkColorType:
        format = mojom::ImageFormat::kBgra8;
        break;
      default:
        continue;
    }

    const size_t row_bytes = bitmap.rowBytes();
    const size_t expected_row = static_cast<size_t>(bitmap.width()) * 4u;
    const uint8_t* pixels = static_cast<const uint8_t*>(bitmap.getPixels());
    if (!pixels) {
      continue;
    }

    mojo_base::BigBuffer buffer;
    if (row_bytes == expected_row) {
      // Tightly packed — single span suffices.
      buffer = mojo_base::BigBuffer(UNSAFE_BUFFERS(
          base::span<const uint8_t>(pixels, expected_row * bitmap.height())));
    } else {
      // Row stride padding — repack into a contiguous heap buffer first.
      std::vector<uint8_t> packed(expected_row *
                                  static_cast<size_t>(bitmap.height()));
      for (int y = 0; y < bitmap.height(); ++y) {
        const uint8_t* src = static_cast<const uint8_t*>(bitmap.getAddr(0, y));
        UNSAFE_BUFFERS(memcpy(packed.data() + y * expected_row, src,
                              expected_row));
      }
      buffer = mojo_base::BigBuffer(packed);
    }

    // Hide-first: blur the IMG immediately so the user never sees a frame
    // of unblurred content while the ML round-trip is in flight. Save the
    // pre-existing inline `style` so we can put it back unchanged on a
    // negative reply.
    blink::WebString original_style =
        element.GetAttribute(blink::WebString::FromASCII("style"));
    std::string blurred_style = original_style.Utf8();
    if (!blurred_style.empty() && blurred_style.back() != ';') {
      blurred_style.push_back(';');
    }
    blurred_style.append(kHideFirstStyleSuffix);
    element.SetAttribute(blink::WebString::FromASCII("style"),
                         blink::WebString::FromUTF8(blurred_style));
    {
      blink::WebString readback =
          element.GetAttribute(blink::WebString::FromASCII("style"));
      blink::WebString src =
          element.GetAttribute(blink::WebString::FromASCII("src"));
      LOG(INFO) << "[Basarunaa-renderer] hide-first applied (src="
                << src.Utf8().substr(0, 60) << "…) style="
                << readback.Utf8();
    }

    GetImageAnalyzer()->AnalyzeImage(
        std::move(buffer), bitmap.width(), bitmap.height(), format,
        base::BindOnce(&BasarunaaRenderFrameObserver::OnAnalyzed,
                       weak_ptr_factory_.GetWeakPtr(), element,
                       std::move(original_style), bitmap.width(),
                       bitmap.height()));
    ++sent;
  }

  if (total_imgs > 0) {
    LOG(INFO) << "[Basarunaa-renderer] DidFinishLoad — " << with_pixels << "/"
              << total_imgs << " <img> decoded, " << sent
              << " sent to ML on " << document.Url().GetString().Utf8();
  }
}

void BasarunaaRenderFrameObserver::OnAnalyzed(
    blink::WebElement element,
    blink::WebString original_style,
    int width,
    int height,
    std::vector<mojom::AnalyzedPersonPtr> persons) {
  LOG(INFO) << "[Basarunaa-renderer] AnalyzeImage(" << width << "x" << height
            << ") → " << persons.size() << " person(s)";
  for (size_t i = 0; i < persons.size(); ++i) {
    const auto& p = persons[i];
    VLOG(1) << "  [" << i << "] bbox=(" << p->x << "," << p->y << ") "
            << p->w << "x" << p->h << " score=" << p->score;
  }

  // M2.3a — full-image blur V1. If the element has been collected since we
  // dispatched, do nothing. If no person was detected, put the original
  // `style` back. If a person was detected, leave the blur in place. M2.3b
  // will replace this with a per-bbox overlay div.
  if (element.IsNull()) {
    LOG(INFO) << "[Basarunaa-renderer] OnAnalyzed: element gone, no-op";
    return;
  }
  if (persons.empty()) {
    element.SetAttribute(blink::WebString::FromASCII("style"), original_style);
    blink::WebString readback =
        element.GetAttribute(blink::WebString::FromASCII("style"));
    LOG(INFO) << "[Basarunaa-renderer] OnAnalyzed: blur restored — style=\""
              << readback.Utf8() << "\"";
  } else {
    LOG(INFO) << "[Basarunaa-renderer] OnAnalyzed: keeping blur (person found)";
  }
}

}  // namespace basarunaa
