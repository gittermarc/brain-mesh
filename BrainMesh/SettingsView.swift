//
//  SettingsView.swift
//  BrainMesh
//
//  Created by Marc Fechner on 10.02.26.
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var onboarding: OnboardingCoordinator

    @State private var isRebuildingImageCache: Bool = false
    @State private var isClearingAttachmentCache: Bool = false

    @State private var alertState: AlertState? = nil

    private struct AlertState: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "–"
    }

    var body: some View {
        List {
            Section("Hilfe") {
                Button {
                    onboarding.isPresented = true
                } label: {
                    Label("Onboarding anzeigen", systemImage: "questionmark.circle")
                }
            }

            Section("Wartung") {
                Button {
                    Task { @MainActor in
                        guard isRebuildingImageCache == false else { return }
                        isRebuildingImageCache = true
                        await ImageHydrator.forceRebuild(using: modelContext)
                        isRebuildingImageCache = false
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

                Button {
                    Task { @MainActor in
                        guard isClearingAttachmentCache == false else { return }
                        isClearingAttachmentCache = true
                        defer { isClearingAttachmentCache = false }

                        do {
                            try AttachmentStore.clearCache()
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
            }

            Section("Darstellung") {
                NavigationLink {
                    DisplaySettingsView()
                } label: {
                    Label("Darstellung", systemImage: "paintpalette")
                }
            }

            Section("Info") {
                LabeledContent("Version", value: appVersion)
                LabeledContent("Build", value: buildNumber)
            }
        }
        .navigationTitle("Einstellungen")
        .navigationBarTitleDisplayMode(.inline)
        .alert(item: $alertState) { state in
            Alert(
                title: Text(state.title),
                message: Text(state.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Fertig") { dismiss() }
            }
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(OnboardingCoordinator())
    }
}
