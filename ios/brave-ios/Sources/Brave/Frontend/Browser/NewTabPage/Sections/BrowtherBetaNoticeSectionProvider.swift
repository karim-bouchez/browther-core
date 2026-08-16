// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BraveStrings
import BraveUI
import Foundation
import Preferences
import Shared
import SnapKit
import UIKit

/// Bandeau « accès anticipé » en tête du Nouvel Onglet — parité desktop
/// `browther_beta_notice.tsx`.
///
/// Pourquoi dans l'app et pas sur le site : la quasi-totalité des installs iOS
/// arrivent par la recherche App Store et ne voient jamais browther.devndin.com.
/// Un utilisateur qui rencontre un bug sans savoir qu'il est sur une version en
/// cours de finition conclut que le produit est mauvais — il désinstalle, ou
/// pire, garde l'app sans jamais la rouvrir. Le contexte transforme la
/// déception en patience, et les deux liens transforment le silence en retour.
///
/// À retirer quand Browther sort de l'accès anticipé (ce fichier, son insertion
/// dans `NewTabPageViewController`, les 4 strings et la pref).
class BrowtherBetaNoticeSectionProvider: NSObject, NTPObservableSectionProvider {
  var sectionDidChange: (() -> Void)?

  /// Ouvre une URL de canal (WhatsApp / Telegram) dans un nouvel onglet.
  var onChannelTapped: ((URL) -> Void)?

  private let sizingView = BrowtherBetaNoticeView()

  private typealias BetaNoticeCell = NewTabCenteredCollectionViewCell<BrowtherBetaNoticeView>

  /// Version applicative en cours, qui sert de clé au « déjà vu ».
  private static var currentVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
  }

  /// Fermé « pour cette version » seulement : une mise à jour le fait revenir
  /// une fois. Si la version est illisible on montre le bandeau — se taire par
  /// défaut serait le pire des deux comportements.
  func shouldShowNotice() -> Bool {
    let version = Self.currentVersion
    if version.isEmpty {
      return true
    }
    return Preferences.General.browtherBetaNoticeDismissedVersion.value != version
  }

  // MARK: - NTPSectionProvider

  func registerCells(to collectionView: UICollectionView) {
    collectionView.register(BetaNoticeCell.self)
  }

  func collectionView(
    _ collectionView: UICollectionView,
    numberOfItemsInSection section: Int
  ) -> Int {
    shouldShowNotice() ? 1 : 0
  }

  func collectionView(
    _ collectionView: UICollectionView,
    cellForItemAt indexPath: IndexPath
  ) -> UICollectionViewCell {
    let cell = collectionView.dequeueReusableCell(for: indexPath) as BetaNoticeCell
    cell.view.closeHandler = { [weak self] in
      Preferences.General.browtherBetaNoticeDismissedVersion.value = Self.currentVersion
      self?.sectionDidChange?()
    }
    cell.view.channelHandler = { [weak self] url in
      self?.onChannelTapped?(url)
    }
    return cell
  }

  func collectionView(
    _ collectionView: UICollectionView,
    layout collectionViewLayout: UICollectionViewLayout,
    sizeForItemAt indexPath: IndexPath
  ) -> CGSize {
    var size = fittingSizeForCollectionView(collectionView, section: indexPath.section)
    size.height = sizingView.systemLayoutSizeFitting(size).height
    return size
  }

  func collectionView(
    _ collectionView: UICollectionView,
    layout collectionViewLayout: UICollectionViewLayout,
    insetForSectionAt section: Int
  ) -> UIEdgeInsets {
    if !shouldShowNotice() {
      return .zero
    }
    return UIEdgeInsets(top: 12, left: 16, bottom: 0, right: 16)
  }
}

// MARK: - BrowtherBetaNoticeView

private class BrowtherBetaNoticeView: UIView {
  /// Mêmes URL que l'étape d'onboarding « suivre les canaux dev&din »
  /// (`components/brave_welcome_ui/components/follow-channels/qr_codes.ts`).
  /// Doivent rester en phase avec elle.
  private static let whatsAppURL = URL(string: "https://whatsapp.com/channel/0029Vb8ydkv5vKABH78PVX32")
  private static let telegramURL = URL(string: "https://t.me/devndin_nouveautes")

