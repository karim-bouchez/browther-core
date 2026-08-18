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

#include "base/atomic_sequence_num.h"
#include "base/base_paths.h"
#include "base/containers/span.h"
#include "base/files/file_path.h"
#include "base/files/file_util.h"
#include "base/functional/bind.h"
#include "base/logging.h"
#include "base/path_service.h"
#include "base/strings/stringprintf.h"
#include "base/strings/utf_string_conversions.h"
#include "base/task/thread_pool.h"
#include "base/time/time.h"
#include "build/build_config.h"
#include "brave/browser/basarunaa/basarunaa_service_factory.h"
#include "brave/components/basarunaa/core/basarunaa_features.h"
#include "brave/components/basarunaa/core/basarunaa_service.h"
#include "brave/components/browther_analytics/browther_analytics_service.h"
#include "third_party/skia/include/core/SkBitmap.h"
#include "third_party/skia/include/core/SkColor.h"
#include "third_party/skia/include/core/SkImageInfo.h"
#include "ui/gfx/canvas.h"
#include "ui/gfx/codec/png_codec.h"
#include "ui/gfx/font_list.h"
#include "ui/gfx/geometry/rect.h"
#include "ui/gfx/geometry/rect_f.h"
#include "ui/gfx/geometry/size.h"
#include "ui/gfx/image/image_skia.h"
#include "brave/components/constants/pref_names.h"
#include "chrome/browser/profiles/profile.h"
#include "components/prefs/pref_service.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/web_contents.h"
#include "mojo/public/cpp/bindings/callback_helpers.h"

