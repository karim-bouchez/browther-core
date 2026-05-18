/* Copyright (c) 2019 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/. */

#include "brave/browser/brave_shields/brave_shields_web_contents_observer.h"

#include <string>

#include "brave/browser/android/brave_shields_content_settings.h"
#include "brave/components/browther_analytics/browther_analytics_service.h"
#include "brave/components/brave_shields/core/common/brave_shield_constants.h"
#include "chrome/browser/android/tab_android.h"
#include "content/public/browser/web_contents.h"

using content::WebContents;

namespace brave_shields {
// static
void BraveShieldsWebContentsObserver::DispatchBlockedEventForWebContents(
    const std::string& block_type,
    const std::string& subresource,
    WebContents* web_contents) {
  if (!web_contents) {
    return;
  }

  int tabId = 0;
  TabAndroid* tab = TabAndroid::FromWebContents(web_contents);
  if (tab) {
    tabId = tab->GetAndroidId();
  }
  chrome::android::BraveShieldsContentSettings::DispatchBlockedEvent(
      tabId, block_type, subresource);

  // Browther: report to public stats counter (browther.devndin.com).
  // Desktop fait la même chose dans brave_shields_web_contents_observer.cc#L144,
  // mais sur Android le code passe par cette static method dispatch_for_web_contents
  // dédiée — sans le hook le compteur ads_blocked Android reste à 0.
  if (block_type == kAds) {
    if (auto* analytics =
            browther_analytics::BrowtherAnalyticsService::GetInstance()) {
      analytics->IncrementAdsBlocked(1);
    }
  }
}

}  // namespace brave_shields