  /// Ambre du badge « Beta » du site et du bandeau desktop — une seule couleur,
  /// qui signale sans dramatiser : ce n'est pas une erreur.
  private static let accent = UIColor(red: 0.98, green: 0.75, blue: 0.14, alpha: 1)

  var closeHandler: (() -> Void)?
  var channelHandler: ((URL) -> Void)?

  private let titleLabel = UILabel().then {
    $0.text = Strings.Browther.betaNoticeTitle
    $0.font = .systemFont(ofSize: 15, weight: .semibold)
    $0.textColor = .white
    $0.numberOfLines = 0
  }

  private let bodyLabel = UILabel().then {
    $0.text = Strings.Browther.betaNoticeText
    $0.font = .systemFont(ofSize: 13)
    $0.textColor = UIColor(white: 1, alpha: 0.75)
    $0.numberOfLines = 0
  }

  private let followLabel = UILabel().then {
    $0.text = Strings.Browther.betaNoticeFollow
    $0.font = .systemFont(ofSize: 13)
    $0.textColor = UIColor(white: 1, alpha: 0.75)
    $0.numberOfLines = 0
  }

  private lazy var whatsAppButton = channelButton(title: "WhatsApp", url: Self.whatsAppURL)
  private lazy var telegramButton = channelButton(title: "Telegram", url: Self.telegramURL)

  private let closeButton = UIButton().then {
    $0.setImage(
      UIImage(named: "close_tab_bar", in: .module, compatibleWith: nil)?.template,
      for: .normal
    )
    $0.tintColor = UIColor(white: 1, alpha: 0.6)
    $0.contentEdgeInsets = UIEdgeInsets(equalInset: 6)
    $0.accessibilityLabel = Strings.Browther.betaNoticeDismiss
  }

  override init(frame: CGRect) {
    super.init(frame: frame)

    clipsToBounds = true
    layer.cornerRadius = 12
    layer.cornerCurve = .continuous
    layer.borderWidth = 1
    layer.borderColor = Self.accent.withAlphaComponent(0.32).cgColor
    // Le NTP porte une photo de fond : un voile sombre garde le texte lisible
    // sans masquer l'image, comme le `material.thin` + blur du desktop.
    backgroundColor = UIColor(white: 0, alpha: 0.35)

    // Les deux liens suivent le libellé sur la même ligne quand ça tient, et
    // passent dessous sinon (l'arabe et l'allemand allongent le libellé).
    let channelsStack = UIStackView(
      arrangedSubviews: [followLabel, whatsAppButton, telegramButton]
    ).then {
      $0.axis = .horizontal
      $0.spacing = 10
      $0.alignment = .firstBaseline
    }

    let textStack = UIStackView(
      arrangedSubviews: [titleLabel, bodyLabel, channelsStack]
    ).then {
      $0.axis = .vertical
      $0.spacing = 4
      $0.setCustomSpacing(8, after: bodyLabel)
    }

    addSubview(textStack)
    addSubview(closeButton)

    closeButton.addTarget(self, action: #selector(close), for: .touchUpInside)

    textStack.snp.makeConstraints {
      $0.top.bottom.equalToSuperview().inset(14)
      $0.leading.equalToSuperview().inset(16)
      $0.trailing.equalTo(closeButton.snp.leading).offset(-8)
    }

    closeButton.snp.makeConstraints {
      $0.top.equalToSuperview().inset(8)
      $0.trailing.equalToSuperview().inset(8)
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError()
  }

  private func channelButton(title: String, url: URL?) -> UIButton {
    let button = UIButton(type: .system)
    button.setTitle(title, for: .normal)
    button.setTitleColor(Self.accent, for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
    button.setContentHuggingPriority(.required, for: .horizontal)
    button.setContentCompressionResistancePriority(.required, for: .horizontal)
    button.addAction(
      UIAction { [weak self] _ in
        guard let url else { return }
        self?.channelHandler?(url)
      },
      for: .touchUpInside
    )
    return button
  }

  @objc private func close() {
    closeHandler?()
  }
}
