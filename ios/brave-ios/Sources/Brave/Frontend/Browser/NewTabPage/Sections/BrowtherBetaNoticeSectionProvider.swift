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
    // ⚠️ La forme à UN argument de `systemLayoutSizeFitting` traite la taille
    // passée comme un SOUHAIT sur les deux axes (priorité `fittingSizeLevel`),
    // pas comme une contrainte. La largeur n'est donc pas imposée, et la hauteur
    // renvoyée n'a rien à voir avec la mise en page réelle : sur device
    // (2026-08-28) la carte occupait tout l'écran, le `textStack` — épinglé haut
    // ET bas — étirant ses éléments pour combler l'excédent, d'où un grand vide
    // entre le texte et les liens.
    //
    // La forme à trois arguments impose la largeur (`.required`) et laisse la
    // hauteur se calculer (`.fittingSizeLevel`). C'est la seule correcte pour
    // une cellule auto-dimensionnée dont on connaît la largeur.
    sizingView.frame = CGRect(origin: .zero, size: CGSize(width: size.width, height: 0))
    sizingView.layoutIfNeeded()
    size.height = sizingView.systemLayoutSizeFitting(
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
    // Ceinture et bretelles avec la mise en page verticale ci-dessous : ce
    // libellé ne doit jamais être comprimé sous sa largeur naturelle par un
    // voisin. C'est cette compression qui l'avait rendu haut de sept lignes.
    $0.setContentCompressionResistancePriority(.required, for: .horizontal)
  }

  /// Bécher de laboratoire plutôt qu'un point d'exclamation : « en cours
  /// d'expérimentation », pas « attention, erreur ». Parité desktop, qui
  /// utilise l'icône Leo `beaker`. Repli en chaîne au cas où le symbole
  /// manquerait sur une version d'iOS : sans lui, la vue perdrait sa colonne
  /// d'icône et le texte se décalerait.
  private let iconView = UIImageView().then {
    $0.image =
      UIImage(systemName: "testtube.2")
      ?? UIImage(systemName: "flask")
      ?? UIImage(systemName: "sparkles")
    $0.tintColor = BrowtherBetaNoticeView.accent
    $0.contentMode = .scaleAspectFit
    $0.setContentHuggingPriority(.required, for: .horizontal)
  }

  private lazy var whatsAppButton = channelButton(
    title: Strings.Browther.betaNoticeWhatsApp,
    url: Self.whatsAppURL
  )
  private lazy var telegramButton = channelButton(
    title: Strings.Browther.betaNoticeTelegram,
    url: Self.telegramURL
  )

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

    // ⚠️ Le libellé est sur SA PROPRE LIGNE, les deux liens en dessous.
    //
    // La v1 (2026-08-16) mettait les trois dans un `UIStackView` HORIZONTAL, en
    // pariant que « les liens suivent le libellé sur la même ligne quand ça
    // tient, et passent dessous sinon ». Un stack horizontal ne sait pas passer
    // à la ligne : ce comportement-là n'existe pas. Ce qui s'est produit sur
    // device (constaté le 2026-08-28, iPhone 13) : les deux boutons ont gardé
    // leur largeur intrinsèque, le libellé a été écrasé à une colonne d'un mot,
    // il est devenu haut de sept lignes — et comme c'est LUI qui donne sa
    // hauteur à la carte, le bandeau occupait tout l'écran d'accueil.
    //
    // Un seul défaut, deux symptômes qui n'avaient pas l'air liés. La leçon
    // vaut au-delà d'ici : quand un commentaire décrit un repli au lieu de
    // l'implémenter (« passent dessous sinon »), c'est une intention, pas un
    // comportement. Ici la mise en page verticale tient dans toutes les
    // langues, y compris l'arabe et l'allemand qui allongent le libellé.
    let linksRow = UIStackView(arrangedSubviews: [whatsAppButton, telegramButton]).then {
      $0.axis = .horizontal
      $0.spacing = 16
      $0.alignment = .firstBaseline
    }

    let channelsStack = UIStackView(arrangedSubviews: [followLabel, linksRow]).then {
      $0.axis = .vertical
      $0.spacing = 6
      $0.alignment = .leading
    }

    let textStack = UIStackView(
      arrangedSubviews: [titleLabel, bodyLabel, channelsStack]
    ).then {
      $0.axis = .vertical
      $0.spacing = 4
      $0.setCustomSpacing(8, after: bodyLabel)
    }

    addSubview(iconView)
    addSubview(textStack)
    addSubview(closeButton)

    closeButton.addTarget(self, action: #selector(close), for: .touchUpInside)

    // L'icône s'aligne sur la première ligne du titre, pas sur le centre du
    // bandeau : sa hauteur varie avec le texte (traductions plus longues,
    // Dynamic Type), un centrage la ferait flotter au milieu du paragraphe.
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
