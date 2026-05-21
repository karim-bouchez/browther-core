// Copyright (c) 2026 The Browther Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/components/sawtunaa/browser/sawtunaa_tab_helper.h"

#include <utility>

#include "base/logging.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/web_contents.h"

namespace sawtunaa {

// static
void SawtunaaTabHelper::BindSawtunaa(
    content::RenderFrameHost* rfh,
    mojo::PendingReceiver<mojom::Sawtunaa> receiver) {
  auto* web_contents = content::WebContents::FromRenderFrameHost(rfh);
  if (!web_contents) {
    return;
  }
  SawtunaaTabHelper::CreateForWebContents(web_contents);
  auto* helper = SawtunaaTabHelper::FromWebContents(web_contents);
  if (!helper) {
    return;
  }
  helper->receivers_.Add(helper, std::move(receiver), rfh);
}

SawtunaaTabHelper::SawtunaaTabHelper(content::WebContents* web_contents)
    : content::WebContentsUserData<SawtunaaTabHelper>(*web_contents) {
  LOG(INFO) << "[Sawtunaa] TabHelper created for WebContents";
}

SawtunaaTabHelper::~SawtunaaTabHelper() = default;

// --- mojom::Sawtunaa stubs (Jalon 2.B.3 — LOG only) ---

void SawtunaaTabHelper::LogJs(const std::string& message) {
  LOG(INFO) << "[Sawtunaa/JS] " << message;
}

void SawtunaaTabHelper::EmitMetric(const std::string& metric_json) {
  LOG(INFO) << "[Sawtunaa/metric] " << metric_json;
}

void SawtunaaTabHelper::PreprocessChunk(double timestamp_ms,
                                        const std::vector<float>& samples) {
  LOG(INFO) << "[Sawtunaa/chunk] ts=" << timestamp_ms
            << " n=" << samples.size();
}

void SawtunaaTabHelper::PlayAt(double timestamp_ms) {
  LOG(INFO) << "[Sawtunaa/playAt] ms=" << timestamp_ms;
}

void SawtunaaTabHelper::ClearChunks() {
  LOG(INFO) << "[Sawtunaa/clearChunks]";
}

void SawtunaaTabHelper::PageReset(const std::string& url) {
  LOG(INFO) << "[Sawtunaa/pageReset] " << url;
}

void SawtunaaTabHelper::SeekTo(double to_ms) {
  LOG(INFO) << "[Sawtunaa/seekTo] ms=" << to_ms;
}

void SawtunaaTabHelper::EvictRange(double start_ms, double end_ms) {
  LOG(INFO) << "[Sawtunaa/evictRange] " << start_ms << " -> " << end_ms;
}

void SawtunaaTabHelper::SyncRanges(std::vector<mojom::TimeRangePtr> ranges) {
  LOG(INFO) << "[Sawtunaa/syncRanges] count=" << ranges.size();
}

void SawtunaaTabHelper::PauseAudio() {
  LOG(INFO) << "[Sawtunaa/pauseAudio]";
}

void SawtunaaTabHelper::ResumeAudio() {
  LOG(INFO) << "[Sawtunaa/resumeAudio]";
}

WEB_CONTENTS_USER_DATA_KEY_IMPL(SawtunaaTabHelper);

}  // namespace sawtunaa
