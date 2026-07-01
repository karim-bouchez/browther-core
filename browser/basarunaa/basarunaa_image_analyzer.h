// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_BROWSER_BASARUNAA_BASARUNAA_IMAGE_ANALYZER_H_
#define BRAVE_BROWSER_BASARUNAA_BASARUNAA_IMAGE_ANALYZER_H_

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

// Phase 3.1.5 — Étape 2 mini-spike (2026-05-10). Browser-side handler de
// l'interface ImageAnalyzer pour le hook renderer C++ (M2.2).
//
// **Stub V1** : retourne toujours un vector vide. Le but ici est de valider
// que le pattern Mojo IPC C++ → C++ ne crashe pas sous stress, indépendamment
// de l'inférence ML. Quand le pattern est validé, on branchera
// BasarunaaService::AnalyzeImageRgba (M2.2c).
//
// Non-associated `mojo::ReceiverSet` (canal Mojo dédié, pattern Skus). Le
// précédent bridge utilisait `AssociatedRemote` côté JS+V8 et a crashé sous
// stress — hypothèse : la chaîne V8/cppgc, pas Mojo. À confirmer ici.
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
  // réponse Mojo est simplement abandonnée (pipe fermé).
  void OnAnalyzeDone(AnalyzeImageCallback callback,
                     std::vector<mojom::AnalyzedPersonPtr> persons);

  mojo::ReceiverSet<mojom::ImageAnalyzer> receivers_;

  WEB_CONTENTS_USER_DATA_KEY_DECL();

  base::WeakPtrFactory<BasarunaaImageAnalyzer> weak_factory_{this};
};

}  // namespace basarunaa

#endif  // BRAVE_BROWSER_BASARUNAA_BASARUNAA_IMAGE_ANALYZER_H_
