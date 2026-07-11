// Copyright 2026 dev&din. All rights reserved.
// Browther — NTP ad banner section (régie devndin-ads)

import BraveShields
import BraveStrings
import BraveUI
import BrowtherAnalytics
import Foundation
import SnapKit
import UIKit

/// Bannière pub devndin-ads sous les favoris du NTP. Carousel paginé,
/// aspect-ratio piloté par le champ `ratio` du serve, label « Pub » par slide
/// si `showAdLabel` (annonceur externe) — parité desktop
/// `browther_ad_banner.tsx` + `ads/docs/INTEGRATION.md` § 3.
///
/// Le serve (mode public X-Publisher-Id, re-serve throttlé ~10 min), le
/// batching des impressions et la résolution du click URL vivent dans
/// `BrowtherAdsClient` (module BrowtherAnalytics). Seuls `id`, `imageURL`,
/// `ratio` et `showAdLabel` traversent jusqu'ici (parité mojom `BrowtherAd`).
class BrowtheAdSectionProvider: NSObject, NTPSectionProvider {
  private static let placement = "browther-ntp-banner"

  private var ads: [BrowtherServedAd] = []

  var onAdTapped: ((_ url: URL) -> Void)?
  /// Appelé quand des pubs sont récupérées et que la section doit se recharger.
  var onAdLoaded: (() -> Void)?

  override init() {
    super.init()
    fetchAds()
  }

  // MARK: - API

  private func fetchAds() {
    BrowtherAdsClient.shared.serve(placement: Self.placement, count: 3) { [weak self] ads in
      guard let self, !ads.isEmpty else { return }
      self.ads = ads
      self.onAdLoaded?()
    }
  }

  // MARK: - NTPSectionProvider

  func registerCells(to collectionView: UICollectionView) {
    collectionView.register(BrowtheAdCarouselCell.self)
  }

  func collectionView(
    _ collectionView: UICollectionView,
    numberOfItemsInSection section: Int
  ) -> Int {
    ads.isEmpty ? 0 : 1
  }

  func collectionView(
    _ collectionView: UICollectionView,
    cellForItemAt indexPath: IndexPath
  ) -> UICollectionViewCell {
    let cell = collectionView.dequeueReusableCell(for: indexPath) as BrowtheAdCarouselCell
    cell.configure(
      ads: ads,
      onVisible: { id in
        // Impression à visibilité réelle (≥ page centrée), une fois par pub
        // servie — batching + idempotence gérés côté client.
        BrowtherAdsClient.shared.markVisible(id: id)
      },
      onTap: { [weak self] id in
        guard let url = BrowtherAdsClient.shared.clickURL(id: id) else { return }
        self?.onAdTapped?(url)
      }
    )
    return cell
  }

  func collectionView(
    _ collectionView: UICollectionView,
    layout collectionViewLayout: UICollectionViewLayout,
    sizeForItemAt indexPath: IndexPath
  ) -> CGSize {
    let width = fittingSizeForCollectionView(collectionView, section: indexPath.section).width
    // Aspect-ratio piloté par le champ `ratio` du serve (pas de valeur en
    // dur, cf. ads/docs/INTEGRATION.md § 3) ; le placement a un format
    // unique, toutes les pubs du lot partagent le même ratio.
    let height = width / Self.aspect(of: ads.first)
    return CGSize(width: width, height: height)
  }

  func collectionView(
    _ collectionView: UICollectionView,
    layout collectionViewLayout: UICollectionViewLayout,
    insetForSectionAt section: Int
  ) -> UIEdgeInsets {
    UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
  }

  /// "3.2:1" → 3.2 ; fallback si champ absent/illisible (vieux cache serveur).
  private static func aspect(of ad: BrowtherServedAd?) -> CGFloat {
    let parts = (ad?.ratio ?? "").split(separator: ":")
    guard parts.count == 2,
      let w = Double(parts[0]), let h = Double(parts[1]),
      w > 0, h > 0
    else {
      return 3.2
    }
    return CGFloat(w / h)
  }
}

