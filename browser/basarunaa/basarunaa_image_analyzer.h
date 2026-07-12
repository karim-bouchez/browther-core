// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_BROWSER_BASARUNAA_BASARUNAA_IMAGE_ANALYZER_H_
#define BRAVE_BROWSER_BASARUNAA_BASARUNAA_IMAGE_ANALYZER_H_

#include <array>
#include <cstdint>
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

// Résultat de la tâche pool (RunYoloOnPool → OnAnalyzeDone) : personnes +
// score NSFW image entière (Marqo). Doit être visible ici car c'est le type de
// retour passé à OnAnalyzeDone par PostTaskAndReplyWithResult. Move-only (le
// vecteur de StructPtr Mojo n'est pas copiable).
struct PoolResult {
  PoolResult();
  PoolResult(PoolResult&&) noexcept;
  PoolResult& operator=(PoolResult&&) noexcept;
  PoolResult(const PoolResult&) = delete;
  PoolResult& operator=(const PoolResult&) = delete;
  ~PoolResult();
  std::vector<mojom::AnalyzedPersonPtr> persons;
  float nsfw_score = -1.f;   // Marqo (image entière), < 0 si non checké/indispo
  bool nsfw_exposed = false;  // NudeNet : partie exposée détectée
};

// Browser-side handler de l'interface Mojo ImageAnalyzer, appelé par le RFO
// renderer avec les frames vidéo décodées-en-avance (BGRA). Fait tourner le
// vrai ML (YOLO11n-pose via BasarunaaService::AnalyzeImageRgba) sur le
// ThreadPool et répond les personnes détectées au renderer (-> overlay de flou).
//
// Canal Mojo non-associé (`mojo::ReceiverSet`, pattern Skus) : le bridge V1
// précédent utilisait `AssociatedRemote` côté JS+V8 et crashait sous stress
// (chaîne V8/cppgc) — ce canal C++→C++ dédié s'est avéré stable.
//
// Refonte 2026-07-04 : plus AUCUNE cadence ici. Le browser analyse
// inconditionnellement chaque frame reçue (le RFO renderer a déjà filtré :
// keyframes + frontières de cut). La non-concurrence des inférences est garantie
// par BasarunaaService::analyze_mutex_ (global), donc pas de cap "1 en vol" (qui
// droppait fautivement la 2e frame d'une paire n-1/n de cut).
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
                    bool want_nsfw,
                    AnalyzeImageCallback callback) override;

  // Reçoit le résultat YOLO (calculé sur le ThreadPool) et répond au renderer
  // sur le thread UI. Gate WeakPtr : si l'analyzer est détruit entretemps, la
  // réponse Mojo est simplement abandonnée (pipe fermé). debug_mode,
  // blur_enabled, mode + gender_certainty sont lus côté UI et renvoyés tels quels
  // au renderer (overlay : dessin debug, gating flou, recalcul shouldBlur voté).
  void OnAnalyzeDone(AnalyzeImageCallback callback,
                     std::string debug_mode,
                     bool blur_enabled,
                     std::string mode,
                     double gender_certainty,
                     double min_skeleton,
                     double nsfw_conf,
                     bool censor_eyes,
                     PoolResult result);

  // #18 : compte les personnes floutées (genre fusionné browser, `p->blur`) et
  // incrémente le compteur cumulatif NTP, dédupliqué par IoU vs l'analyse
  // précédente (sinon +N à chaque keyframe). Voir .cc pour la sémantique.
  void CountBlurredPersons(
      const std::vector<mojom::AnalyzedPersonPtr>& persons,
      bool blur_enabled);
  // Bbox {x, y, w, h} (pixels) des personnes floutées à l'analyse précédente.
  std::vector<std::array<float, 4>> prev_blurred_boxes_;

  mojo::ReceiverSet<mojom::ImageAnalyzer> receivers_;

  WEB_CONTENTS_USER_DATA_KEY_DECL();

  base::WeakPtrFactory<BasarunaaImageAnalyzer> weak_factory_{this};
};

}  // namespace basarunaa

#endif  // BRAVE_BROWSER_BASARUNAA_BASARUNAA_IMAGE_ANALYZER_H_
