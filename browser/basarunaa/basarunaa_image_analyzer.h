// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_BROWSER_BASARUNAA_BASARUNAA_IMAGE_ANALYZER_H_
#define BRAVE_BROWSER_BASARUNAA_BASARUNAA_IMAGE_ANALYZER_H_

#include <vector>

#include "brave/components/basarunaa/common/mojom/basarunaa.mojom.h"
#include "content/public/browser/render_frame_host_receiver_set.h"
#include "content/public/browser/web_contents_user_data.h"
#include "mojo/public/cpp/bindings/pending_associated_receiver.h"
#include "mojo/public/cpp/base/big_buffer.h"

namespace content {
class RenderFrameHost;
class WebContents;
}  // namespace content

namespace basarunaa {

// Phase 3.1.5 — M2.1. Browser-process side of the ImageAnalyzer interface.
// One TabHelper per WebContents; the underlying RenderFrameHostReceiverSet
// dispatches calls coming from each RenderFrameHost (main frame + iframes).
//
// For M2.1 the implementation is a stub: it logs the request shape and
// returns an empty `persons` array. M2.2c will plumb the buffer through
// BasarunaaService::AnalyzeImageRgba on a worker pool.
class BasarunaaImageAnalyzer
    : public content::WebContentsUserData<BasarunaaImageAnalyzer>,
      public mojom::ImageAnalyzer {
 public:
  BasarunaaImageAnalyzer(const BasarunaaImageAnalyzer&) = delete;
  BasarunaaImageAnalyzer& operator=(const BasarunaaImageAnalyzer&) = delete;
  ~BasarunaaImageAnalyzer() override;

  // Registered from BraveContentBrowserClient::
  // RegisterAssociatedInterfaceBindersForRenderFrameHost.
  static void BindReceiver(
      content::RenderFrameHost* rfh,
      mojo::PendingAssociatedReceiver<mojom::ImageAnalyzer> receiver);

 private:
  friend class content::WebContentsUserData<BasarunaaImageAnalyzer>;

  explicit BasarunaaImageAnalyzer(content::WebContents* web_contents);

  // mojom::ImageAnalyzer:
  void AnalyzeImage(mojo_base::BigBuffer pixels,
                    int32_t width,
                    int32_t height,
                    mojom::ImageFormat format,
                    AnalyzeImageCallback callback) override;

  content::RenderFrameHostReceiverSet<mojom::ImageAnalyzer> receivers_;

  WEB_CONTENTS_USER_DATA_KEY_DECL();
};

}  // namespace basarunaa

#endif  // BRAVE_BROWSER_BASARUNAA_BASARUNAA_IMAGE_ANALYZER_H_
