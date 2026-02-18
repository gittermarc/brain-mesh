//
//  AttachmentsSection.swift
//  BrainMesh
//
//  Created by Marc Fechner on 10.02.26.
//

import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

struct AttachmentsSection: View {
    @Environment(\.modelContext) var modelContext

    let ownerKind: NodeKind
    let ownerID: UUID
    let graphID: UUID?

    @Query var attachments: [MetaAttachment]

    // NOTE: must be module-visible because the import pipeline lives in a separate extension file.
    @StateObject var importProgress = ImportProgressState()

    @State var isImportingFile = false
    @State var isPickingVideo = false
    @State var videoPlayback: VideoPlaybackRequest? = nil
    @State var activeSheet: ActiveSheet? = nil
    @State var pendingSheet: ActiveSheet? = nil
    @State var requestGeneration: Int = 0

    @State var errorMessage: String? = nil

    /// Keep it sane: this is meant for small files.
    let maxBytes: Int = 25 * 1024 * 1024

    init(ownerKind: NodeKind, ownerID: UUID, graphID: UUID?) {
        self.ownerKind = ownerKind
        self.ownerID = ownerID
        self.graphID = graphID

        let kindRaw = ownerKind.rawValue
        let oid = ownerID
        let gid = graphID
        let galleryRaw = AttachmentContentKind.galleryImage.rawValue

		// IMPORTANT: keep predicates store-translatable (avoid OR / optional tricks).
		if let gid {
			_attachments = Query(
				filter: #Predicate<MetaAttachment> { a in
					a.ownerKindRaw == kindRaw &&
					a.ownerID == oid &&
					a.graphID == gid &&
					a.contentKindRaw != galleryRaw
				},
				sort: [SortDescriptor(\MetaAttachment.createdAt, order: .reverse)]
			)
		} else {
			_attachments = Query(
				filter: #Predicate<MetaAttachment> { a in
					a.ownerKindRaw == kindRaw &&
					a.ownerID == oid &&
					a.contentKindRaw != galleryRaw
				},
				sort: [SortDescriptor(\MetaAttachment.createdAt, order: .reverse)]
			)
		}
    }

    var body: some View {
        Section {
            if importProgress.isPresented {
                ImportProgressCard(progress: importProgress)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            if attachments.isEmpty {
                Text("Keine Anhänge hinzugefügt.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(attachments) { att in
                    AttachmentCardRow(attachment: att)
                        .onTapGesture {
                            openPreview(for: att)
                        }
                }
                .onDelete(perform: deleteAttachments)
            }

            Menu {
                Button {
                    requestFileImport()
                } label: {
                    Label("Datei auswählen", systemImage: "doc")
                }

                Button {
                    requestVideoPick()
                } label: {
                    Label("Video aus Fotos", systemImage: "video")
                }
            } label: {
                Label("Anhang hinzufügen", systemImage: "paperclip")
            }
        } header: {
            DetailSectionHeader(
                title: "Anhänge",
                systemImage: "paperclip",
                subtitle: "Dateien & Videos (klein halten – maximal \(ByteCountFormatter.string(fromByteCount: Int64(maxBytes), countStyle: .file)))."
            )
        }
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
        .sheet(item: $activeSheet, onDismiss: handleSheetDismiss) { sheet in
            switch sheet {
            case .preview(let state):
                AttachmentPreviewSheet(
                    title: state.title,
                    url: state.url,
                    contentTypeIdentifier: state.contentTypeIdentifier,
                    fileExtension: state.fileExtension
                )
            }
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
        .alert("Anhang konnte nicht hinzugefügt werden", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Sheet Models

    struct PreviewState: Identifiable {
        let url: URL
        let title: String
        let contentTypeIdentifier: String
        let fileExtension: String
        var id: String { url.absoluteString }
    }

    enum ActiveSheet: Identifiable {
        case preview(PreviewState)

        var id: String {
            switch self {
            case .preview(let p):
                return "preview-\(p.id)"
            }
        }
    }
}
