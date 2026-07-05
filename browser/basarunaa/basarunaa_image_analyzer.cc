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
#include "brave/components/constants/pref_names.h"
#include "chrome/browser/profiles/profile.h"
#include "components/prefs/pref_service.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/web_contents.h"
#include "mojo/public/cpp/bindings/callback_helpers.h"

namespace basarunaa {

namespace {

// Décision de floutage, port de VIDEO_V2.md §4 (chemin VIDÉO, plus prudent que
// content.js image) : flouter si `gender===target` OU `genderConf < certainty`
// OU `gender==null`. « Inconnu = sûr » : une personne sans visage exploitable
// (dos tourné, floue…) a gender_conf = -1, donc captée par le filet
// `conf < certainty` → floutée. Seuls les NON-cibles classifiés avec confiance
// (ex. homme sûr en mode blur-female) sont épargnés.
bool ShouldBlur(const DetectedPerson& p,
                const std::string& mode,
                double certainty) {
  if (mode == "blur-all") {
    return true;
  }
  const bool female_target = (mode == "blur-female");
  const bool male_target = (mode == "blur-male");
  if (!female_target && !male_target) {
    return false;  // mode inattendu → ne floute rien
  }
  const Gender target = female_target ? Gender::kFemale : Gender::kMale;
  if (p.gender == target) {
    return true;
  }
  // Filet privacy : non-cible peu sûr OU non classifié (conf -1) → floute.
  if (p.gender_conf < certainty) {
    return true;
  }
  return false;
}

int8_t GenderToInt(Gender g) {
  switch (g) {
    case Gender::kFemale:
      return 1;
    case Gender::kMale:
      return 0;
    default:
      return -1;
  }
}

// Exécuté sur le ThreadPool (pipeline full pose+face+genre+corps, ~57 ms en
// kOrtDetectorThreads, ne doit PAS bloquer le thread UI). Le service est
// profile-keyed et vit toute la session ; AnalyzeImageRgba est sérialisé
// globalement (analyze_mutex_, cf. header). On renvoie TOUTES les personnes
// (pas seulement celles à flouter) avec leur genre + conf + le flag `blur`
// (décision shouldBlur) : l'overlay a besoin de tout pour le mode debug ; en
// mode normal il ne floute que `blur==true`.
PoolResult RunYoloOnPool(BasarunaaService* service,
                         std::vector<uint8_t> pixels,
                         int width,
                         int height,
                         bool bgra,
                         std::string mode,
                         double certainty,
                         double conf_body,
                         double conf_face,
                         bool want_nsfw,
                         double nudenet_conf) {
  PoolResult res;
  std::vector<mojom::AnalyzedPersonPtr>& out = res.persons;
  float nsfw_score = -1.f;
  bool nsfw_exposed = false;
  // Marqo + NudeNet (NSFW, ~120ms) seulement quand le RFO le demande (throttle
  // ~1/s + cuts) : sinon out-params nullptr → le service saute les 2 modèles
  // (score reste -1, exposed false → l'overlay gèle le dernier verdict).
  const std::vector<DetectedPerson> persons = service->AnalyzeImageRgba(
      pixels.data(), width, height, bgra, static_cast<float>(conf_body),
      static_cast<float>(conf_face), want_nsfw ? &nsfw_score : nullptr,
      want_nsfw ? &nsfw_exposed : nullptr, static_cast<float>(nudenet_conf));
  res.nsfw_score = nsfw_score;
  res.nsfw_exposed = nsfw_exposed;
  out.reserve(persons.size());
  for (const DetectedPerson& p : persons) {
    auto ap = mojom::AnalyzedPerson::New();
    ap->x = p.x;
    ap->y = p.y;
    ap->w = p.w;
    ap->h = p.h;
    ap->score = p.score;
    ap->gender = GenderToInt(p.gender);
    ap->gender_source = static_cast<int8_t>(p.gender_source);
    ap->gender_conf = p.gender_conf;
    ap->blur = ShouldBlur(p, mode, certainty);
    // Sorties BRUTES par-modèle → fusion + vote temporel + debug côté overlay.
    ap->face_gender = GenderToInt(p.face_gender);
    ap->face_conf = p.face_conf;
    ap->body_gender = GenderToInt(p.body_gender);
    ap->body_conf = p.body_conf;
    ap->has_legs = p.has_legs;
    // Keypoints normalisés [0,1] → squelette debug + filtre min-squelette + flou
    // polygone côté overlay.
    ap->keypoints.reserve(p.keypoints.size());
    const float fw = width > 0 ? width : 1;
    const float fh = height > 0 ? height : 1;
    for (const DetectedKeyPoint& kp : p.keypoints) {
      auto mk = mojom::KeyPoint::New();
      mk->x = kp.x / fw;
      mk->y = kp.y / fh;
      mk->confidence = kp.confidence;
      ap->keypoints.push_back(std::move(mk));
    }
    out.push_back(std::move(ap));
  }
  return res;
}

}  // namespace

PoolResult::PoolResult() = default;
PoolResult::PoolResult(PoolResult&&) noexcept = default;
PoolResult& PoolResult::operator=(PoolResult&&) noexcept = default;
PoolResult::~PoolResult() = default;

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
                                          bool want_nsfw,
                                          AnalyzeImageCallback callback) {
  // Refonte 2026-07-04 : le browser n'a PLUS AUCUNE cadence. Le RFO renderer a
  // déjà décidé que cette frame vaut une analyse (keyframe à cadence garantie OU
  // frontière n-1/n d'un cut) → on l'analyse INCONDITIONNELLEMENT (plus de hash,
  // plus de full-vs-skip, plus de cap "1 en vol"). La sérialisation des
  // inférences est assurée GLOBALEMENT par BasarunaaService::analyze_mutex_ :
  // deux frames rapprochées (la paire n-1/n d'un cut) sont donc TOUTES DEUX
  // analysées, séquentiellement, sans drop — ce que l'ancien cap cassait.
  const bool bgra = (format == mojom::ImageFormat::kBgra8);
  const size_t expected =
      static_cast<size_t>(width) * static_cast<size_t>(height) * 4u;
  if (width <= 0 || height <= 0 || pixels.size() < expected) {
    std::move(callback).Run({}, "", false, "", 0.0, 0.0, false, -1.0f);
    return;
  }

  auto* profile =
      Profile::FromBrowserContext(GetWebContents().GetBrowserContext());
  auto* service =
      profile ? BasarunaaServiceFactory::GetForProfile(profile) : nullptr;
  if (!service) {
    std::move(callback).Run({}, "", false, "", 0.0, 0.0, false, -1.0f);
    return;
  }
  // Prefs lues sur le thread UI (obligatoire). mode + certitude → pool (calcul
  // du flag blur repli) ET renvoyés au renderer (overlay : recalcul de shouldBlur
  // depuis le genre VOTÉ). conf_body/conf_face → seuils des détecteurs (pool).
  // debug_mode + blur_enabled + min_skeleton → renderer (dessin/gating/filtre).
  // Défauts = ceux du POC.
  std::string mode = "blur-female";
  double certainty = 0.70;
  std::string debug_mode = "none";
  bool blur_enabled = true;
  double conf_body = 0.25;
  double conf_face = 0.30;
  double min_skeleton = 0.0;
  double nsfw_conf = 0.50;
  double nudenet_conf = 0.50;
  if (auto* prefs = profile->GetPrefs()) {
    mode = prefs->GetString(kBasarunaaMode);
    certainty = prefs->GetDouble(kBasarunaaGenderCertainty);
    debug_mode = prefs->GetString(kBasarunaaDebugMode);
    blur_enabled = prefs->GetBoolean(kBasarunaaBlurEnabled);
    conf_body = prefs->GetDouble(kBasarunaaConfBody);
    conf_face = prefs->GetDouble(kBasarunaaConfFace);
    min_skeleton = prefs->GetDouble(kBasarunaaMinSkeleton);
    nsfw_conf = prefs->GetDouble(kBasarunaaNsfwConf);
    nudenet_conf = prefs->GetDouble(kBasarunaaNudenetConf);
  }
  // Copie pour le reply (le pool consomme `mode` par move pour le flag repli).
  std::string mode_reply = mode;

  // BigBuffer -> span (conversion implicite) bornée à |expected|, puis copie
  // dans un vector possédé par la tâche pool (itérateurs sûrs, pas
  // d'arithmétique de pointeur → -Wunsafe-buffer-usage).
  const auto full = base::span(pixels).first(expected);
  std::vector<uint8_t> buf(full.begin(), full.end());

  // ⚠️ WeakPtr gate + WrapCallbackWithDefaultInvokeIfNotRun : si l'onglet est
  // détruit pendant la tâche, le callback est TOUJOURS invoqué (persons vides) →
  // jamais de responder Mojo dangling (corruption de tas confirmée Sentry,
  // bisect 2026-07-02).
  auto safe_callback = mojo::WrapCallbackWithDefaultInvokeIfNotRun(
      std::move(callback), std::vector<mojom::AnalyzedPersonPtr>(),
      std::string(), false, std::string(), 0.0, 0.0, false, -1.0f);

  base::ThreadPool::PostTaskAndReplyWithResult(
      FROM_HERE,
      {base::MayBlock(), base::TaskPriority::USER_VISIBLE,
       base::TaskShutdownBehavior::SKIP_ON_SHUTDOWN},
      base::BindOnce(&RunYoloOnPool, base::Unretained(service), std::move(buf),
                     width, height, bgra, std::move(mode), certainty, conf_body,
                     conf_face, want_nsfw, nudenet_conf),
      base::BindOnce(&BasarunaaImageAnalyzer::OnAnalyzeDone,
                     weak_factory_.GetWeakPtr(), std::move(safe_callback),
                     std::move(debug_mode), blur_enabled,
                     std::move(mode_reply), certainty, min_skeleton, nsfw_conf));
}

