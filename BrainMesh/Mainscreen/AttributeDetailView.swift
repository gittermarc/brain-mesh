//
//  AttributeDetailView.swift
//  BrainMesh
//
//  Created by Marc Fechner on 13.12.25.
//

import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers
import UIKit

struct AttributeDetailView: View {
    @Environment(\.modelContext) private var modelContext

    @Bindable var attribute: MetaAttribute

    @Query private var outgoingLinks: [MetaLink]
    @Query private var incomingLinks: [MetaLink]

    @Query private var galleryImages: [MetaAttachment]
    @Query private var attachments: [MetaAttachment]

    @State private var showAddLink = false
    @State private var showBulkLink = false
    @State private var showLinkChooser = false

    // Gallery presentation is owned by the screen (stable host).
    @State private var showGalleryBrowser: Bool = false
    @State private var galleryViewerRequest: PhotoGalleryViewerRequest? = nil

    // Attachments add / manage
    @State private var showAttachmentChooser: Bool = false
    @State private var showMediaManageChooser: Bool = false
    @State private var showAttachmentsManager: Bool = false
    @State private var isImportingFile: Bool = false
    @State private var isPickingVideo: Bool = false

    @State private var attachmentPreviewSheet: AttachmentPreviewSheetState? = nil
    @State private var videoPlayback: VideoPlaybackRequest? = nil

    @State private var showNotesEditor: Bool = false

    @State private var confirmDelete: Bool = false
    @State private var errorMessage: String? = nil

    @State private var connectionsSegment: NodeLinkDirectionSegment = .outgoing

    private let maxBytes: Int = 25 * 1024 * 1024

