// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import BraveStrings
import BrowtherReferral
import SwiftUI
import UIKit

/// La jauge — `docs/PARRAINAGE.md` § 2.2 et § 12.4, pendant iOS de
/// `fajrunaa/components/referral/ReferralGauge.tsx` (⛔ pas une recopie : les
/// outils natifs).
///
/// ⭐ **C'est un JOUET** : on la glisse pour voir ce que rapporteraient plus
/// d'invitations. Rien n'est enregistré, rien n'est demandé au serveur. Le
/// barème vient du statut (`scale`) : ⛔ aucun palier recopié ici.
///
/// ## Deux tempéraments (les MÊMES noms partout : ils sortent dans l'analytique)
///
/// - **`toy`** (écrans 2b et 4) : « Si j'invite N proches · je gagne M mois »,
///   en or. Elle part d'au moins 1, **reste où on la laisse**, et se souvient
///   d'un écran à l'autre du même moment (§ 12.20).
/// - **`spring`** (écran Parrainage) : au repos elle dit ce qu'on A (vert) ;
///   tirée, ce qu'on AURAIT (or) ; on ne la tire que vers le HAUT ; relâchée,
///   elle revient en ressort en partant de l'élan du doigt.
///
/// ## Pourquoi une physique à la main
///
/// Une animation SwiftUI ne laisse lire ni la position en cours, ni la
/// vitesse : or **les chiffres défilent EN CHEMIN** pendant le retour, **la main
/// arrête net** la démo là où est le curseur, et le ressort **part de l'élan du
/// doigt**. D'où un ressort amorti intégré image par image (`GaugeMotion`).
///
/// ## Ce que les recettes mobiles ont appris (§ 12.4, § 12.24)
///
/// - 🔴 **Horizontal seulement** : sinon la jauge vole le défilement vertical
///   de l'écran (un `UIPanGestureRecognizer` qui ne commence que si le geste
///   est plus horizontal que vertical).
/// - 🔴 Le ressort sous le doigt : **0,9 s, amortissement 0,72** — le réglage du
///   web (0,7 s, rebond 0,3) est trop rapide et trop rebondi.
/// - ⭐ Un cran se sent par invitation (au doigt seulement), le retour se pose
///   d'un petit choc, « à vie » atteint au doigt se fête.
/// - ⭐ **La démo** joue à chaque affichage, jusqu'au jour où la personne a tiré
///   le curseur ELLE-MÊME jusqu'à « à vie » (`MilestoneScale.demoTarget`).
/// - ⚠️ Hauteurs FIXES au-dessus de la piste : rien ne saute pendant qu'on tire.
/// - ⚠️ Piste posée en LTR : 1 → 10 se lit dans ce sens en arabe aussi.
struct ReferralGaugeView: View {
  enum Mode: String {
    case toy, spring
  }

  let validated: Int
  let scale: MilestoneScale
  let mode: Mode
  /// La démo, à chaque affichage tant que la jauge n'a pas été comprise.
  var demo = true
  /// Le jouet reprend où on l'a laissé (§ 12.20).
  var intention: Binding<Int?>?
  /// « À vie » atteint AU DOIGT : l'écran tire ses confettis.
  var onCelebrate: (() -> Void)?

  @StateObject private var motion = GaugeMotion()
  @State private var width: CGFloat = 0
  @State private var pulledOnce = false
  @State private var demoPlayed = false
  @State private var lastBurst = Date.distantPast
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  /// La porte des écrans (§ 13.8) : muette si la jauge est dans un aperçu.
  @Environment(\.referralNote) private var note

  private static let thumb: CGFloat = 28
  private static let edge: CGFloat = thumb / 2

  private var maxValue: Int { scale.lifetimeAt }
  private var actual: Int { max(0, min(maxValue, validated)) }
  private var rest: Double {
    mode == .spring ? Double(actual) : Double(max(intention?.wrappedValue ?? actual, 1))
  }
  /// Le ressort ne se tire que vers le HAUT : sous l'acquis, il n'y a rien à voir.
  private var minimum: Double { mode == .spring ? Double(actual) : 1 }
  private var span: CGFloat { max(0, width - Self.thumb) }

