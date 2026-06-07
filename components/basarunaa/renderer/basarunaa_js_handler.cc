// Copyright (c) 2026 The Browther Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/components/basarunaa/renderer/basarunaa_js_handler.h"

#include <cstring>
#include <string>
#include <utility>
#include <vector>

#include "base/base64.h"
#include "base/compiler_specific.h"
#include "base/strings/string_number_conversions.h"
#include "brave/components/basarunaa/renderer/basarunaa_render_frame_observer_android.h"
#include "content/public/renderer/render_frame.h"
#include "gin/arguments.h"
#include "gin/converter.h"
#include "gin/handle.h"
#include "gin/object_template_builder.h"
#include "third_party/blink/public/platform/browser_interface_broker_proxy.h"
#include "third_party/blink/public/platform/scheduler/web_agent_group_scheduler.h"
#include "third_party/blink/public/web/web_local_frame.h"
#include "v8/include/cppgc/allocation.h"
#include "v8/include/v8-context.h"
#include "v8/include/v8-cppgc.h"
#include "v8/include/v8-isolate.h"
#include "v8/include/v8-object.h"
#include "v8/include/v8-primitive.h"

namespace basarunaa {
namespace android {

BasarunaaJsHandler::BasarunaaJsHandler(
    content::RenderFrame* render_frame,
    BasarunaaRenderFrameObserverAndroid* rfo)
    : render_frame_(render_frame), rfo_(rfo) {}

BasarunaaJsHandler::~BasarunaaJsHandler() = default;

// static
void BasarunaaJsHandler::Install(content::RenderFrame* render_frame,
                                  BasarunaaRenderFrameObserverAndroid* rfo) {
  CHECK(render_frame);
  CHECK(rfo);
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

  BasarunaaJsHandler* handler =
      cppgc::MakeGarbageCollected<BasarunaaJsHandler>(
          isolate->GetCppHeap()->GetAllocationHandle(), render_frame, rfo);

  v8::PropertyDescriptor desc(handler->GetWrapper(isolate).ToLocalChecked(),
                              /*writable=*/false);
  desc.set_configurable(false);
  desc.set_enumerable(false);

  global->DefineProperty(context, gin::StringToV8(isolate, "__basarunaa"), desc)
      .Check();
}

const gin::WrapperInfo* BasarunaaJsHandler::wrapper_info() const {
  return &kWrapperInfo;
}

gin::ObjectTemplateBuilder BasarunaaJsHandler::GetObjectTemplateBuilder(
    v8::Isolate* isolate) {
  return gin::Wrappable<BasarunaaJsHandler>::GetObjectTemplateBuilder(isolate)
      .SetMethod("send", &BasarunaaJsHandler::Send)
      .SetMethod("isEnabled", &BasarunaaJsHandler::IsEnabled)
      .SetMethod("getConfig", &BasarunaaJsHandler::GetConfig);
}

bool BasarunaaJsHandler::IsEnabled() {
  return rfo_ && rfo_->is_enabled();
}

v8::Local<v8::Object> BasarunaaJsHandler::GetConfig(gin::Arguments* args) {
  v8::Isolate* isolate = args->isolate();
  v8::Local<v8::Context> context = isolate->GetCurrentContext();
  v8::Local<v8::Object> obj = v8::Object::New(isolate);
  if (!rfo_ || !rfo_->settings()) {
    obj->Set(context, gin::StringToV8(isolate, "enabled"),
             v8::Boolean::New(isolate, false))
        .Check();
    return obj;
  }
  const auto* s = rfo_->settings();
  obj->Set(context, gin::StringToV8(isolate, "enabled"),
           v8::Boolean::New(isolate, s->enabled))
      .Check();
  obj->Set(context, gin::StringToV8(isolate, "mode"),
           gin::StringToV8(isolate, s->mode))
      .Check();
  obj->Set(context, gin::StringToV8(isolate, "confBody"),
           v8::Number::New(isolate, s->conf_body))
      .Check();
  obj->Set(context, gin::StringToV8(isolate, "confFace"),
           v8::Number::New(isolate, s->conf_face))
      .Check();
  obj->Set(context, gin::StringToV8(isolate, "genderCertainty"),
           v8::Number::New(isolate, s->gender_certainty))
      .Check();
  obj->Set(context, gin::StringToV8(isolate, "debugMode"),
           gin::StringToV8(isolate, s->debug_mode))
      .Check();
  return obj;
}

bool BasarunaaJsHandler::EnsureRemote() {
  if (basarunaa_.is_bound()) {
    return true;
  }
  if (!render_frame_) {
    return false;
  }
  render_frame_->GetBrowserInterfaceBroker().GetInterface(
      basarunaa_.BindNewPipeAndPassReceiver());
  return basarunaa_.is_bound();
}

void BasarunaaJsHandler::Send(gin::Arguments* args) {
  std::string action;
  std::string data;
  if (!args->GetNext(&action)) {
    return;
  }
  args->GetNext(&data);  // optionnel selon action

  if (!EnsureRemote()) {
    return;
  }

  if (action == "log") {
    basarunaa_->LogJs(data);
    return;
  }
  if (action == "metric") {
    basarunaa_->EmitMetric(data);
    return;
  }
  if (action == "analyzeImage") {
    // Format : "imageId|base64(bytes)". Le base64 ne contient pas de '|'.
    auto sep = data.find('|');
    if (sep == std::string::npos) {
      return;
    }
    int image_id = 0;
    if (!base::StringToInt(data.substr(0, sep), &image_id)) {
      return;
    }
    std::string decoded;
    if (!base::Base64Decode(data.substr(sep + 1), &decoded)) {
      return;
    }
    std::vector<uint8_t> bytes(decoded.size());
    if (!decoded.empty()) {
      // SAFETY: bytes vient d'être resize à decoded.size(). Owned buffers,
      // pas d'aliasing.
      UNSAFE_BUFFERS(
          std::memcpy(bytes.data(), decoded.data(), decoded.size()));
    }
    basarunaa_->AnalyzeImage(image_id, std::move(bytes));
    return;
  }
  if (action == "cancelAnalyze") {
    int image_id = 0;
    if (!base::StringToInt(data, &image_id)) {
      return;
    }
    basarunaa_->CancelAnalyze(image_id);
    return;
  }
  if (action == "pageReset") {
    basarunaa_->PageReset(data);
    return;
  }
  if (action == "sentinelFrame") {
    // V2.5 — même encodage que analyzeImage : "frameId|base64(bytes)".
    auto sep = data.find('|');
    if (sep == std::string::npos) {
      return;
    }
    int frame_id = 0;
    if (!base::StringToInt(data.substr(0, sep), &frame_id)) {
      return;
    }
    std::string decoded;
    if (!base::Base64Decode(data.substr(sep + 1), &decoded)) {
      return;
    }
    std::vector<uint8_t> bytes(decoded.size());
    if (!decoded.empty()) {
      // SAFETY: bytes resize à decoded.size(). Owned buffers, pas d'aliasing.
      UNSAFE_BUFFERS(
          std::memcpy(bytes.data(), decoded.data(), decoded.size()));
    }
    basarunaa_->SentinelFrame(frame_id, std::move(bytes));
    return;
  }
  // Action inconnue → ThrowError plutôt que silencieux.
  args->isolate()->ThrowError(
      v8::String::NewFromUtf8(args->isolate(), "basarunaa: unknown action",
                              v8::NewStringType::kNormal)
          .ToLocalChecked());
}

}  // namespace android
}  // namespace basarunaa
