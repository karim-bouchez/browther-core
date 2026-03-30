// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BraveCore
import Preferences
import Shared
import UIKit

enum NTPWallpaper {
  case image(NTPBackgroundImage)

  var backgroundImage: UIImage? {
    switch self {
    case .image(let background):
      return UIImage(contentsOfFile: background.imagePath.path)
    }
  }

  var focalPoint: CGPoint? {
    switch self {
    case .image:
      return nil  // Will eventually return a real value
    }
  }
}

public class NTPDataSource {
  private(set) var privateBrowsingManager: PrivateBrowsingManager

  /// This is the number of backgrounds that must appear before a background can be repeated.
  /// This number _must_ be less than the number of backgrounds!
  private static let numberOfDuplicateAvoidance = 6

  let service: NTPBackgroundImagesService

  public init(
    service: NTPBackgroundImagesService,
    rewards: BraveRewards?,
    privateBrowsingManager: PrivateBrowsingManager
  ) {
    self.service = service
    self.privateBrowsingManager = privateBrowsingManager

    Preferences.NewTabPage.selectedCustomTheme.observe(from: self)
  }

  private var lastBackgroundChoices = [Int]()

  /// Browther bundled background images
  private static let browtheBackgrounds: [NTPBackgroundImage] = {
    let imageNames = [
      ("abdou-faiz-TQipjFceOBg-unsplash", "Abdou Faiz"),
      ("agnieszka-stankiewicz-MVrgqBB-fqU-unsplash", "Agnieszka Stankiewicz"),
      ("clarisse-meyer-N88l6zWEhZk-unsplash", "Clarisse Meyer"),
      ("david-billings-KCEwOduK8ck-unsplash", "David Billings"),
      ("izuddin-helmi-adnan-JFirQekVo3U-unsplash", "Izuddin Helmi Adnan"),
      ("john-fowler-7Ym9rpYtSdA-unsplash", "John Fowler"),
      ("localize-eXwQCS2TUUE-unsplash", "Localize"),
      ("pommelien-da-silva-cosme-nnDgdAGoeAE-unsplash", "Pommelien Da Silva Cosme"),
      ("yasmine-arfaoui-R6rh5ttDO-4-unsplash", "Yasmine Arfaoui"),
      ("younes-m-zVBWVMontM4-unsplash", "Younes M"),
    ]
    return imageNames.compactMap { (name, _) in
      guard let url = Bundle.module.url(forResource: name, withExtension: "jpg") else {
        return nil
      }
      return NTPBackgroundImage(
        imagePath: url,
        author: "",
        link: URL(string: "https://unsplash.com")!
      )
    }
  }()

  private func getImageBackground() -> NTPWallpaper? {
    // Browther: use bundled images instead of Brave CDN
    let backgroundSet: [NTPWallpaper] = {
      let images = NTPDataSource.browtheBackgrounds
      if images.isEmpty {
        return [NTPWallpaper.image(.fallback)]
      }
      return images.map(NTPWallpaper.image)
    }()

    if backgroundSet.isEmpty { return nil }

    // Choosing the actual index / item to use
    let backgroundIndex = { () -> Int in
      let availableRange = 0..<backgroundSet.count
      // This takes all indeces and filters out ones that were shown recently
      let availableBackgroundIndeces = availableRange.filter {
        !self.lastBackgroundChoices.contains($0)
      }
      // Due to how many display modes currently exist, the background avoidance counter may get utilized on a smaller subset.
      // This can be repro by swapping between normal backgrounds and a super referrer, where all available indeces get squeezed out, resulting in an empty set.
      // To avoid issues, first fallback results in full set.

      // Chooses a new random index to use from the available indeces
      let chosenIndex =
        availableBackgroundIndeces.randomElement() ?? availableRange.randomElement() ?? -1
      assert(chosenIndex >= 0, "NTP index was nil, this is terrible.")
      assert(chosenIndex < backgroundSet.count, "NTP index is too large, BAD!")

      // This index is now added to 'past' tracking list to prevent duplicates
      self.lastBackgroundChoices.append(chosenIndex)
      // Trimming to fixed length to release older backgrounds

      self.lastBackgroundChoices = self.lastBackgroundChoices
        .suffix(min(backgroundSet.count - 1, NTPDataSource.numberOfDuplicateAvoidance))
      return chosenIndex
    }()

    return backgroundSet[safe: backgroundIndex]
  }

  func newBackground() -> NTPWallpaper? {
    if !Preferences.NewTabPage.backgroundImages.value { return nil }
    return getImageBackground()
  }
}

extension NTPDataSource: PreferencesObserver {
  public func preferencesDidChange(for key: String) {
    let customThemePref = Preferences.NewTabPage.selectedCustomTheme
    let installedThemesPref = Preferences.NewTabPage.installedCustomThemes

    switch key {
    case customThemePref.key:
      let installedThemes = installedThemesPref.value
      if let theme = customThemePref.value, !installedThemes.contains(theme) {
        installedThemesPref.value = installedThemesPref.value + [theme]
      }
    default:
      break
    }
  }
}

extension NTPBackgroundImage {
  static let fallback: NTPBackgroundImage = .init(
    imagePath: Bundle.module.url(forResource: "corwin-prescott-3", withExtension: "jpg")!,
    author: "Corwin Prescott",
    link: URL(string: "https://www.brave.com")!
  )
}

