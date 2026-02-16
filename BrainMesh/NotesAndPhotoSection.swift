//
//  NotesAndPhotoSection.swift
//  BrainMesh
//
//  Created by Marc Fechner on 14.12.25.
//

import SwiftUI
import SwiftData
import PhotosUI
import UIKit

struct NotesAndPhotoSection: View {
    @Environment(\.modelContext) private var modelContext

    @Binding var notes: String

    // ✅ CloudKit-sync (JPEG bytes)
    @Binding var imageData: Data?

    // ✅ Local cache filename (synct mit, aber deterministisch)
    @Binding var imagePath: String?

    /// ✅ stabiler Schlüssel: Dateiname = "<stableID>.jpg"
    let stableID: UUID

    @State private var pickerItem: PhotosPickerItem?
    @State private var loadError: String?

    // Display cache (avoid disk reads inside `body`)
    @State private var previewUIImage: UIImage?

    // Fullscreen preview
    @State private var showFullscreen = false
    @State private var fullscreenImage: UIImage?

    var body: some View {
        Section {
            notesEditor
            photoBlock
        } header: {
            DetailSectionHeader(
                title: "Notizen & Bild",
                systemImage: "pencil.and.outline",
                subtitle: "Notizen sind durchsuchbar. Bilder werden iCloud-schonend gespeichert."
            )
        }
        .task {
            await ensureLocalCacheIfPossibleAsync()
            await refreshPreviewImageAsync()
        }
        .onChange(of: imageData) { _, _ in
            Task {
                await ensureLocalCacheIfPossibleAsync()
                await refreshPreviewImageAsync()
            }
        }
        .onChange(of: imagePath) { _, _ in
            Task { await refreshPreviewImageAsync() }
        }
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem else { return }
            Task { await importPhoto(newItem) }
        }
        .alert("Bild konnte nicht geladen werden", isPresented: Binding(
            get: { loadError != nil },
            set: { if !$0 { loadError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(loadError ?? "")
        }
        .fullScreenCover(isPresented: $showFullscreen) {
            if let img = fullscreenImage {
                FullscreenPhotoView(image: img)
            }
        }
    }

    private var notesEditor: some View {
        ZStack(alignment: .topLeading) {
            if notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Notizen hinzufügen …")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 8)
            }
            TextEditor(text: $notes)
                .frame(minHeight: 140)
        }
    }

    private var photoBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let ui = previewUIImage {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.secondary.opacity(0.25)))
                    .padding(.top, 6)
                    .onTapGesture {
                        fullscreenImage = ui
                        showFullscreen = true
                    }
            } else {
                Text("Kein Bild ausgewählt.")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label((imageData == nil && imagePath == nil) ? "Bild auswählen" : "Bild ersetzen",
                          systemImage: "photo")
                }

                if imageData != nil || (imagePath?.isEmpty == false) {
                    Button(role: .destructive) {
                        let oldPath = imagePath
                        imagePath = nil
                        imageData = nil
                        previewUIImage = nil

                        Task {
                            await ImageStore.deleteAsync(path: oldPath)
                            await MainActor.run { try? modelContext.save() }
                        }
                    } label: {
                        Label("Entfernen", systemImage: "trash")
                    }
                }

                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Display / cache

    private func stableFilename() -> String {
        "\(stableID.uuidString).jpg"
    }

    private func refreshPreviewImageAsync() async {
        // Prefer local file cache
        if let path = imagePath, !path.isEmpty {
            if let ui = await ImageStore.loadUIImageAsync(path: path) {
                await MainActor.run { previewUIImage = ui }
                return
            }
        }

        // Fallback: synced bytes
        if let d = imageData, !d.isEmpty {
            let ui = UIImage(data: d)
            await MainActor.run { previewUIImage = ui }
            return
        }

        await MainActor.run { previewUIImage = nil }
    }

    /// If `imageData` exists but the deterministic cache file is missing, write it off-main.
    private func ensureLocalCacheIfPossibleAsync() async {
        guard let d = imageData, !d.isEmpty else { return }

        let filename = stableFilename()

        // Keep the path deterministic (important for sync conflict freedom)
        if imagePath != filename {
            await MainActor.run { imagePath = filename }
        }

        if ImageStore.fileExists(path: filename) {
            return
        }

        do {
            _ = try await ImageStore.saveJPEGAsync(d, preferredName: filename)
        } catch {
            // Not fatal – image is still available via `imageData`.
        }

        await MainActor.run { try? modelContext.save() }
    }

    // MARK: - Import

    @MainActor
    private func importPhoto(_ item: PhotosPickerItem) async {
        do {
            guard let raw = try await item.loadTransferable(type: Data.self) else {
                loadError = "Keine Bilddaten erhalten."
                return
            }

            let filename = stableFilename()
            let oldPath = imagePath

            let processed = await Task.detached(priority: .userInitiated) { () -> (jpeg: Data, preview: UIImage)? in
                guard let decoded = ImageImportPipeline.decodeImageSafely(from: raw, maxPixelSize: 2200) else {
                    return nil
                }
                guard let jpeg = ImageImportPipeline.prepareJPEGForCloudKit(decoded) else {
                    return nil
                }
                let preview = UIImage(data: jpeg) ?? decoded
                return (jpeg: jpeg, preview: preview)
            }.value

            guard let processed else {
                loadError = "Bild konnte nicht dekodiert werden."
                return
            }

            imageData = processed.jpeg
            imagePath = filename
            previewUIImage = processed.preview

            if let oldPath, !oldPath.isEmpty, oldPath != filename {
                await ImageStore.deleteAsync(path: oldPath)
            }

            do {
                _ = try await ImageStore.saveJPEGAsync(processed.jpeg, preferredName: filename)
                ImageStore.cacheUIImage(processed.preview, path: filename)
            } catch {
                // CloudKit sync still works via `imageData`.
            }

            try? modelContext.save()
            pickerItem = nil

        } catch {
            loadError = error.localizedDescription
        }
    }
}
