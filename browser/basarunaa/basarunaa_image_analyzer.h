// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_BROWSER_BASARUNAA_BASARUNAA_IMAGE_ANALYZER_H_
#define BRAVE_BROWSER_BASARUNAA_BASARUNAA_IMAGE_ANALYZER_H_

#include <string>
#include <vector>

#include "base/memory/weak_ptr.h"
#include "brave/components/basarunaa/common/mojom/basarunaa.mojom.h"
#include "content/public/browser/web_contents_user_data.h"
#include "mojo/public/cpp/base/big_buffer.h"
#include "mojo/public/cpp/bindings/pending_receiver.h"
#include "mojo/public/cpp/bindings/receiver_set.h"

namespace content {
class RenderFrameHost;
class WebContents;
}  // namespace content

namespace basarunaa {

// Browser-side handler de l'interface Mojo ImageAnalyzer, appelé par le RFO
// renderer avec les frames vidéo décodées-en-avance (BGRA). Fait tourner le
// vrai ML (YOLO11n-pose via BasarunaaService::AnalyzeImageRgba) sur le
// ThreadPool et répond les personnes détectées au renderer (-> overlay de flou).
//
// Canal Mojo non-associé (`mojo::ReceiverSet`, pattern Skus) : le bridge V1
// précédent utilisait `AssociatedRemote` côté JS+V8 et crashait sous stress
// (chaîne V8/cppgc) — ce canal C++→C++ dédié s'est avéré stable.
//
// Cap 1 analyse YOLO en vol (|analysis_in_flight_|) : les frames qui arrivent
// pendant qu'une analyse tourne sont droppées (évite deux AnalyzeImageRgba
// concurrentes = crash flaky, + cap "frames en vol" du design §11).
class BasarunaaImageAnalyzer
    : public content::WebContentsUserData<BasarunaaImageAnalyzer>,
      public mojom::ImageAnalyzer {
 public:
  BasarunaaImageAnalyzer(const BasarunaaImageAnalyzer&) = delete;
  BasarunaaImageAnalyzer& operator=(const BasarunaaImageAnalyzer&) = delete;
  ~BasarunaaImageAnalyzer() override;

  // Registered from BraveContentBrowserClient::
  // RegisterBrowserInterfaceBindersForFrame via map->Add<>().
  static void BindReceiver(
      content::RenderFrameHost* rfh,
      mojo::PendingReceiver<mojom::ImageAnalyzer> receiver);

 private:
  friend class content::WebContentsUserData<BasarunaaImageAnalyzer>;

  explicit BasarunaaImageAnalyzer(content::WebContents* web_contents);

  // mojom::ImageAnalyzer:
  void AnalyzeImage(mojo_base::BigBuffer pixels,
                    int32_t width,
                    int32_t height,
                    mojom::ImageFormat format,
                    AnalyzeImageCallback callback) override;

  // Reçoit le résultat YOLO (calculé sur le ThreadPool) et répond au renderer
  // sur le thread UI. Gate WeakPtr : si l'analyzer est détruit entretemps, la
  // réponse Mojo est simplement abandonnée (pipe fermé). debug_mode +
  // blur_enabled sont lus côté UI et renvoyés tels quels au renderer (overlay).
  void OnAnalyzeDone(AnalyzeImageCallback callback,
                     std::string debug_mode,
                     bool blur_enabled,
                     std::vector<mojom::AnalyzedPersonPtr> persons);

  mojo::ReceiverSet<mojom::ImageAnalyzer> receivers_;

  // ④ : cap 1 analyse YOLO en vol (thread UI). Les frames qui arrivent pendant
  // qu'une analyse tourne sur le ThreadPool sont DROPPÉES (répondent []), ce qui
  // (a) évite deux AnalyzeImageRgba concurrentes (crash flaky observé) et
  // (b) implémente le cap "frames en vol" du design §11. Accès UI thread only.
  bool analysis_in_flight_ = false;

  WEB_CONTENTS_USER_DATA_KEY_DECL();

  base::WeakPtrFactory<BasarunaaImageAnalyzer> weak_factory_{this};
};

}  // namespace basarunaa

#endif  // BRAVE_BROWSER_BASARUNAA_BASARUNAA_IMAGE_ANALYZER_H_
