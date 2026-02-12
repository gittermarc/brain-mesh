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
        .task { ensureLocalCacheIfPossible() }
        .onChange(of: imageData) { _, _ in
            ensureLocalCacheIfPossible()
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
            if let ui = currentUIImage() {
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
                        ImageStore.delete(path: imagePath)
                        imagePath = nil
                        imageData = nil
                        try? modelContext.save()
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

    private func currentUIImage() -> UIImage? {
        // 1) Cache-Datei bevorzugen
        if let ui = ImageStore.loadUIImage(path: imagePath) { return ui }

        // 2) Fallback: direkt aus gesyncten Daten
        if let d = imageData, let ui = UIImage(data: d) { return ui }

        return nil
    }

    /// Wenn `imageData` vorhanden ist, aber Cache-Datei fehlt → schreibe sie.
    private func ensureLocalCacheIfPossible() {
        guard let d = imageData, !d.isEmpty else { return }

        // deterministischer Name (wichtig für Sync-Konfliktfreiheit)
        let filename = stableFilename()
        if imagePath != filename { imagePath = filename }

        if ImageStore.fileExists(path: imagePath) { return }

        do {
            _ = try ImageStore.saveJPEG(d, preferredName: filename)
        } catch {
            // Nicht fatal – Bild ist trotzdem via imageData verfügbar
        }

        // imagePath ggf. persistieren (damit andere Views stabil sind)
        try? modelContext.save()
    }

    // MARK: - Import

    @MainActor
    private func importPhoto(_ item: PhotosPickerItem) async {
        do {
            guard let raw = try await item.loadTransferable(type: Data.self) else {
                loadError = "Keine Bilddaten erhalten."
                return
            }

            // ✅ robustes Decode → verhindert „2266x0 image slot“
            guard let decoded = ImageImportPipeline.decodeImageSafely(from: raw, maxPixelSize: 2200) else {
                loadError = "Bild konnte nicht dekodiert werden."
                return
            }

            // ✅ CloudKit-freundlich: runter skalieren + stark komprimieren
            guard let jpeg = ImageImportPipeline.prepareJPEGForCloudKit(decoded) else {
                loadError = "JPEG-Erzeugung fehlgeschlagen."
                return
            }

            // deterministischer Dateiname
            let filename = stableFilename()

            // altes lokales File weg (falls vorhanden)
            ImageStore.delete(path: imagePath)

            // cloud: data setzen (synct)
            imageData = jpeg

            // local: cache schreiben + path setzen (deterministisch)
            _ = try ImageStore.saveJPEG(jpeg, preferredName: filename)
            imagePath = filename

            // ✅ wichtig: explizit speichern, damit SwiftData es sicher exportiert
            try? modelContext.save()

            pickerItem = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

}
