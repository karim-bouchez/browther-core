// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import Preferences

extension Preferences {
  /// Basarunaa (image-blur) iOS — pipeline ML natif CoreML.
  ///
  /// Aligned with the macOS POC popup
  /// (`private/extensions/basarunaa/CLAUDE.md` § "Configuration utilisateur" /
  ///  `components/basarunaa/resources/panel/basarunaa_panel.html`).
  ///
  /// Storage keys mirror the desktop pref names so the same user-facing
  /// defaults document covers both platforms.
  final public class Basarunaa {
    /// Master ON/OFF — when false, the Basarunaa user script is **not injected
    /// at all** (`BrowserViewController.preferencesDidChange` →
    /// `setScripts(scripts: [.basarunaa: isOn])` + reload), so no hide-first
    /// blur is ever painted and no ML analysis runs.
    ///
    /// ⚠️ Corrigé le 2026-08-28 : ce commentaire disait « keeps the default CSS
    /// blur on but skips ML analysis », ce qui n'est plus vrai depuis le
    /// live-toggle et décrit en fait le bug **desktop** réparé le 2026-08-23
    /// (`hide-first.css` déclaré dans le manifest MV3, donc injecté
    /// indépendamment de la pref → flou d'attente alors que le floutage est
    /// OFF). Un commentaire périmé coûte cher ici : il a fait passer iOS pour
    /// atteint par un bug qu'il n'a pas, lors de l'audit de parité.
    ///
    /// Default `true` to match the desktop default (cf. `private/CLAUDE.md`)
    /// and the Browther "navigateur pré-configuré" UX.
    ///
    /// Note historique : avant 2026-05-22, le piège `UserScriptManager.
    /// dynamicScripts` (dict figé au boot, valeur nil = clé supprimée) faisait
    /// que `false` au lancement bloquait toute activation ultérieure jusqu'à
    /// un force-quit. Fixé en sortant `.basarunaa` de `alwaysEnabledScripts`,
    /// en l'ajoutant au `scriptPreferences` de `tabDidCreateWebView`, et en
    /// observant le pref dans `BrowserViewController.preferencesDidChange`.
    public static let enabled = Option<Bool>(
      key: "basarunaa.enabled",
      default: true
    )

    /// Which persons should stay blurred when ML runs.
    /// Valid values: `"blur-female"` (POC default), `"blur-male"`, `"blur-all"`.
    /// The historical iOS values `"blur"` / `"strict"` are migrated on read
    /// (see `effectiveMode`) so existing testers don't end up in a broken state.
    public static let mode = Option<String>(
      key: "basarunaa.mode",
      default: "blur-female"
    )

    /// Detection floor (advanced) — panel "Debug" section. Depuis le single-shot
    /// gender-v2n ce score EST le % des labels ; laisser bas (0.25). `conf_face`
    /// a été retiré (plus de détecteur de visage séparé).
    public static let confBody = Option<Double>(
      key: "basarunaa.conf-body",
      default: 0.25
    )
    /// Seuil de prudence du flou (macOS « Blur caution level »). Sous ce score,
    /// une personne est floutée par précaution ; au-dessus, sa classe décide.
    public static let genderCertainty = Option<Double>(
      key: "basarunaa.gender-certainty",
      default: 0.70
    )

    /// NSFW detection (Marqo full-frame + NudeNet). Opt-in, OFF by default —
    /// Marqo is CPU-bound (~120 ms) → adds latency. Matches the desktop default
    /// (`brave.basarunaa.nsfw_enabled`, cf. `private/extensions/basarunaa/CLAUDE.md`).
    /// When OFF, the script handler skips `checkNsfw` entirely.
    public static let nsfwEnabled = Option<Bool>(
      key: "basarunaa.nsfw-enabled",
      default: false
    )
    /// Seuil du classifieur NSFW plein-cadre (Marqo). Au-dessus → flou complet.
    public static let nsfwConf = Option<Double>(
      key: "basarunaa.nsfw-conf",
      default: 0.50
    )
    /// Seuil de détection des parties explicites (NudeNet). Plus bas = plus sensible.
    public static let nudenetConf = Option<Double>(
      key: "basarunaa.nudenet-conf",
      default: 0.50
    )

