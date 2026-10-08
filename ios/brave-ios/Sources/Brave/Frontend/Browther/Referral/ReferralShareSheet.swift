// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BraveStrings
import BrowtherReferral
import SwiftUI
import UIKit

/// La feuille **« Partager mon code »** : deux onglets, **Statut WhatsApp** puis
/// **Message** — `private/docs/PARRAINAGE.md` § 11, porté de la référence
/// Fajrunaa (`components/referral/ShareCodeSheet.tsx`, `StatusShareContent.tsx`,
/// `MessageShareContent.tsx`), recettée sur iPhone par Karim le 2026-10-08.
///
/// ⭐ **UN bouton sur l'écran, et le statut en PREMIER onglet** (choix D de Karim
/// sur maquette) : c'est le partage qui touche le plus de monde ; il était « un
/// peu caché » derrière un second bouton en contour. Ouvert par défaut, il
/// reçoit tout le trafic du bouton principal sans forcer personne. ⛔ L'ordre des
/// onglets n'est pas cosmétique : ne pas remettre le message devant.
///
/// 🔴 **Rien ici ne retient le geste d'avant** : pas de vidéo (réseau, vidéo
/// coupée, absente dans la langue, pas arrivée en `waitSeconds`) ⇒ l'onglet
/// Statut redevient l'image seule dans un grand cadre, l'onglet Message envoie
/// l'image, sans case à cocher. ⛔ Aucun bouton ne dépend de la vidéo.
///
/// ⭐ **Les 3 jours du moment « partage » se disent UNE fois, quand la feuille se
/// referme** (`report`) — pas entre les deux envois, sous WhatsApp. Refermée
/// après un envoi sur deux : le partage a abouti quand même.
/// ⚠️ Un seul onglet est monté à la fois : chacun a son lecteur vidéo.
struct ReferralShareSheet: View {
  let status: ReferralStatus
  let origin: ReferralShareOrigin
  let note: ReferralNote
  var onAchieved: (() -> Void)?
  let close: () -> Void

  private enum Tab: Hashable {
    case status, message
  }

  @StateObject private var video = ReferralStatusVideoWatch()
  @State private var tab: Tab = .status
  @State private var image: UIImage?
  @State private var imageFile: URL?
  @State private var achieved = false
  @State private var reported = false

  /// 🔴 La langue de l'image, de la vidéo et du message joint = celle de l'app
  /// (on parle à SES contacts) : fr, en ou ar, sinon l'anglais.
  private var texts: Strings.BrowtherReferral.StatusImage {
    Strings.BrowtherReferral.StatusImage.current(lifetimeAt: MilestoneScale(status: status).lifetimeAt)
  }

  private var code: String { status.referral.code.uppercased() }
  private var link: String { ReferralShare.link(code: code, url: status.referral.url) }

