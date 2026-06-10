//
//  SettingsView+MaintenanceSection.swift
//  BrainMesh
//
//  Created by Marc Fechner on 10.02.26.
//

import SwiftUI

extension SyncMaintenanceView {
    var maintenanceSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    Task { @MainActor in
                        guard isMaintenanceBusy == false else { return }
                        isRebuildingImageCache = true
                        defer { isRebuildingImageCache = false }

                        await ImageHydrator.shared.forceRebuild()
                        refreshCacheSizes()
                        alertState = AlertState(
                            title: "Bildcache aktualisiert",
                            message: "Der lokale Bildcache wurde neu aufgebaut. Originalbilder und Graph-Daten bleiben erhalten. Wenn Vorschaubilder gefehlt haben, sollten sie nach und nach wieder erscheinen."
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
                .disabled(isMaintenanceBusy)

                Text("Aktuell: \(imageCacheSizeText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 30)

                Text("Erstellt lokale Vorschaudateien neu. Die in BrainMesh gespeicherten Bilder werden dadurch nicht gelöscht.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 30)
            }

            VStack(alignment: .leading, spacing: 6) {
                Button {
                    Task { @MainActor in
                        guard isMaintenanceBusy == false else { return }
                        isClearingAttachmentCache = true
                        defer { isClearingAttachmentCache = false }

                        do {
                            try AttachmentStore.clearCache()
                            refreshCacheSizes()
                            alertState = AlertState(
                                title: "Anhänge-Cache bereinigt",
                                message: "Der lokale Anhänge-Cache wurde gelöscht. Deine Anhänge bleiben in SwiftData erhalten und werden bei Bedarf wieder lokal für die Vorschau erstellt."
                            )
                        } catch {
#if DEBUG
                            print("Attachment cache clear failed: \(error)")
#endif
                            alertState = AlertState(
                                title: "Anhänge-Cache",
                                message: "Der lokale Cache konnte gerade nicht bereinigt werden. Deine Anhänge bleiben erhalten. Prüfe den freien Speicher und versuche es erneut."
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
                .disabled(isMaintenanceBusy)

                Text("Aktuell: \(attachmentCacheSizeText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 30)

                Text("Löscht nur lokale Vorschau- und Arbeitsdateien. Die eigentlichen Anhänge bleiben in der Datenbank und können erneut vorbereitet werden.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 30)
            }
        } header: {
            Text("Wartung")
        } footer: {
            Text("Diese Werkzeuge reparieren lokale Cache-Dateien. Sie verändern keine Graph-Struktur und ersetzen kein Backup.")
        }
    }
}
