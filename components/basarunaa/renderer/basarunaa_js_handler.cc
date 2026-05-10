// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/components/basarunaa/renderer/basarunaa_js_handler.h"

#include <utility>
#include <vector>

#include "base/check.h"
#include "base/compiler_specific.h"
#include "base/functional/bind.h"
#include "base/logging.h"
#include "content/public/renderer/render_frame.h"
#include "gin/converter.h"
#include "gin/object_template_builder.h"
#include "mojo/public/cpp/base/big_buffer.h"
#include "third_party/blink/public/common/associated_interfaces/associated_interface_provider.h"
#include "third_party/blink/public/platform/scheduler/web_agent_group_scheduler.h"
#include "third_party/blink/public/web/web_local_frame.h"
#include "v8/include/cppgc/allocation.h"
#include "v8/include/v8-cppgc.h"

namespace basarunaa {

namespace {

// Sanity caps pour rejeter les appels JS malveillants/cassés avant tout
// I/O. Au-delà on pourrait saturer le worker pool ML.
constexpr int kMaxImageSide = 4096;

}  // namespace

// static
void BasarunaaJSHandler::Install(content::RenderFrame* render_frame,
                                 v8::Local<v8::Context> context) {
  CHECK(render_frame);
  blink::WebLocalFrame* web_frame = render_frame->GetWebFrame();
  if (!web_frame) {
    return;
  }
  v8::Isolate* isolate = web_frame->GetAgentGroupScheduler()->Isolate();
  v8::HandleScope handle_scope(isolate);
  v8::Context::Scope context_scope(context);

  v8::Local<v8::Object> global = context->Global();
  v8::Local<v8::String> property_name =
      gin::StringToV8(isolate, "__basarunaa");

  v8::Local<v8::Value> existing;
  if (global->Get(context, property_name).ToLocal(&existing) &&
      !existing->IsUndefined() && !existing->IsNull()) {
    return;
  }

  BasarunaaJSHandler* handler = cppgc::MakeGarbageCollected<BasarunaaJSHandler>(
      isolate->GetCppHeap()->GetAllocationHandle(), render_frame);

  v8::Local<v8::Object> wrapper;
  if (!handler->GetWrapper(isolate).ToLocal(&wrapper)) {
    return;
  }

  v8::PropertyDescriptor desc(wrapper, /*writable=*/false);
  desc.set_configurable(false);
  desc.set_enumerable(false);
  std::ignore = global->DefineProperty(context, property_name, desc);
  LOG(INFO) << "[Basarunaa-bridge] window.__basarunaa installed";
}

BasarunaaJSHandler::BasarunaaJSHandler(content::RenderFrame* render_frame)
    : render_frame_(render_frame) {}

BasarunaaJSHandler::~BasarunaaJSHandler() = default;

bool BasarunaaJSHandler::EnsureConnected() {
  if (!image_analyzer_.is_bound()) {
    if (!render_frame_) {
      return false;
    }
    render_frame_->GetRemoteAssociatedInterfaces()->GetInterface(
        &image_analyzer_);
    image_analyzer_.reset_on_disconnect();
  }
  return image_analyzer_.is_bound();
}

gin::ObjectTemplateBuilder BasarunaaJSHandler::GetObjectTemplateBuilder(
    v8::Isolate* isolate) {
  return gin::Wrappable<BasarunaaJSHandler>::GetObjectTemplateBuilder(isolate)
      .SetMethod("analyze", &BasarunaaJSHandler::Analyze);
}

const gin::WrapperInfo* BasarunaaJSHandler::wrapper_info() const {
  return &kWrapperInfo;
}

v8::Local<v8::Promise> BasarunaaJSHandler::Analyze(
    v8::Isolate* isolate,
    v8::Local<v8::Value> pixels,
    int32_t width,
    int32_t height,
    std::string format) {
  v8::Local<v8::Context> context = isolate->GetCurrentContext();
  v8::Local<v8::Promise::Resolver> resolver =
      v8::Promise::Resolver::New(context).ToLocalChecked();
  v8::Local<v8::Promise> promise = resolver->GetPromise();

  auto reject = [&](std::string_view reason) {
    LOG(WARNING) << "[Basarunaa-bridge] analyze rejected: " << reason;
    v8::Local<v8::Value> err =
        v8::Exception::Error(gin::StringToV8(isolate, std::string(reason)));
    std::ignore = resolver->Reject(context, err);
  };

  if (width <= 0 || height <= 0 || width > kMaxImageSide ||
      height > kMaxImageSide) {
    reject("invalid dimensions");
    return promise;
  }

  mojom::ImageFormat fmt;
  if (format == "rgba8") {
    fmt = mojom::ImageFormat::kRgba8;
  } else if (format == "bgra8") {
    fmt = mojom::ImageFormat::kBgra8;
  } else {
    reject("unsupported format (expected 'rgba8' or 'bgra8')");
    return promise;
  }

  size_t expected = static_cast<size_t>(width) *
                    static_cast<size_t>(height) * 4u;
  void* data = nullptr;
  size_t byte_length = 0;
  if (pixels->IsArrayBufferView()) {
    auto view = pixels.As<v8::ArrayBufferView>();
    auto buffer = view->Buffer();
    data = UNSAFE_BUFFERS(static_cast<uint8_t*>(buffer->Data()) +
                          view->ByteOffset());
    byte_length = view->ByteLength();
  } else if (pixels->IsArrayBuffer()) {
    auto buffer = pixels.As<v8::ArrayBuffer>();
    data = buffer->Data();
    byte_length = buffer->ByteLength();
  } else {
    reject("pixels must be an ArrayBuffer or ArrayBufferView");
    return promise;
  }
  if (byte_length != expected) {
    reject("pixel buffer size mismatch");
    return promise;
  }

  if (!EnsureConnected()) {
    reject("ImageAnalyzer Mojo unavailable");
    return promise;
  }

  mojo_base::BigBuffer buffer(UNSAFE_BUFFERS(base::span<const uint8_t>(
      static_cast<const uint8_t*>(data), byte_length)));

  v8::Global<v8::Promise::Resolver> global_resolver(isolate, resolver);
  v8::Global<v8::Context> global_context(isolate, context);

  image_analyzer_->AnalyzeImage(
      std::move(buffer), width, height, fmt,
      base::BindOnce(&BasarunaaJSHandler::OnAnalyzed,
                     weak_ptr_factory_.GetWeakPtr(),
                     std::move(global_resolver), isolate,
                     std::move(global_context)));

  return promise;
}

void BasarunaaJSHandler::OnAnalyzed(
    v8::Global<v8::Promise::Resolver> resolver,
    v8::Isolate* isolate,
    v8::Global<v8::Context> context,
    std::vector<mojom::AnalyzedPersonPtr> persons) {
  v8::HandleScope handle_scope(isolate);
  v8::Local<v8::Context> local_context = context.Get(isolate);
  v8::Context::Scope context_scope(local_context);
  // Required by v8 when calling Promise::Resolver::Resolve from a non-JS
  // entry point (Mojo callback). Without it v8 crashes with
  // "microtask_queue->GetMicrotasksScopeDepth()" DCHECK.
  v8::MicrotasksScope microtasks_scope(
      local_context, v8::MicrotasksScope::kRunMicrotasks);

  v8::Local<v8::Array> result = v8::Array::New(isolate, persons.size());
  for (uint32_t i = 0; i < persons.size(); ++i) {
    const auto& p = persons[i];
    v8::Local<v8::Object> obj = v8::Object::New(isolate);
    std::ignore = obj->Set(local_context, gin::StringToV8(isolate, "x"),
                           v8::Number::New(isolate, p->x));
    std::ignore = obj->Set(local_context, gin::StringToV8(isolate, "y"),
                           v8::Number::New(isolate, p->y));
    std::ignore = obj->Set(local_context, gin::StringToV8(isolate, "w"),
                           v8::Number::New(isolate, p->w));
    std::ignore = obj->Set(local_context, gin::StringToV8(isolate, "h"),
                           v8::Number::New(isolate, p->h));
    std::ignore = obj->Set(local_context, gin::StringToV8(isolate, "score"),
                           v8::Number::New(isolate, p->score));
    std::ignore = result->Set(local_context, i, obj);
  }
  std::ignore = resolver.Get(isolate)->Resolve(local_context, result);
}

}  // namespace basarunaa
