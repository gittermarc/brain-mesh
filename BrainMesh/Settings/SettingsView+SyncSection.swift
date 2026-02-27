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
            LabeledContent("Status", value: syncRuntime.storageMode.title)

            VStack(alignment: .leading, spacing: 4) {
                LabeledContent("iCloud", value: syncRuntime.iCloudAccountStatusText)

                Button {
                    Task { @MainActor in
                        await syncRuntime.refreshAccountStatus()
                    }
                } label: {
                    Label("iCloud-Status prüfen", systemImage: "arrow.clockwise")
                }
                .font(.subheadline)
                .buttonStyle(.plain)
                .padding(.leading, 2)
            }

#if DEBUG
            LabeledContent("Container", value: SyncRuntime.containerIdentifier)
                .font(.footnote)
#endif

        } header: {
            Text("Sync")
        } footer: {
#if DEBUG
            Text("Debug-Builds nutzen die CloudKit-Development-Umgebung. Wenn iPhone und iPad unterschiedliche Build-Konfigurationen (Debug vs. Release/TestFlight) verwenden, werden Daten nicht gegenseitig sichtbar.")
#else
            Text("Sync läuft über iCloud. Wenn du mehrere Geräte nutzt, stelle sicher, dass du überall mit derselben Apple‑ID angemeldet bist.")
#endif
        }
    }
}
