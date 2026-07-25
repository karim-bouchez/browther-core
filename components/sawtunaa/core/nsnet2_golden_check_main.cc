// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

// Golden vectors NSNet2 — vérifie la parité DSP entre le moteur Python
// (référence, ../sawtunaa/app/engine/sawtunaa_engine.py) et le port C++
// (Nsnet2Stream). Les vecteurs sont générés par
// private/scripts/gen-sawtunaa-golden.py ; ce binaire les rejoue et compare.
//
//   out/Component_arm64/sawtunaa_golden_check \
//       --model=<…>/nsnet2-stateful.onnx \
//       --golden-dir=<…>/private/testdata/sawtunaa-golden
//
// Chaque cas est rejoué en batchs de 512 samples (comme le générateur Python)
// PUIS en batchs de 256 ms (comme AudioRendererImpl en prod) : la taille de
// batch ne doit RIEN changer au résultat (état frame-par-frame). Le 3ᵉ passage
// est stéréo L==R — le downmix des spectres doit redonner exactement le mono.
// Enfin le flush (EOS) est vérifié sur sa propriété : sortie totale == entrée
// totale, au sample près (le moteur Python n'a pas d'équivalent — sa latence
// est rendue par un padding de tête, retiré par le générateur).
//
// Tolérances (float32 PFFFT vs float64 numpy, GRU stateful → l'écart
// s'accumule) : max |Δ| et RMSE relative, cf. kMaxAbsTolerance / kRmseRelTol.
// Un dépassement = régression du portage, pas un « bruit de mesure ».

#include <algorithm>
#include <cmath>
#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "base/at_exit.h"
#include "base/command_line.h"
#include "base/containers/span.h"
#include "base/files/file_path.h"
#include "base/files/file_util.h"
#include "base/json/json_reader.h"
#include "base/logging.h"
#include "base/strings/stringprintf.h"
#include "base/values.h"
#include "brave/components/sawtunaa/core/nsnet2_stream.h"
#include "onnxruntime_cxx_api.h"

namespace {

// Écarts admis entre le port C++ (PFFFT float32) et la référence Python
// (numpy float64). Ces seuils attrapent une vraie divergence de portage
// (fenêtre, ordre des bins, downmix, overlap-add), pas l'arrondi.
//
// ⚠️ La RMSE est normalisée par le RMS de l'ENTRÉE, pas de la sortie :
// l'erreur d'arrondi est proportionnelle au signal qui traverse la FFT, alors
// que la sortie peut être atténuée de 30-60 dB par le masque (le cas
// dc_nyquist_dirac sort à -64 dB). Normaliser par la sortie ferait exploser un
// ratio parfaitement sain.
constexpr double kMaxAbsTolerance = 2e-3;
constexpr double kRmseRelTol = 1e-4;

// 256 ms @48 kHz : la taille de batch de AudioRendererImpl en prod.
constexpr int kProdBatch = 12288;

struct Comparison {
  double max_abs = 0.0;
  double rmse = 0.0;
  double scale = 0.0;  // RMS de l'entrée du cas (échelle de référence)
  size_t max_abs_index = 0;
  size_t compared = 0;

