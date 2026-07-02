// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/browser/basarunaa/basarunaa_image_analyzer.h"

#include <cstdint>
#include <utility>
#include <vector>

#include "base/containers/span.h"
#include "base/functional/bind.h"
#include "base/logging.h"
#include "base/task/thread_pool.h"
#include "brave/browser/basarunaa/basarunaa_service_factory.h"
#include "brave/components/basarunaa/core/basarunaa_service.h"
#include "chrome/browser/profiles/profile.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/web_contents.h"

namespace basarunaa {

namespace {

// Exécuté sur le ThreadPool (YOLO ~100-230 ms, ne doit PAS bloquer le thread
// UI). Le service est profile-keyed et vit toute la session ; AnalyzeImageRgba
// est thread-safe (std::call_once + Ort::Session::Run réentrant, cf. header).
std::vector<mojom::AnalyzedPersonPtr> RunYoloOnPool(BasarunaaService* service,
                                                    std::vector<uint8_t> pixels,
                                                    int width,
                                                    int height,
                                                    bool bgra) {
  std::vector<mojom::AnalyzedPersonPtr> out;
  const std::vector<DetectedPerson> persons =
      service->AnalyzeImageRgba(pixels.data(), width, height, bgra);
  out.reserve(persons.size());
  for (const DetectedPerson& p : persons) {
    auto ap = mojom::AnalyzedPerson::New();
    ap->x = p.x;
    ap->y = p.y;
    ap->w = p.w;
    ap->h = p.h;
    ap->score = p.score;
    out.push_back(std::move(ap));
  }
  return out;
}

}  // namespace

// static
void BasarunaaImageAnalyzer::BindReceiver(
    content::RenderFrameHost* rfh,
    mojo::PendingReceiver<mojom::ImageAnalyzer> receiver) {
  auto* web_contents = content::WebContents::FromRenderFrameHost(rfh);
  if (!web_contents) {
    return;
  }
  BasarunaaImageAnalyzer::CreateForWebContents(web_contents);
  if (auto* analyzer =
          BasarunaaImageAnalyzer::FromWebContents(web_contents)) {
    analyzer->receivers_.Add(analyzer, std::move(receiver));
  }
}

BasarunaaImageAnalyzer::BasarunaaImageAnalyzer(
    content::WebContents* web_contents)
    : content::WebContentsUserData<BasarunaaImageAnalyzer>(*web_contents) {}

BasarunaaImageAnalyzer::~BasarunaaImageAnalyzer() = default;

void BasarunaaImageAnalyzer::AnalyzeImage(mojo_base::BigBuffer pixels,
                                          int32_t width,
                                          int32_t height,
                                          mojom::ImageFormat format,
                                          AnalyzeImageCallback callback) {
  // ③b : vrai ML natif (YOLO11n-pose) sur le ThreadPool. Le buffer arrive en
  // BGRA (kBgra8, cf. WebMediaPlayerImpl::OnLeadFrame + kN32 Apple).
  const bool bgra = (format == mojom::ImageFormat::kBgra8);
  const size_t expected = static_cast<size_t>(width) *
                          static_cast<size_t>(height) * 4u;
  if (width <= 0 || height <= 0 || pixels.size() < expected) {
    std::move(callback).Run({});
    return;
  }

  // Cap 1 analyse en vol : DROP les frames qui arrivent pendant qu'une YOLO
  // tourne (évite AnalyzeImageRgba concurrentes + cap design §11).
  if (analysis_in_flight_) {
    std::move(callback).Run({});
    return;
  }

  auto* profile =
      Profile::FromBrowserContext(GetWebContents().GetBrowserContext());
  auto* service =
      profile ? BasarunaaServiceFactory::GetForProfile(profile) : nullptr;
  if (!service) {
    std::move(callback).Run({});
    return;
  }
  analysis_in_flight_ = true;

  // Copie le buffer (BigBuffer peut être en mémoire partagée) dans un vector
  // possédé par la tâche pool. BigBuffer -> span (conversion implicite), puis
  // itérateurs sûrs -> pas d'arithmétique de pointeur (-Wunsafe-buffer-usage).
  const auto src = base::span(pixels).first(expected);
  std::vector<uint8_t> buf(src.begin(), src.end());

  base::ThreadPool::PostTaskAndReplyWithResult(
      FROM_HERE,
      {base::MayBlock(), base::TaskPriority::USER_VISIBLE,
       base::TaskShutdownBehavior::SKIP_ON_SHUTDOWN},
      base::BindOnce(&RunYoloOnPool, base::Unretained(service), std::move(buf),
                     width, height, bgra),
      base::BindOnce(&BasarunaaImageAnalyzer::OnAnalyzeDone,
                     weak_factory_.GetWeakPtr(), std::move(callback)));
}

void BasarunaaImageAnalyzer::OnAnalyzeDone(
    AnalyzeImageCallback callback,
    std::vector<mojom::AnalyzedPersonPtr> persons) {
  analysis_in_flight_ = false;
  LOG(INFO) << "[Basarunaa/YOLO] " << persons.size() << " persons";
  std::move(callback).Run(std::move(persons));
}

WEB_CONTENTS_USER_DATA_KEY_IMPL(BasarunaaImageAnalyzer);

}  // namespace basarunaa