  var body: some View {
    let shown = Int(motion.position.rounded())
    let reading = scale.reading(at: motion.position)
    let pulled = mode == .spring && motion.source != .system && shown > actual
    let gold = mode == .toy || pulled
    let accent = gold ? ReferralPalette.goldFill : ReferralPalette.greenFill
    let accentText = gold ? ReferralPalette.gold : ReferralPalette.green

    VStack(spacing: 8) {
      VStack(spacing: 4) {
        numbers(reading: reading, gold: gold, pulled: pulled, accentText: accentText)
        bonusLine(reading)
        track(shown: shown, accent: accent)
        ticks(shown: shown, accentText: accentText)
        // ⛔ Rien sous le ressort de l'écran Parrainage : la démo montre qu'il se tire (§ 12.26).
        if mode == .toy {
          Text(actual > 0 ? Strings.BrowtherReferral.gaugeNow(actual) : Strings.BrowtherReferral.gaugeHelp)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
        }
      }
      .padding(.horizontal, 16)
      .padding(.top, 12)
      .padding(.bottom, 10)
      .background(ReferralPalette.panel, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

      ReferralLifetimeCard(count: shown, lit: reading.lifetime, lifetimeAt: maxValue)
    }
    .onAppear {
      motion.jump(to: rest)
      motion.onNotch = { value, byHand in notch(value, byHand: byHand) }
      motion.onSettled = { byHand in
        if byHand, mode == .spring { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
      }
    }
    .onChange(of: validated) { _, _ in
      // L'état réel change (une invitation validée) : la jauge au repos le suit,
      // sans à-coup — ⛔ pas pendant qu'on la tient, ⛔ jamais le jouet.
      guard mode == .spring, !motion.dragging else { return }
      motion.animate(to: rest, duration: 0.35, damping: 1)
    }
    .onChange(of: width) { _, _ in playDemoIfNeeded() }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(Strings.BrowtherReferral.gaugeA11y)
    .accessibilityValue("\(reading.invitations) · \(reading.lifetime ? Strings.BrowtherReferral.gaugeLifetime : Strings.BrowtherReferral.gaugeMonths(reading.months))")
    .accessibilityAdjustableAction { direction in
      let step: Double = direction == .increment ? 1 : -1
      let next = max(minimum, min(Double(maxValue), motion.position.rounded() + step))
      grab()
      motion.animate(to: next, duration: 0.35, damping: 1, byHand: true)
      release(landed: Int(next), velocity: 0)
    }
  }

  // MARK: Les deux nombres — ⚠️ hauteurs FIXES

  private func numbers(reading: MilestoneScale.Reading, gold: Bool, pulled: Bool, accentText: Color) -> some View {
    let labelColor = gold ? ReferralPalette.gold : Color.secondary
    let ifLabel = mode == .toy
      ? Strings.BrowtherReferral.gaugeIf
      : pulled ? Strings.BrowtherReferral.gaugeIfElastic : Strings.BrowtherReferral.gaugeRestIf
    let thenLabel = mode == .toy
      ? Strings.BrowtherReferral.gaugeThen
      : pulled ? Strings.BrowtherReferral.gaugeThenElastic : Strings.BrowtherReferral.gaugeRestThen
    let unit = mode == .spring
      ? Strings.BrowtherReferral.gaugeUnitInvitation(reading.invitations)
      : Strings.BrowtherReferral.gaugeUnit(reading.invitations)

    return HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text(ifLabel)
          .font(.footnote)
          .foregroundStyle(labelColor)
          .lineLimit(1)
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          bigNumber(reading.invitations, color: .primary)
          Text(unit)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .frame(height: 38, alignment: .bottom)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      VStack(alignment: .trailing, spacing: 2) {
        Text(thenLabel)
          .font(.footnote)
          .foregroundStyle(labelColor)
          .lineLimit(1)
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          if reading.lifetime {
            Text(Strings.BrowtherReferral.gaugeLifetime)
              .font(.system(size: 28, weight: .semibold, design: .rounded))
              .foregroundStyle(ReferralPalette.gold)
          } else {
            bigNumber(reading.months, color: accentText)
            Text(Strings.BrowtherReferral.gaugeMonths(reading.months))
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
        }
        .frame(height: 38, alignment: .bottom)
      }
      .frame(maxWidth: .infinity, alignment: .trailing)
    }
    // Les nombres se lisent de gauche à droite, même en arabe.
    .environment(\.layoutDirection, .leftToRight)
  }

  /// ⭐ Seuls les CHIFFRES bougent (défilement chiffre par chiffre) ; les
  /// libellés restent en place (§ 12.4).
  private func bigNumber(_ value: Int, color: Color) -> some View {
    Text("\(value)")
      .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
      .foregroundStyle(color)
      .contentTransition(.numericText(value: Double(value)))
      .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: value)
  }