    init(attribute: MetaAttribute) {
        self.attribute = attribute

        _outgoingLinks = NodeLinksQueryBuilder.outgoingLinksQuery(
            kind: .attribute,
            id: attribute.id,
            graphID: attribute.graphID
        )

        _incomingLinks = NodeLinksQueryBuilder.incomingLinksQuery(
            kind: .attribute,
            id: attribute.id,
            graphID: attribute.graphID
        )

        _galleryImages = PhotoGalleryQueryBuilder.galleryImagesQuery(
            ownerKind: .attribute,
            ownerID: attribute.id,
            graphID: attribute.graphID
        )

        let kindRaw = NodeKind.attribute.rawValue
        let oid = attribute.id
        let gid = attribute.graphID
        let galleryRaw = AttachmentContentKind.galleryImage.rawValue

        _attachments = Query(
            filter: #Predicate<MetaAttachment> { a in
                a.ownerKindRaw == kindRaw &&
                a.ownerID == oid &&
                (gid == nil || a.graphID == gid) &&
                a.contentKindRaw != galleryRaw
            },
            sort: [SortDescriptor(\MetaAttachment.createdAt, order: .reverse)]
        )
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 14) {
                    NodeHeroCard(
                        kindTitle: "Attribut",
                        placeholderIcon: attribute.iconSymbolName ?? "tag",
                        imageData: attribute.imageData,
                        imagePath: attribute.imagePath,
                        title: Binding(
                            get: { attribute.name },
                            set: { attribute.name = $0 }
                        ),
                        subtitle: attribute.owner?.name,
                        pills: [
                            NodeStatPill(title: "\(outgoingLinks.count)", systemImage: "arrow.up.right"),
                            NodeStatPill(title: "\(incomingLinks.count)", systemImage: "arrow.down.left"),
                            NodeStatPill(title: "\(galleryImages.count + attachments.count)", systemImage: "photo.on.rectangle")
                        ]
                    )

                    NodeToolbelt {
                        NodeToolbeltButton(title: "Link", systemImage: "link") {
                            showLinkChooser = true
                        }

                        NodeToolbeltButton(title: "Foto", systemImage: "photo") {
                            showGalleryBrowser = true
                        }

                        NodeToolbeltButton(title: "Datei", systemImage: "paperclip") {
                            showAttachmentChooser = true
                        }
                    }

                    let noteSnippet = attribute.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                    let hasNote = !noteSnippet.isEmpty
                    let topLinks = NodeTopLinks.compute(outgoing: outgoingLinks, incoming: incomingLinks, max: 2)

                    NodeHighlightsRow {
                        NodeHighlightTile(
                            title: "Notiz",
                            systemImage: "note.text",
                            subtitle: hasNote ? NodeTopLinks.previewText(noteSnippet, maxChars: 80) : "Noch keine Notiz",
                            footer: hasNote ? "Tippen zum Bearbeiten" : "Tippen zum Schreiben",
                            onTap: {
                                showNotesEditor = true
                            }
                        )

                        NodeHighlightTile(
                            title: "Medien",
                            systemImage: "photo.on.rectangle",
                            subtitle: "\(galleryImages.count) Fotos · \(attachments.count) Anhänge",
                            footer: galleryImages.isEmpty && attachments.isEmpty ? "Tippen zum Hinzufügen" : "Tippen zum Ansehen",
                            onTap: {
                                proxy.scrollTo(NodeDetailAnchor.media.rawValue, anchor: .top)
                            },
                            accessory: {
                                NodeMiniThumbStrip(attachments: Array(galleryImages.prefix(3)))
                            }
                        )

                        NodeHighlightTile(
                            title: "Top Links",
                            systemImage: "link",
                            subtitle: topLinks.isEmpty ? "Keine Links" : topLinks.map { $0.label }.joined(separator: " · "),
                            footer: "Tippen für Alle",
                            onTap: {
                                proxy.scrollTo(NodeDetailAnchor.connections.rawValue, anchor: .top)
                            }
                        )
                    }

                    NodeNotesCard(
                        notes: Binding(
                            get: { attribute.notes },
                            set: { attribute.notes = $0 }
                        ),
                        onEdit: { showNotesEditor = true }
                    )
                    .id(NodeDetailAnchor.notes.rawValue)

                    if let owner = attribute.owner {
                        NodeOwnerCard(owner: owner)
                    }

                    NodeConnectionsCard(
                        ownerKind: .attribute,
                        ownerID: attribute.id,
                        graphID: attribute.graphID,
                        outgoing: outgoingLinks,
                        incoming: incomingLinks,
                        segment: $connectionsSegment,
                        previewLimit: 5
                    )
                    .id(NodeDetailAnchor.connections.rawValue)

                    NodeMediaCard(
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
                        mainStableID: attribute.id,
                        galleryImages: galleryImages,
                        attachments: attachments,
                        onOpenAll: {},
                        onManage: {
                            showMediaManageChooser = true
                        },
                        onTapGallery: { id in
                            galleryViewerRequest = PhotoGalleryViewerRequest(startAttachmentID: id)
                        },
                        onTapAttachment: { att in
                            openAttachment(att)
                        }
                    )
                    .id(NodeDetailAnchor.media.rawValue)

                    NodeAppearanceCard(iconSymbolName: Binding(
                        get: { attribute.iconSymbolName },
                        set: { attribute.iconSymbolName = $0 }
                    ))

                    Spacer(minLength: 8)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 18)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(attribute.displayName)
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
                        title: attribute.displayName.isEmpty ? "Notiz" : "Notiz – \(attribute.displayName)",
                        notes: Binding(
                            get: { attribute.notes },
                            set: { attribute.notes = $0 }
                        )
                    )
                }
            }
        }
    }

    // MARK: - Attachments (Preview)

    private func openAttachment(_ attachment: MetaAttachment) {
        guard let url = AttachmentStore.ensurePreviewURL(for: attachment) else {
            errorMessage = "Vorschau ist nicht verfügbar (keine Daten/Datei gefunden)."
            return
        }

        let isVideo = AttachmentStore.isVideo(contentTypeIdentifier: attachment.contentTypeIdentifier)
            || ["mov", "mp4", "m4v"].contains(attachment.fileExtension.lowercased())

        if isVideo {
            try? modelContext.save()
            videoPlayback = VideoPlaybackRequest(url: url, title: attachment.title.isEmpty ? attachment.originalFilename : attachment.title)
            return
        }

        try? modelContext.save()
        attachmentPreviewSheet = AttachmentPreviewSheetState(
            url: url,
            title: attachment.title.isEmpty ? attachment.originalFilename : attachment.title,
            contentTypeIdentifier: attachment.contentTypeIdentifier,
            fileExtension: attachment.fileExtension
        )
    }

    // MARK: - Import

    private func importFile(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }

        let fileName = url.lastPathComponent
        let ext = url.pathExtension

        let contentType = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)?.identifier ?? ""
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0

        if fileSize > maxBytes {
            errorMessage = "Datei ist zu groß (\(ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file))). Bitte nur kleine Anhänge hinzufügen."
            return
        }

        let attachmentID = UUID()

        do {
            let copiedName = try AttachmentStore.copyIntoCache(from: url, attachmentID: attachmentID, fileExtension: ext)
            guard let copiedURL = AttachmentStore.url(forLocalPath: copiedName) else {
                errorMessage = "Lokale Datei konnte nicht erstellt werden."
                return
            }

            let data = try Data(contentsOf: copiedURL, options: [.mappedIfSafe])
            if data.count > maxBytes {
                AttachmentStore.delete(localPath: copiedName)
                errorMessage = "Datei ist zu groß (\(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))). Bitte nur kleine Anhänge hinzufügen."
                return
            }

            let title = url.deletingPathExtension().lastPathComponent

            let inferredKind: AttachmentContentKind
            if let t = UTType(contentType) {
                if t.conforms(to: .image) {
                    inferredKind = .galleryImage
                } else if t.conforms(to: .movie) || t.conforms(to: .video) {
                    inferredKind = .video
                } else {
                    inferredKind = .file
                }
            } else {
                inferredKind = .file
            }

            let att = MetaAttachment(
                id: attachmentID,
                ownerKind: .attribute,
                ownerID: attribute.id,
                graphID: attribute.graphID,
                contentKind: inferredKind,
                title: title,
                originalFilename: fileName,
                contentTypeIdentifier: contentType,
                fileExtension: ext,
                byteCount: data.count,
                fileData: data,
                localPath: copiedName
            )

            modelContext.insert(att)
            try? modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func handlePickedVideo(_ result: Result<PickedVideo, Error>) async {
        isPickingVideo = false

        switch result {
        case .success(let picked):
            await importVideoFromURL(
                picked.url,
                suggestedFilename: picked.suggestedFilename,
                contentTypeIdentifier: picked.contentTypeIdentifier,
                fileExtension: picked.fileExtension
            )
        case .failure(let error):
            if let pickerError = error as? VideoPickerError, pickerError == .cancelled {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func importVideoFromURL(
        _ url: URL,
        suggestedFilename: String,
        contentTypeIdentifier: String,
        fileExtension: String
    ) async {
        do {
            let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if fileSize > maxBytes {
                errorMessage = "Video ist zu groß (\(ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file))). Bitte nur kleine Videos hinzufügen."
                return
            }

            let attachmentID = UUID()
            let ext = fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: ".")).isEmpty ? "mov" : fileExtension

            let cachedFilename = try AttachmentStore.copyIntoCache(from: url, attachmentID: attachmentID, fileExtension: ext)
            guard let cachedURL = AttachmentStore.url(forLocalPath: cachedFilename) else {
                errorMessage = "Lokale Videodatei konnte nicht erstellt werden."
                return
            }

            try? FileManager.default.removeItem(at: url)

            let data = try Data(contentsOf: cachedURL, options: [.mappedIfSafe])
            if data.count > maxBytes {
                AttachmentStore.delete(localPath: cachedFilename)
                errorMessage = "Video ist zu groß (\(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))). Bitte nur kleine Videos hinzufügen."
                return
            }

            let title = URL(fileURLWithPath: suggestedFilename).deletingPathExtension().lastPathComponent
            let originalName = suggestedFilename.isEmpty ? "Video.\(ext)" : suggestedFilename

            let typeID: String
            if !contentTypeIdentifier.isEmpty {
                typeID = contentTypeIdentifier
            } else if let t = UTType(filenameExtension: ext)?.identifier {
                typeID = t
            } else {
                typeID = UTType.movie.identifier
            }

            let att = MetaAttachment(
                id: attachmentID,
                ownerKind: .attribute,
                ownerID: attribute.id,
                graphID: attribute.graphID,
                contentKind: .video,
                title: title.isEmpty ? "Video" : title,
                originalFilename: originalName,
                contentTypeIdentifier: typeID,
                fileExtension: ext,
                byteCount: data.count,
                fileData: data,
                localPath: cachedFilename
            )

            modelContext.insert(att)
            try? modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Delete

    private func deleteAttribute() {
        AttachmentCleanup.deleteAttachments(ownerKind: .attribute, ownerID: attribute.id, in: modelContext)
        LinkCleanup.deleteLinks(referencing: .attribute, id: attribute.id, graphID: attribute.graphID, in: modelContext)

        if let owner = attribute.owner {
            owner.removeAttribute(attribute)
        }

        modelContext.delete(attribute)
        try? modelContext.save()
    }
}
