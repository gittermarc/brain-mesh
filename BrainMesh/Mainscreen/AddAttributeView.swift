//
//  AddAttributeView.swift
//  BrainMesh
//
//  Created by Marc Fechner on 10.02.26.
//

import SwiftUI
import SwiftData
import PhotosUI
import UIKit

struct AddAttributeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var systemModals: SystemModalCoordinator

    @Bindable var entity: MetaEntity

    @StateObject private var draft = NodeCreateDraft()

    @State private var didCreate: Bool = false
    @State private var didMarkSystemModal: Bool = false

    private var canSubmit: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                previewHeader

                basicsSection

                notesAndPhotoSection

                Section {
                    Text("Attribute sind frei benennbar.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Neues Attribut")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        Task { await draft.cleanupOrphanedLocalCacheIfNeeded() }
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    Button {
                        save()
                    } label: {
                        Text("Attribut hinzufügen")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!canSubmit)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
            }
            .photosPicker(
                isPresented: Binding(
                    get: { draft.isPickingPhoto },
                    set: { draft.isPickingPhoto = $0 }
                ),
                selection: Binding(
                    get: { draft.pickerItem },
                    set: { draft.pickerItem = $0 }
                ),
                matching: .images
            )
            .onChange(of: draft.pickerItem) { _, newItem in
                guard let newItem else { return }
                Task { await draft.importPhoto(newItem) }
            }
            .onChange(of: draft.isPickingPhoto) { _, isPresented in
                if isPresented {
                    if !didMarkSystemModal {
                        didMarkSystemModal = true
                        systemModals.beginSystemModal()
                    }
                } else {
                    if didMarkSystemModal {
                        didMarkSystemModal = false
                        systemModals.endSystemModal()
                    }
                }
            }
            .onDisappear {
                if didMarkSystemModal {
                    didMarkSystemModal = false
                    systemModals.endSystemModal()
                }

                if !didCreate {
                    Task { await draft.cleanupOrphanedLocalCacheIfNeeded() }
                }
            }
            .alert("Bild konnte nicht geladen werden", isPresented: Binding(
                get: { draft.loadError != nil },
                set: { if !$0 { draft.loadError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(draft.loadError ?? "")
            }
        }
    }

    private var previewHeader: some View {
        Section {
            NodeCreatePreviewHeader(
                kindTitle: "Attribut",
                name: draft.name,
                iconSymbolName: draft.iconSymbolName,
                subtitle: entity.name.isEmpty ? nil : "Für \(entity.name)",
                previewImage: draft.previewUIImage
            )
            .padding(.vertical, 6)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
        .listSectionSeparator(.hidden)
    }

    private var basicsSection: some View {
        Section {
            TextField("Name (z.B. 2023)", text: Binding(
                get: { draft.name },
                set: { draft.name = $0 }
            ))
            .textInputAutocapitalization(.words)

            IconPickerRow(
                title: "Icon auswählen",
                symbolName: Binding(
                    get: { draft.iconSymbolName },
                    set: { draft.iconSymbolName = $0 }
                )
            )
        } header: {
            DetailSectionHeader(
                title: "Basics",
                systemImage: "sparkles",
                subtitle: "Optional: Icon, Notiz & Headerbild."
            )
        }
    }

    private var notesAndPhotoSection: some View {
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
    }

    private var notesEditor: some View {
        ZStack(alignment: .topLeading) {
            if draft.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Notizen hinzufügen …")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 8)
            }
            TextEditor(text: Binding(
                get: { draft.notes },
                set: { draft.notes = $0 }
            ))
            .frame(minHeight: 140)
        }
    }

    private var photoBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let ui = draft.previewUIImage {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.secondary.opacity(0.25)))
                    .padding(.top, 6)
            } else {
                Text("Kein Headerbild ausgewählt.")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button {
                    draft.isPickingPhoto = true
                } label: {
                    Label(draft.hasPhoto() ? "Headerbild ersetzen" : "Headerbild auswählen", systemImage: "photo")
                }

                if draft.hasPhoto() {
                    Button(role: .destructive) {
                        draft.removePhoto()
                    } label: {
                        Label("Entfernen", systemImage: "trash")
                    }
                }

                Spacer(minLength: 0)
            }
        }
    }

    private func save() {
        let cleaned = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        let attr = MetaAttribute(name: cleaned, owner: nil, graphID: entity.graphID, iconSymbolName: draft.iconSymbolName)
        attr.id = draft.stableID
        attr.notes = draft.notes

        if let d = draft.imageData, !d.isEmpty {
            attr.imageData = d
            attr.imagePath = (draft.imagePath?.isEmpty == false) ? draft.imagePath : draft.stableFilename()
        }

        modelContext.insert(attr)
        entity.addAttribute(attr)

        try? modelContext.save()

        didCreate = true
        dismiss()
    }
}
