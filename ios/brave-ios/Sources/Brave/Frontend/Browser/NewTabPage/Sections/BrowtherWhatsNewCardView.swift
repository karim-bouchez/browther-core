// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BraveStrings
import BraveUI
import Foundation
import Shared
import SnapKit
import UIKit

/// Encart « Ce qui a changé » du Nouvel Onglet (`docs/SURFACES-COMMUNES.md`
/// §3.6). Il occupe l'emplacement du bandeau « accès anticipé » — même
/// matière, même ambre — et le remplace pour la version qui l'apporte (cf.
/// `BrowtherBetaNoticeSectionProvider`).
///
/// Ce qu'il montre, et rien d'autre : la date de diffusion en surtitre, le
/// titre, les lignes, « J'ai compris ». ⛔ Pas de numéro de version, pas d'intro
/// « corrigé grâce à vos retours » : c'est la ligne elle-même, qui dit d'abord
/// le problème vécu, qui permet à quelqu'un de reconnaître son signalement.
final class BrowtherWhatsNewCardView: UIView {
  /// Même ambre que le bandeau « accès anticipé » (`BrowtherBetaNoticeView`).
  static let accent = UIColor(red: 0.98, green: 0.75, blue: 0.14, alpha: 1)

  var closeHandler: (() -> Void)?
  var acknowledgeHandler: (() -> Void)?

  private let dateLabel = UILabel().then {
    $0.font = .systemFont(ofSize: 12, weight: .medium)
    $0.textColor = UIColor(white: 1, alpha: 0.6)
    $0.numberOfLines = 1
  }

  private let titleLabel = UILabel().then {
    $0.text = Strings.Browther.whatsNewTitle
    $0.font = .systemFont(ofSize: 15, weight: .semibold)
    $0.textColor = .white
    $0.numberOfLines = 0
  }

  private let linesStack = UIStackView().then {
    $0.axis = .vertical
    $0.spacing = 6
    $0.alignment = .fill
  }

  private let iconView = UIImageView().then {
    $0.image = UIImage(systemName: "sparkles")
    $0.tintColor = BrowtherWhatsNewCardView.accent
    $0.contentMode = .scaleAspectFit
    $0.setContentHuggingPriority(.required, for: .horizontal)
  }

  private let acknowledgeButton = UIButton(type: .system).then {
    $0.setTitle(Strings.Browther.whatsNewAcknowledge, for: .normal)
    $0.setTitleColor(BrowtherWhatsNewCardView.accent, for: .normal)
    $0.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
    $0.contentHorizontalAlignment = .leading
  }

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
    backgroundColor = UIColor(white: 0, alpha: 0.35)

    // Tout en VERTICAL, comme le bandeau d'accès anticipé : un stack
    // horizontal ne sait pas passer à la ligne (le défaut du 2026-08-28, où le
    // bandeau avait fini haut comme l'écran).
    let textStack = UIStackView(
      arrangedSubviews: [dateLabel, titleLabel, linesStack, acknowledgeButton]
    ).then {
      $0.axis = .vertical
      $0.spacing = 4
      $0.alignment = .fill
      $0.setCustomSpacing(8, after: titleLabel)
      $0.setCustomSpacing(10, after: linesStack)
    }

    addSubview(iconView)
    addSubview(textStack)
    addSubview(closeButton)

    closeButton.addTarget(self, action: #selector(close), for: .touchUpInside)
    acknowledgeButton.addTarget(self, action: #selector(acknowledge), for: .touchUpInside)

    iconView.snp.makeConstraints {
      $0.top.equalToSuperview().inset(15)
      $0.leading.equalToSuperview().inset(16)
      $0.width.height.equalTo(20)
    }

    textStack.snp.makeConstraints {
      $0.top.bottom.equalToSuperview().inset(14)
      $0.leading.equalTo(iconView.snp.trailing).offset(12)
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

  /// Rappelable à volonté (réutilisation de cellule, vue de mesure).
  func configure(with release: BrowtherSurfacesRules.WhatsNewRelease) {
    let localization = Bundle.main.preferredLocalizations.first ?? "en"

    let date = release.date.flatMap { BrowtherSurfacesRules.parseReleaseDate($0) }
    if let date {
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: localization)
      formatter.dateStyle = .long
      formatter.timeStyle = .none
      dateLabel.text = formatter.string(from: date)
      dateLabel.isHidden = false
    } else {
      dateLabel.text = nil
      dateLabel.isHidden = true
    }

    linesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
    for line in BrowtherSurfacesRules.lines(of: release, localization: localization) {
      linesStack.addArrangedSubview(
        UILabel().then {
          $0.text = "•  \(line)"
          $0.font = .systemFont(ofSize: 13)
          $0.textColor = UIColor(white: 1, alpha: 0.85)
          $0.numberOfLines = 0
        }
      )
    }
  }

  @objc private func close() {
    closeHandler?()
  }

  @objc private func acknowledge() {
    acknowledgeHandler?()
  }
}
