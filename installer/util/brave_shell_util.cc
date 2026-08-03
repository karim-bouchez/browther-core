/* Copyright (c) 2021 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/. */

#include "brave/installer/util/brave_shell_util.h"

#include "base/notreached.h"
#include "chrome/install_static/install_util.h"
#include "components/version_info/channel.h"

namespace installer {

std::wstring GetProgIdForFileType() {
  // Browther: ProgIds fichiers (associations .pdf/.svg, visibles dans
  // « Ouvrir avec ») rebrandés — famille « Brwthr » ≤ 11 chars, cohérente
  // avec chromium_install_modes.h.
  switch (install_static::GetChromeChannel()) {
    case version_info::Channel::STABLE:
      return L"BrwthrFile";
    case version_info::Channel::BETA:
      return L"BrwthrBFile";
    case version_info::Channel::DEV:
      return L"BrwthrDFile";
    case version_info::Channel::CANARY:
      return L"BrwthrSFile";
    default:
      break;
  }
  // install_static::GetChromeChannel() only gives above four types
  // for official build. And we don't support installer build for
  // unofficial build.
  NOTREACHED();
}

bool ShouldUseFileTypeProgId(std::wstring_view ext) {
  return (ext == L".pdf" || ext == L".svg");
}

}  // namespace installer
