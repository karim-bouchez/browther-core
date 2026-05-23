// Copyright (c) 2026 The Browther Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/components/sawtunaa/renderer/sawtunaa_js_handler.h"

#include <string>
#include <utility>
#include <vector>

#include "base/base64.h"
#include "base/containers/span.h"
#include "base/strings/string_number_conversions.h"
#include "base/strings/string_split.h"
#include "content/public/renderer/render_frame.h"
#include "gin/arguments.h"
#include "gin/handle.h"
#include "gin/object_template_builder.h"
#include "third_party/blink/public/platform/browser_interface_broker_proxy.h"
#include "third_party/blink/public/platform/scheduler/web_agent_group_scheduler.h"
#include "third_party/blink/public/web/web_local_frame.h"
#include "v8/include/cppgc/allocation.h"
#include "v8/include/v8-context.h"
#include "v8/include/v8-cppgc.h"
#include "v8/include/v8-object.h"
#include "v8/include/v8-primitive.h"

namespace sawtunaa {

SawtunaaJsHandler::SawtunaaJsHandler(content::RenderFrame* render_frame)
    : render_frame_(render_frame) {}

SawtunaaJsHandler::~SawtunaaJsHandler() = default;

// static
void SawtunaaJsHandler::Install(content::RenderFrame* render_frame) {
  CHECK(render_frame);
  v8::Isolate* isolate =
      render_frame->GetWebFrame()->GetAgentGroupScheduler()->Isolate();
  v8::HandleScope handle_scope(isolate);
  v8::Local<v8::Context> context =
      render_frame->GetWebFrame()->MainWorldScriptContext();
  if (context.IsEmpty()) {
    return;
  }
  v8::Context::Scope context_scope(context);

  v8::Local<v8::Object> global = context->Global();

  // window.__sawtunaa : nouvelle instance par DidClearWindowObject.
  SawtunaaJsHandler* handler = cppgc::MakeGarbageCollected<SawtunaaJsHandler>(
      isolate->GetCppHeap()->GetAllocationHandle(), render_frame);

  v8::PropertyDescriptor desc(handler->GetWrapper(isolate).ToLocalChecked(),
                              /*writable=*/false);
  desc.set_configurable(false);
  desc.set_enumerable(false);

  global
      ->DefineProperty(context, gin::StringToV8(isolate, "__sawtunaa"), desc)
      .Check();
}

const gin::WrapperInfo* SawtunaaJsHandler::wrapper_info() const {
  return &kWrapperInfo;
}

gin::ObjectTemplateBuilder SawtunaaJsHandler::GetObjectTemplateBuilder(
    v8::Isolate* isolate) {
  return gin::Wrappable<SawtunaaJsHandler>::GetObjectTemplateBuilder(isolate)
      .SetMethod("send", &SawtunaaJsHandler::Send);
}

bool SawtunaaJsHandler::EnsureRemote() {
  if (sawtunaa_.is_bound()) {
    return true;
  }
  if (!render_frame_) {
    return false;
  }
  render_frame_->GetBrowserInterfaceBroker().GetInterface(
      sawtunaa_.BindNewPipeAndPassReceiver());
  return sawtunaa_.is_bound();
}

void SawtunaaJsHandler::Send(gin::Arguments* args) {
  std::string action;
  std::string data;
  if (!args->GetNext(&action)) {
    return;
  }
  // `data` est optionnel (certaines actions n'en ont pas).
  args->GetNext(&data);

  if (!EnsureRemote()) {
    return;
  }

  if (action == "log") {
    sawtunaa_->LogJs(data);
    return;
  }
  if (action == "metric") {
    sawtunaa_->EmitMetric(data);
    return;
  }
  if (action == "playAt") {
    double ms = 0.0;
    if (base::StringToDouble(data, &ms)) {
      sawtunaa_->PlayAt(ms);
    }
    return;
  }
  if (action == "clearChunks") {
    sawtunaa_->ClearChunks();
    return;
  }
  if (action == "pageReset") {
    sawtunaa_->PageReset(data);
    return;
  }
  if (action == "seekTo") {
    double ms = 0.0;
    if (base::StringToDouble(data, &ms)) {
      sawtunaa_->SeekTo(ms);
    }
    return;
  }
  if (action == "evictRange") {
    // Format iOS : "startMs|endMs".
    auto parts = base::SplitString(
        data, "|", base::TRIM_WHITESPACE, base::SPLIT_WANT_NONEMPTY);
    double start = 0.0;
    double end = 0.0;
    if (parts.size() == 2 && base::StringToDouble(parts[0], &start) &&
        base::StringToDouble(parts[1], &end)) {
      sawtunaa_->EvictRange(start, end);
    }
    return;
  }
  if (action == "pauseAudio") {
    sawtunaa_->PauseAudio();
    return;
  }
  if (action == "resumeAudio") {
    sawtunaa_->ResumeAudio();
    return;
  }
  if (action == "preprocess") {
    // Format iOS : "timestampMs|base64Float32Binary". Pipeline :
    //   1. split sur '|' (maxsplit=1, le base64 ne contient pas de '|')
    //   2. parseDouble(parts[0]) → timestamp
    //   3. base64decode(parts[1]) → bytes
    //   4. reinterpret bytes en float32 little-endian → std::vector<float>
    //   5. Mojo PreprocessChunk(ts, samples)
    auto sep = data.find('|');
    if (sep == std::string::npos) {
      return;
    }
    double ts = 0.0;
    if (!base::StringToDouble(data.substr(0, sep), &ts)) {
      return;
    }
    std::string decoded;
    if (!base::Base64Decode(data.substr(sep + 1), &decoded)) {
      return;
    }
    // V8 Float32Array est little-endian sur toutes les plateformes Chromium
    // que Browther target (arm64 Android = LE, x86_64 = LE). Bytes alignement :
    // base64 décodé doit faire multiple de 4. Sinon on drop.
    if (decoded.size() % sizeof(float) != 0) {
      return;
    }
    const size_t n_floats = decoded.size() / sizeof(float);
    std::vector<float> samples(n_floats);
    if (n_floats > 0) {
      // base::span copy_from = safe alternative à std::memcpy (Chromium
      // -Wunsafe-buffer-usage-in-libc-call). Vérifie l'égalité de taille
      // en CHECK donc on safety-clamp avant.
      base::as_writable_byte_span(samples)
          .copy_from(base::as_byte_span(decoded));
    }
    sawtunaa_->PreprocessChunk(ts, std::move(samples));
    return;
  }
  if (action == "syncRanges") {
    // Format iOS : "s|e,s|e,s|e". Split commas, puis chaque range split '|'.
    std::vector<mojom::TimeRangePtr> ranges;
    auto chunks = base::SplitString(
        data, ",", base::TRIM_WHITESPACE, base::SPLIT_WANT_NONEMPTY);
    ranges.reserve(chunks.size());
    for (const auto& chunk : chunks) {
      auto parts = base::SplitString(
          chunk, "|", base::TRIM_WHITESPACE, base::SPLIT_WANT_NONEMPTY);
      double s = 0.0;
      double e = 0.0;
      if (parts.size() == 2 && base::StringToDouble(parts[0], &s) &&
          base::StringToDouble(parts[1], &e)) {
        ranges.push_back(mojom::TimeRange::New(s, e));
      }
    }
    sawtunaa_->SyncRanges(std::move(ranges));
    return;
  }
  // Action inconnue — on logge dans la console JS plutôt que silencieux.
  args->isolate()->ThrowError(
      v8::String::NewFromUtf8(args->isolate(),
                              "sawtunaa: unknown action",
                              v8::NewStringType::kNormal)
          .ToLocalChecked());
}

}  // namespace sawtunaa