    /// "Ignore hands only" filter (`min_skeleton`). `> 0` = active: a person
    /// whose only reliable keypoints are the wrists is NOT blurred. Default
    /// `0.0` (off) to match desktop (`brave_profile_prefs.cc`). Toggle maps on→0.1 / off→0.
    public static let minSkeleton = Option<Double>(
      key: "basarunaa.min-skeleton",
      default: 0.0
    )

    /// Debug overlay mode — visible in the panel's Debug section.
    /// Valid values: `"none"`, `"boxes"`, `"debug"`.
    public static let debugMode = Option<String>(
      key: "basarunaa.debug-mode",
      default: "none"
    )
    /// When true, the analyzed image + decision are persisted under
    /// `Documents/Basarunaa-capture/` (visible via Files.app when file
    /// sharing is enabled on the bundle).
    public static let captureMode = Option<Bool>(
      key: "basarunaa.capture-mode",
      default: false
    )

    // MARK: - Collecte de corpus (opt-in, locale)
    //
    // Voir `private/extensions/basarunaa/docs/COLLECTE.md`. Trois préférences
    // seulement, et c'est délibéré : desktop persiste un objet de configuration
    // complet, ce qui lui a coûté une version de schéma, une migration et trois
    // pannes de divergence entre « ce que le réglage dit » et « ce que le
    // collecteur fait ». Les réglages fins (taux, quotas, listes) sont ici des
    // constantes de code (`CollectConfig`) — on ne peut pas diverger d'une
    // valeur qui n'a qu'une seule source.

    /// **L'interrupteur.** OFF par défaut : rien n'est collecté tant que
    /// personne ne le coche, et il vit dans le panel → Debug, au même titre que
    /// « Capture des analyses ». L'écran de contrôle ne peut PAS l'activer — il
    /// ne porte que le nom d'appareil, les compteurs et l'export.
    public static let collectEnabled = Option<Bool>(
      key: "basarunaa.collect-enabled",
      default: false
    )

    /// Nom d'appareil (`karim`, `epouse`) — préfixe les archives et marque
    /// chaque ligne du manifeste (`dev`).
    ///
    /// ⚠️ Sans lui, deux appareils produisent des archives `anon-*`
    /// indistinguables et le découpage par personne est perdu **sans recours**
    /// pour les images déjà collectées. L'écran de contrôle lève un bandeau
    /// tant qu'il est vide.
    public static let collectDevice = Option<String>(
      key: "basarunaa.collect-device",
      default: ""
    )

    /// Échantillonner aussi une frame par SCÈNE de vidéo.
    ///
    /// Capturer une frame impose un readback GPU→CPU, précisément ce que
    /// l'overlay vidéo évite à 60 fps. C'est borné (au plus une fois par scène,
    /// plafonné par vidéo et par jour), mais **si une saccade apparaît sur une
    /// vidéo, c'est le premier interrupteur à basculer**.
    public static let collectVideoScenes = Option<Bool>(
      key: "basarunaa.collect-video-scenes",
      default: true
    )

    /// Returns one of `"blur-female"` / `"blur-male"` / `"blur-all"`, migrating
    /// legacy iOS values (`"blur"` → `"blur-female"`, `"strict"` → `"blur-all"`,
    /// `"off"` → `"blur-female"` + enabled=false equivalent).
    public static var effectiveMode: String {
      switch mode.value {
      case "blur-female", "blur-male", "blur-all":
        return mode.value
      case "strict":
        return "blur-all"
      default:
        return "blur-female"
      }
    }
  }
}
