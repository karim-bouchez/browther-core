/* Copyright (c) 2026 dev&din. All rights reserved.
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at https://mozilla.org/MPL/2.0/. */

// [Browther] Détection de l'état réel d'une lecture EME, pour pouvoir en dire
// quelque chose d'honnête à l'utilisateur. Cf. private/docs/WIDEVINE_VMP.md
// § 10 (« Plan B — détection fiable de l'échec DRM »).
//
// Le piège : sans VMP, le CDM s'initialise, le challenge de licence part, et
// c'est le SERVEUR DU SERVICE qui refuse. Côté moteur, tout s'est bien passé —
// il n'y a aucune erreur à intercepter. On doit donc détecter l'ABSENCE DE
// SUCCÈS, pas la présence d'une erreur. D'où les deux signaux bruts remontés
// ici, et la temporisation qui vit côté browser (BrowtherProtectedContentTabHelper).
//
// Volontairement PAS de filtre sur le key system : `MediaKeySession` ne
// l'expose pas, et le critère comportemental (« un challenge est parti, aucune
// clé n'est devenue utilisable ») est déjà spécifique. Clear Key (tests)
// produit une clé utilisable immédiatement → annulé avant l'échéance.

namespace blink {
class ExecutionContext;

namespace {
void BrowtherReportDrmLicenseRequest(ExecutionContext* context);
void BrowtherReportDrmKeyUsable(ExecutionContext* context);
}  // namespace
}  // namespace blink

// Un challenge de licence part vers la page → arme la temporisation browser.
#define BROWTHER_MEDIA_KEY_SESSION_ON_MESSAGE                   \
  if (message_type == media::CdmMessageType::LICENSE_REQUEST) { \
    BrowtherReportDrmLicenseRequest(GetExecutionContext());     \
  }

// Une clé est devenue utilisable → le déchiffrement marche, on désarme.
#define BROWTHER_MEDIA_KEY_SESSION_ON_KEYS_CHANGE                \
  for (const auto& browther_key : keys) {                        \
    if (browther_key.Status() ==                                 \
        WebEncryptedMediaKeyInformation::KeyStatus::kUsable) {   \
      BrowtherReportDrmKeyUsable(GetExecutionContext());         \
      break;                                                     \
    }                                                            \
  }

#include <third_party/blink/renderer/modules/encryptedmedia/media_key_session.cc>

#undef BROWTHER_MEDIA_KEY_SESSION_ON_MESSAGE
#undef BROWTHER_MEDIA_KEY_SESSION_ON_KEYS_CHANGE

#include "brave/components/browther_drm/browther_drm.mojom-blink.h"
#include "mojo/public/cpp/bindings/associated_remote.h"
#include "third_party/blink/public/common/associated_interfaces/associated_interface_provider.h"
#include "third_party/blink/renderer/core/frame/local_dom_window.h"
#include "third_party/blink/renderer/core/frame/local_frame.h"
#include "third_party/blink/renderer/core/frame/local_frame_client.h"

namespace blink {
namespace {

// Remote éphémère, calqué sur MaybeOnWidevineRequest
// (chromium_src/.../navigator_request_media_key_system_access.cc) : le message
// est écrit sur le pipe à l'appel, l'objet peut mourir juste après. Ces deux
// notifications sont rares (quelques-unes par lecture) — pas de remote gardé.
mojo::AssociatedRemote<browther_drm::mojom::blink::BrowtherDrmStatus>
GetBrowtherDrmStatus(ExecutionContext* context) {
  mojo::AssociatedRemote<browther_drm::mojom::blink::BrowtherDrmStatus> remote;
  auto* window = DynamicTo<LocalDOMWindow>(context);
  if (!window) {
    return remote;
  }
  LocalFrame* frame = window->GetFrame();
  if (!frame || !frame->Client() ||
      !frame->Client()->GetRemoteNavigationAssociatedInterfaces()) {
    return remote;
  }
  frame->Client()->GetRemoteNavigationAssociatedInterfaces()->GetInterface(
      &remote);
  return remote;
}

void BrowtherReportDrmLicenseRequest(ExecutionContext* context) {
  auto remote = GetBrowtherDrmStatus(context);
  if (remote.is_bound()) {
    remote->OnLicenseRequestSent();
  }
}

void BrowtherReportDrmKeyUsable(ExecutionContext* context) {
  auto remote = GetBrowtherDrmStatus(context);
  if (remote.is_bound()) {
    remote->OnKeyUsable();
  }
}

}  // namespace
}  // namespace blink
