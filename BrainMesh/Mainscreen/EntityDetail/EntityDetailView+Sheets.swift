//
//  EntityDetailView+Sheets.swift
//  BrainMesh
//
//  P0.3 Split: Sheets / dialogs / routing modifiers
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct AttachmentPreviewSheetState: Identifiable {
    let url: URL
    let title: String
    let contentTypeIdentifier: String
    let fileExtension: String

    var id: String { url.absoluteString }
}



struct NodeAttachmentsManageView: View {
    let ownerKind: NodeKind
    let ownerID: UUID
    let graphID: UUID?

    var body: some View {
        List {
            AttachmentsSection(ownerKind: ownerKind, ownerID: ownerID, graphID: graphID)
        }
        .navigationTitle("Anhänge")
        .navigationBarTitleDisplayMode(.inline)
    }
}



extension EntityDetailView {

    @ViewBuilder
    func decorate<Content: View>(_ content: Content) -> some View {
        content
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(entity.name.isEmpty ? "Entität" : entity.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
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
            .alert("Entität löschen?", isPresented: $confirmDelete) {
                Button("Löschen", role: .destructive) {
                    deleteEntity()
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
            .sheet(isPresented: $showAddAttribute) {
                AddAttributeView(entity: entity)
            }
            .sheet(isPresented: $showGalleryBrowser) {
                NavigationStack {
                    PhotoGalleryBrowserView(
                        ownerKind: .entity,
                        ownerID: entity.id,
                        graphID: entity.graphID,
                        mainImageData: Binding(
                            get: { entity.imageData },
                            set: { entity.imageData = $0 }
                        ),
                        mainImagePath: Binding(
                            get: { entity.imagePath },
                            set: { entity.imagePath = $0 }
                        ),
                        mainStableID: entity.id
                    )
                }
            }
            .sheet(isPresented: $showAttachmentsManager) {
                NavigationStack {
                    NodeAttachmentsManageView(
                        ownerKind: .entity,
                        ownerID: entity.id,
                        graphID: entity.graphID
                    )
                }
            }
            .fullScreenCover(item: $galleryViewerRequest) { req in
                PhotoGalleryViewerView(
                    ownerKind: .entity,
                    ownerID: entity.id,
                    graphID: entity.graphID,
                    startAttachmentID: req.startAttachmentID,
                    mainImageData: Binding(
                        get: { entity.imageData },
                        set: { entity.imageData = $0 }
                    ),
                    mainImagePath: Binding(
                        get: { entity.imagePath },
                        set: { entity.imagePath = $0 }
                    ),
                    mainStableID: entity.id
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
                    importFile(from: url, ownerKind: .entity, ownerID: entity.id, graphID: entity.graphID)
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
            .addLinkSheet(isPresented: $showAddLink, source: entity.nodeRef, graphID: entity.graphID)
            .bulkLinkSheet(isPresented: $showBulkLink, source: entity.nodeRef, graphID: entity.graphID)
            .sheet(isPresented: $showNotesEditor) {
                NavigationStack {
                    NodeNotesEditorView(
                        title: entity.name.isEmpty ? "Notiz" : "Notiz – \(entity.name)",
                        notes: Binding(
                            get: { entity.notes },
                            set: { entity.notes = $0 }
                        )
                    )
                }
            }
    }

    // MARK: - Delete

    fileprivate func deleteEntity() {
        AttachmentCleanup.deleteAttachments(ownerKind: .entity, ownerID: entity.id, in: modelContext)
        for attr in entity.attributesList {
            AttachmentCleanup.deleteAttachments(ownerKind: .attribute, ownerID: attr.id, in: modelContext)
        }

        LinkCleanup.deleteLinks(referencing: .entity, id: entity.id, graphID: entity.graphID, in: modelContext)

        modelContext.delete(entity)
        try? modelContext.save()
    }

}
