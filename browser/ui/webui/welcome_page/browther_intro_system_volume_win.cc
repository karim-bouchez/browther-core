/* Copyright (c) 2026 dev&din. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

#include "brave/browser/ui/webui/welcome_page/browther_intro_system_volume.h"

#include <mmdeviceapi.h>
#include <windows.h>

#include <endpointvolume.h>
#include <wrl/client.h>

#include <algorithm>

#include "base/win/com_init_util.h"

namespace browther_intro {

namespace {

using Microsoft::WRL::ComPtr;

// Le réglage de la sortie par défaut, celle du mélangeur de la barre des
// tâches. `eConsole` : c'est aussi la sortie où Chromium joue l'extrait
// (`AudioDeviceDescription::kDefaultDeviceId`).
//
// Appelé depuis le ThreadPool : le processus navigateur y initialise COM en MTA
// pour tous les fils (`StartBrowserThreadPool`), rien à initialiser ici.
ComPtr<IAudioEndpointVolume> DefaultOutputVolume() {
  base::win::AssertComInitialized();

  ComPtr<IMMDeviceEnumerator> enumerator;
  if (FAILED(::CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr,
                                CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(&enumerator)))) {
    return nullptr;
  }
  // `E_NOTFOUND` sans aucune sortie active (rien de branché, service Audio
  // arrêté) : l'écran masque alors la jauge.
  ComPtr<IMMDevice> device;
  if (FAILED(enumerator->GetDefaultAudioEndpoint(eRender, eConsole, &device))) {
    return nullptr;
  }
  ComPtr<IAudioEndpointVolume> volume;
  if (FAILED(device->Activate(__uuidof(IAudioEndpointVolume),
                              CLSCTX_INPROC_SERVER, nullptr, &volume))) {
    return nullptr;
  }
  return volume;
}

}  // namespace

std::optional<SystemVolume> GetSystemVolume() {
  ComPtr<IAudioEndpointVolume> endpoint = DefaultOutputVolume();
  if (!endpoint) {
    return std::nullopt;
  }

  SystemVolume volume;
  // Le niveau tel que le montre le curseur de Windows (échelle perçue), pas
  // les décibels de `GetMasterVolumeLevel`.
  float level = 0;
  if (SUCCEEDED(endpoint->GetMasterVolumeLevelScalar(&level))) {
    volume.level = std::clamp(level, 0.0f, 1.0f);
  }
  BOOL muted = FALSE;
  if (SUCCEEDED(endpoint->GetMute(&muted))) {
    volume.muted = muted != FALSE;
  }
  return volume;
}

void SetSystemVolume(double level) {
  ComPtr<IAudioEndpointVolume> endpoint = DefaultOutputVolume();
  if (!endpoint) {
    return;
  }
  const float value = static_cast<float>(std::clamp(level, 0.0, 1.0));
  endpoint->SetMasterVolumeLevelScalar(value, nullptr);
  if (value > 0) {
    endpoint->SetMute(FALSE, nullptr);
  }
}

}  // namespace browther_intro