  var body: some View {
    VStack(spacing: 0) {
      Text(Strings.BrowtherReferral.shareMyCode)
        .font(.headline)
        .padding(.top, 26)
        .padding(.bottom, 14)
      Picker("", selection: $tab) {
        Text(Strings.BrowtherReferral.statusTab).tag(Tab.status)
        Text(Strings.BrowtherReferral.shareTabMessage).tag(Tab.message)
      }
      .pickerStyle(.segmented)
      .padding(.horizontal, 20)
      .padding(.bottom, 14)
      ScrollView {
        Group {
          switch tab {
          case .status:
            ReferralStatusShareContent(
              link: link,
              image: image,
              imageFile: imageFile,
              video: video,
              origin: origin,
              onSent: { achieved = true },
              onFinished: finish
            )
          case .message:
            ReferralMessageShareContent(
              status: status,
              texts: texts,
              link: link,
              image: image,
              imageFile: imageFile,
              video: video,
              origin: origin,
              onSent: { achieved = true },
              onFinished: finish
            )
          }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
      }
    }
    .background(ReferralPalette.screen.ignoresSafeArea())
    .environment(\.referralNote, note)
    .onAppear(perform: prepare)
    .onDisappear(perform: report)
  }

  /// L'image est dessinée UNE fois, ici : l'aperçu des deux onglets et le
  /// fichier qui part sont la même image (ce qu'on voit est ce qui part).
  private func prepare() {
    let texts = texts
    if image == nil {
      let rendered = ReferralStatusImage.render(code: code, texts: texts)
      image = rendered
      imageFile = ReferralSharing.statusImageFile(rendered, code: code)
    }
    video.start(language: ReferralStatusVideo.statusLanguage(appLanguage: texts.language))
  }

  private func finish() {
    close()
    report()
  }

  private func report() {
    guard achieved, !reported else { return }
    reported = true
    onAchieved?()
    BrowtherReferralController.shared.shareDone(from: origin, preview: note.preview)
  }
}

// MARK: - Onglet « Statut WhatsApp »

/// ⭐ **L'aperçu dit ce que fait le geste** (Karim, 2026-09-29) : chaque statut
/// est montré dans un cadre de statut — la barre en haut, le LIEN EN LÉGENDE en
/// bas, là où WhatsApp le posera.
///
/// ⭐ **Deux statuts, côte à côte, à cocher** (choix A de Karim sur maquette,
/// 2026-10-08) : la vidéo de présentation et l'image qui porte le code. UN
/// bouton, qui publie le prochain statut coché ; après le premier, il annonce le
/// second (« 2 sur 2 ») et **se déclenche tout seul** au bout d'un court
/// décompte, montré par la jauge du bouton — un tap le devance.
/// ⛔ Ce passage automatique : jamais sans la jauge, jamais app en
/// arrière-plan, et UNE fois par envoi réussi — une feuille de partage refermée
/// ne se rouvre pas toute seule.
/// 🔴 **Un envoi par statut** : WhatsApp ne donne le lien qu'au premier média
/// d'un envoi (`ReferralStatusVideo`). ⛔ Ne pas regrouper les deux.
struct ReferralStatusShareContent: View {
  let link: String
  let image: UIImage?
  let imageFile: URL?
  @ObservedObject var video: ReferralStatusVideoWatch
  let origin: ReferralShareOrigin
  var onSent: () -> Void
  var onFinished: () -> Void

  @Environment(\.referralNote) private var note
  @State private var picked = ReferralStatusFlags.both
  @State private var sent = ReferralStatusFlags.none
  @State private var busy = false
  /// Le passage automatique au statut suivant : armé par un envoi réussi,
  /// désarmé dès qu'un envoi démarre (le sien compris).
  @State private var autoArmed = false
  /// ⚠️ Pas `scenePhase` : dans une vue hébergée par UIKit il ne suit pas
  /// l'application — on écoute ses notifications.
  @State private var appActive = UIApplication.shared.applicationState == .active
  @State private var progress: CGFloat = 0
  @State private var videoSeconds: Double?

  private var two: Bool { video.offered }
  /// Sans vidéo, une seule chose à publier : l'image, d'office.
  private var wanted: ReferralStatusFlags { two ? picked : .imageOnly }
  private var next: ReferralStatusSegment? { ReferralStatusVideo.queue(picked: wanted, sent: sent).first }
  private var cta: ReferralStatusCta { ReferralStatusVideo.cta(picked: wanted, sent: sent) }

  private var nextReady: Bool {
    switch next {
    case .video: return video.file != nil
    case .image: return imageFile != nil
    case nil: return false
    }
  }
  private var canPublish: Bool { !busy && nextReady }

  private var autoOn: Bool {
    guard two, autoArmed, appActive, canPublish, case .next = cta else { return false }
    return true
  }