namespace basarunaa {

namespace {

// #18 stats : IoU de deux bbox {x, y, w, h} (pixels). Sert à dédupliquer les
// personnes floutées entre analyses successives (même seuil que l'overlay).
constexpr float kBlurTrackIoU = 0.2f;
float BoxIoU(const std::array<float, 4>& a, const std::array<float, 4>& b) {
  const float ix1 = std::max(a[0], b[0]);
  const float iy1 = std::max(a[1], b[1]);
  const float ix2 = std::min(a[0] + a[2], b[0] + b[2]);
  const float iy2 = std::min(a[1] + a[3], b[1] + b[3]);
  const float iw = std::max(0.f, ix2 - ix1);
  const float ih = std::max(0.f, iy2 - iy1);
  const float inter = iw * ih;
  const float uni = a[2] * a[3] + b[2] * b[3] - inter;
  return uni > 0.f ? inter / uni : 0.f;
}

#if !defined(OFFICIAL_BUILD)
// [Browther/Basarunaa] Capture mode (pref kBasarunaaCaptureMode) : sauve la frame
// vidéo analysée dans ~/Downloads/basarunaa-capture/ en 2 PNG — RAW (propre, pour
// rouvrir comme IMAGE et la reclasser via le flow image) + ANNOTÉE (box par genre
// + LABEL texte : genre fusionné + conf, sorties visage/corps). Le label est
// dessiné via gfx::Canvas (gère les fonts) ; on reformate les valeurs déjà
// calculées côté service. Écrit depuis le ThreadPool du process browser (non
// sandboxé macOS → accès Downloads OK).
//
// ⚠️ OUTIL DE DEV UNIQUEMENT — **absent du binaire Release** (`OFFICIAL_BUILD`).
// Ce code écrit sur disque les pixels de la frame analysée : sur un flux DRM il
// contournerait la protection de sortie de l'OS. La chaîne d'accès à ces pixels
// est déjà coupée en amont (refus du tap sur contenu protégé, cf.
// VideoRendererImpl / WebMediaPlayerImpl), et le déclencheur est verrouillé en
// prod (`IsBasarunaaDebugUiEnabled`) — ce #if est la 3e barrière : le dump
// n'existe tout simplement pas dans ce qu'on distribue. Cf. docs/TODO.md
// § « Basarunaa lit (et peut écrire sur disque) du média DRM déchiffré ».
//
// Écrit le RAW (frame propre) et renvoie l'index (pour nommer l'annotée du même
// numéro). Sûr sur le ThreadPool (aucun font). -1 si échec dossier.
int SaveCaptureRaw(const std::vector<uint8_t>& bgra, int width, int height) {
  base::FilePath home;
  if (!base::PathService::Get(base::DIR_HOME, &home)) {
    return -1;
  }
  const base::FilePath dir =
      home.Append("Downloads").Append("basarunaa-capture");
  if (!base::CreateDirectory(dir)) {
    return -1;
  }
  static base::AtomicSequenceNumber seq;
  const int n = seq.GetNext();
  if (auto png = gfx::PNGCodec::Encode(bgra.data(), gfx::PNGCodec::FORMAT_BGRA,
                                       gfx::Size(width, height), width * 4,
                                       /*discard_transparency=*/false, {})) {
    base::WriteFile(dir.Append(base::StringPrintf("raw_%05d.png", n)), *png);
  }
  return n;
}

// Une box à annoter (couleur genre + label texte), passée du pool au thread UI.
struct CaptureBox {
  float x = 0.f;
  float y = 0.f;
  float w = 0.f;
  float h = 0.f;
  SkColor color = SK_ColorWHITE;
  std::string label;
};

// Rend l'ANNOTÉE (frame + box + labels) SUR LE THREAD UI (gfx::FontList → cache
// de fonts lié à la séquence UI ; sur le ThreadPool = DCHECK CalledOnValidSequence,
// crash 2026-07-06). L'écriture fichier (bloquante, interdite sur UI) est
// re-postée sur le ThreadPool. bgra/boxes reçus PAR VALEUR (copie possédée).
void RenderAnnotatedCaptureOnUI(std::vector<uint8_t> bgra,
                                int width,
                                int height,
                                int n,
                                std::vector<CaptureBox> boxes,
                                std::string footer) {
  if (n < 0) {
    return;
  }
  base::FilePath home;
  if (!base::PathService::Get(base::DIR_HOME, &home)) {
    return;
  }
  const base::FilePath path = home.Append("Downloads")
                                  .Append("basarunaa-capture")
                                  .Append(base::StringPrintf("annot_%05d.png", n));
  SkBitmap frame;
  frame.installPixels(
      SkImageInfo::Make(width, height, kBGRA_8888_SkColorType,
                        kUnpremul_SkAlphaType),
      bgra.data(), static_cast<size_t>(width) * 4);
  gfx::Canvas canvas(gfx::Size(width, height), 1.0f, /*is_opaque=*/true);
  canvas.DrawImageInt(gfx::ImageSkia::CreateFromBitmap(frame, 1.0f), 0, 0);
  const gfx::FontList font;
  for (const auto& b : boxes) {
    canvas.DrawSolidFocusRect(gfx::RectF(b.x, b.y, b.w, b.h), b.color, 3);
    const int ty = std::max(0, static_cast<int>(b.y) - 15);
    const gfx::Rect lr(static_cast<int>(b.x), ty, width, 15);
    canvas.FillRect(lr, SkColorSetARGB(170, 0, 0, 0));
    canvas.DrawStringRect(base::UTF8ToUTF16(b.label), font, SK_ColorWHITE, lr);
  }
  // Footer bas-gauche : temps modèles + résolution.
  if (!footer.empty()) {
    const gfx::Rect fr(4, height - 18, width - 8, 16);
    canvas.FillRect(fr, SkColorSetARGB(190, 0, 0, 0));
    canvas.DrawStringRect(base::UTF8ToUTF16(footer), font,
                          SkColorSetRGB(120, 255, 120), fr);
  }
  auto png = gfx::PNGCodec::EncodeBGRASkBitmap(canvas.GetBitmap(),
                                               /*discard_transparency=*/false);
  if (png) {
    base::ThreadPool::PostTask(
        FROM_HERE, {base::MayBlock()},
        base::BindOnce(
            [](base::FilePath p, std::vector<uint8_t> d) {
              base::WriteFile(p, d);
            },
            path, std::move(*png)));
  }
}
#endif  // !defined(OFFICIAL_BUILD)

// Décision de floutage, port de VIDEO_V2.md §4 (chemin VIDÉO, plus prudent que
// content.js image) : flouter si `gender===target` OU `genderConf < certainty`
// OU `gender==null`. « Inconnu = sûr » : une personne non détectable a
// gender_conf = -1, donc captée par le filet `conf < certainty` → floutée. Les
// NON-cibles confiants (homme sûr en mode blur-female, ENFANT sûr dans tout mode
// genré) sont épargnés — l'enfant n'est jamais une cible, cf. parité image.
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
    case Gender::kMale:
      return 0;
    case Gender::kFemale:
      return 1;
    case Gender::kChild:
      return 2;
    default:
      return -1;  // kUnknown
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
                         bool want_nsfw,
                         double nudenet_conf,
                         bool capture) {
  PoolResult res;
  std::vector<mojom::AnalyzedPersonPtr>& out = res.persons;
  float nsfw_score = -1.f;
  bool nsfw_exposed = false;
  // Marqo + NudeNet (NSFW, ~120ms) seulement quand le RFO le demande (throttle
  // ~1/s + cuts) : sinon out-params nullptr → le service saute les 2 modèles
  // (score reste -1, exposed false → l'overlay gèle le dernier verdict).
  const auto t_analyze = base::TimeTicks::Now();
  const std::vector<DetectedPerson> persons = service->AnalyzeImageRgba(
      pixels.data(), width, height, bgra, static_cast<float>(conf_body),
      want_nsfw ? &nsfw_score : nullptr, want_nsfw ? &nsfw_exposed : nullptr,
      static_cast<float>(nudenet_conf));
  res.nsfw_score = nsfw_score;
  res.nsfw_exposed = nsfw_exposed;
  const double analyze_ms =
      (base::TimeTicks::Now() - t_analyze).InMillisecondsF();
  // Capture mode : RAW (frame propre) écrit ici sur le pool ; l'ANNOTÉE (labels
  // texte via gfx::FontList) est rendue sur le thread UI (obligatoire), puis
  // ré-écrite sur le pool. Chaque analyse (~1/s) tant que la pref est ON.
#if defined(OFFICIAL_BUILD)
  // Le dump disque n'est pas compilé en Release (cf. SaveCaptureRaw ci-dessus).
  // `capture` est de toute façon forcé false par IsBasarunaaDebugUiEnabled().
  (void)capture;
  (void)analyze_ms;
#else
  if (capture) {
    const int n = SaveCaptureRaw(pixels, width, height);
    // Footer bas-gauche : temps du modèle + résolution d'analyse.
    const std::string footer =
        base::StringPrintf("analyse %.0f ms · %dx%d · gender-v2n%s", analyze_ms,
                           width, height, want_nsfw ? "+nsfw" : "");
    std::vector<CaptureBox> boxes;
    boxes.reserve(persons.size());
    auto tag = [](Gender g) {
      return g == Gender::kFemale  ? "F"
             : g == Gender::kMale  ? "H"
             : g == Gender::kChild ? "E"
                                   : "?";
    };
    for (const DetectedPerson& p : persons) {
      CaptureBox b;
      b.x = p.x;
      b.y = p.y;
      b.w = p.w;
      b.h = p.h;
      b.color = p.gender == Gender::kFemale  ? SkColorSetRGB(255, 20, 147)
                : p.gender == Gender::kMale  ? SkColorSetRGB(30, 144, 255)
                : p.gender == Gender::kChild ? SkColorSetRGB(0, 200, 83)
                                             : SkColorSetRGB(255, 204, 0);
      b.label = base::StringPrintf(
          "%s %.0f%%", tag(p.gender),
          (p.gender_conf >= 0 ? p.gender_conf : 0.f) * 100);
      boxes.push_back(std::move(b));
    }
    content::GetUIThreadTaskRunner({})->PostTask(
        FROM_HERE, base::BindOnce(&RenderAnnotatedCaptureOnUI, pixels, width,
                                  height, n, std::move(boxes), footer));
  }
#endif  // defined(OFFICIAL_BUILD)
  out.reserve(persons.size());
  for (const DetectedPerson& p : persons) {
    auto ap = mojom::AnalyzedPerson::New();
    ap->x = p.x;
    ap->y = p.y;
    ap->w = p.w;
    ap->h = p.h;
    ap->score = p.score;
    ap->gender = GenderToInt(p.gender);
    ap->gender_conf = p.gender_conf;
    ap->blur = ShouldBlur(p, mode, certainty);
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
    std::move(callback).Run({}, "", false, "", 0.0, 0.0, false, -1.0f, false);
    return;
  }

  auto* profile =
      Profile::FromBrowserContext(GetWebContents().GetBrowserContext());
  auto* service =
      profile ? BasarunaaServiceFactory::GetForProfile(profile) : nullptr;
  if (!service) {
    std::move(callback).Run({}, "", false, "", 0.0, 0.0, false, -1.0f, false);
    return;
  }
  // Filet du toggle OFF (jumeau du gate batch Sawtunaa) : le RFO renderer
  // arrête déjà d'envoyer dès que VideoTapConfig::SetEnabled(false) arrive,
  // mais c'est la pref lue ICI, sur le thread UI, qui fait foi — un frame qui
  // n'aurait pas reçu le push (WebContents sans TabHelper, course au
  // démarrage) ne peut pas faire tourner le ML pour rien.
  if (!profile->GetPrefs()->GetBoolean(kBasarunaaEnabled)) {
    std::move(callback).Run({}, "", false, "", 0.0, 0.0, false, -1.0f, false);
    return;
  }
  // Prefs lues sur le thread UI (obligatoire). mode + certitude → pool (calcul
  // du flag blur repli) ET renvoyés au renderer (overlay : recalcul de shouldBlur
  // depuis le genre VOTÉ). conf_body → plancher de score du modèle (pool).
  // debug_mode + blur_enabled + min_skeleton → renderer (dessin/gating/filtre).
  // Défauts = ceux du POC.
  std::string mode = "blur-female";
  double certainty = 0.70;
  std::string debug_mode = "none";
  bool blur_enabled = true;
  double conf_body = 0.25;
  double min_skeleton = 0.0;
  double nsfw_conf = 0.50;
  double nudenet_conf = 0.50;
  bool nsfw_enabled = false;  // détection NSFW opt-in (off = latence optimale)
  bool censor_eyes = false;   // censure des yeux opt-in (overlay dessine la bande)
  bool capture_mode = false;
  // Debug-UI verrouillé (prod sans --basarunaa-debug-ui) → on IGNORE les prefs
  // debug et on garde les défauts sûrs : debug_mode="none" (aucun overlay),
  // capture_mode=false (aucune écriture ~/Downloads), blur_enabled=true (le
  // floutage ne peut PAS être coupé par un pref resté d'un test). Sinon un
  // utilisateur final avec un pref « boxes »/blur-off stocké verrait
  // l'outillage ou perdrait le flou.
  const bool debug_ui = IsBasarunaaDebugUiEnabled();
  if (auto* prefs = profile->GetPrefs()) {
    mode = prefs->GetString(kBasarunaaMode);
    certainty = prefs->GetDouble(kBasarunaaGenderCertainty);
    conf_body = prefs->GetDouble(kBasarunaaConfBody);
    min_skeleton = prefs->GetDouble(kBasarunaaMinSkeleton);
    nsfw_conf = prefs->GetDouble(kBasarunaaNsfwConf);
    nudenet_conf = prefs->GetDouble(kBasarunaaNudenetConf);
    nsfw_enabled = prefs->GetBoolean(kBasarunaaNsfwEnabled);
    censor_eyes = prefs->GetBoolean(kBasarunaaCensorEyes);
    if (debug_ui) {
      debug_mode = prefs->GetString(kBasarunaaDebugMode);
      blur_enabled = prefs->GetBoolean(kBasarunaaBlurEnabled);
      capture_mode = prefs->GetBoolean(kBasarunaaCaptureMode);
    }
  }
  // NSFW opt-in : si la pref est off, on n'exécute JAMAIS Marqo+NudeNet (le RFO
  // peut demander want_nsfw sur les cuts/1s, mais Marqo est CPU-bound ~120ms et
  // sérialise sur analyze_mutex_ → sinon il starve la détection de genre ~14ms).
  want_nsfw = want_nsfw && nsfw_enabled;

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
      std::string(), false, std::string(), 0.0, 0.0, false, -1.0f, false);

