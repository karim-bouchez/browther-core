// Copyright 2020 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BraveStrings
import BraveUI
import Foundation
import Onboarding
import Preferences
import Shared
import SnapKit
import UIKit

class NTPDefaultBrowserCalloutProvider: NSObject, NTPObservableSectionProvider {
  var sectionDidChange: (() -> Void)?
  private var defaultCalloutView = DefaultBrowserCalloutView()
  private let isBackgroundNTPSI: Bool

  // Browther : pleine largeur, comme le bandeau « accès anticipé » juste au-dessus
  // (`BrowtherBetaNoticeSectionProvider`) — centrée à sa largeur naturelle, la
  // carte s'arrêtait en retrait des cartes voisines.
  private typealias DefaultBrowserCalloutCell = DefaultBrowserFullWidthCell<
    DefaultBrowserCalloutView
  >

  // MARK: Lifecycle
  init(isBackgroundNTPSI: Bool) {
    self.isBackgroundNTPSI = isBackgroundNTPSI
  }

  // MARK: UICollectionViewDelegate

  func collectionView(
    _ collectionView: UICollectionView,
    numberOfItemsInSection section: Int
  ) -> Int {
    shouldShowCallout() ? 1 : 0
  }

  func collectionView(
    _ collectionView: UICollectionView,
    cellForItemAt indexPath: IndexPath
  ) -> UICollectionViewCell {
    let cell = collectionView.dequeueReusableCell(for: indexPath) as DefaultBrowserCalloutCell
    cell.view.addTarget(self, action: #selector(openSettings), for: .touchUpInside)
    cell.view.closeHaandler = { [weak self] in
      Preferences.General.defaultBrowserCalloutDismissed.value = true
      self?.sectionDidChange?()

    }
    return cell
  }

  func collectionView(
    _ collectionView: UICollectionView,
    layout collectionViewLayout: UICollectionViewLayout,
    sizeForItemAt indexPath: IndexPath
  ) -> CGSize {

    var size = fittingSizeForCollectionView(collectionView, section: indexPath.section)
    // Browther : la largeur est IMPOSÉE, la hauteur se calcule — la forme à un
    // argument de `systemLayoutSizeFitting` prend la taille pour un souhait et
    // rend une hauteur sans rapport (piège déjà payé par le bandeau voisin).
    defaultCalloutView.frame = CGRect(origin: .zero, size: CGSize(width: size.width, height: 0))
    defaultCalloutView.layoutIfNeeded()
    size.height =
      defaultCalloutView.systemLayoutSizeFitting(
        CGSize(width: size.width, height: UIView.layoutFittingCompressedSize.height),
        withHorizontalFittingPriority: .required,
        verticalFittingPriority: .fittingSizeLevel
      ).height
    return size
  }

  func collectionView(
    _ collectionView: UICollectionView,
    layout collectionViewLayout: UICollectionViewLayout,
    insetForSectionAt section: Int
  ) -> UIEdgeInsets {
    if !shouldShowCallout() {
      return .zero
    }

    return UIEdgeInsets(top: 12, left: 16, bottom: 0, right: 16)
  }

  func registerCells(to collectionView: UICollectionView) {
    collectionView.register(DefaultBrowserCalloutCell.self)
  }

  func shouldShowCallout() -> Bool {
    // Never show Default Browser Notification over an NPT SI
    if isBackgroundNTPSI {
      return false
    }

    let defaultBrowserDisplayCriteria =
      !Preferences.General.defaultBrowserCalloutDismissed.value

    guard let appRetentionLaunchDate = Preferences.DAU.appRetentionLaunchDate.value else {
      return defaultBrowserDisplayCriteria
    }

    // User should not see default browser first 7 days
    // also after 14 days
    var defaultBrowserTimeConstraintCriteria = false

    let rightNow = Date()
    let first7DayPeriod = appRetentionLaunchDate.addingTimeInterval(7.days)
    let first14DayPeriod = appRetentionLaunchDate.addingTimeInterval(14.days)

    if rightNow > first7DayPeriod, rightNow < first14DayPeriod {
      defaultBrowserTimeConstraintCriteria = true
    }

    return defaultBrowserDisplayCriteria && defaultBrowserTimeConstraintCriteria
  }

  @objc func openSettings() {
    // ⛔ Plus la fiche de l'app : depuis iOS 18 le choix du navigateur par
    // défaut est dans « Apps par défaut » — et, comme les autres points
    // d'entrée, avec la vidéo en incrustation (`BrowtherDefaultBrowserSettings`).
    Preferences.General.defaultBrowserCalloutDismissed.value = true
    sectionDidChange?()
    let isDarkMode = defaultCalloutView.traitCollection.userInterfaceStyle == .dark
    Task { @MainActor in
      await BrowtherDefaultBrowserSettings.openWithGuide(isDarkMode: isDarkMode)
    }
  }
}

/// La vue occupe toute la cellule, dont `sizeForItemAt` fixe la largeur.
private final class DefaultBrowserFullWidthCell<View: UIView>: UICollectionViewCell,
  CollectionViewReusable
{
  let view = View()

  override init(frame: CGRect) {
    super.init(frame: frame)
    contentView.addSubview(view)
    view.snp.makeConstraints {
      $0.edges.equalToSuperview()
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError()
  }
}

/// Browther : l'encart redessiné (2026-09-27) — l'encart de Brave (texte
/// « …dans iOS. Appuyez ici pour ouvrir les paramètres. », fond vert
/// translucide, croix de travers) était resté brut ; Karim : « c'est moche ».
///
/// ⭐ **La même famille que le bandeau « accès anticipé »** posé juste au-dessus
/// (`BrowtherBetaNoticeView`) : voile sombre, liseré ambre, mêmes cotes, même
/// croix, une action en ambre. Pendant Android : `BrowtherDefaultBrowserNotice`.
/// ⭐ **Aucun texte neuf** : titre et phrase de l'étape « navigateur par défaut »
/// de l'introduction, action de l'écran de Focus (« Définir par défaut ») —
/// tous déjà traduits.
private class DefaultBrowserCalloutView: SpringButton {

  /// L'ambre du bandeau voisin — ⚠️ à garder identique.
  private static let accent = UIColor(red: 0.98, green: 0.75, blue: 0.14, alpha: 1)

  var closeHaandler: (() -> Void)?

  private let iconView = UIImageView().then {
    $0.image =
      UIImage(systemName: "checkmark.shield.fill")
      ?? UIImage(systemName: "shield.fill")
    $0.tintColor = DefaultBrowserCalloutView.accent
    $0.contentMode = .scaleAspectFit
    $0.setContentHuggingPriority(.required, for: .horizontal)
  }

  private let titleLabel = UILabel().then {
    $0.text = Strings.BrowtherIntro.defaultTitle
    $0.font = .systemFont(ofSize: 15, weight: .semibold)
    $0.textColor = .white
    $0.numberOfLines = 0
  }

  private let bodyLabel = UILabel().then {
    $0.text = Strings.BrowtherIntro.defaultSubtitle
    $0.font = .systemFont(ofSize: 13)
    $0.textColor = UIColor(white: 1, alpha: 0.75)
    $0.numberOfLines = 0
  }

  /// L'action se voit (en ambre) ; toute la carte reste touchable, comme chez Brave.
  private let actionLabel = UILabel().then {
    $0.text = Strings.FocusOnboarding.systemSettingsButtonTitle
    $0.font = .systemFont(ofSize: 13, weight: .semibold)
    $0.textColor = DefaultBrowserCalloutView.accent
    $0.numberOfLines = 0
  }

  private let closeButton = UIButton().then {
    $0.setImage(
      UIImage(named: "close_tab_bar", in: .module, compatibleWith: nil)?.template,
      for: .normal
    )
    $0.tintColor = UIColor(white: 1, alpha: 0.6)
    $0.contentEdgeInsets = UIEdgeInsets(equalInset: 6)
    $0.accessibilityLabel = Strings.defaultBrowserCalloutCloseAccesabilityLabel
  }

  override init(frame: CGRect) {
    super.init(frame: frame)

    clipsToBounds = true
    layer.cornerRadius = 12
    layer.cornerCurve = .continuous
    layer.borderWidth = 1
    layer.borderColor = Self.accent.withAlphaComponent(0.32).cgColor
    backgroundColor = UIColor(white: 0, alpha: 0.35)

    let textStack = UIStackView(arrangedSubviews: [titleLabel, bodyLabel, actionLabel]).then {
      $0.axis = .vertical
      $0.spacing = 4
      $0.setCustomSpacing(8, after: bodyLabel)
      $0.isUserInteractionEnabled = false
    }
    iconView.isUserInteractionEnabled = false

    addSubview(iconView)
    addSubview(textStack)
    addSubview(closeButton)

    closeButton.addTarget(self, action: #selector(closeTab), for: .touchUpInside)

    // Les cotes du bandeau voisin, à l'identique.
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

  @objc func closeTab() {
    closeHaandler?()
  }

}
