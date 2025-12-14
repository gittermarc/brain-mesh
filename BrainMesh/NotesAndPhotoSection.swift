//
//  NotesAndPhotoSection.swift
//  BrainMesh
//
//  Created by Marc Fechner on 14.12.25.
//

import SwiftUI
import PhotosUI
import UIKit

struct NotesAndPhotoSection: View {
    @Binding var notes: String
    @Binding var imagePath: String?

    @State private var pickerItem: PhotosPickerItem?
    @State private var loadError: String?

    var body: some View {
        Section("Notizen") {
            TextEditor(text: $notes)
                .frame(minHeight: 120)
        }

        Section("Bild") {
            if let ui = ImageStore.loadUIImage(path: imagePath) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.secondary.opacity(0.25)))
                    .padding(.vertical, 6)

                Button(role: .destructive) {
                    ImageStore.delete(path: imagePath)
                    imagePath = nil
                } label: {
                    Label("Bild entfernen", systemImage: "trash")
                }
            } else {
                Text("Kein Bild ausgewählt.")
                    .foregroundStyle(.secondary)
            }

            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label(imagePath == nil ? "Bild auswählen" : "Bild ersetzen", systemImage: "photo")
            }
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
    }

    @MainActor
    private func importPhoto(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                loadError = "Keine Bilddaten erhalten."
                return
            }
            guard let ui = UIImage(data: data) else {
                loadError = "Bildformat nicht unterstützt."
                return
            }
            guard let jpeg = ui.jpegData(compressionQuality: 0.85) else {
                loadError = "JPEG-Konvertierung fehlgeschlagen."
                return
            }

            // altes Bild löschen, damit kein Müll liegen bleibt
            ImageStore.delete(path: imagePath)

            let newPath = try ImageStore.saveJPEG(jpeg)
            imagePath = newPath
            pickerItem = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}
