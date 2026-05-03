// Copyright (c) 2026 The Browther Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_COMPONENTS_BROWTHER_ANALYTICS_POSTHOG_CLIENT_H_
#define BRAVE_COMPONENTS_BROWTHER_ANALYTICS_POSTHOG_CLIENT_H_

#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "base/memory/scoped_refptr.h"
#include "base/timer/timer.h"
#include "base/values.h"

class GURL;

namespace network {
class SharedURLLoaderFactory;
class SimpleURLLoader;
}  // namespace network

namespace browther_analytics {

// Client HTTP minimal pour PostHog (region EU par défaut).
// Bufferise les events en mémoire et flush par batch.
//
// Pas de SDK, juste des POST JSON vers /batch/.
class PostHogClient {
 public:
  PostHogClient(scoped_refptr<network::SharedURLLoaderFactory> url_loader_factory,
                std::string distinct_id);
  ~PostHogClient();

  PostHogClient(const PostHogClient&) = delete;
  PostHogClient& operator=(const PostHogClient&) = delete;

  // Enqueue un event. Flush automatique périodique ou si buffer plein.
  void Enqueue(const std::string& event_name, base::DictValue properties);

  // Flush immédiat (best effort, fire-and-forget).
  void Flush();

  // True si la config est valide (API key non vide).
  static bool IsConfigured();

 private:
  void OnFlushComplete(std::unique_ptr<network::SimpleURLLoader> loader,
                       std::optional<std::string> response_body);

  scoped_refptr<network::SharedURLLoaderFactory> url_loader_factory_;
  std::string distinct_id_;
  std::vector<base::DictValue> buffer_;
  base::RepeatingTimer flush_timer_;

  static constexpr size_t kMaxBufferSize = 50;
};

}  // namespace browther_analytics

#endif  // BRAVE_COMPONENTS_BROWTHER_ANALYTICS_POSTHOG_CLIENT_H_
