// Copyright 2020 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BraveCore
import BraveUI
import DesignSystem
import Preferences
import Shared
import SnapKit
import UIKit

/// The background view of new tab page which will hold static elements such as
/// the image credit, brand logos or the share by QR code button
///
/// Currently this view displays a single active button and a play button if
/// the video background is shown
class NewTabPageBackgroundButtonsView: UIView, PreferencesObserver {
  /// The button kind to display
  enum ActiveButton {
    /// Displays the image credit button showing credit to some `name`
    case imageCredit(_ name: String)
  }
  /// A block executed when a user taps one of the active buttons.
  var tappedActiveButton: ((UIControl) -> Void)?
  /// The current active button.
  ///
  /// Setting this to `nil` hides all button types
  var activeButton: ActiveButton? {
    didSet {
      guard let activeButton = activeButton else {
        imageCreditButton.isHidden = true
        return
      }
      switch activeButton {
      case .imageCredit(let name):
        imageCreditButton.label.text = String(format: Strings.photoBy, name)
        imageCreditButton.isHidden = false
      }
    }
  }

  private let imageCreditButton = ImageCreditButton().then {
    $0.isHidden = true
  }

  /// The parent safe area insets (since UICollectionView doesn't feed down
  /// proper `safeAreaInsets` when the `contentInsetAdjustmentBehavior` is set
  /// to `always`)
  var collectionViewSafeAreaInsets: UIEdgeInsets = .zero {
    didSet {
      safeAreaInsetsConstraint?.update(inset: collectionViewSafeAreaInsets)
    }
  }
  private var safeAreaInsetsConstraint: Constraint?
  private let collectionViewSafeAreaLayoutGuide = UILayoutGuide()
  private let privateBrowsingManager: PrivateBrowsingManager
  private let profilePrefs: any PrefService

  init(privateBrowsingManager: PrivateBrowsingManager, profilePrefs: any PrefService) {
    self.privateBrowsingManager = privateBrowsingManager
    self.profilePrefs = profilePrefs

    super.init(frame: .zero)

    backgroundColor = .clear
    addLayoutGuide(collectionViewSafeAreaLayoutGuide)
    collectionViewSafeAreaLayoutGuide.snp.makeConstraints {
      self.safeAreaInsetsConstraint = $0.edges.equalTo(self).constraint
    }

    addSubview(imageCreditButton)
    imageCreditButton.addTarget(self, action: #selector(tappedButton(_:)), for: .touchUpInside)
  }

  @available(*, unavailable)
  required init(coder: NSCoder) {
    fatalError()
  }

  override func layoutSubviews() {
    super.layoutSubviews()

    imageCreditButton.snp.remakeConstraints {
      $0.leading.equalTo(collectionViewSafeAreaLayoutGuide).inset(16)
      $0.bottom.equalTo(collectionViewSafeAreaLayoutGuide).inset(16)
    }
  }

  @objc private func tappedButton(_ sender: UIControl) {
    tappedActiveButton?(sender)
  }

  func preferencesDidChange(for key: String) {
    setNeedsLayout()
  }
}

extension NewTabPageBackgroundButtonsView {
  private class ImageCreditButton: SpringButton {
    private let backgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .light)).then {
      $0.clipsToBounds = true
      $0.isUserInteractionEnabled = false
      $0.layer.cornerRadius = 4
      $0.layer.cornerCurve = .continuous
    }

    let label = UILabel().then {
      $0.textColor = .white
      $0.font = UIFont.systemFont(ofSize: 12.0, weight: .medium)
    }

    override init(frame: CGRect) {
      super.init(frame: frame)

      addSubview(backgroundView)
      backgroundView.contentView.addSubview(label)

      backgroundView.snp.makeConstraints {
        $0.edges.equalToSuperview()
      }
      label.snp.makeConstraints {
        $0.edges.equalToSuperview().inset(UIEdgeInsets(top: 5, left: 10, bottom: 5, right: 10))
      }
    }
  }
}
