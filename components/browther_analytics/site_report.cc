// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// you can obtain one at https://mozilla.org/MPL/2.0/.

#include "brave/components/browther_analytics/site_report.h"

#include <utility>

#include "base/values.h"
#include "brave/components/browther_analytics/browther_analytics_service.h"
#include "content/public/browser/web_contents.h"
#include "net/base/registry_controlled_domains/registry_controlled_domain.h"
#include "url/gurl.h"

namespace browther_analytics {

namespace {

// Domaine enregistrable de l'onglet, ou vide s'il n'y en a pas.
//
// `GetLastCommittedURL` et pas l'URL visible : on veut la page réellement
// chargée. Les schémas internes (browther://, chrome://, about:) n'ont pas de
// domaine enregistrable et retombent donc naturellement sur la chaîne vide —
// pas besoin de les lister.
//
// INCLUDE_PRIVATE_REGISTRIES : `foo.github.io` doit rester `foo.github.io` et
// pas s'effondrer en `github.io`, sinon des sites distincts se confondent dans
// les statistiques.
std::string RegistrableDomain(content::WebContents* web_contents) {
  if (!web_contents) {
    return std::string();
  }
  const GURL& url = web_contents->GetLastCommittedURL();
  if (!url.SchemeIsHTTPOrHTTPS()) {
    return std::string();
  }
  return net::registry_controlled_domains::GetDomainAndRegistry(
      url, net::registry_controlled_domains::INCLUDE_PRIVATE_REGISTRIES);
}

}  // namespace

SiteReportState GetSiteReportState(content::WebContents* web_contents) {
  SiteReportState state;
  state.domain = RegistrableDomain(web_contents);
  auto* analytics = BrowtherAnalyticsService::GetInstance();
  state.analytics_off = !analytics || !analytics->IsTrackingEnabled();
  state.can_report = !state.domain.empty() && !state.analytics_off;
  return state;
}

bool ReportSite(content::WebContents* web_contents,
                const std::string& feature) {
  const SiteReportState state = GetSiteReportState(web_contents);
  if (!state.can_report) {
    return false;
  }
  auto* analytics = BrowtherAnalyticsService::GetInstance();
  if (!analytics) {
    return false;
  }
  base::DictValue props;
  props.Set("feature", feature);
  props.Set("domain", state.domain);
  analytics->Track("site_reported", std::move(props));
  return true;
}

}  // namespace browther_analytics
