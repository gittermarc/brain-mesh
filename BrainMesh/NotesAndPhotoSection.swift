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
import ImageIO

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
        Section("Notizen") {
            TextEditor(text: $notes)
                .frame(minHeight: 120)
        }

        Section("Bild") {
            if let ui = currentUIImage() {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.secondary.opacity(0.25)))
                    .padding(.vertical, 6)
                    .onTapGesture {
                        fullscreenImage = ui
                        showFullscreen = true
                    }

                Button(role: .destructive) {
                    ImageStore.delete(path: imagePath)
                    imagePath = nil
                    imageData = nil
                    try? modelContext.save()
                } label: {
                    Label("Bild entfernen", systemImage: "trash")
                }
            } else {
                Text("Kein Bild ausgewählt.")
                    .foregroundStyle(.secondary)
            }

            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label((imageData == nil && imagePath == nil) ? "Bild auswählen" : "Bild ersetzen",
                      systemImage: "photo")
            }
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
            guard let decoded = decodeImageSafely(from: raw) else {
                loadError = "Bild konnte nicht dekodiert werden."
                return
            }

            // ✅ CloudKit-freundlich: runter skalieren + stark komprimieren
            guard let jpeg = prepareJPEGForCloudKit(decoded) else {
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

    // MARK: - Decode + compression

    private func decodeImageSafely(from data: Data) -> UIImage? {
        let cfData = data as CFData
        guard let src = CGImageSourceCreateWithData(cfData, nil) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            // Max Pixel, damit wir keine riesen 12MP+ Bilder in RAM ziehen
            kCGImageSourceThumbnailMaxPixelSize: 2200
        ]

        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else { return nil }
        let ui = UIImage(cgImage: cg)

        // Hard guard gegen „0 Höhe/Weite“
        if ui.size.width < 1 || ui.size.height < 1 { return nil }

        return ui
    }

    private func prepareJPEGForCloudKit(_ image: UIImage) -> Data? {
        // Ziel: deutlich unter 1MB bleiben (CloudKit Record-Limit). Lieber klein als „geht nicht“.
        // 250–300KB ist meistens safe.
        let targetBytes = 280_000

        // 1) Resize (maxDimension)
        var maxDim: CGFloat = 1400
        var resized = image.resizedToFit(maxDimension: maxDim)

        // 2) Compress iterativ
        var q: CGFloat = 0.78
        var data = resized.jpegData(compressionQuality: q)

        func tooBig(_ d: Data?) -> Bool {
            guard let d else { return true }
            return d.count > targetBytes
        }

        // Qualität runter
        while tooBig(data) && q > 0.38 {
            q -= 0.08
            data = resized.jpegData(compressionQuality: q)
        }

        // Wenn immer noch zu groß: nochmal kleiner skalieren und erneut komprimieren
        if tooBig(data) {
            maxDim = 1100
            resized = resized.resizedToFit(maxDimension: maxDim)
            q = 0.68
            data = resized.jpegData(compressionQuality: q)

            while tooBig(data) && q > 0.34 {
                q -= 0.08
                data = resized.jpegData(compressionQuality: q)
            }
        }

        return data
    }
}

private extension UIImage {
    func resizedToFit(maxDimension: CGFloat) -> UIImage {
        let w = size.width
        let h = size.height
        let maxSide = max(w, h)

        guard maxSide > maxDimension, maxSide > 0, w > 0, h > 0 else { return self }

        let scale = maxDimension / maxSide
        let newSize = CGSize(width: max(1, w * scale), height: max(1, h * scale))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