  base::ThreadPool::PostTaskAndReplyWithResult(
      FROM_HERE,
      {base::MayBlock(), base::TaskPriority::USER_VISIBLE,
       base::TaskShutdownBehavior::SKIP_ON_SHUTDOWN},
      base::BindOnce(&RunYoloOnPool, base::Unretained(service), std::move(buf),
                     width, height, bgra, std::move(mode), certainty, conf_body,
                     want_nsfw, nudenet_conf, capture_mode),
      base::BindOnce(&BasarunaaImageAnalyzer::OnAnalyzeDone,
                     weak_factory_.GetWeakPtr(), std::move(safe_callback),
                     std::move(debug_mode), blur_enabled,
                     std::move(mode_reply), certainty, min_skeleton, nsfw_conf,
                     censor_eyes));
}

void BasarunaaImageAnalyzer::OnAnalyzeDone(
    AnalyzeImageCallback callback,
    std::string debug_mode,
    bool blur_enabled,
    std::string mode,
    double gender_certainty,
    double min_skeleton,
    double nsfw_conf,
    bool censor_eyes,
    PoolResult result) {
  VLOG(1) << "[Basarunaa/YOLO] " << result.persons.size() << " persons"
            << " nsfw=" << result.nsfw_score
            << " exposed=" << result.nsfw_exposed;
  // NSFW plein cadre = Marqo au-dessus du seuil OU NudeNet a vu une partie exposée
  // (port v1 : isNsfw = marqo.isNsfw || exposed). L'exposé déclenche même si Marqo
  // (image entière) ne flag pas — gros plans de parties explicites.
  const bool nsfw = (result.nsfw_score >= 0.f &&
                     result.nsfw_score >= static_cast<float>(nsfw_conf)) ||
                    result.nsfw_exposed;
  // Mesure de `p` (vidéo) — voir le header. Le pipeline vidéo desktop passe
  // exclusivement par ici depuis 2026-07-07, donc ce compteur porte bien sur les
  // frames vidéo, séparément de celui des images (offscreen MV3).
  ++p_frames_;
  if (!result.persons.empty()) {
    ++p_frames_with_person_;
  }
  if (p_frames_ <= 20 ? p_frames_ % 10 == 0
                      : (p_frames_ <= 100 ? p_frames_ % 25 == 0
                                          : p_frames_ % 200 == 0)) {
    LOG(INFO) << "[Basarunaa:p/video] frames=" << p_frames_ << " p="
              << (100 * p_frames_with_person_ / p_frames_) << "%";
  }

  // #18 stats « personnes floutées » (parité Android) : compte les personnes
  // floutées AVANT de move les persons dans le callback.
  CountBlurredPersons(result.persons, blur_enabled);
  std::move(callback).Run(std::move(result.persons), std::move(debug_mode),
                          blur_enabled, std::move(mode), gender_certainty,
                          min_skeleton, nsfw, result.nsfw_score, censor_eyes);
}