  private func bonusLine(_ reading: MilestoneScale.Reading) -> some View {
    Group {
      if !reading.lifetime, reading.bonusMonths > 0 {
        ReferralRichText(text: Strings.BrowtherReferral.gaugeBonus(reading.bonusMonths))
      } else {
        Text(" ")
      }
    }
    .font(.footnote)
    .foregroundStyle(.secondary)
    .frame(maxWidth: .infinity, alignment: .trailing)
    .frame(height: 18)
  }

  // MARK: La piste

  private func track(shown: Int, accent: Color) -> some View {
    ZStack(alignment: .leading) {
      Capsule()
        .fill(ReferralPalette.track)
        .frame(height: 6)
        .padding(.horizontal, Self.edge)
      // Le tiré (or), sous l'acquis (vert) : ⚠️ l'acquis est TOUJOURS peint.
      Capsule()
        .fill(accent)
        .frame(width: Self.edge + CGFloat(motion.position / Double(maxValue)) * span, height: 6)
      if actual > 0, span > 0 {
        Capsule()
          .fill(ReferralPalette.greenFill)
          .frame(width: Self.edge + CGFloat(Double(actual) / Double(maxValue)) * span, height: 6)
      }
      // Un cran PAR invitation — ⛔ pas seulement aux paliers.
      if span > 0 {
        ForEach(1..<maxValue, id: \.self) { at in
          Circle()
            .fill(at <= shown ? Color.white.opacity(0.8) : Color.secondary.opacity(0.45))
            .frame(width: 4, height: 4)
            .offset(x: Self.edge + CGFloat(at) / CGFloat(maxValue) * span - 2)
        }
      }
      Circle()
        .fill(Color.white)
        .overlay(Circle().strokeBorder(accent, lineWidth: 4))
        .frame(width: Self.thumb, height: Self.thumb)
        // ⚠️ Le halo était une OMBRE colorée : invisible en thème clair, où le
        // fond est déjà clair (recette Karim, 2026-09-23 : « je ne vois pas le
        // contour du curseur »). Un vrai disque derrière le curseur se voit
        // dans les deux thèmes ; l'ombre ne fait plus que le décoller.
        .background(
          Circle()
            .fill(accent.opacity(0.22))
            .frame(width: Self.thumb + 14, height: Self.thumb + 14)
        )
        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
        .scaleEffect(motion.dragging ? 1.12 : 1)
        .animation(.easeOut(duration: 0.12), value: motion.dragging)
        .offset(x: CGFloat(motion.position / Double(maxValue)) * span)
    }
    .frame(height: Self.thumb + 14)
    .background {
      GeometryReader { geometry in
        Color.clear
          .onAppear { width = geometry.size.width }
          .onChange(of: geometry.size.width) { _, next in width = next }
      }
    }
    // 🔴 Horizontal seulement : un doigt qui part à la verticale fait défiler la page.
    .overlay {
      HorizontalPanView(
        onBegan: { grab() },
        onChanged: { translation in drag(translation) },
        onEnded: { velocity in
          let points = span > 0 ? velocity / span * CGFloat(maxValue) : 0
          release(landed: Int(motion.position.rounded()), velocity: Double(points))
        },
        onTap: { x in tap(at: x) }
      )
    }
    .environment(\.layoutDirection, .leftToRight)
  }

  private struct Tick: Identifiable {
    let at: Int
    let bonus: Int?
    let lifetime: Bool
    var id: Int { at }
  }

  private func ticks(shown: Int, accentText: Color) -> some View {
    var ticks = [Tick(at: 1, bonus: nil, lifetime: false)]
    ticks += scale.bonuses.map { Tick(at: $0.at, bonus: $0.months, lifetime: false) }
    ticks.append(Tick(at: maxValue, bonus: nil, lifetime: true))
    return ZStack(alignment: .topLeading) {
      if span > 0 {
        ForEach(ticks) { tick in
          let reached = shown >= tick.at
          VStack(spacing: 1) {
            Text("\(tick.at)")
              .font(.caption.weight(.semibold))
              .foregroundStyle(reached ? accentText : Color.secondary)
            if tick.lifetime || tick.bonus != nil {
              Text(
                tick.lifetime
                  ? Strings.BrowtherReferral.gaugeTickLifetime
                  : Strings.BrowtherReferral.gaugeTickBonus(tick.bonus ?? 0)
              )
              .font(.caption2)
              .foregroundStyle(reached ? accentText : Color.secondary.opacity(0.7))
              .lineLimit(1)
              .fixedSize()
            }
          }
          .frame(width: 60)
          .offset(x: Self.edge + CGFloat(tick.at) / CGFloat(maxValue) * span - 30)
        }
      }
    }
    .frame(maxWidth: .infinity, minHeight: 30, alignment: .topLeading)
    .environment(\.layoutDirection, .leftToRight)
  }

