// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/components/basarunaa/renderer/basarunaa_render_frame_observer.h"

#include "base/logging.h"
#include "content/public/renderer/render_frame.h"
#include "third_party/blink/public/platform/web_string.h"
#include "third_party/blink/public/web/web_document.h"
#include "third_party/blink/public/web/web_element.h"
#include "third_party/blink/public/web/web_element_collection.h"
#include "third_party/blink/public/web/web_local_frame.h"
#include "third_party/skia/include/core/SkBitmap.h"
#include "ui/gfx/geometry/size.h"

namespace basarunaa {

BasarunaaRenderFrameObserver::BasarunaaRenderFrameObserver(
    content::RenderFrame* render_frame)
    : content::RenderFrameObserver(render_frame) {}

BasarunaaRenderFrameObserver::~BasarunaaRenderFrameObserver() = default;

void BasarunaaRenderFrameObserver::OnDestruct() {
  delete this;
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
    VLOG(1) << "[Basarunaa-renderer] image " << bitmap.width() << "x"
            << bitmap.height()
            << " color=" << static_cast<int>(bitmap.colorType())
            << " bytes=" << bitmap.computeByteSize();
  }
  if (total_imgs > 0) {
    LOG(INFO) << "[Basarunaa-renderer] DidFinishLoad — " << with_pixels << "/"
              << total_imgs << " <img> decoded on "
              << document.Url().GetString().Utf8();
  }
}

}  // namespace basarunaa
