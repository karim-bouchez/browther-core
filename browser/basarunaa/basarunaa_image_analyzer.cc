// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/browser/basarunaa/basarunaa_image_analyzer.h"

#include <algorithm>
#include <array>
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

// Hash 8×8 grayscale (moyenne par bloc) — port de core/video/frame-diff.ts.
// Grayscale pondéré (R*2 + G*3 + B)/6 comme la v1. Buffer packé BGRA/RGBA.
std::array<uint8_t, 64> ComputeHash8x8(base::span<const uint8_t> px,
                                       int w,
                                       int h,
                                       bool bgra) {
  std::array<uint64_t, 64> sum = {};
  std::array<uint32_t, 64> cnt = {};
  const size_t r_idx = bgra ? 2 : 0;
  const size_t b_idx = bgra ? 0 : 2;
  for (int y = 0; y < h; ++y) {
    const int cy = std::min(7, y * 8 / h);
    for (int x = 0; x < w; ++x) {
      const int cx = std::min(7, x * 8 / w);
      const size_t off = (static_cast<size_t>(y) * w + x) * 4;
      const uint32_t gray =
          (px[off + r_idx] * 2u + px[off + 1] * 3u + px[off + b_idx]) / 6u;
      const int cell = cy * 8 + cx;
      sum[cell] += gray;
      cnt[cell] += 1;
    }
  }
  std::array<uint8_t, 64> hash = {};
  for (int i = 0; i < 64; ++i) {
    hash[i] = cnt[i] ? static_cast<uint8_t>(sum[i] / cnt[i]) : 0;
  }
  return hash;
}

// Ratio de diff [0,1] entre deux hash (somme des |Δ| / (64*255)).
float HashDiff(const std::array<uint8_t, 64>& a,
               const std::array<uint8_t, 64>& b) {
  int total = 0;
  for (int i = 0; i < 64; ++i) {
    const int d = static_cast<int>(a[i]) - static_cast<int>(b[i]);
    total += d < 0 ? -d : d;
  }
  return total / (64.f * 255.f);
}

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

