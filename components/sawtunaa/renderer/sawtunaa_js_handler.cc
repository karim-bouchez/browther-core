// Copyright (c) 2026 The Browther Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/components/sawtunaa/renderer/sawtunaa_js_handler.h"

#include <string>

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
  // "preprocess" (Float32 binary base64) et "syncRanges" (multi-range) sont
  // câblées au Jalon 2.C.2 — pour 2.C.1 elles sont no-op.
  if (action == "preprocess" || action == "syncRanges") {
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