  var body: some View {
    VStack(spacing: 16) {
      if two {
        HStack(alignment: .top, spacing: 12) {
          ForEach(ReferralStatusVideo.segments(hasVideo: true), id: \.self) { segment in
            card(segment)
          }
        }
      } else {
        ReferralStatusFrame(small: false, link: link, loading: image == nil, dimmed: false, sentLabel: nil) {
          media(.image)
        }
        .frame(maxWidth: 232)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Strings.BrowtherReferral.statusPreviewA11y)
        .accessibilityAddTraits(.isImage)
      }

      ReferralGaugeButton(
        label: buttonText,
        systemImage: "circle.dashed.inset.filled",
        busy: busy,
        progress: autoOn ? progress : nil,
        action: publish
      )
      .disabled(!canPublish)

      if let hint {
        Text(hint)
          .font(.footnote)
          .foregroundStyle(Color.secondary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
      appActive = true
    }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
      appActive = false
    }
    // ⭐ Le statut suivant part tout seul quand la jauge est pleine. Le décompte
    // ne repart de zéro que si SA condition change.
    .task(id: autoOn) {
      progress = 0
      guard autoOn else { return }
      withAnimation(.linear(duration: ReferralStatusVideo.nextAutoSeconds)) { progress = 1 }
      try? await Task.sleep(nanoseconds: UInt64(ReferralStatusVideo.nextAutoSeconds * 1_000_000_000))
      guard !Task.isCancelled else { return }
      publish()
    }
  }

  // MARK: Les vignettes

