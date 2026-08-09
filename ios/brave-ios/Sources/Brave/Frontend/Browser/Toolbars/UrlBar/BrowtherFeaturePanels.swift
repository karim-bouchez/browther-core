// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Basarunaa
import BraveUI
import BrowtherAnalytics
import Preferences
import Sawtunaa
import SwiftUI
import UIKit

// MARK: - « Ça ne marche pas ici ? » — signalement d'un site non géré
//
// Parité desktop (`components/browther_analytics/site_report.{h,cc}` +
// les deux panels WebUI). Mêmes règles, portées ici à la main faute de pouvoir
// partager le C++ :
//   • seul le DOMAINE part, jamais l'URL — il est calculé par l'appelant
//     (`baseDomain`) et affiché dans l'infobulle avant le clic ;
//   • rien ne part sans clic : pas de télémétrie passive de navigation ;
//   • le consentement statistiques est respecté — `track` est déjà un no-op
//     quand il est coupé (BrowtherAnalyticsService:87), mais on n'affiche pas
//     un bouton qui ne ferait rien : on explique à la place.
//
// C'est l'UTILISATEUR qui juge : il sait ce qu'il s'attendait à voir traité,
// là où une heuristique produirait des faux positifs sur des pages normales.
struct ReportSiteRow: View {
  /// Domaine enregistrable de l'onglet actif, ou nil sur une page interne.
  let domain: String?
  /// "sawtunaa" | "basarunaa"
  let feature: String

  @State private var reported = false

  private var analyticsOff: Bool {
    !Preferences.BrowtherAnalytics.posthogEnabled.value
  }

  var body: some View {
    if let domain, !domain.isEmpty {
      VStack(spacing: 0) {
        Divider()
        Group {
          if analyticsOff {
            // Ne pas proposer une action dont le seul effet serait un no-op.
            Text(verbatim: "Le signalement a besoin des statistiques d'usage, qui sont désactivées.")
              .foregroundStyle(Color(.secondaryBraveLabel))
          } else if reported {
            Text(verbatim: "Merci — site signalé.")
              .fontWeight(.semibold)
              .foregroundStyle(Color(.braveSuccessLabel))
          } else {
            HStack(spacing: 8) {
              Text(verbatim: "Ça ne marche pas sur ce site ?")
                .foregroundStyle(Color(.secondaryBraveLabel))
              Button {
                BrowtherAnalyticsService.shared.track(
                  event: "site_reported",
                  properties: ["feature": feature, "domain": domain]
                )
                reported = true
              } label: {
                Text(verbatim: "Signaler ce site")
                  .fontWeight(.semibold)
              }
              .buttonStyle(.bordered)
              .controlSize(.small)
            }
          }
        }
        .font(.caption)
        .multilineTextAlignment(.center)
        .padding(.top, 12)
        .padding(.horizontal)
      }
      .padding(.top, 4)
    }
  }
}

// MARK: - Sawtunaa panel

struct SawtunaaPanelView: View {
  /// Domaine de l'onglet actif (nil sur une page interne) — cf. ReportSiteRow.
  let reportDomain: String?

  @ObservedObject private var enabled = Preferences.Sawtunaa.enabled
  @State private var showLimitations = false