  double rmse_rel() const { return scale > 0.0 ? rmse / scale : rmse; }
  bool Passes() const {
    return compared > 0 && max_abs <= kMaxAbsTolerance &&
           rmse_rel() <= kRmseRelTol;
  }
};

double Rms(base::span<const float> values) {
  if (values.empty()) {
    return 0.0;
  }
  double sum_sq = 0.0;
  for (const float v : values) {
    sum_sq += static_cast<double>(v) * v;
  }
  return std::sqrt(sum_sq / values.size());
}

bool ReadFloatFile(const base::FilePath& path, std::vector<float>* out) {
  std::string bytes;
  if (!base::ReadFileToString(path, &bytes)) {
    LOG(ERROR) << "lecture impossible : " << path;
    return false;
  }
  if (bytes.size() % sizeof(float) != 0) {
    LOG(ERROR) << "taille non multiple de 4 : " << path;
    return false;
  }
  // Fichiers écrits par numpy en little-endian float32 ('<f4') — toutes nos
  // cibles le sont. Pas de memcpy (banni) : copie via spans d'octets.
  // allow_nonunique_obj : requis pour réinterpréter des float en octets.
  out->assign(bytes.size() / sizeof(float), 0.f);
  base::as_writable_byte_span(base::allow_nonunique_obj, *out)
      .copy_from(base::as_byte_span(bytes));
  return true;
}

Comparison Compare(base::span<const float> got,
                   base::span<const float> expected,
                   double scale) {
  Comparison c;
  c.scale = scale;
  c.compared = std::min(got.size(), expected.size());
  double sum_sq_err = 0.0;
  for (size_t i = 0; i < c.compared; ++i) {
    const double diff = static_cast<double>(got[i]) - expected[i];
    if (std::abs(diff) > c.max_abs) {
      c.max_abs = std::abs(diff);
      c.max_abs_index = i;
    }
    sum_sq_err += diff * diff;
  }
  if (c.compared > 0) {
    c.rmse = std::sqrt(sum_sq_err / c.compared);
  }
  return c;
}

// Rejoue |input| dans un Nsnet2Stream neuf, par batchs de |batch| samples.
// |channels| == 2 duplique le mono sur L et R et ne renvoie que le canal
// gauche (le downmix des spectres doit être un no-op). |flush_at_end| : envoie
// le dernier batch avec flush=true (vide la queue d'overlap-add en paddant des
// zéros → les derniers samples n'ont PAS d'équivalent dans la référence).
bool RunStream(Ort::Session* session,
               const std::vector<float>& input,
               int batch,
               int channels,
               bool flush_at_end,
               std::vector<float>* out) {
  sawtunaa::Nsnet2Stream stream(session, channels);
  out->clear();
  out->reserve(input.size());
  std::vector<float> planar;
  std::vector<float> processed;
  const size_t total = input.size();
  for (size_t offset = 0; offset < total; offset += batch) {
    const size_t frames =
        std::min(static_cast<size_t>(batch), total - offset);
    const bool last = (offset + frames >= total);
    const auto chunk = base::span(input).subspan(offset, frames);
    planar.assign(chunk.begin(), chunk.end());
    if (channels == 2) {
      planar.insert(planar.end(), chunk.begin(), chunk.end());
    }
    if (!stream.ProcessBatch(planar, static_cast<int>(frames),
                             last && flush_at_end, &processed)) {
      LOG(ERROR) << "ProcessBatch a échoué (offset=" << offset << ")";
      return false;
    }
    const size_t produced = processed.size() / channels;
    out->insert(out->end(), processed.begin(),
                processed.begin() + static_cast<ptrdiff_t>(produced));
  }
  return true;
}

void PrintResult(const char* label, const Comparison& c) {
  LOG(INFO) << base::StringPrintf(
      "  %-26s n=%7zu  max|Δ|=%.3e (idx %zu)  rmse/entrée=%.3e  %s", label,
      c.compared, c.max_abs, c.max_abs_index, c.rmse_rel(),
      c.Passes() ? "OK" : "ÉCHEC");
}

}  // namespace