  // MARK: Le geste

  @State private var grabbedAt: Double = 0

  private func grab() {
    // ⭐ La main arrête net la démo ou le retour en cours.
    motion.stop()
    motion.dragging = true
    motion.source = .user
    grabbedAt = motion.position
    if !pulledOnce {
      pulledOnce = true
      // ⚠️ Une fois par jauge affichée : « on y a touché », pas combien.
      note(.referralGaugePulled, ["mode": mode.rawValue])
    }
  }

  private func drag(_ translation: CGFloat) {
    guard span > 0 else { return }
    // Le curseur s'attrape n'importe où et garde son écart avec le doigt.
    let next = grabbedAt + Double(translation / span) * Double(maxValue)
    motion.setByHand(max(minimum, min(Double(maxValue), next)))
  }

  private func release(landed: Int, velocity: Double) {
    motion.dragging = false
    if mode == .spring {
      motion.animate(to: rest, duration: 0.9, damping: 0.72, velocity: velocity, byHand: true)
    } else {
      motion.animate(to: Double(landed), duration: 0.35, damping: 1, velocity: velocity)
      intention?.wrappedValue = landed
    }
  }

  private func tap(at x: CGFloat) {
    guard span > 0 else { return }
    let target = Double(((x - Self.edge) / span) * CGFloat(maxValue)).rounded()
    let landed = max(minimum, min(Double(maxValue), target))
    grab()
    motion.dragging = false
    if mode == .spring {
      // Toucher un palier le montre, puis le ressort ramène à l'acquis.
      motion.animate(to: landed, duration: 0.35, damping: 1, byHand: true) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
          guard !motion.dragging else { return }
          motion.animate(to: rest, duration: 0.9, damping: 0.72, byHand: true)
        }
      }
    } else {
      motion.animate(to: landed, duration: 0.35, damping: 1, byHand: true)
      intention?.wrappedValue = Int(landed)
    }
  }

  private func notch(_ value: Int, byHand: Bool) {
    guard byHand else { return }
    UISelectionFeedbackGenerator().selectionChanged()
    if scale.understood(value: value, byHand: true) {
      ReferralStorage.shared.gaugeUnderstood = true
    }
    if value >= maxValue {
      UINotificationFeedbackGenerator().notificationOccurred(.success)
      // Un va-et-vient au bout de la piste ne tire pas une rafale.
      if Date().timeIntervalSince(lastBurst) > 2.5 {
        lastBurst = Date()
        onCelebrate?()
      }
    }
  }

  // MARK: La démo (§ 12.4)

  private func playDemoIfNeeded() {
    guard demo, !reduceMotion, span > 0, !demoPlayed, !pulledOnce else { return }
    // ⛔ Pas de démo par-dessus une réponse déjà donnée (§ 12.20).
    guard intention?.wrappedValue == nil else { return }
    guard !ReferralStorage.shared.gaugeUnderstood else { return }
    guard let target = scale.demoTarget(from: Int(rest)) else { return }
    demoPlayed = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
      guard !motion.dragging, motion.source != .user else { return }
      motion.source = .demo
      motion.animate(to: Double(target), duration: 0.9, damping: 1) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
          guard !motion.dragging, motion.source == .demo else { return }
          motion.animate(to: rest, duration: 0.9, damping: 0.72) {
            if motion.source == .demo { motion.source = .system }
          }
        }
      }
    }
  }
}

// MARK: - Le ressort, image par image

/// Un ressort amorti intégré à chaque image (`CADisplayLink`) — ce qu'une
/// animation SwiftUI ne donne pas : la position EN COURS (les chiffres qui
/// défilent en chemin), la vitesse (l'élan du doigt), et l'arrêt net.
@MainActor
final class GaugeMotion: ObservableObject {
  enum Source { case system, demo, user }

  @Published private(set) var position: Double = 0
  @Published var dragging = false
  @Published var source: Source = .system

  var onNotch: ((Int, Bool) -> Void)?
  var onSettled: ((Bool) -> Void)?

  private var target: Double = 0
  private var velocity: Double = 0
  private var stiffness: Double = 0
  private var damping: Double = 0
  private var byHand = false
  private var completion: (() -> Void)?
  private var link: CADisplayLink?
  private var lastTimestamp: CFTimeInterval = 0
  private var lastNotch = 0

  func jump(to value: Double) {
    stop()
    position = value
    lastNotch = Int(value.rounded())
  }

  func setByHand(_ value: Double) {
    position = value
    emitNotch(byHand: true)
  }

