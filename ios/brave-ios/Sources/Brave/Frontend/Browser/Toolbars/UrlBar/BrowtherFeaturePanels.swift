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

// MARK: - Sawtunaa panel

struct SawtunaaPanelView: View {
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
  init() {
    super.init(rootView: SawtunaaPanelView())
    preferredContentSize = CGSize(width: 360, height: 260)
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
  @ObservedObject private var enabled = Preferences.Basarunaa.enabled
  @ObservedObject private var mode = Preferences.Basarunaa.mode
  @ObservedObject private var confBody = Preferences.Basarunaa.confBody
  @ObservedObject private var confFace = Preferences.Basarunaa.confFace
  @ObservedObject private var genderCertainty = Preferences.Basarunaa.genderCertainty
  @ObservedObject private var debugMode = Preferences.Basarunaa.debugMode
  @ObservedObject private var captureMode = Preferences.Basarunaa.captureMode
  @ObservedObject private var nsfwEnabled = Preferences.Basarunaa.nsfwEnabled
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
              subtitle: "Floute le contenu explicite en plein cadre. Ajoute de la latence.",
              isOn: Binding(get: { nsfwEnabled.value }, set: { nsfwEnabled.value = $0 })
            )
          }
        }
        .disabled(!enabled.value)
        .opacity(enabled.value ? 1.0 : 0.4)

        // MARK: Détection
        section(title: "Détection") {
          VStack(spacing: 12) {
            sliderRow(label: "Confiance corps", value: Binding(
              get: { confBody.value },
              set: { confBody.value = $0 }
            ))
            sliderRow(label: "Confiance visage", value: Binding(
              get: { confFace.value },
              set: { confFace.value = $0 }
            ))
            sliderRow(label: "Certitude du genre", value: Binding(
              get: { genderCertainty.value },
              set: { genderCertainty.value = $0 }
            ))
            Divider()
            toggleRow(
              title: "Ignorer les mains seules",
              subtitle: "Ne floute pas une personne dont seuls les poignets sont détectés.",
              isOn: Binding(
                get: { minSkeleton.value > 0 },
                set: { minSkeleton.value = $0 ? 0.1 : 0 }
              )
            )
          }
        }
        .disabled(!enabled.value)
        .opacity(enabled.value ? 1.0 : 0.4)

        // MARK: Debug (visible to all builds — required so the user can report issues)
        debugSection
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

  private func sliderRow(label: String, value: Binding<Double>) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(label).font(.subheadline.weight(.medium))
        Spacer()
        Text(String(format: "%.0f%%", value.wrappedValue * 100))
          .font(.caption.monospacedDigit())
          .foregroundColor(.secondary)
      }
      Slider(value: value, in: 0...1)
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
  init() {
    super.init(rootView: BasarunaaPanelView())
    preferredContentSize = CGSize(width: 360, height: 640)
  }

  @MainActor required dynamic init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}
