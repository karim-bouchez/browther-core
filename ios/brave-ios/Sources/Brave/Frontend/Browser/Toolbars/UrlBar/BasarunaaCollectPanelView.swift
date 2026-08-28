// Copyright 2026 dev&din. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Basarunaa
import Preferences
import SwiftUI

/// Écran de contrôle de la collecte de corpus (opt-in).
///
/// Équivalent de la page `collect.html` de l'extension desktop, avec une
/// différence de principe : **cet écran ne peut rien activer**. La collecte
/// s'allume dans le panel → Debug, et nulle part ailleurs.
///
/// ── Ce qu'il affiche vient DU COLLECTEUR, pas des préférences ──────────────
/// Desktop a passé une semaine avec un écran qui annonçait « Collecte : active »
/// en lisant le STOCKAGE pendant que le collecteur, lui, n'avait jamais reçu sa
/// configuration : 349 images vues, zéro présentée, aucune raison de rejet, et
/// rien à l'écran pour le dire. Ici l'état affiché est celui que le collecteur
/// rapporte lui-même (`Collector.status()`) — c'est la seule lecture qui ne
/// peut pas mentir.
struct BasarunaaCollectPanelView: View {
  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var device = Preferences.Basarunaa.collectDevice
  @ObservedObject private var videoScenes = Preferences.Basarunaa.collectVideoScenes

  @State private var status: Collector.Status?
  @State private var exporting = false
  @State private var lastArchive: String?
  @State private var showPurgeConfirm = false

  var body: some View {
    NavigationView {
      Form {
        stateSection
        deviceSection
        countersSection
        strataSection
        dropsSection
        actionsSection
      }
      .navigationTitle(Text(verbatim: "Collecte de corpus"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button { dismiss() } label: { Text(verbatim: "OK") }
        }
      }
    }
    .task { await refresh() }
  }

  // MARK: - Sections

  @ViewBuilder private var stateSection: some View {
    Section {
      if let s = status {
        LabeledContent {
          Text(verbatim: s.ready && s.enabled ? "active" : "inactive")
            .foregroundColor(s.ready && s.enabled ? .green : .secondary)
        } label: {
          Text(verbatim: "Collecte, côté collecteur")
        }
        if let error = s.initError {
          // Une panne qu'on voit mais qui ne dit rien coûte plus cher qu'une
          // panne franche : elle oriente le diagnostic vers la mauvaise pièce.
          // D'où la cause affichée telle quelle, même illisible.
          Label(error, systemImage: "xmark.octagon.fill")
            .font(.caption)
            .foregroundColor(.red)
        }
        // `reçues` distingue « rien à collecter » de « le pipeline n'appelle
        // même pas le collecteur ». Sans ce compteur les deux cas affichent
        // des zéros et se ressemblent trait pour trait.
        LabeledContent {
          Text(verbatim: "\(s.received)")
        } label: {
          Text(verbatim: "Images reçues (cette session)")
        }
        LabeledContent {
          Text(verbatim: "\(s.inflight) en cours · \(s.pending) en attente")
        } label: {
          Text(verbatim: "File")
        }
      } else {
        Text(verbatim: "Lecture de l'état…").foregroundColor(.secondary)
      }
    } header: {
      Text(verbatim: "État")
    } footer: {
      Text(
        verbatim:
          "L'interrupteur est dans le panel Basarunaa → Debug. Cet écran ne peut pas activer la collecte."
      )
    }
  }

  @ViewBuilder private var deviceSection: some View {
    Section {
      TextField(
        "karim",
        text: Binding(get: { device.value }, set: { device.value = $0 })
      )
      .textInputAutocapitalization(.never)
      .autocorrectionDisabled()

      Toggle(isOn: Binding(get: { videoScenes.value }, set: { videoScenes.value = $0 })) {
        VStack(alignment: .leading, spacing: 2) {
          Text(verbatim: "Échantillonner les vidéos")
          Text(verbatim: "Une image par scène. À couper en premier si une vidéo saccade.")
            .font(.caption2).foregroundColor(.secondary)
        }
      }
    } header: {
      Text(verbatim: "Appareil")
    } footer: {
      if device.value.isEmpty {
        Text(
          verbatim:
            "⚠️ Sans nom, les archives des deux téléphones sont indistinguables — et c'est sans recours pour les images déjà collectées."
        )
        .foregroundColor(.orange)
      } else {
        Text(verbatim: "Préfixe les archives et marque chaque ligne du manifeste.")
      }
    }
  }

