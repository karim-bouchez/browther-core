// Copyright 2026 dev&din. All rights reserved.
// Browther — NTP ad banner section

import BraveUI
import Foundation
import SnapKit
import UIKit

/// Ad response from browther-api
private struct BrowtheAd: Codable {
  let id: Int
  let image_url: String
  let click_url: String
  let alt_text: String?
}

/// Displays a single ad banner (320×100 ratio) below favorites on the NTP.
class BrowtheAdSectionProvider: NSObject, NTPSectionProvider {
  private static let apiBaseURL = "https://browther-api.devndin.com"
  private static let cacheDuration: TimeInterval = 60

  private var cachedAd: BrowtheAd?
  private var lastFetchDate: Date?
  private var isFetching = false
  private var impressionReported = false

  var onAdTapped: ((_ url: URL) -> Void)?
  /// Called when an ad is fetched and the section needs to reload
  var onAdLoaded: (() -> Void)?

  override init() {
    super.init()
    fetchAdIfNeeded()
  }

  // MARK: - API

  private func fetchAdIfNeeded() {
    if let lastFetch = lastFetchDate,
      Date().timeIntervalSince(lastFetch) < Self.cacheDuration
    {
      return
    }
    guard !isFetching else { return }
    isFetching = true

    let platform = "ios"
    let locale = Locale.current.language.languageCode?.identifier ?? "en"
    let urlString = "\(Self.apiBaseURL)/api/ad?platform=\(platform)&locale=\(locale)"

    guard let url = URL(string: urlString) else {
      isFetching = false
      return
    }

    var request = URLRequest(url: url)
    request.timeoutInterval = 5

    URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
      defer { self?.isFetching = false }
      guard let self = self else { return }

      guard let data = data,
        let httpResponse = response as? HTTPURLResponse,
        httpResponse.statusCode == 200
      else {
        return
      }

      do {
        let ad = try JSONDecoder().decode(BrowtheAd.self, from: data)
        DispatchQueue.main.async {
          self.cachedAd = ad
          self.lastFetchDate = Date()
          self.impressionReported = false
          self.onAdLoaded?()
        }
      } catch {
        // Silently fail — no ad shown
      }
    }.resume()
  }

  private func reportImpression(adId: Int) {
    guard !impressionReported else { return }
    impressionReported = true

    guard let url = URL(string: "\(Self.apiBaseURL)/api/ad/\(adId)/impression") else { return }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let body: [String: String] = ["platform": "ios"]
    request.httpBody = try? JSONEncoder().encode(body)

    URLSession.shared.dataTask(with: request) { _, _, _ in }.resume()
  }

  private func reportClick(adId: Int) {
    guard let url = URL(string: "\(Self.apiBaseURL)/api/ad/\(adId)/click") else { return }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try? JSONEncoder().encode([String: String]())

    URLSession.shared.dataTask(with: request) { _, _, _ in }.resume()
  }

  // MARK: - NTPSectionProvider

  func registerCells(to collectionView: UICollectionView) {
    collectionView.register(BrowtheAdCell.self)
  }

  func collectionView(
    _ collectionView: UICollectionView,
    numberOfItemsInSection section: Int
  ) -> Int {
    guard cachedAd != nil else {
      return 0
    }
    return 1
  }

  func collectionView(
    _ collectionView: UICollectionView,
    cellForItemAt indexPath: IndexPath
  ) -> UICollectionViewCell {
    let cell = collectionView.dequeueReusableCell(for: indexPath) as BrowtheAdCell

    if let ad = cachedAd {
      cell.configure(imageURL: ad.image_url, altText: ad.alt_text)
      reportImpression(adId: ad.id)
    }

    return cell
  }

  func collectionView(
    _ collectionView: UICollectionView,
    didSelectItemAt indexPath: IndexPath
  ) {
    guard let ad = cachedAd, let url = URL(string: ad.click_url) else { return }
    reportClick(adId: ad.id)
    onAdTapped?(url)
  }

  func collectionView(
    _ collectionView: UICollectionView,
    layout collectionViewLayout: UICollectionViewLayout,
    sizeForItemAt indexPath: IndexPath
  ) -> CGSize {
    let width = fittingSizeForCollectionView(collectionView, section: indexPath.section).width
    // 16:5 ratio for the banner
    let height = width * (5.0 / 16.0)
    return CGSize(width: width, height: height)
  }

  func collectionView(
    _ collectionView: UICollectionView,
    layout collectionViewLayout: UICollectionViewLayout,
    insetForSectionAt section: Int
  ) -> UIEdgeInsets {
    return UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
  }
}

// MARK: - BrowtheAdCell

private class BrowtheAdCell: UICollectionViewCell, CollectionViewReusable {
  private let imageView = UIImageView().then {
    $0.contentMode = .scaleAspectFill
    $0.clipsToBounds = true
    $0.layer.cornerRadius = 12
    $0.backgroundColor = UIColor(white: 0.2, alpha: 0.8)
  }

  private let placeholderLabel = UILabel().then {
    $0.text = "Browther"
    $0.textColor = .white
    $0.font = .systemFont(ofSize: 14, weight: .medium)
    $0.textAlignment = .center
  }

  override init(frame: CGRect) {
    super.init(frame: frame)

    contentView.addSubview(imageView)
    imageView.addSubview(placeholderLabel)
    imageView.snp.makeConstraints {
      $0.edges.equalToSuperview()
    }
    placeholderLabel.snp.makeConstraints {
      $0.center.equalToSuperview()
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError()
  }

  func configure(imageURL: String, altText: String?) {
    imageView.accessibilityLabel = altText
    imageView.image = nil

    guard let url = URL(string: imageURL) else { return }

    URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
      guard let data = data, let image = UIImage(data: data) else { return }
      DispatchQueue.main.async {
        self?.imageView.image = image
        self?.placeholderLabel.isHidden = true
      }
    }.resume()
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    imageView.image = nil
  }
}
