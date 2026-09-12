// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreText
import SwiftUI
import UIKit

/// La police du verset.
///
/// Le texte coranique se compose en **uthmani** : les polices système (SF
/// Arabic, Geeza Pro) dessinent un arabe moderne, qui ne porte ni les signes de
/// waṣl ni les petites lettres superscrites du muṣḥaf — le verset s'affiche,
/// mais il ne ressemble pas à ce qu'on lit dans un Coran.
///
/// On embarque donc **Amiri Quran** (SIL OFL 1.1, `aliftype/amiri`), qui est la
/// police du muṣḥaf en libre. Elle vit dans un paquet SPM, donc `UIAppFonts` de
/// l'`Info.plist` ne peut pas la déclarer : on l'enregistre au premier usage.
enum BrowtherIntroFont {
  static let quranName = "AmiriQuran-Regular"

  /// Le verset, à la taille demandée. Si l'enregistrement échoue, on retombe
  /// sur la police système — le verset reste lisible, il perd son ductus.
  static func quran(size: CGFloat) -> Font {
    registerOnce
    return UIFont(name: quranName, size: size).map(Font.init) ?? .system(size: size)
  }

  private static let registerOnce: Void = {
    guard
      let url = Bundle.module.url(forResource: quranName, withExtension: "ttf")
    else { return }
    CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
  }()
}
