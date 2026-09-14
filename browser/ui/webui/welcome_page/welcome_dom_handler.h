/* Copyright (c) 2023 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

#ifndef BRAVE_BROWSER_UI_WEBUI_WELCOME_PAGE_WELCOME_DOM_HANDLER_H_
#define BRAVE_BROWSER_UI_WEBUI_WELCOME_PAGE_WELCOME_DOM_HANDLER_H_

#include <optional>
#include <string>
#include <vector>

#include "base/memory/raw_ptr.h"
#include "base/memory/scoped_refptr.h"
#include "base/memory/weak_ptr.h"
#include "base/task/sequenced_task_runner.h"
#include "brave/browser/ui/webui/brave_education/brave_education_server_checker.h"
#include "brave/browser/ui/webui/welcome_page/browther_intro_installed_browsers.h"
#include "brave/browser/ui/webui/welcome_page/browther_intro_system_volume.h"
#include "chrome/browser/shell_integration.h"
#include "content/public/browser/web_ui_message_handler.h"

class Profile;
class Browser;

namespace base {
class ListValue;
}  // namespace base

// The handler for Javascript messages for the chrome://welcome page
class WelcomeDOMHandler : public content::WebUIMessageHandler {
 public:
  explicit WelcomeDOMHandler(Profile* profile);
  WelcomeDOMHandler(const WelcomeDOMHandler&) = delete;
  WelcomeDOMHandler& operator=(const WelcomeDOMHandler&) = delete;
  ~WelcomeDOMHandler() override;

  // WebUIMessageHandler implementation.
  void RegisterMessages() override;

 private:
  void HandleImportNowRequested(const base::ListValue& args);
  void HandleRecordP3A(const base::ListValue& args);
  void HandleGetDefaultBrowser(const base::ListValue& args);
  void SetLocalStateBooleanEnabled(const std::string& path,
                                   const base::ListValue& args);
  void OnGetDefaultBrowser(shell_integration::DefaultWebClientState state,
                           const std::u16string& name);
  void SetP3AEnabled(const base::ListValue& args);
  void HandleOpenSettingsPage(const base::ListValue& args);
  void HandleSetMetricsReportingEnabled(const base::ListValue& args);
  void HandleEnableWebDiscovery(const base::ListValue& args);
  void HandleGetWelcomeCompleteURL(const base::ListValue& args);
  // Browther: track event PostHog depuis le flow d'onboarding.
  // args[0] = event_name (string), args[1] = properties (dict, optionnel).
  void HandleTrackOnboardingEvent(const base::ListValue& args);

  // Browther : l'introduction (cf. private/docs/ONBOARDING-SPEC.md).
  void HandleBrowtherIntroStarted(const base::ListValue& args);
  // args[0] = "blur-female" | "blur-male" | "blur-all".
  void HandleSetBasarunaaMode(const base::ListValue& args);
  // args[0] = "basarunaa" | "sawtunaa". Hors accès anticipé seulement.
  void HandleEnableBrowtherFeature(const base::ListValue& args);
  void HandleGetSystemVolume(const base::ListValue& args);
  void HandleGetInstalledBrowsers(const base::ListValue& args);
  void OnGotInstalledBrowsers(
      const std::string& callback_id,
      std::optional<std::vector<std::string>> browsers);
  void HandleSetSystemVolume(const base::ListValue& args);
  void OnGotSystemVolume(const std::string& callback_id,
                         std::optional<browther_intro::SystemVolume> volume);

  void OnGettingStartedServerCheck(const std::string& callback_id,
                                   bool available);

  Browser* GetBrowser();

  size_t last_onboarding_phase_ = 0;
  std::u16string default_browser_name_;
  raw_ptr<Profile> profile_ = nullptr;
  brave_education::BraveEducationServerChecker brave_education_server_checker_;
  // CoreAudio peut bloquer (IPC vers coreaudiod) : jamais sur le fil UI, et
  // une seule séquence pour que les réglages successifs du curseur arrivent
  // dans l'ordre.
  scoped_refptr<base::SequencedTaskRunner> system_volume_task_runner_;
  base::WeakPtrFactory<WelcomeDOMHandler> weak_ptr_factory_{this};
};

#endif  // BRAVE_BROWSER_UI_WEBUI_WELCOME_PAGE_WELCOME_DOM_HANDLER_H_