void BasarunaaImageAnalyzer::OnAnalyzeDone(
    AnalyzeImageCallback callback,
    std::string debug_mode,
    bool blur_enabled,
    std::string mode,
    double gender_certainty,
    double min_skeleton,
    double nsfw_conf,
    PoolResult result) {
  LOG(INFO) << "[Basarunaa/YOLO] " << result.persons.size() << " persons"
            << " nsfw=" << result.nsfw_score
            << " exposed=" << result.nsfw_exposed;
  // NSFW plein cadre = Marqo au-dessus du seuil OU NudeNet a vu une partie exposée
  // (port v1 : isNsfw = marqo.isNsfw || exposed). L'exposé déclenche même si Marqo
  // (image entière) ne flag pas — gros plans de parties explicites.
  const bool nsfw = (result.nsfw_score >= 0.f &&
                     result.nsfw_score >= static_cast<float>(nsfw_conf)) ||
                    result.nsfw_exposed;
  std::move(callback).Run(std::move(result.persons), std::move(debug_mode),
                          blur_enabled, std::move(mode), gender_certainty,
                          min_skeleton, nsfw, result.nsfw_score);
}

WEB_CONTENTS_USER_DATA_KEY_IMPL(BasarunaaImageAnalyzer);

}  // namespace basarunaa
