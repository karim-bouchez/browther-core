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
      // Release 2026.10.8 : suppression du compte dev&din dans l'app (Apple
      // 5.1.1(v) — la 2026.9.30 permettait de le créer sans pouvoir le
      // supprimer), Sawtunaa qui bascule sans recharger et sa pause de cinq
      // minutes (validés sur iPhone le 2026-10-01), carte du code réparée.
      // ⚠️ Pas annoncé, bien qu'embarqué : la bascule Basarunaa sans
      // rechargement (pas encore recettée sur iPhone à l'heure de l'archive).
      id: "2026-10-08",
      date: "2026-10-08",
      lines: [
        "fr": [
          "Il n’y avait aucun moyen de supprimer son compte dev&din depuis l’app. Paramètres › Compte dev&din le permet maintenant, avec un code de confirmation reçu par e-mail.",
          "Allumer ou éteindre Sawtunaa rechargeait la page. La bascule se fait maintenant sur place, et la vidéo reste où elle en était.",
          "Pour écouter un passage tel quel, il fallait éteindre Sawtunaa puis penser à le rallumer. « Réactiver automatiquement dans 5 min » le fait revenir tout seul.",
          "Sur l’écran Parrainage, la carte de ton code était rognée en haut et son logo disparaissait en thème clair. Elle s’affiche maintenant en entier.",
        ],
        "en": [
          "There was no way to delete your dev&din account from the app. Settings › dev&din account now lets you do it, with a confirmation code sent by email.",
          "Turning Sawtunaa on or off reloaded the page. It now switches in place, and the video stays where it was.",
          "To listen to a passage as it is, you had to turn Sawtunaa off and then remember to turn it back on. “Turn back on automatically in 5 min” now brings it back by itself.",
          "On the Referrals screen, the card with your code was cut off at the top and its logo vanished in light mode. It now shows in full.",
        ],
        "ar": [
          "لم تكن هناك طريقة لحذف حسابك في dev&din من داخل التطبيق. صار ذلك ممكنًا الآن من الإعدادات › حساب dev&din، برمز تأكيد يصلك عبر البريد الإلكتروني.",
          "كان تشغيل Sawtunaa أو إيقافه يعيد تحميل الصفحة. صار التبديل يتم في مكانه، ويبقى الفيديو حيث كان.",
          "للاستماع إلى مقطع كما هو، كان عليك إيقاف Sawtunaa ثم تذكّر إعادة تشغيله. صار خيار «إعادة التفعيل تلقائيًا بعد 5 دقائق» يعيده من تلقاء نفسه.",
          "في شاشة التزكية، كانت بطاقة رمزك مقصوصة من الأعلى وكان شعارها يختفي في الوضع الفاتح. صارت تظهر كاملة.",
        ],
      ]
    ),
    .init(
      // Release 2026.9.30 : floutage des images chargées au défilement, flou
      // vidéo adouci, choix « qui flouter » en cases dans le panel Basarunaa.
      id: "2026-09-30",
      date: "2026-09-30",
      lines: [
        "fr": [
          "Certaines images, chargées au fil du défilement, restaient visibles sans flou. Elles sont maintenant floutées comme les autres.",
          "Le flou des vidéos s’arrêtait net sur les bords. Il se fond maintenant dans l’image, comme sur les photos.",
          "Choisir qui flouter demandait de viser de petits boutons. Le panneau Basarunaa reprend les grandes cases de l’introduction.",
        ],
        "en": [
          "Some images, loaded as you scrolled, stayed visible without any blur. They are now blurred like the others.",
          "The blur on videos stopped abruptly at the edges. It now fades into the picture, just like on photos.",
          "Choosing who to blur meant aiming at small buttons. The Basarunaa panel now uses the large tiles from the introduction.",
        ],
        "ar": [
          "بعض الصور التي تُحمَّل أثناء التمرير كانت تبقى ظاهرة دون تمويه. صارت الآن تُموَّه مثل غيرها.",
          "كان تمويه الفيديوهات يتوقف فجأة عند الحواف. صار الآن يذوب في الصورة، تمامًا كما في الصور.",
          "كان اختيار من يُموَّه يتطلب الضغط على أزرار صغيرة. صارت لوحة Basarunaa تعتمد المربعات الكبيرة نفسها التي في المقدمة.",
        ],
      ]
    ),
    .init(
      // Release 2026.9.18 : seule nouveauté visible des utilisateurs déjà
      // installés — l'introduction ne s'ouvre qu'au premier lancement.
      id: "2026-09-11",
      date: "2026-09-18",
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
