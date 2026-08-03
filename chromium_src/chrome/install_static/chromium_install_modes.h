/* Copyright (c) 2020 The Brave Authors. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

// Brand-specific types and constants for Google Chrome.

#ifndef BRAVE_CHROMIUM_SRC_CHROME_INSTALL_STATIC_CHROMIUM_INSTALL_MODES_H_
#define BRAVE_CHROMIUM_SRC_CHROME_INSTALL_STATIC_CHROMIUM_INSTALL_MODES_H_

#include <stdlib.h>

#include <array>

#include "brave/components/brave_origin/buildflags/buildflags.h"
#include "chrome/app/chrome_dll_resource.h"
#include "chrome/common/chrome_icon_resources_win.h"
#include "chrome/install_static/install_constants.h"

namespace install_static {

// Brand-specific constants and install modes for Browther.
//
// Browther (2026-08-03) : rebrand complet des modes Windows. Sans ça :
// - user data dir = BraveSoftware\Brave-Browser* → PROFIL PARTAGÉ avec un
//   vrai Brave installé (SingletonLock cross-spawn, cookies/passwords mêlés) —
//   le jumeau Windows du fix mac brave_product_dir_name (config.gni:196),
//   qui est is_mac only ;
// - « Brave » affiché dans Paramètres Windows → Applications par défaut,
//   « Ouvrir avec », et les notifications toast (base_app_name/AUMID) ;
// - GUIDs/CLSIDs identiques à Brave officiel → collisions COM (toast
//   activator, elevator) et Active Setup si Brave est installé à côté.
// GUIDs regénérés (uuid4), SIDs sandbox distincts. ⚠️ Changer
// kCompanyPathName/kProductPathName abandonne l'ancien profil
// (BraveSoftware\…) — acceptable : Windows pas encore distribué (PC de test
// uniquement), même décision que sur mac (V1 beta, 2026-05-30).

// The brand-specific company name to be included as a component of the install
// and user data directory paths. May be empty if no such dir is to be used.
inline constexpr wchar_t kCompanyPathName[] = L"devndin";

// The brand-specific product name to be included as a component of the install
// and user data directory paths.
#if defined(OFFICIAL_BUILD)
#if BUILDFLAG(IS_BRAVE_ORIGIN_BRANDED)
// Brave Origin uses "Brave-Origin" instead of "Brave-Browser" to allow
// side-by-side installation with Brave Browser.
inline constexpr wchar_t kProductPathName[] = L"Brave-Origin";
#else
inline constexpr wchar_t kProductPathName[] = L"Browther";
#endif  // BUILDFLAG(IS_BRAVE_ORIGIN_BRANDED)
#else
// If you change this, then you also need to change occurrences of this string
// in mini_installer_constants.cc. (Browther : mini_installer non buildé —
// distribution zip — mais la remarque upstream reste vraie si ça change.)
inline constexpr wchar_t kProductPathName[] = L"Browther-Development";
#endif

// The brand-specific safe browsing client name.
inline constexpr char kSafeBrowsingName[] = "chromium";

// Note: This list of indices must be kept in sync with the brand-specific
// resource strings in chrome/installer/util/prebuild/create_string_rc.
enum InstallConstantIndex {
#if defined(OFFICIAL_BUILD)
  STABLE_INDEX,
  BETA_INDEX,
  DEV_INDEX,
  NIGHTLY_INDEX,
#else
  DEVELOPER_INDEX,
#endif
  NUM_INSTALL_MODES,
};

#if defined(OFFICIAL_BUILD)

// This is overriding the upstream value and shouldn't be undef'ed
// CHROMIUM_SRC_NOLINT
#define CHROMIUM_INDEX STABLE_INDEX

// Regarding the install switch, use the same values that are in
// chrome/installer/mini_installer/configuration.cc
#if BUILDFLAG(IS_BRAVE_ORIGIN_BRANDED)
// Brave Origin uses separate identifiers from Brave Browser to allow
// side-by-side installation and independent update infrastructure.
inline constexpr auto kInstallModes = std::to_array<InstallConstants>({
    // The primary install mode for stable Brave Origin.
    {
        .size = sizeof(InstallConstants),
        .index = STABLE_INDEX,  // The first mode is for stable/beta/dev.
        .install_switch =
            "",  // No install switch for the primary install mode.
        .install_suffix =
            L"",  // Empty install suffix - "Origin" is in kProductPathName.
        .logo_suffix = L"",  // No logo suffix for the primary install mode.
        .app_guid = L"{F1EF32DE-F987-4289-81D2-6C4780027F9B}",
        .base_app_name = L"Brave Origin",         // A distinct base_app_name.
        .base_app_id = L"BraveOrigin",            // A distinct base_app_id.
        .browser_prog_id_prefix = L"BraveOHTML",  // Browser ProgID prefix.
        .browser_prog_id_description =
            L"Brave Origin HTML Document",  // Browser ProgID description.
        .direct_launch_url_scheme = "brave-origin",
        .pdf_prog_id_prefix = L"BraveOPDF",  // PDF ProgID prefix.
        .pdf_prog_id_description =
            L"Brave Origin PDF Document",  // PDF ProgID description.
        .active_setup_guid =
            L"{F1EF32DE-F987-4289-81D2-6C4780027F9B}",  // Active Setup GUID.
        .legacy_command_execute_clsid =
            L"{A7B3C8D1-E2F4-5A6B-9C8D-1E2F3A4B5C6D}",  // CommandExecuteImpl
                                                        // CLSID.
        .toast_activator_clsid = {0x8a7b6c5d,
                                  0x4e3f,
                                  0x2a1b,
                                  {0x9c, 0x8d, 0x7e, 0x6f, 0x5a, 0x4b, 0x3c,
                                   0x2d}},  // Toast activator CLSID.
        .elevator_clsid = {0x1a2b3c4d,
                           0x5e6f,
                           0x7a8b,
                           {0x9c, 0x0d, 0x1e, 0x2f, 0x3a, 0x4b, 0x5c,
                            0x6d}},  // Elevator CLSID.
        .elevator_iid = {0x2b3c4d5e,
                         0x6f7a,
                         0x8b9c,
                         {0x0d, 0x1e, 0x2f, 0x3a, 0x4b, 0x5c, 0x6d, 0x7e}},
        .default_channel_name = L"",  // The empty string means "stable".
        .channel_strategy = ChannelStrategy::FLOATING,
        .supports_system_level = true,  // Supports system-level installs.
        .supports_set_as_default_browser =
            true,  // Supports in-product set as default browser UX.
        .app_icon_resource_index =
            icon_resources::kApplicationIndex,  // App icon resource index.
        .app_icon_resource_id = IDR_MAINFRAME,  // App icon resource id.
        .sandbox_sid_prefix =
            L"S-1-15-2-3251537155-1984446955-2931258699-841473695-1938553385-"
            L"934012153-",  // App container sid prefix for sandbox.
    },
    // A secondary install mode for Brave Origin Beta
    {
        .size = sizeof(InstallConstants),
        .index = BETA_INDEX,  // The mode for the side-by-side beta channel.
        .install_switch = "chrome-beta",  // Install switch.
        .install_suffix = L"-Beta",       // Install suffix.
        .logo_suffix = L"Beta",           // Logo suffix.
        .app_guid =
            L"{56DA94FD-D872-416B-BFC4-1D7011DA7473}",  // A distinct app GUID.
        .base_app_name = L"Brave Origin Beta",     // A distinct base_app_name.
        .base_app_id = L"BraveOriginBeta",         // A distinct base_app_id.
        .browser_prog_id_prefix = L"BraveOBHTML",  // Browser ProgID prefix.
        .browser_prog_id_description =
            L"Brave Origin Beta HTML Document",  // Browser ProgID description.
        .direct_launch_url_scheme = "brave-origin-beta",
        .pdf_prog_id_prefix = L"BraveOBPDF",  // PDF ProgID prefix.
        .pdf_prog_id_description =
            L"Brave Origin Beta PDF Document",  // PDF ProgID description.
        .active_setup_guid =
            L"{56DA94FD-D872-416B-BFC4-1D7011DA7473}",  // Active Setup GUID.
        .legacy_command_execute_clsid = L"",  // CommandExecuteImpl CLSID.
        .toast_activator_clsid = {0x3c4d5e6f,
                                  0x7a8b,
                                  0x9c0d,
                                  {0x1e, 0x2f, 0x3a, 0x4b, 0x5c, 0x6d, 0x7e,
                                   0x8f}},  // Toast activator CLSID.
        .elevator_clsid = {0x4d5e6f7a,
                           0x8b9c,
                           0x0d1e,
                           {0x2f, 0x3a, 0x4b, 0x5c, 0x6d, 0x7e, 0x8f,
                            0x9a}},  // Elevator CLSID.
        .elevator_iid = {0x5e6f7a8b,
                         0x9c0d,
                         0x1e2f,
                         {0x3a, 0x4b, 0x5c, 0x6d, 0x7e, 0x8f, 0x9a, 0x0b}},
        .default_channel_name = L"beta",  // Forced channel name.
        .channel_strategy = ChannelStrategy::FIXED,
        .supports_system_level = true,  // Supports system-level installs.
        .supports_set_as_default_browser =
            true,  // Supports in-product set as default browser UX.
        .app_icon_resource_index =
            icon_resources::kBetaApplicationIndex,  // App icon resource index.
        .app_icon_resource_id = IDR_X005_BETA,      // App icon resource id.
        .sandbox_sid_prefix =
            L"S-1-15-2-3251537155-1984446955-2931258699-841473695-1938553385-"
            L"934012154-",  // App container sid prefix for sandbox.
    },
    // A secondary install mode for Brave Origin Dev
    {
        .size = sizeof(InstallConstants),
        .index = DEV_INDEX,  // The mode for the side-by-side dev channel.
        .install_switch = "chrome-dev",  // Install switch.
        .install_suffix = L"-Dev",       // Install suffix.
        .logo_suffix = L"Dev",           // Logo suffix.
        .app_guid =
            L"{716D6A4A-D071-47A8-AC64-DBDE3EE3797B}",  // A distinct app GUID.
        .base_app_name = L"Brave Origin Dev",      // A distinct base_app_name.
        .base_app_id = L"BraveOriginDev",          // A distinct base_app_id.
        .browser_prog_id_prefix = L"BraveODHTML",  // Browser ProgID prefix.
        .browser_prog_id_description =
            L"Brave Origin Dev HTML Document",  // Browser ProgID description.
        .direct_launch_url_scheme = "brave-origin-dev",
        .pdf_prog_id_prefix = L"BraveODPDF",  // PDF ProgID prefix.
        .pdf_prog_id_description =
            L"Brave Origin Dev PDF Document",  // PDF ProgID description.
        .active_setup_guid =
            L"{716D6A4A-D071-47A8-AC64-DBDE3EE3797B}",  // Active Setup GUID.
        .legacy_command_execute_clsid = L"",  // CommandExecuteImpl CLSID.
        .toast_activator_clsid = {0x6f7a8b9c,
                                  0x0d1e,
                                  0x2f3a,
                                  {0x4b, 0x5c, 0x6d, 0x7e, 0x8f, 0x9a, 0x0b,
                                   0x1c}},  // Toast activator CLSID.
        .elevator_clsid = {0x7a8b9c0d,
                           0x1e2f,
                           0x3a4b,
                           {0x5c, 0x6d, 0x7e, 0x8f, 0x9a, 0x0b, 0x1c,
                            0x2d}},  // Elevator CLSID.
        .elevator_iid = {0x8b9c0d1e,
                         0x2f3a,
                         0x4b5c,
                         {0x6d, 0x7e, 0x8f, 0x9a, 0x0b, 0x1c, 0x2d, 0x3e}},
        .default_channel_name = L"dev",  // Forced channel name.
        .channel_strategy = ChannelStrategy::FIXED,
        .supports_system_level = true,  // Supports system-level installs.
        .supports_set_as_default_browser =
            true,  // Supports in-product set as default browser UX.
        .app_icon_resource_index =
            icon_resources::kDevApplicationIndex,  // App icon resource index.
        .app_icon_resource_id = IDR_X004_DEV,      // App icon resource id.
        .sandbox_sid_prefix =
            L"S-1-15-2-3251537155-1984446955-2931258699-841473695-1938553385-"
            L"934012155-",  // App container sid prefix for sandbox.
    },
    // A secondary install mode for Brave Origin SxS (nightly).
    {
        .size = sizeof(InstallConstants),
        .index =
            NIGHTLY_INDEX,  // The mode for the side-by-side nightly channel.
        .install_switch = "chrome-sxs",  // Install switch.
        .install_suffix = L"-Nightly",   // Install suffix.
        .logo_suffix = L"Canary",        // Logo suffix.
        .app_guid =
            L"{50474E96-9CD2-4BC8-B0A7-0D4B6EF2E709}",  // A distinct app GUID.
        .base_app_name = L"Brave Origin Nightly",  // A distinct base_app_name.
        .base_app_id = L"BraveOriginNightly",      // A distinct base_app_id.
        .browser_prog_id_prefix = L"BraveOSHTM",   // Browser ProgID prefix.
        .browser_prog_id_description =
            L"Brave Origin Nightly HTML Document",  // Browser ProgID
                                                    // description.
        .direct_launch_url_scheme = "brave-origin-nightly",
        .pdf_prog_id_prefix = L"BraveOSPDF",  // PDF ProgID prefix.
        .pdf_prog_id_description =
            L"Brave Origin Nightly PDF Document",  // PDF ProgID description.
        .active_setup_guid =
            L"{50474E96-9CD2-4BC8-B0A7-0D4B6EF2E709}",  // Active Setup GUID.
        .legacy_command_execute_clsid =
            L"{B8C9D0E1-F2A3-4B5C-6D7E-8F9A0B1C2D3E}",  // CommandExecuteImpl
                                                        // CLSID.
        .toast_activator_clsid = {0x9c0d1e2f,
                                  0x3a4b,
                                  0x5c6d,
                                  {0x7e, 0x8f, 0x9a, 0x0b, 0x1c, 0x2d, 0x3e,
                                   0x4f}},  // Toast activator CLSID.
        .elevator_clsid = {0x0d1e2f3a,
                           0x4b5c,
                           0x6d7e,
                           {0x8f, 0x9a, 0x0b, 0x1c, 0x2d, 0x3e, 0x4f,
                            0x5a}},  // Elevator CLSID.
        .elevator_iid = {0x1e2f3a4b,
                         0x5c6d,
                         0x7e8f,
                         {0x9a, 0x0b, 0x1c, 0x2d, 0x3e, 0x4f, 0x5a, 0x6b}},
        .default_channel_name = L"nightly",  // Forced channel name.
        .channel_strategy = ChannelStrategy::FIXED,
        .supports_system_level = true,  // Support system-level installs.
        .supports_set_as_default_browser =
            true,  // Support in-product set as default browser UX.
        .app_icon_resource_index =
            icon_resources::kSxSApplicationIndex,  // App icon resource index.
        .app_icon_resource_id = IDR_SXS,           // App icon resource id.
        .sandbox_sid_prefix =
            L"S-1-15-2-3251537155-1984446955-2931258699-841473695-1938553385-"
            L"934012156-",  // App container sid prefix for sandbox.
    },
});
#else   // !BUILDFLAG(IS_BRAVE_ORIGIN_BRANDED)
inline constexpr auto kInstallModes = std::to_array<InstallConstants>({
    // The primary install mode for stable Brave.
    {
        .size = sizeof(InstallConstants),
        .index = STABLE_INDEX,  // The first mode is for stable/beta/dev.
        .install_switch =
            "",  // No install switch for the primary install mode.
        .install_suffix =
            L"",  // Empty install_suffix for the primary install mode.
        .logo_suffix = L"",  // No logo suffix for the primary install mode.
        .app_guid = L"{AB3E02AE-6B57-4964-9386-FD93D824BB7A}",
        .base_app_name = L"Browther",             // A distinct base_app_name.
        .base_app_id = L"Browther",               // A distinct base_app_id.
        .browser_prog_id_prefix = L"BrwthrHTML",  // Browser ProgID prefix.
        .browser_prog_id_description =
            L"Browther HTML Document",  // Browser ProgID description.
        .direct_launch_url_scheme = "browther-browser",
        .pdf_prog_id_prefix = L"BrwthrPDF",  // PDF ProgID prefix.
        .pdf_prog_id_description =
            L"Browther PDF Document",  // PDF ProgID description.
        .active_setup_guid =
            L"{AB3E02AE-6B57-4964-9386-FD93D824BB7A}",  // Active Setup GUID.
        .legacy_command_execute_clsid =
            L"{59B39799-FE8C-4B13-8D12-FC6F734945C2}",  // CommandExecuteImpl
                                                        // CLSID.
        .toast_activator_clsid = {0x39059a8f,
                                  0xbc36,
                                  0x451f,
                                  {0xa4, 0x77, 0xca, 0x85, 0x6c, 0xb0, 0x39,
                                   0x75}},  // Toast activator CLSID.
        .elevator_clsid = {0xe087e72,
                           0x939f,
                           0x46cd,
                           {0x8d, 0xab, 0x6, 0x6f, 0xd7, 0x1c, 0xd3,
                            0x6b}},  // Elevator CLSID.
        .elevator_iid = {0x45e838e1,
                         0xf15e,
                         0x4953,
                         {0x84, 0x87, 0x8d, 0x9d, 0xd4, 0x3c, 0xa8, 0x3a}},
        .default_channel_name = L"",  // The empty string means "stable".
        .channel_strategy = ChannelStrategy::FLOATING,
        .supports_system_level = true,  // Supports system-level installs.
        .supports_set_as_default_browser =
            true,  // Supports in-product set as default browser UX.
        .app_icon_resource_index =
            icon_resources::kApplicationIndex,  // App icon resource index.
        .app_icon_resource_id = IDR_MAINFRAME,  // App icon resource id.
        .sandbox_sid_prefix =
            L"S-1-15-2-1603428234-1040624772-3436777400-1038063792-2846197712-"
            L"700000001-",  // App container sid prefix for sandbox.
    },
    // A secondary install mode for Brave Beta
    {
        .size = sizeof(InstallConstants),
        .index = BETA_INDEX,  // The mode for the side-by-side beta channel.
        .install_switch = "chrome-beta",  // Install switch.
        .install_suffix = L"-Beta",       // Install suffix.
        .logo_suffix = L"Beta",           // Logo suffix.
        .app_guid =
            L"{B6278743-1F2D-442E-B080-544568318C31}",  // A distinct app GUID.
        .base_app_name = L"Browther Beta",         // A distinct base_app_name.
        .base_app_id = L"BrowtherBeta",            // A distinct base_app_id.
        .browser_prog_id_prefix = L"BrwthrBHTML",  // Browser ProgID prefix.
        .browser_prog_id_description =
            L"Browther Beta HTML Document",  // Browser ProgID description.
        .direct_launch_url_scheme = "browther-browser-beta",
        .pdf_prog_id_prefix = L"BrwthrBPDF",  // PDF ProgID prefix.
        .pdf_prog_id_description =
            L"Browther Beta PDF Document",  // PDF ProgID description.
        .active_setup_guid =
            L"{B6278743-1F2D-442E-B080-544568318C31}",  // Active Setup GUID.
        .legacy_command_execute_clsid = L"",  // CommandExecuteImpl CLSID.
        .toast_activator_clsid = {0x5fe092d6,
                                  0x6336,
                                  0x49b3,
                                  {0xb1, 0x48, 0xc2, 0x61, 0x94, 0x9d, 0xc3,
                                   0x98}},  // Toast activator CLSID.
        .elevator_clsid = {0xaa19fd6c,
                           0x4461,
                           0x4801,
                           {0xa6, 0x52, 0x94, 0xcc, 0x8d, 0x7f, 0xf4,
                            0x13}},  // Elevator CLSID.
        .elevator_iid = {0x8ea74dcb,
                         0xce06,
                         0x4fd6,
                         {0x87, 0x34, 0x7b, 0xb0, 0x70, 0x72, 0x44, 0x24}},
        .default_channel_name = L"beta",  // Forced channel name.
        .channel_strategy = ChannelStrategy::FIXED,
        .supports_system_level = true,  // Supports system-level installs.
        .supports_set_as_default_browser =
            true,  // Supports in-product set as default browser UX.
        .app_icon_resource_index =
            icon_resources::kBetaApplicationIndex,  // App icon resource index.
        .app_icon_resource_id = IDR_X005_BETA,      // App icon resource id.
        .sandbox_sid_prefix =
            L"S-1-15-2-1603428234-1040624772-3436777400-1038063792-2846197712-"
            L"700000002-",  // App container sid prefix for sandbox.
    },
    // A secondary install mode for Brave Dev
    {
        .size = sizeof(InstallConstants),
        .index = DEV_INDEX,  // The mode for the side-by-side dev channel.
        .install_switch = "chrome-dev",  // Install switch.
        .install_suffix = L"-Dev",       // Install suffix.
        .logo_suffix = L"Dev",           // Logo suffix.
        .app_guid =
            L"{CCF8A632-1CDF-4209-903A-452F5EAE355A}",  // A distinct app GUID.
        .base_app_name = L"Browther Dev",          // A distinct base_app_name.
        .base_app_id = L"BrowtherDev",             // A distinct base_app_id.
        .browser_prog_id_prefix = L"BrwthrDHTML",  // Browser ProgID prefix.
        .browser_prog_id_description =
            L"Browther Dev HTML Document",  // Browser ProgID description.
        .direct_launch_url_scheme = "browther-browser-dev",
        .pdf_prog_id_prefix = L"BrwthrDPDF",  // PDF ProgID prefix.
        .pdf_prog_id_description =
            L"Browther Dev PDF Document",  // PDF ProgID description.
        .active_setup_guid =
            L"{CCF8A632-1CDF-4209-903A-452F5EAE355A}",  // Active Setup GUID.
        .legacy_command_execute_clsid = L"",  // CommandExecuteImpl CLSID.
        .toast_activator_clsid = {0x1f9219e4,
                                  0xf174,
                                  0x4cd8,
                                  {0xbb, 0x22, 0x50, 0xd1, 0xa, 0x27, 0x79,
                                   0x66}},  // Toast activator CLSID.
        .elevator_clsid = {0x70eece82,
                           0x2bb,
                           0x45ee,
                           {0x85, 0xb0, 0x60, 0x9f, 0xde, 0x76, 0x2a,
                            0x6}},  // Elevator CLSID.
        .elevator_iid = {0xeb43fece,
                         0xbb3f,
                         0x42f8,
                         {0x8a, 0x87, 0xc9, 0xc0, 0xd4, 0x9, 0x41, 0x27}},
        .default_channel_name = L"dev",  // Forced channel name.
        .channel_strategy = ChannelStrategy::FIXED,
        .supports_system_level = true,  // Supports system-level installs.
        .supports_set_as_default_browser =
            true,  // Supports in-product set as default browser UX.
        .app_icon_resource_index =
            icon_resources::kDevApplicationIndex,  // App icon resource index.
        .app_icon_resource_id = IDR_X004_DEV,      // App icon resource id.
        .sandbox_sid_prefix =
            L"S-1-15-2-1603428234-1040624772-3436777400-1038063792-2846197712-"
            L"700000003-",  // App container sid prefix for sandbox.
    },
    // A secondary install mode for Brave SxS (canary).
    {
        .size = sizeof(InstallConstants),
        .index =
            NIGHTLY_INDEX,  // The mode for the side-by-side nightly channel.
        .install_switch = "chrome-sxs",  // Install switch.
        .install_suffix = L"-Nightly",   // Install suffix.
        .logo_suffix = L"Canary",        // Logo suffix.
        .app_guid =
            L"{771FB3FE-291C-402D-91F2-CB8F06BA3D8B}",  // A distinct app GUID.
        .base_app_name = L"Browther Nightly",      // A distinct base_app_name.
        .base_app_id = L"BrowtherNightly",         // A distinct base_app_id.
        .browser_prog_id_prefix = L"BrwthrSHTML",  // Browser ProgID prefix.
        .browser_prog_id_description =
            L"Browther Nightly HTML Document",  // Browser ProgID description.
        .direct_launch_url_scheme = "browther-browser-nightly",
        .pdf_prog_id_prefix = L"BrwthrSPDF",  // PDF ProgID prefix.
        .pdf_prog_id_description =
            L"Browther Nightly PDF Document",  // PDF ProgID description.
        .active_setup_guid =
            L"{771FB3FE-291C-402D-91F2-CB8F06BA3D8B}",  // Active Setup GUID.
        .legacy_command_execute_clsid =
            L"{15794531-DD29-4AE4-9122-BE3B092C5F80}",  // CommandExecuteImpl
                                                        // CLSID.
        .toast_activator_clsid = {0xafbdcf3,
                                  0x48a0,
                                  0x4803,
                                  {0xa3, 0x25, 0x66, 0x49, 0x4d, 0xa8, 0x72,
                                   0x4e}},  // Toast activator CLSID.
        .elevator_clsid = {0xf4dceab,
                           0xaf1c,
                           0x46ec,
                           {0xa0, 0xb8, 0x9c, 0x41, 0x32, 0xd7, 0x6e,
                            0x1a}},  // Elevator CLSID.
        .elevator_iid = {0x9c0e44f0,
                         0xeb6d,
                         0x4c6f,
                         {0x8c, 0xb, 0x80, 0x19, 0x8c, 0x59, 0xff, 0xf6}},
        .default_channel_name = L"nightly",  // Forced channel name.
        .channel_strategy = ChannelStrategy::FIXED,
        .supports_system_level = true,  // Support system-level installs.
        .supports_set_as_default_browser =
            true,  // Support in-product set as default browser UX.
        .app_icon_resource_index =
            icon_resources::kSxSApplicationIndex,  // App icon resource index.
        .app_icon_resource_id = IDR_SXS,           // App icon resource id.
        .sandbox_sid_prefix =
            L"S-1-15-2-1603428234-1040624772-3436777400-1038063792-2846197712-"
            L"700000004-",  // App container sid prefix for sandbox.
    },
});
#endif  // BUILDFLAG(IS_BRAVE_ORIGIN_BRANDED)
#else

// CHROMIUM_SRC_NOLINT
#define CHROMIUM_INDEX DEVELOPER_INDEX

inline constexpr auto kInstallModes = std::to_array<InstallConstants>({
    // The primary (and only) install mode for Brave developer build.
    {
        .size = sizeof(InstallConstants),
        .index = DEVELOPER_INDEX,  // The one and only mode for developer mode.
        .install_switch =
            "",  // No install switch for the primary install mode.
        .install_suffix =
            L"",  // Empty install_suffix for the primary install mode.
        .logo_suffix = L"",  // No logo suffix for the primary install mode.
        .app_guid =
            L"",  // Empty app_guid since no integraion with Brave Update.
        .base_app_name = L"Browther Development",  // A distinct base_app_name.
        .base_app_id = L"BrowtherDevelopment",     // A distinct base_app_id.
        .browser_prog_id_prefix = L"BrwthrDvHTM",  // Browser ProgID prefix.
        .browser_prog_id_description =
            L"Browther Development HTML Document",  // Browser ProgID
                                                    // description.
        .direct_launch_url_scheme = "browther-browser-development",
        .pdf_prog_id_prefix = L"BrwthrDvPDF",  // PDF ProgID prefix.
        .pdf_prog_id_description =
            L"Browther Development PDF Document",  // PDF ProgID description.
        .active_setup_guid =
            L"{C69A8A12-DF30-4ED6-B276-1D5E3346FBD7}",  // Active Setup GUID.
        .legacy_command_execute_clsid =
            L"{A9EA6882-015F-4790-B208-3AEEAE348D1B}",  // CommandExecuteImpl
                                                        // CLSID.
        .toast_activator_clsid = {0x26c7cd73,
                                  0x5b99,
                                  0x43fe,
                                  {0x91, 0x21, 0x12, 0x74, 0xe6, 0xfc, 0xa0,
                                   0xb5}},  // Toast activator CLSID.
        .elevator_clsid = {0xf8d95729,
                           0x43a6,
                           0x4747,
                           {0xb7, 0xf3, 0xeb, 0x84, 0x7, 0xc9, 0xfc,
                            0xc6}},  // Elevator CLSID.
        .elevator_iid = {0x18fc8def,
                         0x59dc,
                         0x4ece,
                         {0xb4, 0xb1, 0x35, 0xf, 0x65, 0x55, 0xd0, 0x67}},
        .default_channel_name =
            L"",  // Empty default channel name since no update integration.
        .channel_strategy = ChannelStrategy::UNSUPPORTED,
        .supports_system_level = true,  // Supports system-level installs.
        .supports_set_as_default_browser =
            true,  // Supports in-product set as default browser UX.
        .app_icon_resource_index =
            icon_resources::kApplicationIndex,  // App icon resource index.
        .app_icon_resource_id = IDR_MAINFRAME,  // App icon resource id.
        .sandbox_sid_prefix =
            L"S-1-15-2-1603428234-1040624772-3436777400-1038063792-2846197712-"
            L"700000000-",  // App container sid prefix for sandbox.
    },
});
#endif

}  // namespace install_static

#endif  // BRAVE_CHROMIUM_SRC_CHROME_INSTALL_STATIC_CHROMIUM_INSTALL_MODES_H_