// MARK: - BrowtheAdCarouselCell

/// Cellule NTP unique hébergeant le carousel paginé des pubs servies (une pub
/// pleine largeur par page, snap centré — parité `scroll-snap` desktop).
private class BrowtheAdCarouselCell: UICollectionViewCell, CollectionViewReusable {
  private var ads: [BrowtherServedAd] = []
  private var onVisible: ((String) -> Void)?
  private var onTap: ((String) -> Void)?

  // Ids déjà signalés visibles dans cette instance (le client dédup aussi).
  private var markedVisible = Set<String>()
  private var didMarkInitial = false
  private var lastLaidOutSize: CGSize = .zero

  private let layout = UICollectionViewFlowLayout().then {
    $0.scrollDirection = .horizontal
    $0.minimumLineSpacing = 0
    $0.minimumInteritemSpacing = 0
    $0.sectionInset = .zero
  }

  private lazy var carousel = UICollectionView(
    frame: .zero,
    collectionViewLayout: layout
  ).then {
    $0.isPagingEnabled = true
    $0.showsHorizontalScrollIndicator = false
    $0.backgroundColor = .clear
    $0.dataSource = self
    $0.delegate = self
    $0.contentInsetAdjustmentBehavior = .never
    $0.register(BrowtheAdImageCell.self)
  }

  private let pageControl = UIPageControl().then {
    $0.hidesForSinglePage = true
    $0.isUserInteractionEnabled = false
    $0.currentPageIndicatorTintColor = .white
    $0.pageIndicatorTintColor = UIColor(white: 1, alpha: 0.4)
  }

  override init(frame: CGRect) {
    super.init(frame: frame)

    contentView.addSubview(carousel)
    contentView.addSubview(pageControl)

    carousel.snp.makeConstraints {
      $0.edges.equalToSuperview()
    }
    pageControl.snp.makeConstraints {
      $0.centerX.equalToSuperview()
      $0.bottom.equalToSuperview().inset(6)
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError()
  }

  func configure(
    ads: [BrowtherServedAd],
    onVisible: @escaping (String) -> Void,
    onTap: @escaping (String) -> Void
  ) {
    self.ads = ads
    self.onVisible = onVisible
    self.onTap = onTap
    pageControl.numberOfPages = ads.count
    pageControl.currentPage = 0
    didMarkInitial = false
    carousel.reloadData()
    carousel.setContentOffset(.zero, animated: false)
    setNeedsLayout()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    if carousel.bounds.size != lastLaidOutSize {
      lastLaidOutSize = carousel.bounds.size
      layout.invalidateLayout()
    }
    // Marque la 1ère pub visible une fois le layout valide (parité
    // IntersectionObserver : on ne compte que des pages réellement affichées).
    if !didMarkInitial, carousel.bounds.width > 0, !ads.isEmpty {
      didMarkInitial = true
      markVisiblePage()
    }
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    ads = []
    onVisible = nil
    onTap = nil
    markedVisible.removeAll()
    didMarkInitial = false
  }

  // MARK: - Helpers

  private func currentPage() -> Int {
    guard carousel.bounds.width > 0 else { return 0 }
    let page = Int((carousel.contentOffset.x + carousel.bounds.width / 2) / carousel.bounds.width)
    return min(max(page, 0), max(ads.count - 1, 0))
  }

  private func markVisiblePage() {
    let page = currentPage()
    guard ads.indices.contains(page) else { return }
    let id = ads[page].id
    guard !markedVisible.contains(id) else { return }
    markedVisible.insert(id)
    onVisible?(id)
  }
}

// MARK: - Carousel data source / delegate

extension BrowtheAdCarouselCell: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
  func collectionView(
    _ collectionView: UICollectionView,
    numberOfItemsInSection section: Int
  ) -> Int {
    ads.count
  }