  private func card(_ segment: ReferralStatusSegment) -> some View {
    let labels = labels(segment)
    return Button {
      toggle(segment)
    } label: {
      VStack(alignment: .leading, spacing: 8) {
        ReferralStatusFrame(
          small: true,
          link: link,
          loading: segment == .video ? video.file == nil : image == nil,
          dimmed: !picked[segment] && !sent[segment],
          sentLabel: sent[segment] ? Strings.BrowtherReferral.statusPublished : nil
        ) {
          media(segment)
        }
        .overlay(alignment: .topTrailing) {
          if !sent[segment] {
            ZStack {
              Circle().fill(picked[segment] ? Color(UIColor.systemBackground) : Color.black.opacity(0.25))
              Circle().strokeBorder(Color.white, lineWidth: 2)
              if picked[segment] {
                Image(systemName: "checkmark")
                  .font(.system(size: 12, weight: .bold))
                  .foregroundStyle(Color(UIColor.label))
              }
            }
            .frame(width: 26, height: 26)
            .padding(.top, 14)
            .padding(.trailing, 9)
          }
        }
        VStack(alignment: .leading, spacing: 2) {
          Text(labels.title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
          Text(labels.sub)
            .font(.footnote)
            .foregroundStyle(Color.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 2)
      }
      .frame(maxWidth: 190)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(sent[segment])
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(labels.title), \(labels.sub)")
    .accessibilityAddTraits(picked[segment] ? [.isButton, .isSelected] : .isButton)
  }

  @ViewBuilder private func media(_ segment: ReferralStatusSegment) -> some View {
    switch segment {
    case .video:
      if let file = video.file {
        ReferralStatusVideoPreview(file: file) { videoSeconds = $0 }
          // Le toucher est celui de la vignette, pas du lecteur.
          .allowsHitTesting(false)
          .overlay(alignment: .topLeading) {
            ReferralVideoTag(seconds: videoSeconds)
              .padding(.top, 18)
              .padding(.leading, 9)
          }
      }
    case .image:
      if let image {
        Image(uiImage: image)
          .resizable()
          .scaledToFill()
      }
    }
  }

  private func labels(_ segment: ReferralStatusSegment) -> (title: String, sub: String) {
    switch segment {
    case .video: return (Strings.BrowtherReferral.statusVideoLabel, Strings.BrowtherReferral.statusVideoSub)
    case .image: return (Strings.BrowtherReferral.statusImageLabel, Strings.BrowtherReferral.statusImageSub)
    }
  }

  // MARK: Le bouton et sa ligne

  private var buttonText: String {
    guard two else { return Strings.BrowtherReferral.shareStatus }
    switch cta {
    case .both: return Strings.BrowtherReferral.statusPublishBoth
    case .one(let segment):
      return segment == .video
        ? Strings.BrowtherReferral.statusPublishVideo : Strings.BrowtherReferral.statusPublishImage
    case .next(let segment):
      return segment == .video
        ? Strings.BrowtherReferral.statusPublishVideoNext : Strings.BrowtherReferral.statusPublishImageNext
    case .none: return Strings.BrowtherReferral.statusPickOne
    case .done: return Strings.BrowtherReferral.shareStatus
    }
  }

  private var hint: String? {
    guard two else { return nil }
    switch cta {
    case .both: return Strings.BrowtherReferral.statusHintBoth
    case .one: return Strings.BrowtherReferral.statusHintOne
    case .next(let segment):
      // Ce qui RESTE est `segment` : c'est l'autre qui vient de partir.
      if autoOn {
        return segment == .video
          ? Strings.BrowtherReferral.statusHintImageDoneAuto : Strings.BrowtherReferral.statusHintVideoDoneAuto
      }
      return segment == .video
        ? Strings.BrowtherReferral.statusHintImageDone : Strings.BrowtherReferral.statusHintVideoDone
    case .none: return Strings.BrowtherReferral.statusHintNone
    case .done: return nil
    }
  }

  // MARK: Les gestes

  private func toggle(_ segment: ReferralStatusSegment) {
    guard !busy, !sent[segment] else { return }
    UISelectionFeedbackGenerator().selectionChanged()
    picked[segment].toggle()
  }

  /// ⭐ **Le SEUL endroit qui compte un statut** : `format` le distingue du
  /// message, `media` dit lequel des deux statuts. ⚠️ Un évènement par ENVOI —
  /// qui publie les deux en émet deux : compter des personnes, pas des lignes.
  /// Muet pendant un aperçu de recette (§ 13.8). Verrouillé par
  /// `private/scripts/ios-referral-tests/analytics_check.py`.
  private func count(_ result: ReferralShareResult, _ segment: ReferralStatusSegment) {
    note(.referralShared, ["screen": origin.rawValue, "result": result.rawValue, "format": "status", "media": segment.rawValue])
  }

  /// UN envoi : le prochain statut coché, avec le lien SEUL en texte (WhatsApp
  /// en fait la légende).
  private func publish() {
    guard !busy, let segment = next else { return }
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    autoArmed = false
    let file = segment == .video ? video.file : imageFile
    guard let file, let host = BrowtherReferralPresenter.topController() else {
      count(.unavailable, segment)
      BrowtherReferralToast.show(
        title: segment == .video
          ? Strings.BrowtherReferral.statusFailedVideo : Strings.BrowtherReferral.statusFailed,
        persistent: false,
        duration: 6
      )
      return
    }
    busy = true
    let wanted = wanted
    ReferralSharing.shareFile(file, text: link, from: host) { result in
      busy = false
      count(result, segment)
      guard result.achieved else { return }
      onSent()
      var nowSent = sent
      nowSent[segment] = true
      sent = nowSent
      // Le dernier statut coché est parti : la feuille se referme. Sinon elle
      // reste, le bouton annonce le suivant et sa jauge démarre.
      if ReferralStatusVideo.queue(picked: wanted, sent: nowSent).isEmpty {
        onFinished()
      } else {
        autoArmed = true
      }
    }
  }
}

// MARK: - Onglet « Message »

/// ⭐ **L'aperçu dit ce que fait le geste** : le message dans une bulle de
/// discussion, tel que le proche le recevra.
///
/// ⭐ **Deux messages, selon la case « Joindre la vidéo »** (Karim, 2026-10-08 —
/// un texte et un lien seuls engagent peu) :
/// - cochée : la VIDÉO, et dessous le texte de l'image du statut, le code en
///   clair, le lien (`ReferralShare.videoMessage`) ;
/// - décochée : l'IMAGE du statut (elle porte déjà le texte et la carte), et
///   dessous le code et le lien (`ReferralShare.imageMessage`).
/// Un seul fichier par envoi : le texte devient bien sa légende. ⚠️ iMessage :
/// deux bulles.
/// 🔴 **Jamais d'impasse** : pas de vidéo ⇒ l'image, sans case à cocher ; image
/// qui n'a pas pu être écrite ⇒ le message texte d'avant part seul.
/// 🔴 Partager ne crée AUCUNE invitation (§ 12.1) : un partage abouti n'ouvre
/// droit qu'aux 3 jours.
struct ReferralMessageShareContent: View {
  let status: ReferralStatus
  let texts: Strings.BrowtherReferral.StatusImage
  let link: String
  let image: UIImage?
  let imageFile: URL?
  @ObservedObject var video: ReferralStatusVideoWatch
  let origin: ReferralShareOrigin
  var onSent: () -> Void
  var onFinished: () -> Void

  @Environment(\.referralNote) private var note
  @Environment(\.colorScheme) private var scheme
  @State private var attach = true
  @State private var busy = false
  @State private var videoSeconds: Double?

  /// La bulle : les couleurs d'une discussion, pas celles de l'app.
  private struct Chat {
    let wall: Color
    let bubble: Color
    let ink: Color
    let link: Color

    static let light = Chat(
      wall: Color(UIColor(rgb: 0xEFEAE2)),
      bubble: Color(UIColor(rgb: 0xD9FDD3)),
      ink: Color(UIColor(rgb: 0x111B21)),
      link: Color(UIColor(rgb: 0x027EB5))
    )
    static let dark = Chat(
      wall: Color(UIColor(rgb: 0x0B141A)),
      bubble: Color(UIColor(rgb: 0x144D37)),
      ink: Color(UIColor(rgb: 0xE9EDEF)),
      link: Color(UIColor(rgb: 0x7DD3FC))
    )
  }

  /// La bulle de la vidéo : large, la vidéo y est recadrée et le texte coupé.
  private static let videoBubbleWidth: CGFloat = 236
  private static let videoThumbHeight: CGFloat = 150
  /// Dans l'aperçu, le texte de la vidéo ne prend pas toute la feuille : le
  /// message, lui, part en entier.
  private static let videoTextLines = 5
  /// La bulle de l'image : l'image entière, à ses proportions (9:16).
  private static let imageWidth: CGFloat = 150

  private var code: String { status.referral.code.uppercased() }
  private var withVideo: Bool { video.offered && attach }
  /// ⚠️ On n'attend que ce qui part : la vidéo si elle est cochée.
  private var canSend: Bool { !busy && (!withVideo || video.file != nil) }

  var body: some View {
    let chat = scheme == .dark ? Chat.dark : Chat.light
    VStack(spacing: 12) {
      HStack {
        Spacer(minLength: 0)
        bubble(chat)
      }
      .padding(.vertical, 16)
      .padding(.horizontal, 12)
      .background(chat.wall, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
      // La bulle envoyée reste du même côté, même en arabe (le texte, lui, suit sa langue).
      .environment(\.layoutDirection, .leftToRight)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(Strings.BrowtherReferral.sharePreviewA11y)
      .accessibilityAddTraits(.isImage)

      if video.offered {
        Button {
          UISelectionFeedbackGenerator().selectionChanged()
          attach.toggle()
        } label: {
          HStack(spacing: 12) {
            ZStack {
              RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(attach ? Color(UIColor.label) : Color.clear)
              RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color(UIColor.label), lineWidth: 2)
              if attach {
                Image(systemName: "checkmark")
                  .font(.system(size: 12, weight: .bold))
                  .foregroundStyle(Color(UIColor.systemBackground))
              }
            }
            .frame(width: 22, height: 22)
            Text(Strings.BrowtherReferral.shareAttachVideo)
              .font(.subheadline)
              .foregroundStyle(Color.primary)
            Spacer(minLength: 0)
          }
          .frame(minHeight: 44)
          .padding(.horizontal, 2)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityAddTraits(attach ? [.isButton, .isSelected] : .isButton)
      }

      ReferralGaugeButton(
        label: Strings.BrowtherReferral.shareSend,
        systemImage: "square.and.arrow.up",
        busy: busy,
        progress: nil,
        action: send
      )
      .disabled(!canSend)
    }
  }

  private func bubble(_ chat: Chat) -> some View {
    let rtl: LayoutDirection = texts.isRTL ? .rightToLeft : .leftToRight
    return VStack(alignment: .leading, spacing: 6) {
      if withVideo {
        ZStack {
          Color.black
          if let file = video.file {
            ReferralStatusVideoPreview(file: file) { videoSeconds = $0 }
              .allowsHitTesting(false)
          } else {
            ProgressView().tint(.white)
          }
        }
        .frame(width: Self.videoBubbleWidth, height: Self.videoThumbHeight)
        .overlay(alignment: .bottomLeading) {
          if video.file != nil {
            ReferralVideoTag(seconds: videoSeconds)
              .padding(.leading, 8)
              .padding(.bottom, 7)
          }
        }
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        Text(texts.paragraphs.map(ReferralShare.stripStatusMarks).joined(separator: "\n\n"))
          .font(.footnote)
          .foregroundStyle(chat.ink)
          .lineLimit(Self.videoTextLines)
          .multilineTextAlignment(.leading)
          .frame(maxWidth: .infinity, alignment: .leading)
          .environment(\.layoutDirection, rtl)
          .padding(.horizontal, 4)
      } else {
        ZStack {
          Color.black
          if let image {
            Image(uiImage: image)
              .resizable()
              .scaledToFill()
          } else {
            ProgressView().tint(.white)
          }
        }
        .frame(width: Self.imageWidth, height: (Self.imageWidth * 16 / 9).rounded())
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
      }
      VStack(alignment: .leading, spacing: 1) {
        Text(texts.codeLine(code: code))
          .foregroundStyle(chat.ink)
          .frame(maxWidth: .infinity, alignment: .leading)
          .environment(\.layoutDirection, rtl)
        Text(link.replacingOccurrences(of: "https://", with: ""))
          .foregroundStyle(chat.link)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
      }
      .font(.footnote)
      .padding(.horizontal, 4)
      .padding(.bottom, 2)
    }
    .padding(5)
    .frame(width: (withVideo ? Self.videoBubbleWidth : Self.imageWidth) + 10)
    .background(chat.bubble, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
  }

  /// Ce qui part : la vidéo cochée et arrivée, sinon l'image, sinon le message
  /// texte d'avant. `media` dit ce qui est RÉELLEMENT joint.
  private func send() {
    guard !busy, let host = BrowtherReferralPresenter.topController() else { return }
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    let codeLine = texts.codeLine(code: code)
    let url = status.referral.url
    let media: ReferralStatusSegment?
    let file: URL?
    let message: String
    if withVideo, let videoFile = video.file {
      media = .video
      file = videoFile
      message = ReferralShare.videoMessage(paragraphs: texts.paragraphs, codeLine: codeLine, code: code, url: url)
    } else if let imageFile {
      media = .image
      file = imageFile
      message = ReferralShare.imageMessage(codeLine: codeLine, code: code, url: url)
    } else {
      media = nil
      file = nil
      message = ReferralSharing.message(for: status)
    }
    busy = true
    let done: (ReferralShareResult) -> Void = { result in
      busy = false
      note(.referralShared, ReferralSharing.properties(["screen": origin.rawValue, "result": result.rawValue, "format": "message"], media: media))
      guard result.achieved else { return }
      onSent()
      onFinished()
    }
    if let file {
      ReferralSharing.shareFile(file, text: message, from: host, completion: done)
    } else {
      ReferralSharing.share(status: status, from: host, completion: done)
    }
  }
}

// MARK: - Les pièces communes

/// Un statut WhatsApp en réduction : le média, la barre de progression en haut,
/// le lien en légende en bas. `small` = une des deux vignettes.
struct ReferralStatusFrame<Media: View>: View {
  let small: Bool
  let link: String
  let loading: Bool
  let dimmed: Bool
  /// Le statut est parti : son libellé (« Publié »), sinon `nil`.
  let sentLabel: String?
  @ViewBuilder var media: () -> Media

  var body: some View {
    Color.black
      .aspectRatio(9.0 / 16.0, contentMode: .fit)
      .overlay { media() }
      .overlay(alignment: .top) {
        Capsule()
          .fill(Color.white.opacity(0.8))
          .frame(height: 2)
          .padding(.horizontal, small ? 7 : 8)
          .padding(.top, small ? 7 : 8)
      }
      .overlay(alignment: .bottom) {
        Text(link.replacingOccurrences(of: "https://", with: ""))
          .font(.system(size: small ? 9 : 11))
          .foregroundStyle(Color(UIColor(rgb: 0x7DD3FC)))
          .lineLimit(1)
          .minimumScaleFactor(0.7)
          .environment(\.layoutDirection, .leftToRight)
          .padding(.top, 22)
          .padding(.bottom, small ? 9 : 12)
          .padding(.horizontal, small ? 8 : 12)
          .frame(maxWidth: .infinity)
          .background(
            LinearGradient(
              colors: [Color.black.opacity(0.85), Color.black.opacity(0)],
              startPoint: .bottom,
              endPoint: .top
            )
          )
      }
      .overlay {
        if loading {
          ProgressView().tint(.white)
        }
      }
      .overlay {
        if let sentLabel {
          ZStack {
            Color(UIColor(rgb: 0x0E0C08)).opacity(0.62)
            VStack(spacing: 8) {
              Image(systemName: "checkmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 34, height: 34)
                .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
              Text(sentLabel)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.white)
            }
          }
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: small ? 18 : 22, style: .continuous))
      .opacity(dimmed ? 0.4 : 1)
  }
}

/// La pastille d'une vidéo : ▶ et sa durée.
struct ReferralVideoTag: View {
  let seconds: Double?

  var body: some View {
    HStack(spacing: 4) {
      Image(systemName: "play.fill")
        .font(.system(size: 8))
      if let seconds {
        Text(referralVideoClock(seconds))
          .font(.caption2.weight(.medium))
      }
    }
    .foregroundStyle(Color.white)
    .padding(.horizontal, 7)
    .padding(.vertical, 4)
    .background(Color.black.opacity(0.55), in: Capsule())
    .environment(\.layoutDirection, .leftToRight)
  }
}

/// Le bouton PLEIN de la feuille, et sa **jauge** : elle annonce que le geste
/// suivant partira tout seul (`progress` de 0 à 1 ; `nil` = aucun passage
/// annoncé). ⭐ Plein, et pas un contour qui se remplit : en contour, une jauge
/// se lit « ce bouton n'est pas encore disponible » (retour Karim sur Fajrunaa,
/// 2026-10-07). Elle se remplit dans le sens de lecture.
/// ⚠️ Browther n'avait aucun écran à passage automatique : cette jauge est née
/// ici, sur le modèle d'`AutoAdvanceFill` (Fajrunaa). Mêmes cotes que
/// `ReferralPrimaryButton`.
struct ReferralGaugeButton: View {
  let label: String
  var systemImage: String?
  var busy = false
  var progress: CGFloat?
  let action: () -> Void

  @Environment(\.isEnabled) private var isEnabled

  var body: some View {
    Button(action: action) {
      HStack(spacing: 8) {
        if busy {
          ProgressView().tint(Color(UIColor.systemBackground))
        } else if let systemImage {
          Image(systemName: systemImage)
            .font(.system(size: 16, weight: .semibold))
        }
        Text(label)
          .font(.body.weight(.semibold))
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 8)
      .foregroundStyle(Color(UIColor.systemBackground))
      .frame(maxWidth: .infinity, minHeight: 52)
      .background {
        ZStack(alignment: .leading) {
          Color(UIColor.label)
          if let progress {
            GeometryReader { proxy in
              Color(UIColor.systemBackground)
                .opacity(0.25)
                .frame(width: proxy.size.width * progress)
            }
          }
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
    .buttonStyle(.plain)
    .opacity(isEnabled ? 1 : 0.5)
  }
}