  var body: some View {
    VStack(spacing: 16) {
      header

      ShieldsSwitchView(isEnabled: Binding(
        get: { enabled.value },
        set: { newValue in
          enabled.value = newValue
          BrowtherAnalyticsService.shared.track(
            event: "feature_toggled",
            properties: ["feature": "sawtunaa", "enabled": newValue]
          )
        }
      ))
      .frame(
        width: ShieldsSwitch.size.width,
        height: ShieldsSwitch.size.height
      )

      // Status sous le toggle (cohérent avec "Boucliers Browther ACTIVÉ")
      Group {
        Text(verbatim: "Suppression de la musique ")
          + Text(enabled.value ? "ACTIVÉE" : "DÉSACTIVÉE").bold()
      }
      .font(.footnote)
      .foregroundStyle(Color(.braveLabel))

      Button {
        showLimitations = true
      } label: {
        (
          Text("Pour l'instant, ça fonctionne uniquement sur YouTube. ")
            .foregroundColor(.primary)
          + Text("(en savoir plus)")
            .foregroundColor(.accentColor)
            .underline()
        )
        .font(.footnote.weight(.medium))
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
      }
      .buttonStyle(.plain)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal)

      ReportSiteRow(domain: reportDomain, feature: "sawtunaa")
    }
    .padding(.top, 16)
    .padding(.bottom, 16)
    .frame(maxWidth: 360)
    .background(Color(.braveBackground))
    .alert("Pourquoi seulement YouTube ?", isPresented: $showLimitations) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(
        "Apple impose des restrictions techniques sur iOS qui rendent ce genre de filtrage "
          + "audio plus complexe que sur Mac/Windows/Android. On travaille à étendre ça à "
          + "d'autres sites إن شاء الله."
      )
    }
  }

  private var header: some View {
    HStack(alignment: .center, spacing: 8) {
      Image("sawtunaa.icon.bg", bundle: .module)
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(width: 32, height: 32)
      Image("sawtunaa.wordmark", bundle: .module)
        .renderingMode(.template)
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(height: 24)
        .foregroundStyle(Color(.braveLabel))
    }
    .frame(minWidth: .zero, alignment: .center)
    .padding(.horizontal)
  }
}

