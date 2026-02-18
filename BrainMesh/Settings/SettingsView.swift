//
//  SettingsView.swift
//  BrainMesh
//
//  Created by Marc Fechner on 10.02.26.
//

import Foundation
import SwiftUI
import SwiftData

struct SettingsView: View {
    let showDoneButton: Bool

    init(showDoneButton: Bool = false) {
        self.showDoneButton = showDoneButton
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var onboarding: OnboardingCoordinator

    @AppStorage(VideoImportPreferences.compressVideosOnImportKey)
    private var compressVideosOnImport: Bool = VideoImportPreferences.defaultCompressVideosOnImport

    @AppStorage(VideoImportPreferences.videoCompressionQualityKey)
    private var videoCompressionQualityRaw: String = VideoImportPreferences.defaultQuality.rawValue

    @State private var isRebuildingImageCache: Bool = false
    @State private var isClearingAttachmentCache: Bool = false

    @State private var imageCacheSizeText: String = "—"
    @State private var attachmentCacheSizeText: String = "—"

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

    private var qualityBinding: Binding<VideoCompression.Quality> {
        Binding(
            get: {
                VideoCompression.Quality(rawValue: videoCompressionQualityRaw) ?? VideoImportPreferences.defaultQuality
            },
            set: { newValue in
                videoCompressionQualityRaw = newValue.rawValue
            }
        )
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

            Section {
                Toggle("Videos beim Import komprimieren", isOn: $compressVideosOnImport)

                Picker("Qualität", selection: qualityBinding) {
                    ForEach(VideoCompression.Quality.allCases) { q in
                        Text(q.title).tag(q)
                    }
                }
                .disabled(!compressVideosOnImport)
            } header: {
                Text("Import")
            } footer: {
                Text("Wenn aktiv, werden Videos nur dann komprimiert, wenn sie größer als 25 MB sind. Kleinere Videos bleiben unverändert. \n\nTipp: \"Hoch\" behält mehr Qualität (kann aber eher scheitern, wenn das Video selbst nach Komprimierung nicht unter 25 MB passt). \"Klein\" ist am sparsamsten.")
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

            SettingsAboutSection()
        }
        .navigationTitle("Einstellungen")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            refreshCacheSizes()
        }
        .alert(item: $alertState) { state in
            Alert(
                title: Text(state.title),
                message: Text(state.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .toolbar {
            if showDoneButton {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }

    private func refreshCacheSizes() {
        Task.detached(priority: .utility) {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file

            let imageBytes = (try? ImageStore.cacheSizeBytes()) ?? 0
            let attachmentBytes = (try? AttachmentStore.cacheSizeBytes()) ?? 0

            let imageText = formatter.string(fromByteCount: imageBytes)
            let attachmentText = formatter.string(fromByteCount: attachmentBytes)

            await MainActor.run {
                imageCacheSizeText = imageText
                attachmentCacheSizeText = attachmentText
            }
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView(showDoneButton: false)
            .environmentObject(OnboardingCoordinator())
    }
}
