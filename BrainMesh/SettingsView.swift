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
    @State private var showImageCacheAlert: Bool = false

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
                        showImageCacheAlert = true
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
        .alert("Bildcache aktualisiert", isPresented: $showImageCacheAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Der lokale Bildcache wurde neu aufgebaut. Wenn du gerade Bilder geändert hast, sollte alles sofort korrekt angezeigt werden.")
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