  /// `duration` / `damping` : la grammaire de Reanimated (§ 12.4) — la pulsation
  /// propre vient de la durée, l'amortissement du ratio (1 = sans rebond).
  func animate(
    to value: Double,
    duration: Double,
    damping ratio: Double,
    velocity: Double = 0,
    byHand: Bool = false,
    completion: (() -> Void)? = nil
  ) {
    let omega = 2 * Double.pi / max(duration, 0.05)
    target = value
    self.velocity = velocity
    stiffness = omega * omega
    damping = 2 * ratio * omega
    self.byHand = byHand
    self.completion = completion
    startLink()
  }

  func stop() {
    link?.invalidate()
    link = nil
    completion = nil
    velocity = 0
  }

  private func startLink() {
    link?.invalidate()
    let link = CADisplayLink(target: DisplayLinkProxy(self), selector: #selector(DisplayLinkProxy.tick(_:)))
    link.add(to: .main, forMode: .common)
    lastTimestamp = 0
    self.link = link
  }

  fileprivate func step(_ timestamp: CFTimeInterval) {
    defer { lastTimestamp = timestamp }
    guard lastTimestamp > 0 else { return }
    // Pas fixe de 1/240 s pour la stabilité, quelle que soit la cadence d'écran.
    var remaining = min(timestamp - lastTimestamp, 1.0 / 20)
    let dt = 1.0 / 240
    var x = position
    var v = velocity
    while remaining > 0 {
      let h = min(dt, remaining)
      let acceleration = -stiffness * (x - target) - damping * v
      v += acceleration * h
      x += v * h
      remaining -= h
    }
    velocity = v
    position = x
    emitNotch(byHand: byHand)
    if abs(x - target) < 0.002, abs(v) < 0.01 {
      position = target
      emitNotch(byHand: byHand)
      link?.invalidate()
      link = nil
      let done = completion
      completion = nil
      onSettled?(byHand)
      done?()
    }
  }

  private func emitNotch(byHand: Bool) {
    let value = Int(position.rounded())
    guard value != lastNotch else { return }
    lastNotch = value
    onNotch?(value, byHand)
  }
}

/// `CADisplayLink` retient sa cible : un intermédiaire faible évite que le
/// ressort survive à la jauge.
private final class DisplayLinkProxy: NSObject {
  weak var motion: GaugeMotion?

  init(_ motion: GaugeMotion) {
    self.motion = motion
  }

  @objc func tick(_ link: CADisplayLink) {
    guard let motion else {
      link.invalidate()
      return
    }
    MainActor.assumeIsolated {
      motion.step(link.timestamp)
    }
  }
}

// MARK: - Le geste horizontal

/// Un pan qui ne COMMENCE que s'il est plus horizontal que vertical — le
/// pendant de `activeOffsetX` + `failOffsetY` : la jauge ne vole jamais le
/// défilement vertical de l'écran (§ 12.24). Et un toucher simple sur la piste.
struct HorizontalPanView: UIViewRepresentable {
  var onBegan: () -> Void
  var onChanged: (CGFloat) -> Void
  var onEnded: (CGFloat) -> Void
  var onTap: (CGFloat) -> Void

  func makeUIView(context: Context) -> UIView {
    let view = UIView()
    view.backgroundColor = .clear
    let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
    pan.delegate = context.coordinator
    view.addGestureRecognizer(pan)
    let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
    view.addGestureRecognizer(tap)
    return view
  }

  func updateUIView(_ uiView: UIView, context: Context) {
    context.coordinator.parent = self
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  final class Coordinator: NSObject, UIGestureRecognizerDelegate {
    var parent: HorizontalPanView

    init(parent: HorizontalPanView) {
      self.parent = parent
    }

    @objc func pan(_ recognizer: UIPanGestureRecognizer) {
      let translation = recognizer.translation(in: recognizer.view).x
      switch recognizer.state {
      case .began:
        parent.onBegan()
        parent.onChanged(translation)
      case .changed:
        parent.onChanged(translation)
      case .ended, .cancelled, .failed:
        // 🔴 Un relâchement ne se perd jamais : annulé ou raté, on relâche.
        parent.onEnded(recognizer.velocity(in: recognizer.view).x)
      default:
        break
      }
    }

    @objc func tap(_ recognizer: UITapGestureRecognizer) {
      parent.onTap(recognizer.location(in: recognizer.view).x)
    }

    func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
      guard let pan = recognizer as? UIPanGestureRecognizer else { return true }
      let velocity = pan.velocity(in: pan.view)
      return abs(velocity.x) > abs(velocity.y)
    }
  }
}
