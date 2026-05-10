// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/browser/basarunaa/basarunaa_image_analyzer.h"

#include <utility>
#include <vector>

#include "base/functional/bind.h"
#include "base/logging.h"
#include "base/task/thread_pool.h"
#include "brave/browser/basarunaa/basarunaa_service_factory.h"
#include "brave/components/basarunaa/core/basarunaa_service.h"
#include "chrome/browser/profiles/profile.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/web_contents.h"

namespace basarunaa {

// static
void BasarunaaImageAnalyzer::BindReceiver(
    content::RenderFrameHost* rfh,
    mojo::PendingAssociatedReceiver<mojom::ImageAnalyzer> receiver) {
  auto* web_contents = content::WebContents::FromRenderFrameHost(rfh);
  if (!web_contents) {
    return;
  }
  BasarunaaImageAnalyzer::CreateForWebContents(web_contents);
  if (auto* analyzer =
          BasarunaaImageAnalyzer::FromWebContents(web_contents)) {
    analyzer->receivers_.Bind(rfh, std::move(receiver));
  }
}

BasarunaaImageAnalyzer::BasarunaaImageAnalyzer(
    content::WebContents* web_contents)
    : content::WebContentsUserData<BasarunaaImageAnalyzer>(*web_contents),
      receivers_(web_contents, this) {}

BasarunaaImageAnalyzer::~BasarunaaImageAnalyzer() = default;

namespace {

// Worker-pool stage. Runs AnalyzeImageRgba on the YOLO session and converts
// the result into Mojo structs ready to be sent back. We pass the
// BasarunaaService raw pointer because the service is a KeyedService for the
// profile and outlives any individual ImageAnalyzer call (the receiver is
// torn down well before profile shutdown). `pixels` is moved into this lambda
// so the buffer lives until inference is done.
std::vector<mojom::AnalyzedPersonPtr> AnalyzeOnWorker(
    BasarunaaService* service,
    mojo_base::BigBuffer pixels,
    int32_t width,
    int32_t height,
    bool bgra) {
  std::vector<mojom::AnalyzedPersonPtr> result;
  if (!service) {
    return result;
  }
  // Sanity check: the renderer is untrusted, so the buffer size must match
  // the declared dimensions. Reject mismatches outright.
  if (width <= 0 || height <= 0) {
    LOG(WARNING) << "[Basarunaa] AnalyzeImage rejected: bad dims " << width
                 << "x" << height;
    return result;
  }
  const size_t expected =
      static_cast<size_t>(width) * static_cast<size_t>(height) * 4u;
  if (pixels.size() != expected) {
    LOG(WARNING) << "[Basarunaa] AnalyzeImage rejected: size mismatch got "
                 << pixels.size() << " expected " << expected;
    return result;
  }

  std::vector<DetectedPerson> persons =
      service->AnalyzeImageRgba(pixels.data(), width, height, bgra);

  result.reserve(persons.size());
  for (const auto& p : persons) {
    auto m = mojom::AnalyzedPerson::New();
    m->x = p.x;
    m->y = p.y;
    m->w = p.w;
    m->h = p.h;
    m->score = p.score;
    m->keypoints.reserve(p.keypoints.size());
    for (const auto& kp : p.keypoints) {
      auto mk = mojom::KeyPoint::New();
      mk->x = kp.x;
      mk->y = kp.y;
      mk->confidence = kp.confidence;
      m->keypoints.push_back(std::move(mk));
    }
    if (p.face_bbox) {
      auto mb = mojom::Bbox::New();
      mb->x1 = p.face_bbox->x1;
      mb->y1 = p.face_bbox->y1;
      mb->x2 = p.face_bbox->x2;
      mb->y2 = p.face_bbox->y2;
      m->face_bbox = std::move(mb);
    }
    result.push_back(std::move(m));
  }
  return result;
}

}  // namespace

void BasarunaaImageAnalyzer::AnalyzeImage(mojo_base::BigBuffer pixels,
                                          int32_t width,
                                          int32_t height,
                                          mojom::ImageFormat format,
                                          AnalyzeImageCallback callback) {
  const bool bgra = (format == mojom::ImageFormat::kBgra8);
  LOG(INFO) << "[Basarunaa] AnalyzeImage: " << width << "x" << height
            << " bytes=" << pixels.size() << " fmt=" << (bgra ? "BGRA" : "RGBA");

  auto* rfh = receivers_.GetCurrentTargetFrame();
  if (!rfh) {
    LOG(WARNING) << "[Basarunaa] AnalyzeImage bailout: rfh=null";
    std::move(callback).Run({});
    return;
  }
  auto* profile =
      Profile::FromBrowserContext(rfh->GetBrowserContext());
  auto* service = BasarunaaServiceFactory::GetForProfile(profile);
  if (!service) {
    LOG(WARNING) << "[Basarunaa] AnalyzeImage bailout: service=null profile="
                 << profile;
    std::move(callback).Run({});
    return;
  }

  base::ThreadPool::PostTaskAndReplyWithResult(
      FROM_HERE, {base::MayBlock(), base::TaskPriority::USER_VISIBLE},
      base::BindOnce(&AnalyzeOnWorker, service, std::move(pixels), width,
                     height, bgra),
      std::move(callback));
}

WEB_CONTENTS_USER_DATA_KEY_IMPL(BasarunaaImageAnalyzer);

}  // namespace basarunaa
