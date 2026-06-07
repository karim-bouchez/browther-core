// Copyright 2020 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BraveShields
import BraveStrings
import BraveUI
import BrowtherAnalytics
import Foundation
import Preferences
import Shared
import UIKit

class StatsSectionProvider: NSObject, NTPSectionProvider {
  private let isPrivateBrowsing: Bool
  var openPrivacyHubPressed: () -> Void
  var hidePrivacyHubPressed: () -> Void

  init(
    isPrivateBrowsing: Bool,
    openPrivacyHubPressed: @escaping () -> Void,
    hidePrivacyHubPressed: @escaping () -> Void
  ) {
    self.isPrivateBrowsing = isPrivateBrowsing
    self.openPrivacyHubPressed = openPrivacyHubPressed
    self.hidePrivacyHubPressed = hidePrivacyHubPressed
  }

  @objc private func tappedButton(_ gestureRecognizer: UIGestureRecognizer) {
    guard let cell = gestureRecognizer.view as? BraveShieldStatsView else {
      return
    }

    cell.isHighlighted = true

    Task.delayed(bySeconds: 0.1) { @MainActor in
      cell.isHighlighted = false
      self.openPrivacyHubPressed()
    }
  }

  func collectionView(
    _ collectionView: UICollectionView,
    numberOfItemsInSection section: Int
  ) -> Int {
    // Browther : widget stats toujours visible (pas de toggle "hide stats").
    return 1
  }

  func registerCells(to collectionView: UICollectionView) {
    collectionView.register(NewTabCenteredCollectionViewCell<BraveShieldStatsView>.self)
  }

