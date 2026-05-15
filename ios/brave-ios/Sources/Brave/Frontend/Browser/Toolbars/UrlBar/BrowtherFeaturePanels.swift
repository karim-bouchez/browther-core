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
      .foregroundStyle(Color(.secondaryBraveLabel))

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
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(height: 24)
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

// MARK: - Basarunaa panel (front-only, pipeline ML à venir)

struct BasarunaaPanelView: View {
  @ObservedObject private var enabled = Preferences.Basarunaa.enabled
  @ObservedObject private var mode = Preferences.Basarunaa.mode
  #if DEBUG
  @ObservedObject private var faceThreshold = Preferences.Basarunaa.faceThreshold
  @ObservedObject private var bodyThreshold = Preferences.Basarunaa.bodyThreshold
  #endif

  /// Closure injected by the BVC to run the PoC analysis on the current tab.
  /// Returns a short status string for the UI. `nil` when no analyzable tab.
  let onDebugAnalyze: (() async -> String)?

  @State private var debugStatus: String = ""
  @State private var debugRunning: Bool = false

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
        .foregroundStyle(Color(.secondaryBraveLabel))

        // Mode segmented
        VStack(alignment: .leading, spacing: 6) {
          Text("Mode")
            .font(.subheadline.weight(.medium))
          Picker("Mode", selection: Binding(
            get: { mode.value },
            set: { mode.value = $0 }
          )) {
            Text("Off").tag("off")
            Text("Blur").tag("blur")
            Text("Strict").tag("strict")
          }
          .pickerStyle(.segmented)
          .disabled(!enabled.value)
        }
        .padding(.horizontal)

        #if DEBUG
        VStack(spacing: 12) {
          sliderRow(label: "Seuil visage (dev)", value: Binding(
            get: { faceThreshold.value },
            set: { faceThreshold.value = $0 }
          ))
          sliderRow(label: "Seuil corps (dev)", value: Binding(
            get: { bodyThreshold.value },
            set: { bodyThreshold.value = $0 }
          ))
        }
        .padding(.horizontal)
        #endif

        #if DEBUG
        VStack(spacing: 8) {
          Button {
            guard let onDebugAnalyze, !debugRunning else { return }
            debugStatus = "Analyse en cours…"
            debugRunning = true
            Task { @MainActor in
              let result = await onDebugAnalyze()
              debugStatus = result
              debugRunning = false
            }
          } label: {
            Text(debugRunning ? "Analyse…" : "PoC : analyser la page courante")
              .font(.subheadline.weight(.medium))
              .frame(maxWidth: .infinity)
              .padding(10)
              .background(Color.accentColor.opacity(onDebugAnalyze == nil || debugRunning ? 0.4 : 1.0))
              .foregroundColor(.white)
              .clipShape(RoundedRectangle(cornerRadius: 8))
          }
          .buttonStyle(.plain)
          .disabled(onDebugAnalyze == nil || debugRunning)

          if !debugStatus.isEmpty {
            Text(debugStatus)
              .font(.caption.monospaced())
              .foregroundColor(.secondary)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          Text("Résultat dans Console.app (subsystem: com.devndin.browther)")
            .font(.caption2)
            .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        #endif
      }
      .padding(.top, 16)
      .padding(.bottom, 16)
    }
    .frame(maxWidth: 360)
    .background(Color(.braveBackground))
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
        .disabled(!enabled.value)
    }
  }

  private var header: some View {
    HStack(alignment: .center, spacing: 8) {
      Image("basarunaa.icon.bg", bundle: .module)
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(width: 32, height: 32)
      Image("basarunaa.wordmark", bundle: .module)
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(height: 24)
    }
    .frame(minWidth: .zero, alignment: .center)
    .padding(.horizontal)
  }
}

class BasarunaaPanelViewController: UIHostingController<BasarunaaPanelView>,
  PopoverContentComponent
{
  init(onDebugAnalyze: (() async -> String)? = nil) {
    super.init(rootView: BasarunaaPanelView(onDebugAnalyze: onDebugAnalyze))
    preferredContentSize = CGSize(width: 360, height: 620)
  }

  @MainActor required dynamic init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}