void BasarunaaImageAnalyzer::CountBlurredPersons(
    const std::vector<mojom::AnalyzedPersonPtr>& persons,
    bool blur_enabled) {
  // #18 : alimente le compteur cumulatif NTP « personnes floutées » (widget
  // Stats), à parité avec Android/image. On compte le genre FUSIONNÉ browser
  // (`p->blur` = ShouldBlur, MÊME base que le compteur image — pas le vote
  // overlay, video-spécifique). Dédup par IoU vs l'analyse PRÉCÉDENTE : sans ça,
  // une personne statique serait recomptée à CHAQUE keyframe (~1/s). Un cut fait
  // chuter tous les IoU → la nouvelle scène est comptée (correct). Approximation
  // assumée (mouvement rapide entre 2 keyframes peut re-compter). UI thread
  // (réponse Mojo) → OK pour BrowtherAnalyticsService (PrefService UI-bound).
  if (!blur_enabled) {
    prev_blurred_boxes_.clear();
    return;
  }
  std::vector<std::array<float, 4>> cur;
  for (const auto& p : persons) {
    if (p->blur) {
      cur.push_back({p->x, p->y, p->w, p->h});
    }
  }
  int delta = 0;
  for (const auto& c : cur) {
    bool matched = false;
    for (const auto& prev : prev_blurred_boxes_) {
      if (BoxIoU(c, prev) >= kBlurTrackIoU) {
        matched = true;
        break;
      }
    }
    if (!matched) {
      ++delta;
    }
  }
  prev_blurred_boxes_ = std::move(cur);
  if (delta > 0) {
    auto* analytics =
        browther_analytics::BrowtherAnalyticsService::GetInstance();
    if (analytics) {
      analytics->IncrementPersonsBlurred(delta);
    }
  }
}

WEB_CONTENTS_USER_DATA_KEY_IMPL(BasarunaaImageAnalyzer);

}  // namespace basarunaa
