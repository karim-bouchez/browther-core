// Copyright (c) 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this file,
// You can obtain one at https://mozilla.org/MPL/2.0/.

#ifndef BRAVE_BROWSER_SAWTUNAA_SAWTUNAA_AUDIO_PROCESSOR_H_
#define BRAVE_BROWSER_SAWTUNAA_SAWTUNAA_AUDIO_PROCESSOR_H_

#include <cstdint>
#include <vector>

#include "base/memory/scoped_refptr.h"
#include "base/memory/weak_ptr.h"
#include "base/task/sequenced_task_runner.h"
#include "brave/components/sawtunaa/common/mojom/sawtunaa.mojom.h"
#include "content/public/browser/web_contents_observer.h"
#include "content/public/browser/web_contents_user_data.h"
#include "mojo/public/cpp/base/big_buffer.h"
#include "mojo/public/cpp/bindings/pending_receiver.h"
#include "mojo/public/cpp/bindings/receiver_set.h"

namespace content {
class RenderFrameHost;
class WebContents;
}  // namespace content

namespace sawtunaa {

// Browser-side handler de l'interface Mojo AudioTapProcessor (audio tap V2) :
// reçoit les batchs de PCM décodé du renderer (AudioRendererImpl →
// AudioTapProcessCB → RFO), fait tourner NSNet2 via SawtunaaAudioService et
// répond le PCM traité. Jumeau de BasarunaaImageAnalyzer (WebContentsUserData
// + mojo::ReceiverSet, canal non-associé — pattern stable).
//
// Ordre : TOUS les appels (ProcessBatch/ResetStream/DestroyStream) sont
// postés sur UN SequencedTaskRunner (pool) par WebContents → l'ordre Mojo est
// préservé jusqu'au service (un Reset ne peut pas doubler un batch en vol —
// sinon un batch d'avant-seek polluerait les états du flux d'après-seek).
// La sérialisation inter-onglets reste assurée par le mutex global du service.
class SawtunaaAudioProcessor
    : public content::WebContentsUserData<SawtunaaAudioProcessor>,
      public content::WebContentsObserver,
      public mojom::AudioTapProcessor {
 public:
  SawtunaaAudioProcessor(const SawtunaaAudioProcessor&) = delete;
  SawtunaaAudioProcessor& operator=(const SawtunaaAudioProcessor&) = delete;
  ~SawtunaaAudioProcessor() override;

  // Enregistré par BraveContentBrowserClient::
  // RegisterBrowserInterfaceBindersForFrame via map->Add<>().
  static void BindReceiver(
      content::RenderFrameHost* rfh,
      mojo::PendingReceiver<mojom::AudioTapProcessor> receiver);

  // Le tap natif a-t-il déjà traité de l'audio pour la page courante de cet
  // onglet ? Autrement dit : le WebMediaPlayer en place est-il bien tapé ?
  //
  // Sert au hint « Recharge l'onglet » du panel, qui ne doit s'afficher que
  // quand le reload changerait VRAIMENT quelque chose. Avant (bug rapporté par
  // Karim le 2026-08-09), le hint se basait sur « un média a-t-il déjà été
  // audible » — vrai aussi bien quand la pref était déjà ON au chargement
  // (player tapé, tout marche) que quand elle a été activée après coup (player
  // non tapé). Il s'affichait donc dès qu'on avait écouté quoi que ce soit.
  //
  // C'est un LATCH remis à zéro à chaque changement de page principale, pas un
  // « récemment » : sur une vidéo en pause les batches s'arrêtent alors que le
  // tap reste branché — un critère de fraîcheur recréerait le faux positif.
  // Retourne false si aucun processor n'existe pour cet onglet : personne n'a
  // jamais bindé l'interface, donc rien n'a jamais été tapé.
  static bool HasTappedAudio(content::WebContents* web_contents);

 private:
  friend class content::WebContentsUserData<SawtunaaAudioProcessor>;

  explicit SawtunaaAudioProcessor(content::WebContents* web_contents);

  // mojom::AudioTapProcessor:
  void ProcessBatch(int64_t stream_id,
                    mojo_base::BigBuffer pcm_planar,
                    int32_t frames,
                    int32_t channels,
                    int32_t sample_rate,
                    bool flush,
                    ProcessBatchCallback callback) override;
  void ResetStream(int64_t stream_id) override;
  void DestroyStream(int64_t stream_id) override;

  // content::WebContentsObserver:
  void PrimaryPageChanged(content::Page& page) override;

  // Reply sur le thread UI (le receiver y vit). WeakPtr gate : WebContents
  // détruit pendant la tâche → le callback wrappé répond ok=false (jamais de
  // responder Mojo dangling — leçon Basarunaa 2026-07-02). |channels| et
  // |sample_rate| servent au compteur music_seconds (stat NTP + backend).
  void OnBatchDone(ProcessBatchCallback callback,
                   int channels,
                   int sample_rate,
                   std::pair<bool, std::vector<float>> result);

  // stream_id est attribué par CHAQUE renderer → collision possible entre
  // iframes de process différents dans ce WebContents. Clé unique = id du
  // receiver (context du ReceiverSet, monotone) composé avec stream_id.
  int64_t MakeStreamKey(int64_t stream_id) const;

  // Séquence unique par WebContents pour tout le travail service (cf. doc de
  // classe).
  scoped_refptr<base::SequencedTaskRunner> task_runner_;

  mojo::ReceiverSet<mojom::AudioTapProcessor, int64_t> receivers_;
  int64_t next_receiver_context_ = 1;

  // Fractions de secondes traitées en attente (flushées par seconde entière
  // vers BrowtherAnalyticsService — même granularité que l'extension).
  double music_seconds_accumulator_ = 0.0;

  // Latch « le tap a produit au moins un batch depuis cette navigation »
  // (cf. HasTappedAudio).
  bool has_tapped_audio_ = false;

  WEB_CONTENTS_USER_DATA_KEY_DECL();

  base::WeakPtrFactory<SawtunaaAudioProcessor> weak_factory_{this};
};

}  // namespace sawtunaa

#endif  // BRAVE_BROWSER_SAWTUNAA_SAWTUNAA_AUDIO_PROCESSOR_H_