// Exécuté sur le ThreadPool (YOLO ~100-230 ms + genderage/pplcnet, ne doit PAS
// bloquer le thread UI). Le service est profile-keyed et vit toute la session ;
// AnalyzeImageRgba est sérialisé globalement (analyze_mutex_, cf. header). On
// renvoie TOUTES les personnes (pas seulement celles à flouter) avec leur genre
// + conf + le flag `blur` (décision shouldBlur) : l'overlay a besoin de tout
// pour le mode debug ; en mode normal il ne floute que `blur==true`.
std::vector<mojom::AnalyzedPersonPtr> RunYoloOnPool(BasarunaaService* service,
                                                    std::vector<uint8_t> pixels,
                                                    int width,
                                                    int height,
                                                    bool bgra,
                                                    std::string mode,
                                                    double certainty) {
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
    ap->gender = GenderToInt(p.gender);
    ap->gender_source = static_cast<int8_t>(p.gender_source);
    ap->gender_conf = p.gender_conf;
    ap->blur = ShouldBlur(p, mode, certainty);
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
    std::move(callback).Run({}, "", false);
    return;
  }

  // Cap 1 analyse en vol : DROP les frames qui arrivent pendant qu'une YOLO
  // tourne (évite AnalyzeImageRgba concurrentes + cap design §11).
  if (analysis_in_flight_) {
    std::move(callback).Run({}, "", false);
    return;
  }

  auto* profile =
      Profile::FromBrowserContext(GetWebContents().GetBrowserContext());
  auto* service =
      profile ? BasarunaaServiceFactory::GetForProfile(profile) : nullptr;
  if (!service) {
    std::move(callback).Run({}, "", false);
    return;
  }
  // Prefs lues sur le thread UI (obligatoire). mode + certitude → pool (calcul
  // du flag blur). debug_mode + blur_enabled → renvoyés au renderer (overlay :
  // dessin des boîtes debug + gating du flou). Défauts = ceux du POC.
  std::string mode = "blur-female";
  double certainty = 0.70;
  std::string debug_mode = "none";
  bool blur_enabled = true;
  if (auto* prefs = profile->GetPrefs()) {
    mode = prefs->GetString(kBasarunaaMode);
    certainty = prefs->GetDouble(kBasarunaaGenderCertainty);
    debug_mode = prefs->GetString(kBasarunaaDebugMode);
    blur_enabled = prefs->GetBoolean(kBasarunaaBlurEnabled);
  }

  // BigBuffer -> span (conversion implicite), bornée à |expected|.
  const auto full = base::span(pixels).first(expected);

  // Scene-gating (frame-diff, port core/video/frame-diff.ts) : si la scène n'a
  // quasiment pas bougé depuis la dernière analyse, on SKIP les 2 YOLO +
  // classifs et on réutilise le dernier résultat (persons toujours valides sur
  // du statique). |skip_count_| force un refresh périodique. → sur du contenu
  // statique (plan fixe, tête qui parle), les YOLO ne retournent quasiment pas.
  const std::array<uint8_t, 64> hash =
      ComputeHash8x8(full, width, height, bgra);
  constexpr float kSceneSkipThreshold = 0.02f;
  constexpr int kMaxConsecutiveSkips = 20;  // ~10 s à 2 analyses/s
  if (has_last_hash_ && skip_count_ < kMaxConsecutiveSkips &&
      HashDiff(hash, last_hash_) < kSceneSkipThreshold) {
    ++skip_count_;
    std::vector<mojom::AnalyzedPersonPtr> clone;
    clone.reserve(last_persons_.size());
    for (const auto& p : last_persons_) {
      clone.push_back(p->Clone());
    }
    std::move(callback).Run(std::move(clone), debug_mode, blur_enabled);
    return;
  }
  skip_count_ = 0;
  last_hash_ = hash;
  has_last_hash_ = true;
  analysis_in_flight_ = true;

  // Copie le buffer (BigBuffer peut être en mémoire partagée) dans un vector
  // possédé par la tâche pool. Itérateurs sûrs -> pas d'arithmétique de
  // pointeur (-Wunsafe-buffer-usage).
  std::vector<uint8_t> buf(full.begin(), full.end());

  // ⚠️ Le reply est gaté par WeakPtr : si ce WebContentsUserData est détruit
  // (fermeture d'onglet) pendant que la tâche est en vol, OnAnalyzeDone ne tourne
  // PAS et le callback Mojo serait détruit SANS être exécuté → use-after-free du
  // responder Mojo au teardown (corruption de tas confirmée Sentry, bisect
  // 2026-07-02). WrapCallbackWithDefaultInvokeIfNotRun garantit que le callback
  // est TOUJOURS invoqué (avec un résultat vide s'il est droppé) → jamais de
  // responder dangling.
  auto safe_callback = mojo::WrapCallbackWithDefaultInvokeIfNotRun(
      std::move(callback), std::vector<mojom::AnalyzedPersonPtr>(),
      std::string(), false);

  base::ThreadPool::PostTaskAndReplyWithResult(
      FROM_HERE,
      {base::MayBlock(), base::TaskPriority::USER_VISIBLE,
       base::TaskShutdownBehavior::SKIP_ON_SHUTDOWN},
      base::BindOnce(&RunYoloOnPool, base::Unretained(service), std::move(buf),
                     width, height, bgra, std::move(mode), certainty),
      base::BindOnce(&BasarunaaImageAnalyzer::OnAnalyzeDone,
                     weak_factory_.GetWeakPtr(), std::move(safe_callback),
                     std::move(debug_mode), blur_enabled));
}

void BasarunaaImageAnalyzer::OnAnalyzeDone(
    AnalyzeImageCallback callback,
    std::string debug_mode,
    bool blur_enabled,
    std::vector<mojom::AnalyzedPersonPtr> persons) {
  analysis_in_flight_ = false;
  // Cache le résultat pour le scene-gating : réutilisé tant que la scène reste
  // statique (frame-diff < seuil). |last_hash_| a déjà été posé dans AnalyzeImage.
  last_persons_.clear();
  last_persons_.reserve(persons.size());
  for (const auto& p : persons) {
    last_persons_.push_back(p->Clone());
  }
  LOG(INFO) << "[Basarunaa/YOLO] " << persons.size() << " persons";
  std::move(callback).Run(std::move(persons), std::move(debug_mode),
                          blur_enabled);
}

WEB_CONTENTS_USER_DATA_KEY_IMPL(BasarunaaImageAnalyzer);

}  // namespace basarunaa