class SawtunaaPanelViewController: UIHostingController<SawtunaaPanelView>,
  PopoverContentComponent
{
  init(reportDomain: String?) {
    super.init(rootView: SawtunaaPanelView(reportDomain: reportDomain))
    // +36 pt : la ligne « ça ne marche pas ici ? » n'apparaît que sur une page
    // avec un domaine, mais réserver la hauteur évite un popover qui saute.
    preferredContentSize = CGSize(width: 360, height: reportDomain == nil ? 260 : 296)
  }

  @MainActor required dynamic init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

// MARK: - Basarunaa panel — aligned with the macOS POC popup
//
// Mirror of `components/basarunaa/resources/panel/basarunaa_panel.html`:
//   • big ON/OFF toggle
//   • Mode radios (blur-female / blur-male / blur-all)
//   • Détection sliders (conf-body / conf-face / gender-certainty)
//   • Debug section (visible to all builds so users can describe issues):
//       - debug-mode radios (none / boxes / debug)
//       - capture-mode toggle
//       - PoC "Test inference" button

struct BasarunaaPanelView: View {
  /// Domaine de l'onglet actif (nil sur une page interne) — cf. ReportSiteRow.
  let reportDomain: String?

  @ObservedObject private var enabled = Preferences.Basarunaa.enabled
  @ObservedObject private var mode = Preferences.Basarunaa.mode
  @ObservedObject private var confBody = Preferences.Basarunaa.confBody
  @ObservedObject private var genderCertainty = Preferences.Basarunaa.genderCertainty
  @ObservedObject private var debugMode = Preferences.Basarunaa.debugMode
  @ObservedObject private var captureMode = Preferences.Basarunaa.captureMode
  @ObservedObject private var nsfwEnabled = Preferences.Basarunaa.nsfwEnabled
  @ObservedObject private var nsfwConf = Preferences.Basarunaa.nsfwConf
  @ObservedObject private var nudenetConf = Preferences.Basarunaa.nudenetConf
  @ObservedObject private var minSkeleton = Preferences.Basarunaa.minSkeleton

  var body: some View {
    ScrollView {
      VStack(spacing: 16) {
        header

        ShieldsSwitchView(isEnabled: Binding(
          get: { enabled.value },
          set: { newValue in
            enabled.value = newValue
            BrowtherAnalyticsService.shared.track(
              event: "feature_toggled",
              properties: ["feature": "basarunaa", "enabled": newValue]
            )
          }
        ))
        .frame(
          width: ShieldsSwitch.size.width,
          height: ShieldsSwitch.size.height
        )

        Group {
          Text(verbatim: "Floutage des personnes ")
            + Text(enabled.value ? "ACTIVÉ" : "DÉSACTIVÉ").bold()
        }
        .font(.footnote)
        .foregroundStyle(Color(.braveLabel))

        // MARK: Mode
        section(title: "Mode") {
          VStack(alignment: .leading, spacing: 4) {
            radio(label: "Femmes (par défaut)", value: "blur-female", binding: modeBinding)
            radio(label: "Hommes", value: "blur-male", binding: modeBinding)
            radio(label: "Toutes les personnes", value: "blur-all", binding: modeBinding)
            Divider().padding(.vertical, 4)
            toggleRow(
              title: "Détection NSFW",
              subtitle: "Floute l'image entière si un contenu explicite est détecté (nu, parties intimes). Désactivé par défaut pour une meilleure réactivité.",
              isOn: Binding(get: { nsfwEnabled.value }, set: { nsfwEnabled.value = $0 })
            )
          }
        }
        .disabled(!enabled.value)
        .opacity(enabled.value ? 1.0 : 0.4)

        // MARK: Détection (aligné panneau macOS)
        section(title: "Détection") {
          VStack(spacing: 12) {
            toggleRow(
              title: "Ignorer les mains seules",
              subtitle: "Ne floute pas quand seule une main est visible (ex. tutos vidéo). Dès qu'on voit plus — visage, bras avec coude, jambe, corps — le flou s'applique.",
              isOn: Binding(
                get: { minSkeleton.value > 0 },
                set: { minSkeleton.value = $0 ? 0.1 : 0 }
              )
            )
            Divider()
            sliderRow(
              label: "Prudence du flou",
              value: Binding(get: { genderCertainty.value }, set: { genderCertainty.value = $0 }),
              scaleLeft: "Moins de flou",
              scaleRight: "Plus prudent",
              desc: "Chaque personne reçoit un score de certitude (le % affiché sur son label en debug). Sous ce seuil, elle est floutée par précaution. Au-dessus, sa classe décide (femme → floutée, homme/enfant → non)."
            )
            sliderRow(
              label: "Seuil NSFW (Marqo)",
              value: Binding(get: { nsfwConf.value }, set: { nsfwConf.value = $0 }),
              desc: "Seuil du classifieur NSFW global. Au-dessus, l'image entière est floutée."
            )
            sliderRow(
              label: "Seuil NudeNet",
              value: Binding(get: { nudenetConf.value }, set: { nudenetConf.value = $0 }),
              desc: "Seuil de détection des parties explicites du corps. Plus bas = plus sensible."
            )
          }
        }
        .disabled(!enabled.value)
        .opacity(enabled.value ? 1.0 : 0.4)

        // MARK: Debug (visible to all builds — required so the user can report issues)
        debugSection

        ReportSiteRow(domain: reportDomain, feature: "basarunaa")
      }
      .padding(.top, 16)
      .padding(.bottom, 16)
    }
    .frame(maxWidth: 360)
    .background(Color(.braveBackground))
  }

  // MARK: - Subviews

  private var debugSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 6) {
        Text("🛠")
        Text("Debug")
          .font(.caption.weight(.semibold))
          .textCase(.uppercase)
          .foregroundStyle(.orange)
      }

      sliderRow(
        label: "Plancher de détection (avancé)",
        value: Binding(get: { confBody.value }, set: { confBody.value = $0 }),
        desc: "Depuis le modèle single-shot, ce score EST le % affiché sur les labels debug — le monter fait disparaître des personnes. Laisser à 25 % ; le floutage des cas douteux se règle avec « Prudence du flou »."
      )

      Divider()

      VStack(alignment: .leading, spacing: 4) {
        radio(label: "Aucun", value: "none", binding: debugModeBinding)
        radio(label: "Boxes", value: "boxes", binding: debugModeBinding)
        radio(label: "Debug complet", value: "debug", binding: debugModeBinding)
      }

      Divider()

      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 2) {
          Text("Capture des analyses").font(.subheadline.weight(.medium))
          Text("Sauvegarde les images analysées dans le dossier de l'app (Files.app).")
            .font(.caption2)
            .foregroundColor(.secondary)
        }
        Spacer()
        Toggle("", isOn: Binding(
          get: { captureMode.value },
          set: { captureMode.value = $0 }
        ))
        .labelsHidden()
      }

      Text("Logs : Console.app, subsystem `com.devndin.browther`")
        .font(.caption2.monospaced())
        .foregroundColor(.secondary)
    }
    .padding(12)
    .background(
      RoundedRectangle(cornerRadius: 8)
        .stroke(style: StrokeStyle(lineWidth: 1, dash: [4]))
        .foregroundColor(.orange.opacity(0.4))
    )
    .padding(.horizontal)
  }

  @ViewBuilder
  private func section<Content: View>(
    title: String,
    @ViewBuilder _ content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.caption.weight(.semibold))
        .textCase(.uppercase)
        .foregroundStyle(.secondary)
      content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal)
  }

  private func sliderRow(
    label: String,
    value: Binding<Double>,
    scaleLeft: String? = nil,
    scaleRight: String? = nil,
    desc: String? = nil
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(label).font(.subheadline.weight(.medium))
        Spacer()
        Text(String(format: "%.0f%%", value.wrappedValue * 100))
          .font(.caption.monospacedDigit())
          .foregroundColor(.secondary)
      }
      Slider(value: value, in: 0...1)
      if let scaleLeft, let scaleRight {
        HStack {
          Text(scaleLeft)
          Spacer()
          Text(scaleRight)
        }
        .font(.caption2)
        .foregroundColor(.secondary)
      }
      if let desc {
        Text(desc)
          .font(.caption2)
          .foregroundColor(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private func toggleRow(
    title: String,
    subtitle: String,
    isOn: Binding<Bool>
  ) -> some View {
    HStack(alignment: .top) {
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.subheadline.weight(.medium))
        Text(subtitle).font(.caption2).foregroundColor(.secondary)
      }
      Spacer()
      Toggle("", isOn: isOn).labelsHidden()
    }
  }

  private func radio(
    label: String,
    value: String,
    binding: Binding<String>
  ) -> some View {
    Button {
      binding.wrappedValue = value
    } label: {
      HStack(spacing: 10) {
        ZStack {
          Circle()
            .stroke(binding.wrappedValue == value ? Color.green : Color.secondary, lineWidth: 2)
            .frame(width: 18, height: 18)
          if binding.wrappedValue == value {
            Circle().fill(Color.green).frame(width: 10, height: 10)
          }
        }
        Text(label).font(.subheadline)
        Spacer()
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  // Picker bindings. Reading goes through `effectiveMode` so legacy iOS
  // values (`"blur"` / `"strict"` / `"off"`) are reflected as the POC
  // equivalent in the UI — writes always store the canonical POC string.
  private var modeBinding: Binding<String> {
    Binding(
      get: { Preferences.Basarunaa.effectiveMode },
      set: { mode.value = $0 }
    )
  }
  private var debugModeBinding: Binding<String> {
    Binding(get: { debugMode.value }, set: { debugMode.value = $0 })
  }

  private var header: some View {
    HStack(alignment: .center, spacing: 8) {
      Image("basarunaa.icon.bg", bundle: .module)
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(width: 32, height: 32)
      Image("basarunaa.wordmark", bundle: .module)
        .renderingMode(.template)
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(height: 24)
        .foregroundStyle(Color(.braveLabel))
    }
    .frame(minWidth: .zero, alignment: .center)
    .padding(.horizontal)
  }
}

class BasarunaaPanelViewController: UIHostingController<BasarunaaPanelView>,
  PopoverContentComponent
{
  init(reportDomain: String?) {
    super.init(rootView: BasarunaaPanelView(reportDomain: reportDomain))
    preferredContentSize = CGSize(width: 360, height: 640)
  }

  @MainActor required dynamic init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}