  @ViewBuilder private var countersSection: some View {
    if let s = status {
      Section {
        LabeledContent {
          Text(verbatim: "\(s.stats.totalStored)")
        } label: {
          Text(verbatim: "Images au corpus")
        }
        LabeledContent {
          Text(verbatim: Self.bytes(s.stats.totalBytes))
        } label: {
          Text(verbatim: "Volume total")
        }
        LabeledContent {
          Text(verbatim: "\(s.stats.imagesToday) · \(Self.bytes(s.stats.bytesToday))")
        } label: {
          Text(verbatim: "Aujourd'hui")
        }
        LabeledContent {
          Text(verbatim: "\(s.stats.videoFramesToday)")
        } label: {
          Text(verbatim: "Scènes vidéo aujourd'hui")
        }
        LabeledContent {
          Text(verbatim: "\(Self.bytes(s.stats.spoolBytes)) · \(s.stats.zips) archive(s)")
        } label: {
          Text(verbatim: "Tampon")
        }
        if !s.stats.budgetHitAt.isEmpty {
          Label(
            "Plafond quotidien atteint à \(s.stats.budgetHitAt)",
            systemImage: "gauge.with.dots.needle.100percent"
          )
          .font(.caption)
          .foregroundColor(.orange)
        }
      } header: {
        Text(verbatim: "Compteurs")
      } footer: {
        // Le tampon n'est écrit qu'au seuil (60 Mo ou 6 h). Les premières
        // heures, le dossier reste donc vide alors que la collecte tourne —
        // c'est normal, et le dire ici évite un diagnostic pour rien.
        Text(
          verbatim:
            "Une archive est écrite à 60 Mo de tampon ou toutes les 6 h. Les premières heures, le dossier reste vide : c'est normal. « Exporter maintenant » force l'écriture."
        )
      }
    }
  }

  @ViewBuilder private var strataSection: some View {
    if let s = status, !s.stats.offered.isEmpty {
      Section {
        ForEach(CollectStratum.allCases, id: \.rawValue) { stratum in
          let key = stratum.rawValue
          let offered = s.stats.offered[key] ?? 0
          if offered > 0 {
            LabeledContent {
              Text(
                verbatim:
                  "\(s.stats.stored[key] ?? 0) / \(s.stats.attempted[key] ?? 0) / \(offered)"
              )
              .monospacedDigit()
            } label: {
              Text(verbatim: key)
            }
          }
        }
      } header: {
        Text(verbatim: "Strates — gardées / tirées / présentées")
      } footer: {
        // L'écart tirées → gardées est l'ATTRITION post-tirage (fetch en échec,
        // doublon, image non décodable). Elle n'est pas dans `p`, donc elle ne
        // se corrige pas par pondération : la seule façon de savoir si elle est
        // négligeable est de la regarder.
        Text(
          verbatim:
            "L'écart entre « tirées » et « gardées » est l'attrition : elle n'entre pas dans la pondération, d'où l'intérêt de la voir."
        )
      }
    }
  }

  @ViewBuilder private var dropsSection: some View {
    if let s = status, !s.stats.dropped.isEmpty {
      Section {
        ForEach(s.stats.dropped.sorted(by: { $0.value > $1.value }), id: \.key) { item in
          LabeledContent {
            Text(verbatim: "\(item.value)").monospacedDigit()
          } label: {
            Text(verbatim: item.key)
          }
        }
      } header: {
        Text(verbatim: "Raisons de rejet")
      } footer: {
        Text(
          verbatim:
            "`token-url` = image derrière une URL signée, écartée volontairement. Si ce compteur explose sur un site qui compte, c'est un signal."
        )
      }
    }
  }

  @ViewBuilder private var actionsSection: some View {
    Section {
      Button {
        Task {
          exporting = true
          lastArchive = await Collector.shared.flush(reason: "manuel")
          exporting = false
          await refresh()
        }
      } label: {
        HStack {
          Text(verbatim: "Exporter maintenant")
          if exporting {
            Spacer()
            ProgressView()
          }
        }
      }
      .disabled(exporting || (status?.stats.spoolBytes ?? 0) == 0)

      Button(role: .destructive) {
        showPurgeConfirm = true
      } label: {
        Text(verbatim: "Tout purger")
      }

      Button {
        Task { await refresh() }
      } label: {
        Text(verbatim: "Rafraîchir")
      }
    } header: {
      Text(verbatim: "Actions")
    } footer: {
      VStack(alignment: .leading, spacing: 4) {
        if let name = lastArchive {
          Text(verbatim: "Écrite : \(name)").foregroundColor(.green)
        }
        Text(
          verbatim:
            "Les archives sont dans Fichiers → Sur mon iPhone → Browther → basarunaa-corpus. « Tout purger » vide le tampon et les index ; les archives déjà écrites ne sont pas touchées."
        )
      }
    }
    .confirmationDialog(
      Text(verbatim: "Vider le tampon et les index ?"),
      isPresented: $showPurgeConfirm,
      titleVisibility: .visible
    ) {
      Button(role: .destructive) {
        Task {
          await Collector.shared.purge()
          await refresh()
        }
      } label: {
        Text(verbatim: "Purger")
      }
    } message: {
      Text(
        verbatim:
          "Les images encore dans le tampon seront perdues. Les archives déjà écrites restent."
      )
    }
  }

  // MARK: - Utilitaires

  private func refresh() async {
    status = await Collector.shared.status()
  }

  private static func bytes(_ n: Int) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file)
  }
}
