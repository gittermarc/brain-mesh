//
//  SettingsView+SyncSection.swift
//  BrainMesh
//
//  Created by Marc Fechner on 19.02.26.
//

import SwiftUI

extension SyncMaintenanceView {

    var syncSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                LabeledContent("Speicherstatus", value: syncRuntime.storageMode.title)

                Text(syncRuntime.storageMode.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Label(syncRuntime.storageMode.trustHint, systemImage: "checkmark.shield")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    LabeledContent("iCloud-Konto", value: syncRuntime.iCloudAccountStatusText)

                    if isCheckingICloudStatus {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                Text(syncRuntime.iCloudAccountStatusDetail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    Task { @MainActor in
                        await refreshICloudStatus()
                    }
                } label: {
                    Label("iCloud-Status prüfen", systemImage: "arrow.clockwise")
                }
                .font(.subheadline)
                .buttonStyle(.plain)
                .disabled(isCheckingICloudStatus)
            }
            .padding(.vertical, 2)

#if DEBUG
            LabeledContent("Container", value: SyncRuntime.containerIdentifier)
                .font(.footnote)
#endif

        } header: {
            Text("Sync")
        } footer: {
#if DEBUG
            Text("Debug-Builds nutzen die CloudKit-Development-Umgebung. Wenn iPhone und iPad unterschiedliche Build-Konfigurationen wie Debug, Release oder TestFlight verwenden, werden Daten nicht gegenseitig sichtbar.")
#else
            Text("Sync läuft über iCloud, wenn CloudKit verfügbar ist. Nutze auf allen Geräten dieselbe Apple-ID und sichere wichtige Graphen zusätzlich bewusst per Export.")
#endif
        }
    }
}
