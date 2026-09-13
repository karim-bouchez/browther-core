/* Copyright (c) 2026 dev&din. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

#include "brave/browser/ui/webui/welcome_page/browther_intro_system_volume.h"

#include <CoreAudio/CoreAudio.h>

#include <algorithm>
#include <array>

namespace browther_intro {

namespace {

// `kAudioHardwareServiceDeviceProperty_VirtualMainVolume` (AudioToolbox) :
// le volume « maître » tel que le montre la barre des menus, y compris sur les
// sorties qui n'ont qu'un réglage par canal. Recopié ici pour ne pas lier
// AudioToolbox pour une constante.
// FourCC 'vmvc', écrit en hexadécimal : un littéral multi-caractères ne
// passe pas `-Wmultichar`.
constexpr AudioObjectPropertySelector kVirtualMainVolume = 0x766d7663;

AudioObjectPropertyAddress OutputAddress(AudioObjectPropertySelector selector,
                                         AudioObjectPropertyElement element) {
  return {selector, kAudioDevicePropertyScopeOutput, element};
}

AudioDeviceID DefaultOutputDevice() {
  AudioObjectPropertyAddress address = {
      kAudioHardwarePropertyDefaultOutputDevice,
      kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
  AudioDeviceID device = kAudioObjectUnknown;
  UInt32 size = sizeof(device);
  if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, nullptr,
                                 &size, &device) != noErr) {
    return kAudioObjectUnknown;
  }
  return device;
}

std::optional<Float32> ReadFloat(AudioDeviceID device,
                                 AudioObjectPropertyAddress address) {
  if (!AudioObjectHasProperty(device, &address)) {
    return std::nullopt;
  }
  Float32 value = 0;
  UInt32 size = sizeof(value);
  if (AudioObjectGetPropertyData(device, &address, 0, nullptr, &size, &value) !=
      noErr) {
    return std::nullopt;
  }
  return value;
}

bool WriteFloat(AudioDeviceID device,
                AudioObjectPropertyAddress address,
                Float32 value) {
  Boolean settable = false;
  if (!AudioObjectHasProperty(device, &address) ||
      AudioObjectIsPropertySettable(device, &address, &settable) != noErr ||
      !settable) {
    return false;
  }
  return AudioObjectSetPropertyData(device, &address, 0, nullptr, sizeof(value),
                                    &value) == noErr;
}

// Les deux premiers canaux, pour les sorties sans réglage global.
constexpr std::array<AudioObjectPropertyElement, 2> kStereoChannels = {1, 2};

}  // namespace

std::optional<SystemVolume> GetSystemVolume() {
  const AudioDeviceID device = DefaultOutputDevice();
  if (device == kAudioObjectUnknown) {
    return std::nullopt;
  }

  SystemVolume volume;
  if (auto main = ReadFloat(
          device,
          OutputAddress(kVirtualMainVolume, kAudioObjectPropertyElementMain))) {
    volume.level = *main;
  } else if (auto scalar = ReadFloat(
                 device, OutputAddress(kAudioDevicePropertyVolumeScalar,
                                       kAudioObjectPropertyElementMain))) {
    volume.level = *scalar;
  } else {
    Float32 sum = 0;
    int count = 0;
    for (auto channel : kStereoChannels) {
      if (auto value = ReadFloat(
              device,
              OutputAddress(kAudioDevicePropertyVolumeScalar, channel))) {
        sum += *value;
        ++count;
      }
    }
    if (count > 0) {
      volume.level = sum / count;
    }
  }

  AudioObjectPropertyAddress mute_address =
      OutputAddress(kAudioDevicePropertyMute, kAudioObjectPropertyElementMain);
  if (AudioObjectHasProperty(device, &mute_address)) {
    UInt32 muted = 0;
    UInt32 size = sizeof(muted);
    if (AudioObjectGetPropertyData(device, &mute_address, 0, nullptr, &size,
                                   &muted) == noErr) {
      volume.muted = muted != 0;
    }
  }
  return volume;
}

void SetSystemVolume(double level) {
  const AudioDeviceID device = DefaultOutputDevice();
  if (device == kAudioObjectUnknown) {
    return;
  }
  const Float32 value = static_cast<Float32>(std::clamp(level, 0.0, 1.0));

  if (!WriteFloat(
          device,
          OutputAddress(kVirtualMainVolume, kAudioObjectPropertyElementMain),
          value) &&
      !WriteFloat(device,
                  OutputAddress(kAudioDevicePropertyVolumeScalar,
                                kAudioObjectPropertyElementMain),
                  value)) {
    for (auto channel : kStereoChannels) {
      WriteFloat(device,
                 OutputAddress(kAudioDevicePropertyVolumeScalar, channel),
                 value);
    }
  }

  if (value > 0) {
    AudioObjectPropertyAddress mute_address = OutputAddress(
        kAudioDevicePropertyMute, kAudioObjectPropertyElementMain);
    Boolean settable = false;
    if (AudioObjectHasProperty(device, &mute_address) &&
        AudioObjectIsPropertySettable(device, &mute_address, &settable) ==
            noErr &&
        settable) {
      UInt32 unmuted = 0;
      AudioObjectSetPropertyData(device, &mute_address, 0, nullptr,
                                 sizeof(unmuted), &unmuted);
    }
  }
}

}  // namespace browther_intro
