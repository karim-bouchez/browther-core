// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/components/basarunaa/renderer/basarunaa_js_handler.h"

#include <utility>

#include "base/check.h"
#include "base/logging.h"
#include "brave/components/basarunaa/renderer/basarunaa_render_frame_observer.h"
#include "content/public/renderer/render_frame.h"
#include "gin/converter.h"
#include "gin/object_template_builder.h"
#include "third_party/blink/public/platform/scheduler/web_agent_group_scheduler.h"
#include "third_party/blink/public/web/web_element.h"
#include "third_party/blink/public/web/web_local_frame.h"
#include "v8/include/cppgc/allocation.h"

namespace basarunaa {

// static
void BasarunaaJSHandler::Install(
    content::RenderFrame* render_frame,
    base::WeakPtr<BasarunaaRenderFrameObserver> observer) {
  CHECK(render_frame);
  blink::WebLocalFrame* web_frame = render_frame->GetWebFrame();
  if (!web_frame) {
    return;
  }
  v8::Isolate* isolate = web_frame->GetAgentGroupScheduler()->Isolate();
  v8::HandleScope handle_scope(isolate);
  v8::Local<v8::Context> context = web_frame->MainWorldScriptContext();
  if (context.IsEmpty()) {
    return;
  }
  v8::Context::Scope context_scope(context);

  v8::Local<v8::Object> global = context->Global();
  const v8::Local<v8::String> property_name =
      gin::StringToV8(isolate, "__basarunaa");

  // Re-install no-op: a previous handler is already there.
  v8::Local<v8::Value> existing;
  if (global->Get(context, property_name).ToLocal(&existing) &&
      !existing->IsUndefined() && !existing->IsNull()) {
    return;
  }

  BasarunaaJSHandler* handler =
      cppgc::MakeGarbageCollected<BasarunaaJSHandler>(
          isolate->GetCppHeap()->GetAllocationHandle(), std::move(observer));

  v8::Local<v8::Object> wrapper;
  if (!handler->GetWrapper(isolate).ToLocal(&wrapper)) {
    return;
  }

  v8::PropertyDescriptor desc(wrapper, /*writable=*/false);
  desc.set_configurable(false);
  desc.set_enumerable(false);
  std::ignore = global->DefineProperty(context, property_name, desc);
}

BasarunaaJSHandler::BasarunaaJSHandler(
    base::WeakPtr<BasarunaaRenderFrameObserver> observer)
    : observer_(std::move(observer)) {}

BasarunaaJSHandler::~BasarunaaJSHandler() = default;

gin::ObjectTemplateBuilder BasarunaaJSHandler::GetObjectTemplateBuilder(
    v8::Isolate* isolate) {
  return gin::Wrappable<BasarunaaJSHandler>::GetObjectTemplateBuilder(isolate)
      // The whole binding object is callable as a function, so the page
      // calls `window.__basarunaa_native_notify(img)` directly without an
      // intermediate property dereference.
      .SetMethod("notify", &BasarunaaJSHandler::OnImageObserved);
}

const gin::WrapperInfo* BasarunaaJSHandler::wrapper_info() const {
  return &kWrapperInfo;
}

void BasarunaaJSHandler::OnImageObserved(v8::Isolate* isolate,
                                         v8::Local<v8::Value> element) {
  if (!observer_) {
    return;
  }
  if (element.IsEmpty() || !element->IsObject()) {
    return;
  }
  blink::WebElement web_element =
      blink::WebElement::FromV8Value(isolate, element);
  if (web_element.IsNull()) {
    return;
  }
  observer_->ProcessImageElement(web_element);
}

}  // namespace basarunaa