  func collectionView(
    _ collectionView: UICollectionView,
    cellForItemAt indexPath: IndexPath
  ) -> UICollectionViewCell {
    let cell = collectionView.dequeueReusableCell(for: indexPath) as BrowtheAdImageCell
    if ads.indices.contains(indexPath.item) {
      let ad = ads[indexPath.item]
      cell.configure(imageURL: ad.imageURL, showAdLabel: ad.showAdLabel)
    }
    return cell
  }

  func collectionView(
    _ collectionView: UICollectionView,
    layout collectionViewLayout: UICollectionViewLayout,
    sizeForItemAt indexPath: IndexPath
  ) -> CGSize {
    // Une pub par page, pleine largeur du carousel.
    collectionView.bounds.size
  }

  func collectionView(
    _ collectionView: UICollectionView,
    didSelectItemAt indexPath: IndexPath
  ) {
    guard ads.indices.contains(indexPath.item) else { return }
    onTap?(ads[indexPath.item].id)
  }

  func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
    pageControl.currentPage = currentPage()
    markVisiblePage()
  }

  func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
    pageControl.currentPage = currentPage()
    markVisiblePage()
  }
}

// MARK: - BrowtheAdImageCell

private class BrowtheAdImageCell: UICollectionViewCell, CollectionViewReusable {
  private let imageView = UIImageView().then {
    $0.contentMode = .scaleAspectFill
    $0.clipsToBounds = true
    $0.layer.cornerRadius = 16
    $0.layer.cornerCurve = .continuous
    $0.backgroundColor = UIColor(white: 0.2, alpha: 0.8)
  }

  /// UILabel avec padding horizontal (chip).
  private class PaddedLabel: UILabel {
    override var intrinsicContentSize: CGSize {
      let size = super.intrinsicContentSize
      return CGSize(width: size.width + 14, height: size.height + 4)
    }
  }

  /// Label « Pub » (annonceur externe, `showAdLabel`) : chip semi-transparente
  /// coin supérieur, posée DANS la slide — elle glisse avec sa créa
  /// (INTEGRATION.md § 3, exécution mobile de référence).
  private let adLabel: UILabel = PaddedLabel().then {
    $0.text = Strings.Shields.browtherAdLabel
    $0.font = .systemFont(ofSize: 11, weight: .semibold)
    $0.textColor = .white
    $0.backgroundColor = UIColor(white: 0, alpha: 0.6)
    $0.textAlignment = .center
    $0.layer.cornerRadius = 6
    $0.layer.cornerCurve = .continuous
    $0.clipsToBounds = true
    $0.isHidden = true
  }

  private var imageTask: URLSessionDataTask?
  private var currentURL: String?

  override init(frame: CGRect) {
    super.init(frame: frame)
    contentView.addSubview(imageView)
    contentView.addSubview(adLabel)
    imageView.snp.makeConstraints {
      $0.edges.equalToSuperview()
    }
    adLabel.snp.makeConstraints {
      $0.top.leading.equalToSuperview().inset(10)
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError()
  }

  func configure(imageURL: String, showAdLabel: Bool) {
    currentURL = imageURL
    imageView.image = nil
    imageView.alpha = 0
    adLabel.isHidden = !showAdLabel

    guard let url = URL(string: imageURL) else { return }

    imageTask?.cancel()
    imageTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
      guard let data, let image = UIImage(data: data) else { return }
      DispatchQueue.main.async {
        guard let self, self.currentURL == imageURL else { return }
        self.imageView.image = image
        UIView.animate(withDuration: 0.2) { self.imageView.alpha = 1 }
      }
    }
    imageTask?.resume()
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    imageTask?.cancel()
    imageTask = nil
    currentURL = nil
    imageView.image = nil
    imageView.alpha = 0
    adLabel.isHidden = true
  }
}
