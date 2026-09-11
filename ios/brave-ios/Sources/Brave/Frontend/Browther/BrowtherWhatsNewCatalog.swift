// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation

/// Catalogue de « Ce qui a changé » — **la plus récente en PREMIER**.
///
/// ## ⚠️ À tenir à jour à chaque release iOS (procédure : `private/docs/SURFACES_IOS.md`)
///
/// Une entrée s'ajoute en tête AVANT le build Release, pas après : les lignes
/// sont dans le binaire (pas d'OTA sur iOS). Sans entrée neuve, l'encart ne
/// s'ouvre pas — c'est voulu : une release sans rien de visible ne mérite pas
/// d'interrompre quelqu'un, et le bandeau « accès anticipé » reprend alors sa
/// place comme avant.
///
/// ## ⭐⭐ La règle de rédaction (`docs/SURFACES-COMMUNES.md` §3.6)
///
/// Une ligne par changement, **au passé**, **du point de vue de la personne**, et
/// **rien qu'elle ne puisse constater** (« les vidéos restaient floues après la
/// pause » : oui ; « cache du tap vidéo purgé par temps média » : non). Chaque
/// ligne dit d'abord le problème tel qu'elle l'a vécu, puis ce qui a changé :
/// c'est ce qui lui permet de reconnaître son propre signalement. Pas d'intro
/// « Corrigé grâce à vos retours » (retirée le 2026-09-11, tous produits). Trois
/// à cinq lignes au plus. Tutoiement, comme le reste de la voix dev&din.
///
/// - Langues : `fr`, `en`, `ar` au minimum ; l'anglais sert de repli aux 36
///   autres locales de l'app.
/// - ⛔ Aucun numéro de version dans une ligne : il ne veut rien dire pour la
///   personne.
/// - ⭐ `date` = le jour où la mise à jour PART (jour de la soumission : la
///   publication est automatique à l'approbation, ~24 h), pas celui de la
///   rédaction. C'est le seul repère affiché avec les lignes.
/// - ⛔ Un `id` diffusé ne se modifie JAMAIS : le changer rouvre l'encart chez
///   tous ceux qui l'ont lu. Corriger une coquille dans les lignes, en revanche,
///   ne rouvre rien.
enum BrowtherWhatsNewCatalog {
  static let releases: [BrowtherSurfacesRules.WhatsNewRelease] = [
    .init(
      id: "2026-09-11",
      // ⏳ À DATER le jour de la soumission de la release qui embarque cette
      // entrée (celle qui livre « Nous écrire »), et à compléter de ce qu'elle
      // corrige d'autre. Sans date, l'encart s'affiche sans surtitre.
      date: nil,
      lines: [
        "fr": [
          "Il n’y avait aucun moyen de nous dire, depuis l’app, ce qui ne marchait pas. Paramètres › Nous écrire le permet maintenant, en quelques mots."
        ],
        "en": [
          "There was no way to tell us, from the app, what wasn’t working. Settings › Contact us now lets you do it in a few words."
        ],
        "ar": [
          "لم تكن هناك طريقة لإخبارنا، من داخل التطبيق، بما لا يعمل. صار ذلك ممكنًا الآن ببضع كلمات من الإعدادات › راسلنا."
        ],
      ]
    )
  ]

  /// Fiche montrée par le déclencheur de recette quand le catalogue est vide.
  static let rehearsalSample = BrowtherSurfacesRules.WhatsNewRelease(
    id: "rehearsal-sample",
    date: "2026-09-11",
    lines: [
      "fr": [
        "Exemple de recette : la première ligne dit le problème tel qu’il a été vécu, puis ce qui a changé.",
        "Une deuxième ligne, pour voir la mise en page à plusieurs entrées.",
      ],
      "en": [
        "Rehearsal sample: the first line says the problem as it was experienced, then what changed.",
        "A second line, to check the layout with several entries.",
      ],
      "ar": [
        "مثال للاختبار: السطر الأول يصف المشكلة كما عاشها المستخدم، ثم ما الذي تغيّر.",
        "سطر ثانٍ، للتحقق من التنسيق مع عدة عناصر.",
      ],
    ]
  )
}