int main(int argc, char** argv) {
  base::AtExitManager at_exit;
  base::CommandLine::Init(argc, argv);
  auto* cmd = base::CommandLine::ForCurrentProcess();
  const base::FilePath model = cmd->GetSwitchValuePath("model");
  const base::FilePath dir = cmd->GetSwitchValuePath("golden-dir");
  if (model.empty() || dir.empty()) {
    LOG(ERROR) << "usage: sawtunaa_golden_check "
                  "--model=<nsnet2-stateful.onnx> "
                  "--golden-dir=<dir avec manifest.json>";
    return 2;
  }

  std::string manifest_json;
  if (!base::ReadFileToString(dir.Append("manifest.json"), &manifest_json)) {
    LOG(ERROR) << "manifest.json introuvable dans " << dir;
    return 2;
  }
  std::optional<base::DictValue> manifest =
      base::JSONReader::ReadDict(manifest_json, base::JSON_PARSE_RFC);
  if (!manifest) {
    LOG(ERROR) << "manifest.json illisible";
    return 2;
  }
  const base::ListValue* cases = manifest->FindList("cases");
  if (!cases || cases->empty()) {
    LOG(ERROR) << "manifest.json sans cas";
    return 2;
  }

  std::unique_ptr<Ort::Env> env;
  std::unique_ptr<Ort::Session> session;
  try {
    env = std::make_unique<Ort::Env>(ORT_LOGGING_LEVEL_WARNING,
                                     "sawtunaa_golden_check");
    Ort::SessionOptions options;
    options.SetIntraOpNumThreads(1);
    options.SetInterOpNumThreads(1);
    options.SetGraphOptimizationLevel(ORT_ENABLE_ALL);
    session =
        std::make_unique<Ort::Session>(*env, model.value().c_str(), options);
  } catch (const Ort::Exception& e) {
    LOG(ERROR) << "chargement ORT échoué : " << e.what();
    return 2;
  }

  int failures = 0;
  for (const base::Value& entry : *cases) {
    const base::DictValue* c = entry.GetIfDict();
    if (!c) {
      continue;
    }
    const std::string* name = c->FindString("name");
    const std::string* in_file = c->FindString("input");
    const std::string* exp_file = c->FindString("expected");
    if (!name || !in_file || !exp_file) {
      continue;
    }
    std::vector<float> input;
    std::vector<float> expected;
    if (!ReadFloatFile(dir.AppendASCII(*in_file), &input) ||
        !ReadFloatFile(dir.AppendASCII(*exp_file), &expected)) {
      return 2;
    }
    LOG(INFO) << base::StringPrintf(
        "%s (%zu samples, %.2f s)", name->c_str(), input.size(),
        static_cast<double>(input.size()) /
            sawtunaa::Nsnet2Stream::kSampleRate);

    // Passages comparés à la référence : SANS flush (la queue d'overlap-add
    // reste retenue). Le flush padderait des zéros que la référence n'a pas
    // vus → ses derniers ~512 samples ne sont pas comparables.
    std::vector<float> got_hop;
    std::vector<float> got_prod;
    std::vector<float> got_stereo;
    std::vector<float> got_flushed;
    if (!RunStream(session.get(), input, 512, 1, false, &got_hop) ||
        !RunStream(session.get(), input, kProdBatch, 1, false, &got_prod) ||
        !RunStream(session.get(), input, kProdBatch, 2, false, &got_stereo) ||
        !RunStream(session.get(), input, kProdBatch, 1, true, &got_flushed)) {
      return 2;
    }

    const double scale = Rms(input);
    const Comparison hop = Compare(got_hop, expected, scale);
    const Comparison prod = Compare(got_prod, expected, scale);
    const Comparison stereo = Compare(got_stereo, expected, scale);
    PrintResult("mono, batchs 512", hop);
    PrintResult("mono, batchs 256 ms", prod);
    PrintResult("stéréo L==R, 256 ms", stereo);
    failures += (hop.Passes() ? 0 : 1) + (prod.Passes() ? 0 : 1) +
                (stereo.Passes() ? 0 : 1);

    // Le flush doit rendre EXACTEMENT autant d'échantillons qu'il en a reçu
    // (invariant du portage : aucun trou, aucun doublon à l'EOS), et ne rien
    // changer à ce qui était déjà sorti.
    const bool length_ok = got_flushed.size() == input.size();
    const Comparison prefix = Compare(got_flushed, base::span(got_prod), scale);
    const bool prefix_ok = prefix.max_abs == 0.0;
    LOG(INFO) << base::StringPrintf(
        "  %-26s in=%zu out=%zu  préfixe %s  %s", "flush EOS", input.size(),
        got_flushed.size(), prefix_ok ? "identique" : "DIVERGENT",
        (length_ok && prefix_ok) ? "OK" : "ÉCHEC");
    if (!length_ok || !prefix_ok) {
      ++failures;
    }
  }

  LOG(INFO) << (failures == 0 ? "PARITÉ DSP OK (Python ↔ C++)"
                              : "PARITÉ DSP EN ÉCHEC");
  return failures == 0 ? 0 : 1;
}
