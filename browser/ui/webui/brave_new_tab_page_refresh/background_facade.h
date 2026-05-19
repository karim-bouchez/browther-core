// Copyright (c) 2025 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_BROWSER_UI_WEBUI_BRAVE_NEW_TAB_PAGE_REFRESH_BACKGROUND_FACADE_H_
#define BRAVE_BROWSER_UI_WEBUI_BRAVE_NEW_TAB_PAGE_REFRESH_BACKGROUND_FACADE_H_

#include <memory>
#include <string>
#include <vector>

#include "base/functional/callback.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "brave/browser/ui/webui/brave_new_tab_page_refresh/brave_new_tab_page.mojom.h"
#include "brave/components/brave_ads/core/mojom/brave_ads.mojom.h"
#include "brave/components/ntp_background_images/browser/ntp_background_images_service.h"

class CustomBackgroundFileManager;
class PrefService;

namespace ntp_background_images {
class NTPBackgroundImagesService;
class ViewCounterService;
}  // namespace ntp_background_images

namespace brave_new_tab_page_refresh {

// Provides a simplified interface for accessing background-related APIs from
// the new tab page.
class BackgroundFacade
    : public ntp_background_images::NTPBackgroundImagesService::Observer {
 public:
  BackgroundFacade(
      std::unique_ptr<CustomBackgroundFileManager> custom_file_manager,
      PrefService& pref_service,
      ntp_background_images::NTPBackgroundImagesService* bg_images_service,
      ntp_background_images::ViewCounterService* view_counter_service);

  ~BackgroundFacade() override;

  BackgroundFacade(const BackgroundFacade&) = delete;
  BackgroundFacade& operator=(const BackgroundFacade&) = delete;

  // Browther: registered by NewTabPageHandler so the WebUI gets notified
  // (via mojom::NewTabPage::OnBackgroundsUpdated) when our bundled
  // photo.json finishes loading on the ThreadPool. Without this, the first
  // GetBraveBackgrounds() call races the async file read and silently falls
  // back to the Brave preloaded image (Dylan Malval) in the WebUI.
  void SetBackgroundsLoadedCallback(base::RepeatingClosure callback);

  // ntp_background_images::NTPBackgroundImagesService::Observer:
  void OnBackgroundImagesDataDidUpdate(
      ntp_background_images::NTPBackgroundImagesData* data) override;

  std::vector<mojom::BraveBackgroundPtr> GetBraveBackgrounds();

  std::vector<std::string> GetCustomBackgrounds();

  mojom::SelectedBackgroundPtr GetSelectedBackground();

  mojom::SponsoredImageBackgroundPtr GetSponsoredImageBackground();

  void SelectBackground(mojom::SelectedBackgroundPtr background);

  void SaveCustomBackgrounds(std::vector<base::FilePath> paths,
                             base::OnceClosure callback);

  void RemoveCustomBackground(const std::string& background_url,
                              base::OnceClosure callback);

  void NotifySponsoredImageLogoClicked(
      const std::string& wallpaper_id,
      const std::string& creative_instance_id,
      const std::string& destination_url,
      brave_ads::mojom::NewTabPageAdMetricType metric_type);

 private:
  void OnCustomBackgroundsSaved(base::OnceClosure callback,
                                std::vector<base::FilePath> paths);

  void OnCustomBackgroundRemoved(base::OnceClosure callback,
                                 base::FilePath path,
                                 bool success);

  std::unique_ptr<CustomBackgroundFileManager> custom_file_manager_;
  raw_ref<PrefService> pref_service_;
  raw_ptr<ntp_background_images::NTPBackgroundImagesService> bg_images_service_;
  raw_ptr<ntp_background_images::ViewCounterService> view_counter_service_;
  // Browther: see SetBackgroundsLoadedCallback.
  base::RepeatingClosure backgrounds_loaded_callback_;
  base::WeakPtrFactory<BackgroundFacade> weak_factory_{this};
};

}  // namespace brave_new_tab_page_refresh

#endif  // BRAVE_BROWSER_UI_WEBUI_BRAVE_NEW_TAB_PAGE_REFRESH_BACKGROUND_FACADE_H_
