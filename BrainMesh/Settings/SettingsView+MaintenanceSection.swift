//
//  SettingsView+MaintenanceSection.swift
//  BrainMesh
//
//  Created by Marc Fechner on 10.02.26.
//

import SwiftUI

extension SettingsView {
    var maintenanceSection: some View {
        Section("Wartung") {
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    Task { @MainActor in
                        guard isRebuildingImageCache == false else { return }
                        isRebuildingImageCache = true
                        await ImageHydrator.shared.forceRebuild()
                        isRebuildingImageCache = false
                        refreshCacheSizes()
                        alertState = AlertState(
                            title: "Bildcache aktualisiert",
                            message: "Der lokale Bildcache wurde neu aufgebaut. Wenn du gerade Bilder geändert hast, sollte alles sofort korrekt angezeigt werden."
                        )
                    }
                } label: {
                    HStack {
                        Label("Bildcache neu aufbauen", systemImage: "arrow.clockwise")
                        Spacer()
                        if isRebuildingImageCache {
                            ProgressView()
                        }
                    }
                }
                .disabled(isRebuildingImageCache)

                Text("Aktuell: \(imageCacheSizeText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 30)
            }

            VStack(alignment: .leading, spacing: 4) {
                Button {
                    Task { @MainActor in
                        guard isClearingAttachmentCache == false else { return }
                        isClearingAttachmentCache = true
                        defer { isClearingAttachmentCache = false }

                        do {
                            try AttachmentStore.clearCache()
                            refreshCacheSizes()
                            alertState = AlertState(
                                title: "Anhänge-Cache bereinigt",
                                message: "Der lokale Anhänge-Cache wurde gelöscht. Deine Anhänge bleiben in der Datenbank und werden bei Bedarf wieder lokal für die Vorschau erstellt."
                            )
                        } catch {
                            alertState = AlertState(
                                title: "Anhänge-Cache",
                                message: "Der Cache konnte nicht gelöscht werden: \(error.localizedDescription)"
                            )
                        }
                    }
                } label: {
                    HStack {
                        Label("Anhänge-Cache bereinigen", systemImage: "paperclip")
                        Spacer()
                        if isClearingAttachmentCache {
                            ProgressView()
                        }
                    }
                }
                .disabled(isClearingAttachmentCache)

                Text("Aktuell: \(attachmentCacheSizeText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 30)
            }
        }
    }
}
