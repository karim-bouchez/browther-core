// Copyright 2026 dev&din. All rights reserved.
// Browther — NTP ad banner section (régie devndin-ads)

import BraveUI
import BrowtherAnalytics
import Foundation
import SnapKit
import UIKit

/// Bannière pub devndin-ads sous les favoris du NTP. Carousel ratio 3.2:1,
/// parité desktop `browther_ad_banner.tsx` + `ads/docs/INTEGRATION.md`.
///
/// Le serve signé HMAC, le batching des impressions et la résolution du click
/// URL vivent dans `BrowtherAdsClient` (module BrowtherAnalytics) — le secret
/// publisher ne touche jamais ce provider. Seuls `id` + `imageURL` traversent
/// jusqu'ici (parité mojom `BrowtherAd` desktop).
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
    // Ratio 3.2:1 (parité desktop, cf. ads/docs/INTEGRATION.md § 3).
    let height = width / 3.2
    return CGSize(width: width, height: height)
  }

  func collectionView(
    _ collectionView: UICollectionView,
    layout collectionViewLayout: UICollectionViewLayout,
    insetForSectionAt section: Int
  ) -> UIEdgeInsets {
    UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
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
      cell.configure(imageURL: ads[indexPath.item].imageURL)
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

  private var imageTask: URLSessionDataTask?
  private var currentURL: String?

  override init(frame: CGRect) {
    super.init(frame: frame)
    contentView.addSubview(imageView)
    imageView.snp.makeConstraints {
      $0.edges.equalToSuperview()
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError()
  }

  func configure(imageURL: String) {
    currentURL = imageURL
    imageView.image = nil
    imageView.alpha = 0

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
  }
}
