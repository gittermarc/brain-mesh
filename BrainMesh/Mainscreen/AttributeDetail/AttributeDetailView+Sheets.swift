//
//  AttributeDetailView+Sheets.swift
//  BrainMesh
//
//  P0.4 Split: Sheets / dialogs / routing modifiers
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

extension AttributeDetailView {

    @ViewBuilder
    func decorate<Content: View>(_ content: Content) -> some View {
        content
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: showGalleryBrowser) { isPresented in
                if !isPresented {
                    Task { @MainActor in
                        await reloadMediaPreview()
                    }
                }
            }
            .onChange(of: showAttachmentsManager) { isPresented in
                if !isPresented {
                    Task { @MainActor in
                        await reloadMediaPreview()
                    }
                }
            }
            .navigationTitle(attribute.name.isEmpty ? "Attribut" : attribute.name)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showRenameSheet) {
                NodeRenameSheet(
                    kindTitle: "Attribut",
                    originalName: attribute.name,
                    onSave: { newName in
                        try await renameAttribute(to: newName)
                    }
                )
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showRenameSheet = true
                        } label: {
                            Label("Umbenennen…", systemImage: "pencil")
                        }

                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            Label("Löschen", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Menü")
                }
            }
            .confirmationDialog(
                "Link hinzufügen",
                isPresented: $showLinkChooser,
                titleVisibility: .visible
            ) {
                Button("Link hinzufügen") { showAddLink = true }
                Button("Mehrere Links hinzufügen…") { showBulkLink = true }
                Button("Abbrechen", role: .cancel) {}
            }
            .confirmationDialog(
                "Datei hinzufügen",
                isPresented: $showAttachmentChooser,
                titleVisibility: .visible
            ) {
                Button("Datei auswählen") { isImportingFile = true }
                Button("Video aus Fotos") { isPickingVideo = true }
                Button("Anhänge verwalten") { showAttachmentsManager = true }
                Button("Abbrechen", role: .cancel) {}
            }
            .confirmationDialog(
                "Medien verwalten",
                isPresented: $showMediaManageChooser,
                titleVisibility: .visible
            ) {
                Button("Galerie verwalten") { showGalleryBrowser = true }
                Button("Anhänge verwalten") { showAttachmentsManager = true }
                Button("Abbrechen", role: .cancel) {}
            }
            .alert("Attribut löschen?", isPresented: $confirmDelete) {
                Button("Löschen", role: .destructive) {
                    deleteAttribute()
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Diese Löschung kann nicht rückgängig gemacht werden.")
            }
            .alert("BrainMesh", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .sheet(isPresented: $showGalleryBrowser) {
                NavigationStack {
                    PhotoGalleryBrowserView(
                        ownerKind: .attribute,
                        ownerID: attribute.id,
                        graphID: attribute.graphID,
                        mainImageData: Binding(
                            get: { attribute.imageData },
                            set: { attribute.imageData = $0 }
                        ),
                        mainImagePath: Binding(
                            get: { attribute.imagePath },
                            set: { attribute.imagePath = $0 }
                        ),
                        mainStableID: attribute.id
                    )
                }
            }
            .sheet(isPresented: $showAttachmentsManager) {
                NavigationStack {
                    NodeAttachmentsManageView(
                        ownerKind: .attribute,
                        ownerID: attribute.id,
                        graphID: attribute.graphID
                    )
                }
            }
            .fullScreenCover(item: $galleryViewerRequest) { req in
                PhotoGalleryViewerView(
                    ownerKind: .attribute,
                    ownerID: attribute.id,
                    graphID: attribute.graphID,
                    startAttachmentID: req.startAttachmentID,
                    mainImageData: Binding(
                        get: { attribute.imageData },
                        set: { attribute.imageData = $0 }
                    ),
                    mainImagePath: Binding(
                        get: { attribute.imagePath },
                        set: { attribute.imagePath = $0 }
                    ),
                    mainStableID: attribute.id
                )
            }
            .sheet(item: $attachmentPreviewSheet) { state in
                AttachmentPreviewSheet(
                    title: state.title,
                    url: state.url,
                    contentTypeIdentifier: state.contentTypeIdentifier,
                    fileExtension: state.fileExtension
                )
            }
            .background(
                VideoPickerPresenter(isPresented: $isPickingVideo) { result in
                    Task { @MainActor in
                        await handlePickedVideo(result)
                    }
                }
                .frame(width: 0, height: 0)
            )
            .background(
                VideoPlaybackPresenter(request: $videoPlayback)
                    .frame(width: 0, height: 0)
            )
            .fileImporter(
                isPresented: $isImportingFile,
                allowedContentTypes: [.item],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    importFile(from: url)
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
            .addLinkSheet(isPresented: $showAddLink, source: attribute.nodeRef, graphID: attribute.graphID)
            .bulkLinkSheet(isPresented: $showBulkLink, source: attribute.nodeRef, graphID: attribute.graphID)
            .sheet(isPresented: $showNotesEditor) {
                NavigationStack {
                    NodeNotesEditorView(
                        title: attribute.name.isEmpty ? "Notiz" : "Notiz – \(attribute.name)",
                        notes: Binding(
                            get: { attribute.notes },
                            set: { attribute.notes = $0 }
                        )
                    )
                }
            }
    }

    // MARK: - Rename

    @MainActor
    fileprivate func renameAttribute(to newName: String) async throws {
        let cleaned = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { return }

        let current = attribute.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned == current { return }

        attribute.name = cleaned
        try modelContext.save()

        await NodeRenameService.shared.relabelLinksAfterAttributeRename(
            attributeID: attribute.id,
            graphID: attribute.graphID
        )
    }

    func deleteAttribute() {
        modelContext.delete(attribute)
        try? modelContext.save()
        dismiss()
    }
}