  func collectionView(
    _ collectionView: UICollectionView,
    cellForItemAt indexPath: IndexPath
  ) -> UICollectionViewCell {
    let cell =
      collectionView.dequeueReusableCell(for: indexPath)
      as NewTabCenteredCollectionViewCell<BraveShieldStatsView>

    let tap = UITapGestureRecognizer(target: self, action: #selector(tappedButton(_:)))
    let longPress = UILongPressGestureRecognizer(target: self, action: #selector(tappedButton(_:)))

    cell.view.do {
      $0.isPrivateBrowsing = self.isPrivateBrowsing
      $0.addGestureRecognizer(tap)
      $0.addGestureRecognizer(longPress)

      $0.openPrivacyHubPressed = { [weak self] in
        self?.openPrivacyHubPressed()
      }

      $0.hidePrivacyHubPressed = { [weak self] in
        self?.hidePrivacyHubPressed()
      }
    }

    return cell
  }

  func collectionView(
    _ collectionView: UICollectionView,
    layout collectionViewLayout: UICollectionViewLayout,
    sizeForItemAt indexPath: IndexPath
  ) -> CGSize {
    var size = fittingSizeForCollectionView(collectionView, section: indexPath.section)
    size.height = 110
    return size
  }

  func collectionView(
    _ collectionView: UICollectionView,
    layout collectionViewLayout: UICollectionViewLayout,
    insetForSectionAt section: Int
  ) -> UIEdgeInsets {

    return UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
  }
}

class BraveShieldStatsView: SpringButton {
  var openPrivacyHubPressed: (() -> Void)?
  var hidePrivacyHubPressed: (() -> Void)?

  // Browther : ordre musique → personnes → trackers. Couleurs conservées
  // (statsDataSavedTint = ~vert/turquoise, statsTimeSavedTint = clair,
  // statsAdsBlockedTint = orange) pour parité visuelle avec Desktop NTP.
  private lazy var musicStatView: StatView = {
    let statView = StatView(frame: .zero)
    statView.title = Strings.Shields.musicRemovedStat
    statView.color = .statsDataSavedTint
    return statView
  }()

  private lazy var personsBlurredStatView: StatView = {
    let statView = StatView(frame: .zero)
    statView.title = Strings.Shields.peopleBlurredStat
    statView.color = .statsTimeSavedTint
    return statView
  }()

  private lazy var adsBlockedStatView: StatView = {
    let statView = StatView(frame: CGRect.zero)
    statView.title = Strings.Shields.shieldsAdAndTrackerStats.capitalized
    statView.color = .statsAdsBlockedTint
    return statView
  }()

  private let statsStackView = UIStackView().then {
    $0.distribution = .fillEqually
    $0.spacing = 8
  }

  private let topStackView = UIStackView().then {
    $0.distribution = .equalSpacing
    $0.alignment = .center
    $0.isLayoutMarginsRelativeArrangement = true
    $0.directionalLayoutMargins = .init(.init(top: 8, leading: 0, bottom: -4, trailing: 0))
  }

  private let contentStackView = UIStackView().then {
    $0.axis = .vertical
    $0.spacing = 8
    $0.isLayoutMarginsRelativeArrangement = true
    $0.directionalLayoutMargins = .init(.init(top: 0, leading: 16, bottom: 16, trailing: 16))
  }

  private let privacyReportLabel = UILabel().then {
    let image = UIImage(named: "privacy_reports_shield", in: .module, compatibleWith: nil)!.template
    $0.textColor = .white
    $0.textAlignment = .center

    $0.attributedText = {
      let imageAttachment = NSTextAttachment().then {
        $0.image = image
        if let image = $0.image {
          $0.bounds = .init(x: 0, y: -3, width: image.size.width, height: image.size.height)
        }
      }

      var string = NSMutableAttributedString(attachment: imageAttachment)

      let padding = NSTextAttachment()
      padding.bounds = CGRect(width: 6, height: 0)

      string.append(NSAttributedString(attachment: padding))

      string.append(
        NSMutableAttributedString(
          string: Strings.PrivacyHub.privacyReportsTitle,
          attributes: [.font: UIFont.systemFont(ofSize: 14.0, weight: .medium)]
        )
      )
      return string
    }()
  }

  private let backgroundView = UIView()

  override init(frame: CGRect) {
    super.init(frame: .zero)

    statsStackView.addStackViewItems(
      .view(musicStatView),
      .view(personsBlurredStatView),
      .view(adsBlockedStatView)
    )
    contentStackView.addStackViewItems(.view(topStackView), .view(statsStackView))
    addSubview(contentStackView)

    update()

    contentStackView.snp.makeConstraints {
      $0.edges.equalToSuperview()
      $0.width.equalTo(640)
    }

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(update),
      name: NSNotification.Name(rawValue: BraveGlobalShieldStats.didUpdateNotification),
      object: nil
    )
  }

  required init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  var isPrivateBrowsing: Bool = false {
    didSet {
      if backgroundView.superview != nil {
        return
      }

      // Browther : on retire le check `showNewTabPrivacyHub.value` (widget
      // toujours visible) et le menu 3-dot "Hide Privacy Hub" / "Open Privacy
      // Hub" — parité avec le widget Desktop refresh.
      if !isPrivateBrowsing {
        backgroundView.backgroundColor = .init(white: 0, alpha: 0.25)
        backgroundView.layer.cornerRadius = 12
        backgroundView.layer.cornerCurve = .continuous
        backgroundView.isUserInteractionEnabled = false
        insertSubview(backgroundView, at: 0)
        backgroundView.snp.makeConstraints {
          $0.edges.equalToSuperview()
        }

        topStackView.addStackViewItems(.view(privacyReportLabel))
      }
    }
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  @objc private func update() {
    musicStatView.stat = Self.formatSeconds(BrowtherStatsReporter.shared.musicSecondsTotal)
    personsBlurredStatView.stat = BrowtherStatsReporter.shared.personsBlurredTotal.kFormattedNumber
    adsBlockedStatView.stat =
      (BraveGlobalShieldStats.shared.adblock + BraveGlobalShieldStats.shared.trackingProtection)
      .kFormattedNumber
  }

  /// Formate des secondes cumulées (s/min/h/j) en alignement avec le widget
  /// Desktop `formatTimeFromSeconds`. Pas d'arrondi fancy, un chiffre + unit.
  private static func formatSeconds(_ seconds: Int) -> String {
    if seconds < 60 {
      return "\(seconds)\(Strings.Shields.shieldsTimeStatsSeconds)"
    }
    if seconds < 3600 {
      return "\(seconds / 60)\(Strings.Shields.shieldsTimeStatsMinutes)"
    }
    if seconds < 86400 {
      let hours = Double(seconds) / 3600.0
      return String(format: "%.1f%@", hours, Strings.Shields.shieldsTimeStatsHour)
    }
    let days = Double(seconds) / 86400.0
    return String(format: "%.1f%@", days, Strings.Shields.shieldsTimeStatsDays)
  }
}

private class StatView: UIView {
  var color: UIColor = .braveLabel {
    didSet {
      statLabel.textColor = color
    }
  }

  var stat: String = "" {
    didSet {
      statLabel.text = "\(stat)"
    }
  }

  var title: String = "" {
    didSet {
      titleLabel.text = "\(title)"
    }
  }

  fileprivate var statLabel: UILabel = {
    let label = UILabel()
    label.textAlignment = .center
    label.font = .systemFont(ofSize: 32, weight: UIFont.Weight.medium)
    label.minimumScaleFactor = 0.5
    label.adjustsFontSizeToFitWidth = true
    return label
  }()

  fileprivate var titleLabel: UILabel = {
    let label = UILabel()
    label.textColor = .white
    label.textAlignment = .center
    label.numberOfLines = 0
    label.font = UIFont.systemFont(ofSize: 10, weight: UIFont.Weight.medium)
    return label
  }()

  override init(frame: CGRect) {
    super.init(frame: frame)

    let stackView = UIStackView()
    stackView.axis = .vertical
    stackView.alignment = .center

    stackView.addStackViewItems(.view(statLabel), .view(titleLabel))

    addSubview(stackView)

    stackView.snp.makeConstraints {
      $0.edges.equalToSuperview()
    }
  }

  required init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}
