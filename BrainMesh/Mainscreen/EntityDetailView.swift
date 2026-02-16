//
//  EntityDetailView.swift
//  BrainMesh
//
//  Created by Marc Fechner on 13.12.25.
//

import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers
import UIKit

struct EntityDetailView: View {
    @Environment(\.modelContext) private var modelContext

    @Bindable var entity: MetaEntity

    @Query private var outgoingLinks: [MetaLink]
    @Query private var incomingLinks: [MetaLink]

    @Query private var galleryImages: [MetaAttachment]
    @Query private var attachments: [MetaAttachment]

    @State private var showAddAttribute = false

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

    init(entity: MetaEntity) {
        self.entity = entity

        _outgoingLinks = NodeLinksQueryBuilder.outgoingLinksQuery(
            kind: .entity,
            id: entity.id,
            graphID: entity.graphID
        )

        _incomingLinks = NodeLinksQueryBuilder.incomingLinksQuery(
            kind: .entity,
            id: entity.id,
            graphID: entity.graphID
        )

        _galleryImages = PhotoGalleryQueryBuilder.galleryImagesQuery(
            ownerKind: .entity,
            ownerID: entity.id,
            graphID: entity.graphID
        )

        let kindRaw = NodeKind.entity.rawValue
        let oid = entity.id
        let gid = entity.graphID
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
                        kindTitle: "Entität",
                        placeholderIcon: entity.iconSymbolName ?? "cube",
                        imageData: entity.imageData,
                        imagePath: entity.imagePath,
                        title: Binding(
                            get: { entity.name },
                            set: { entity.name = $0 }
                        ),
                        subtitle: nil,
                        pills: [
                            NodeStatPill(title: "\(entity.attributesList.count)", systemImage: "tag"),
                            NodeStatPill(title: "\(outgoingLinks.count)", systemImage: "arrow.up.right"),
                            NodeStatPill(title: "\(incomingLinks.count)", systemImage: "arrow.down.left"),
                            NodeStatPill(title: "\(galleryImages.count + attachments.count)", systemImage: "photo.on.rectangle")
                        ]
                    )

                    toolbelt(proxy: proxy)

                    highlightsRow(proxy: proxy)

                    NodeNotesCard(
                        notes: Binding(
                            get: { entity.notes },
                            set: { entity.notes = $0 }
                        ),
                        onEdit: { showNotesEditor = true }
                    )
                    .id(NodeDetailAnchor.notes.rawValue)

                    NodeConnectionsCard(
                        ownerKind: .entity,
                        ownerID: entity.id,
                        graphID: entity.graphID,
                        outgoing: outgoingLinks,
                        incoming: incomingLinks,
                        segment: $connectionsSegment,
                        previewLimit: 5
                    )
                    .id(NodeDetailAnchor.connections.rawValue)

                    NodeMediaCard(
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
                        mainStableID: entity.id,
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

                    NodeEntityAttributesCard(entity: entity)
                        .id(NodeDetailAnchor.attributes.rawValue)

                    NodeAppearanceCard(iconSymbolName: Binding(
                        get: { entity.iconSymbolName },
                        set: { entity.iconSymbolName = $0 }
                    ))

                    Spacer(minLength: 8)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 18)
            }
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
            .confirmationDialog(
                "Medien verwalten",
                isPresented: $showMediaManageChooser,
                titleVisibility: .visible
            ) {
                Button("Galerie verwalten") { showGalleryBrowser = true }
                Button("Anhänge verwalten") { showAttachmentsManager = true }
                Button("Abbrechen", role: .cancel) {}
            }
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
    }

    private func toolbelt(proxy: ScrollViewProxy) -> some View {
        NodeToolbelt {
            NodeToolbeltButton(title: "Link", systemImage: "link") {
                showLinkChooser = true
            }

            NodeToolbeltButton(title: "Attribut", systemImage: "tag") {
                showAddAttribute = true
            }

            NodeToolbeltButton(title: "Foto", systemImage: "photo") {
                showGalleryBrowser = true
            }

            NodeToolbeltButton(title: "Datei", systemImage: "paperclip") {
                showAttachmentChooser = true
            }
        }
    }

    private func highlightsRow(proxy: ScrollViewProxy) -> some View {
        let noteSnippet = entity.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasNote = !noteSnippet.isEmpty
        let topLinks = NodeTopLinks.compute(outgoing: outgoingLinks, incoming: incomingLinks, max: 2)

        return NodeHighlightsRow {
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
                footer: galleryImages.isEmpty && attachments.isEmpty ? "Tippen zum Hinzufügen" : "Tippen für Alle",
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

    // MARK: - Import (Files / Videos)

    private func importFile(from url: URL, ownerKind: NodeKind, ownerID: UUID, graphID: UUID?) {
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
                ownerKind: ownerKind,
                ownerID: ownerID,
                graphID: graphID,
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
                fileExtension: picked.fileExtension,
                ownerKind: .entity,
                ownerID: entity.id,
                graphID: entity.graphID
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
        fileExtension: String,
        ownerKind: NodeKind,
        ownerID: UUID,
        graphID: UUID?
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
                ownerKind: ownerKind,
                ownerID: ownerID,
                graphID: graphID,
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

    private func deleteEntity() {
        AttachmentCleanup.deleteAttachments(ownerKind: .entity, ownerID: entity.id, in: modelContext)
        for attr in entity.attributesList {
            AttachmentCleanup.deleteAttachments(ownerKind: .attribute, ownerID: attr.id, in: modelContext)
        }

        LinkCleanup.deleteLinks(referencing: .entity, id: entity.id, graphID: entity.graphID, in: modelContext)

        modelContext.delete(entity)
        try? modelContext.save()
    }
}

// MARK: - Shared Rich Detail Components

enum NodeDetailAnchor: String {
    case notes
    case connections
    case media
    case attributes
}

enum NodeLinkDirectionSegment: String, CaseIterable, Identifiable {
    case outgoing
    case incoming

    var id: String { rawValue }

    var title: String {
        switch self {
        case .outgoing: return "Ausgehend"
        case .incoming: return "Eingehend"
        }
    }

    var systemImage: String {
        switch self {
        case .outgoing: return "arrow.up.right"
        case .incoming: return "arrow.down.left"
        }
    }
}

struct NodeStatPill: Identifiable, Hashable {
    let id: String
    let title: String
    let systemImage: String

    init(title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
        self.id = systemImage + "|" + title
    }
}

struct NodeHeroCard: View {
    let kindTitle: String
    let placeholderIcon: String

    let imageData: Data?
    let imagePath: String?

    @Binding var title: String
    let subtitle: String?
    let pills: [NodeStatPill]

    private var previewImage: UIImage? {
        // Hero image: downsample to a sensible size for the header.
        if let p = imagePath, let ui = ImageStore.loadUIImage(path: p, maxPixelSize: 1800) { return ui }
        if let ui = ImageStore.loadUIImage(data: imageData, maxPixelSize: 1800) { return ui }
        return nil
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(.secondary.opacity(0.12))
                )

            if let ui = previewImage {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 210)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(
                        LinearGradient(
                            colors: [Color.black.opacity(0.55), Color.black.opacity(0.15), Color.clear],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    )
            } else {
                VStack(spacing: 8) {
                    Image(systemName: placeholderIcon)
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.tint)
                    Text(kindTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 210)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(kindTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(previewImage == nil ? Color.secondary : Color.white.opacity(0.85))

                TextField("Name", text: $title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(previewImage == nil ? Color.primary : Color.white)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled(false)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(previewImage == nil ? Color.secondary : Color.white.opacity(0.85))
                        .lineLimit(2)
                }

                if !pills.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(pills) { pill in
                            Label(pill.title, systemImage: pill.systemImage)
                                .font(.caption.weight(.semibold))
                                .labelStyle(.titleAndIcon)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    (previewImage == nil ? AnyShapeStyle(Color(uiColor: .tertiarySystemGroupedBackground)) : AnyShapeStyle(.ultraThinMaterial)),
                                    in: Capsule()
                                )
                                .foregroundStyle(previewImage == nil ? Color.secondary : Color.white)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(16)
        }
        .frame(height: 210)
        .accessibilityElement(children: .contain)
    }
}

struct NodeToolbelt<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 10) {
            content()
        }
    }
}

struct NodeToolbeltButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.secondary.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
    }
}

struct NodeHighlightsRow<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                content()
            }
            .padding(.horizontal, 2)
        }
        .scrollClipDisabled()
    }
}

struct NodeHighlightTile<Accessory: View>: View {
    let title: String
    let systemImage: String
    let subtitle: String
    let footer: String
    var accessory: (() -> Accessory)? = nil
    let onTap: () -> Void

    init(
        title: String,
        systemImage: String,
        subtitle: String,
        footer: String,
        accessory: (() -> Accessory)? = nil,
        onTap: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.subtitle = subtitle
        self.footer = footer
        self.accessory = accessory
        self.onTap = onTap
    }

    init(
        title: String,
        systemImage: String,
        subtitle: String,
        footer: String,
        onTap: @escaping () -> Void,
        accessory: (() -> Accessory)? = nil
    ) {
        self.init(
            title: title,
            systemImage: systemImage,
            subtitle: subtitle,
            footer: footer,
            accessory: accessory,
            onTap: onTap
        )
    }


    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.tint)
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }

                Text(subtitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if let accessory {
                    accessory()
                }

                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(width: 220, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(.secondary.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
    }

}

extension NodeHighlightTile where Accessory == EmptyView {
    init(
        title: String,
        systemImage: String,
        subtitle: String,
        footer: String,
        onTap: @escaping () -> Void
    ) {
        self.init(
            title: title,
            systemImage: systemImage,
            subtitle: subtitle,
            footer: footer,
            accessory: nil,
            onTap: onTap
        )
    }
}

struct NodeMiniThumbStrip
: View {
    let attachments: [MetaAttachment]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(attachments.prefix(3)) { att in
                NodeThumbMiniTile(attachment: att)
            }
        }
    }
}

private struct NodeThumbMiniTile: View {
    let attachment: MetaAttachment

    @State private var thumbnail: UIImage? = nil

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.quaternary)

            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 34, height: 34)
        .clipped()
        .task(id: attachment.id) {
            await loadThumbnailIfNeeded()
        }
    }

    private func loadThumbnailIfNeeded() async {
        if thumbnail != nil { return }
        guard let url = await AttachmentStore.materializeFileURLForThumbnailIfNeededAsync(for: attachment) else { return }

        let scale = UIScreen.main.scale
        let requestSize = CGSize(width: 90, height: 90)

        let img = await AttachmentThumbnailStore.shared.thumbnail(
            attachmentID: attachment.id,
            fileURL: url,
            contentTypeIdentifier: attachment.contentTypeIdentifier,
            fileExtension: attachment.fileExtension,
            isVideo: false,
            requestSize: requestSize,
            scale: scale
        )

        await MainActor.run {
            thumbnail = img
        }
    }

}

struct NodeNotesCard: View {
    @Binding var notes: String
    let onEdit: () -> Void

    private var trimmed: String {
        notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NodeCardHeader(
                title: "Notiz",
                systemImage: "note.text",
                trailingTitle: "Bearbeiten",
                trailingSystemImage: "pencil",
                trailingAction: onEdit
            )

            if trimmed.isEmpty {
                NodeEmptyStateRow(
                    text: "Noch keine Notiz hinterlegt.",
                    ctaTitle: "Notiz schreiben",
                    ctaSystemImage: "pencil",
                    ctaAction: onEdit
                )
            } else {
                Text(trimmed)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.secondary.opacity(0.12))
        )
    }
}

struct NodeNotesEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    @Binding var notes: String

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $notes)
                .padding(12)
                .scrollContentBackground(.hidden)
                .background(Color(uiColor: .secondarySystemBackground))
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Fertig") { dismiss() }
            }
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
    }
}

struct NodeOwnerCard: View {
    let owner: MetaEntity

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NodeCardHeader(title: "Zugehörige Entität", systemImage: "cube")

            NavigationLink {
                EntityDetailView(entity: owner)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: owner.iconSymbolName ?? "cube")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 28)
                        .foregroundStyle(.tint)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(owner.name.isEmpty ? "Entität" : owner.name)
                            .foregroundStyle(.primary)
                        Text("Öffnen")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.secondary.opacity(0.12))
        )
    }
}

struct NodeConnectionsCard: View {
    let ownerKind: NodeKind
    let ownerID: UUID
    let graphID: UUID?

    let outgoing: [MetaLink]
    let incoming: [MetaLink]

    @Binding var segment: NodeLinkDirectionSegment
    let previewLimit: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NodeCardHeader(title: "Verbindungen", systemImage: "link")

            Picker("", selection: $segment) {
                ForEach(NodeLinkDirectionSegment.allCases) { seg in
                    Label(seg.title, systemImage: seg.systemImage)
                        .tag(seg)
                }
            }
            .pickerStyle(.segmented)

            let links = (segment == .outgoing ? outgoing : incoming)
            if links.isEmpty {
                NodeEmptyStateRow(
                    text: segment == .outgoing ? "Keine ausgehenden Links." : "Keine eingehenden Links.",
                    ctaTitle: "Im Toolbelt hinzufügen",
                    ctaSystemImage: "link",
                    ctaAction: {}
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(links.prefix(previewLimit)) { link in
                        NavigationLink {
                            NodeLinkListDestinationView(link: link, direction: segment)
                        } label: {
                            NodeLinkRow(
                                direction: segment,
                                title: segment == .outgoing ? link.targetLabel : link.sourceLabel,
                                note: link.note
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                NavigationLink {
                    NodeConnectionsAllView(
                        ownerKind: ownerKind,
                        ownerID: ownerID,
                        graphID: graphID,
                        initialSegment: segment
                    )
                } label: {
                    Label("Alle", systemImage: "chevron.right")
                        .font(.callout.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.secondary.opacity(0.12))
        )
    }
}

private struct NodeLinkListDestinationView: View {
    @Environment(\.modelContext) private var modelContext

    let link: MetaLink
    let direction: NodeLinkDirectionSegment

    var body: some View {
        let kind: NodeKind = (direction == .outgoing ? link.targetKind : link.sourceKind)
        let id: UUID = (direction == .outgoing ? link.targetID : link.sourceID)

        return NodeDestinationView(kind: kind, id: id)
    }
}

private struct NodeLinkRow: View {
    let direction: NodeLinkDirectionSegment
    let title: String
    let note: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: direction.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 22)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct NodeMediaCard: View {
    let ownerKind: NodeKind
    let ownerID: UUID
    let graphID: UUID?

    @Binding var mainImageData: Data?
    @Binding var mainImagePath: String?
    let mainStableID: UUID

    let galleryImages: [MetaAttachment]
    let attachments: [MetaAttachment]

    let onOpenAll: () -> Void
    let onManage: () -> Void
    let onTapGallery: (UUID) -> Void
    let onTapAttachment: (MetaAttachment) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NodeCardHeader(title: "Medien", systemImage: "photo.on.rectangle")

            if galleryImages.isEmpty && attachments.isEmpty {
                NodeEmptyStateRow(
                    text: "Noch keine Fotos oder Anhänge.",
                    ctaTitle: "Medien hinzufügen",
                    ctaSystemImage: "plus",
                    ctaAction: onManage
                )
            } else {
                NodeGalleryThumbGrid(
                    attachments: Array(galleryImages.prefix(6)),
                    onTap: onTapGallery
                )

                if !attachments.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Anhänge")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ForEach(attachments.prefix(3)) { att in
                            AttachmentCardRow(attachment: att)
                                .onTapGesture {
                                    onTapAttachment(att)
                                }
                        }
                    }
                }

                HStack {
                    Button {
                        onManage()
                    } label: {
                        Label("Verwalten", systemImage: "slider.horizontal.3")
                            .font(.callout.weight(.semibold))
                    }
                    .buttonStyle(.bordered)

                    Spacer(minLength: 0)

                    NavigationLink {
                        NodeMediaAllView(
                            ownerKind: ownerKind,
                            ownerID: ownerID,
                            graphID: graphID,
                            mainImageData: $mainImageData,
                            mainImagePath: $mainImagePath,
                            mainStableID: mainStableID
                        )
                    } label: {
                        Label("Alle", systemImage: "chevron.right")
                            .font(.callout.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.secondary.opacity(0.12))
        )
    }
}

private struct NodeGalleryThumbGrid: View {
    let attachments: [MetaAttachment]
    let onTap: (UUID) -> Void

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(attachments.prefix(6)) { att in
                NodeGalleryThumbTile(attachment: att) {
                    onTap(att.id)
                }
            }

            let missing = max(0, 6 - attachments.count)
            if missing > 0 {
                ForEach(0..<missing, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.quaternary)
                        .frame(height: 82)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.secondary)
                        )
                }
            }
        }
    }
}

private struct NodeGalleryThumbTile: View {
    let attachment: MetaAttachment
    let onTap: () -> Void

    @State private var thumbnail: UIImage? = nil

    var body: some View {
        Button(action: onTap) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.quaternary)

                if let thumbnail {
                    PhotoGalleryThumbnailView(uiImage: thumbnail, cornerRadius: 16, contentPadding: 8)
                } else {
                    ProgressView()
                        .scaleEffect(0.9)
                }
            }
            .frame(height: 82)
        }
        .buttonStyle(.plain)
        .task(id: attachment.id) {
            await loadThumbnailIfNeeded()
        }
    }

    private func loadThumbnailIfNeeded() async {
        if thumbnail != nil { return }
        guard let url = await AttachmentStore.materializeFileURLForThumbnailIfNeededAsync(for: attachment) else { return }

        let scale = UIScreen.main.scale
        let requestSize = CGSize(width: 220, height: 220)

        let img = await AttachmentThumbnailStore.shared.thumbnail(
            attachmentID: attachment.id,
            fileURL: url,
            contentTypeIdentifier: attachment.contentTypeIdentifier,
            fileExtension: attachment.fileExtension,
            isVideo: false,
            requestSize: requestSize,
            scale: scale
        )

        await MainActor.run {
            thumbnail = img
        }
    }

}

struct NodeEntityAttributesCard: View {
    let entity: MetaEntity

    private var preview: [MetaAttribute] {
        Array(entity.attributesList.sorted(by: { $0.nameFolded < $1.nameFolded }).prefix(12))
    }

    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 110), spacing: 8)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NodeCardHeader(title: "Attribute", systemImage: "tag")

            if entity.attributesList.isEmpty {
                NodeEmptyStateRow(
                    text: "Noch keine Attribute.",
                    ctaTitle: "Attribute ansehen",
                    ctaSystemImage: "tag",
                    ctaAction: {}
                )
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(preview) { attr in
                        NavigationLink {
                            AttributeDetailView(attribute: attr)
                        } label: {
                            Label(attr.name.isEmpty ? "Attribut" : attr.name, systemImage: attr.iconSymbolName ?? "tag")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(uiColor: .tertiarySystemGroupedBackground), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }

                NavigationLink {
                    EntityAttributesAllView(entity: entity)
                } label: {
                    Label("Alle", systemImage: "chevron.right")
                        .font(.callout.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.secondary.opacity(0.12))
        )
    }
}

struct NodeAppearanceCard: View {
    @Binding var iconSymbolName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NodeCardHeader(title: "Darstellung", systemImage: "paintbrush")

            IconPickerRow(title: "Icon", symbolName: $iconSymbolName)
                .padding(12)
                .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.secondary.opacity(0.12))
        )
    }
}

struct NodeCardHeader: View {
    let title: String
    let systemImage: String

    var trailingTitle: String? = nil
    var trailingSystemImage: String? = nil
    var trailingAction: (() -> Void)? = nil

    init(
        title: String,
        systemImage: String,
        trailingTitle: String? = nil,
        trailingSystemImage: String? = nil,
        trailingAction: (() -> Void)? = nil
    ) {
        self.title = title
        self.systemImage = systemImage
        self.trailingTitle = trailingTitle
        self.trailingSystemImage = trailingSystemImage
        self.trailingAction = trailingAction
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.tint)

            Text(title)
                .font(.headline)

            Spacer(minLength: 0)

            if let trailingTitle, let trailingSystemImage, let trailingAction {
                Button(action: trailingAction) {
                    Label(trailingTitle, systemImage: trailingSystemImage)
                        .font(.callout.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

struct NodeEmptyStateRow: View {
    let text: String
    let ctaTitle: String
    let ctaSystemImage: String
    let ctaAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text)
                .foregroundStyle(.secondary)

            Button(action: ctaAction) {
                Label(ctaTitle, systemImage: ctaSystemImage)
                    .font(.callout.weight(.semibold))
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct AttachmentPreviewSheetState: Identifiable {
    let url: URL
    let title: String
    let contentTypeIdentifier: String
    let fileExtension: String

    var id: String { url.absoluteString }
}

enum NodeTopLinks {
    static func compute(outgoing: [MetaLink], incoming: [MetaLink], max: Int) -> [NodeRef] {
        var refs: [NodeRef] = []

        for l in outgoing {
            refs.append(NodeRef(kind: l.targetKind, id: l.targetID, label: l.targetLabel, iconSymbolName: nil))
            if refs.count >= max { return refs }
        }

        for l in incoming {
            refs.append(NodeRef(kind: l.sourceKind, id: l.sourceID, label: l.sourceLabel, iconSymbolName: nil))
            if refs.count >= max { return refs }
        }

        return refs
    }

    static func previewText(_ s: String, maxChars: Int) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= maxChars { return trimmed }
        let idx = trimmed.index(trimmed.startIndex, offsetBy: maxChars)
        return String(trimmed[..<idx]) + "…"
    }
}

// MARK: - All Views

struct NodeConnectionsAllView: View {
    @Environment(\.modelContext) private var modelContext

    let ownerKind: NodeKind
    let ownerID: UUID
    let graphID: UUID?

    @Query private var outgoingLinks: [MetaLink]
    @Query private var incomingLinks: [MetaLink]

    @State private var segment: NodeLinkDirectionSegment

    init(ownerKind: NodeKind, ownerID: UUID, graphID: UUID?, initialSegment: NodeLinkDirectionSegment = .outgoing) {
        self.ownerKind = ownerKind
        self.ownerID = ownerID
        self.graphID = graphID
        _segment = State(initialValue: initialSegment)

        _outgoingLinks = NodeLinksQueryBuilder.outgoingLinksQuery(kind: ownerKind, id: ownerID, graphID: graphID)
        _incomingLinks = NodeLinksQueryBuilder.incomingLinksQuery(kind: ownerKind, id: ownerID, graphID: graphID)
    }

    var body: some View {
        List {
            Section {
                Picker("", selection: $segment) {
                    ForEach(NodeLinkDirectionSegment.allCases) { seg in
                        Label(seg.title, systemImage: seg.systemImage)
                            .tag(seg)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                ForEach(currentLinks) { link in
                    NavigationLink {
                        NodeDestinationView(kind: targetKind(for: link), id: targetID(for: link))
                    } label: {
                        NodeLinkListRow(direction: segment, title: targetLabel(for: link), note: link.note)
                    }
                }
                .onDelete(perform: deleteLinks)
            }
        }
        .navigationTitle("Verbindungen")
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.insetGrouped)
    }

    private var currentLinks: [MetaLink] {
        segment == .outgoing ? outgoingLinks : incomingLinks
    }

    private func targetKind(for link: MetaLink) -> NodeKind {
        segment == .outgoing ? link.targetKind : link.sourceKind
    }

    private func targetID(for link: MetaLink) -> UUID {
        segment == .outgoing ? link.targetID : link.sourceID
    }

    private func targetLabel(for link: MetaLink) -> String {
        segment == .outgoing ? link.targetLabel : link.sourceLabel
    }

    private func deleteLinks(at offsets: IndexSet) {
        let list = currentLinks
        for idx in offsets {
            guard list.indices.contains(idx) else { continue }
            modelContext.delete(list[idx])
        }
        try? modelContext.save()
    }
}

private struct NodeLinkListRow: View {
    let direction: NodeLinkDirectionSegment
    let title: String
    let note: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: direction.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 22)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}


struct NodeMediaAllView: View {
    @Environment(\.modelContext) private var modelContext

    let ownerKind: NodeKind
    let ownerID: UUID
    let graphID: UUID?

    @Binding var mainImageData: Data?
    @Binding var mainImagePath: String?
    let mainStableID: UUID

    @Query private var galleryImages: [MetaAttachment]
    @Query private var attachments: [MetaAttachment]

    @State private var viewerRequest: PhotoGalleryViewerRequest? = nil
    @State private var attachmentPreviewSheet: AttachmentPreviewSheetState? = nil
    @State private var videoPlayback: VideoPlaybackRequest? = nil

    @State private var errorMessage: String? = nil

    init(
        ownerKind: NodeKind,
        ownerID: UUID,
        graphID: UUID?,
        mainImageData: Binding<Data?>,
        mainImagePath: Binding<String?>,
        mainStableID: UUID
    ) {
        self.ownerKind = ownerKind
        self.ownerID = ownerID
        self.graphID = graphID
        self._mainImageData = mainImageData
        self._mainImagePath = mainImagePath
        self.mainStableID = mainStableID

        _galleryImages = PhotoGalleryQueryBuilder.galleryImagesQuery(
            ownerKind: ownerKind,
            ownerID: ownerID,
            graphID: graphID
        )

        let kindRaw = ownerKind.rawValue
        let oid = ownerID
        let gid = graphID
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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if galleryImages.isEmpty {
                    Text("Keine Fotos in der Galerie.")
                        .foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110, maximum: 180), spacing: 12)], spacing: 12) {
                        ForEach(galleryImages) { att in
                            NodeGalleryThumbTile(attachment: att) {
                                viewerRequest = PhotoGalleryViewerRequest(startAttachmentID: att.id)
                            }
                        }
                    }
                }

                if !attachments.isEmpty {
                    Text("Anhänge")
                        .font(.headline)

                    ForEach(attachments) { att in
                        AttachmentCardRow(attachment: att)
                            .onTapGesture { openAttachment(att) }
                    }
                } else {
                    Text("Keine Anhänge.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .navigationTitle("Medien")
        .navigationBarTitleDisplayMode(.inline)
        .alert("BrainMesh", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .fullScreenCover(item: $viewerRequest) { req in
            PhotoGalleryViewerView(
                ownerKind: ownerKind,
                ownerID: ownerID,
                graphID: graphID,
                startAttachmentID: req.startAttachmentID,
                mainImageData: $mainImageData,
                mainImagePath: $mainImagePath,
                mainStableID: mainStableID
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
            VideoPlaybackPresenter(request: $videoPlayback)
                .frame(width: 0, height: 0)
        )
    }

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

struct EntityAttributesAllView: View {
    @Environment(\.modelContext) private var modelContext

    @Bindable var entity: MetaEntity

    @State private var searchText: String = ""

    var body: some View {
        List {
            if !searchText.isEmpty {
                Section {
                    Text("Suche: \(searchText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                ForEach(filteredAttributes) { attr in
                    NavigationLink {
                        AttributeDetailView(attribute: attr)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: attr.iconSymbolName ?? "tag")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(width: 22)
                                .foregroundStyle(.tint)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(attr.name.isEmpty ? "Attribut" : attr.name)
                                if !attr.notes.isEmpty {
                                    Text(attr.notes)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }
                .onDelete(perform: deleteAttributes)
            } header: {
                Text("Alle Attribute")
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Attribut suchen…")
        .navigationTitle("Attribute")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var filteredAttributes: [MetaAttribute] {
        let base = entity.attributesList
        let needle = BMSearch.fold(searchText)
        guard !needle.isEmpty else {
            return base.sorted { $0.nameFolded < $1.nameFolded }
        }
        return base.filter { a in
            if a.nameFolded.contains(needle) { return true }
            if !a.notes.isEmpty {
                return BMSearch.fold(a.notes).contains(needle)
            }
            return false
        }
        .sorted { $0.nameFolded < $1.nameFolded }
    }

    private func deleteAttributes(at offsets: IndexSet) {
        for index in offsets {
            guard filteredAttributes.indices.contains(index) else { continue }
            let attr = filteredAttributes[index]

            AttachmentCleanup.deleteAttachments(ownerKind: .attribute, ownerID: attr.id, in: modelContext)
            LinkCleanup.deleteLinks(referencing: .attribute, id: attr.id, graphID: entity.graphID, in: modelContext)

            entity.removeAttribute(attr)
            modelContext.delete(attr)
        }
        try? modelContext.save()
    }
}

struct NodeDestinationView: View {
    @Environment(\.modelContext) private var modelContext

    let kind: NodeKind
    let id: UUID

    var body: some View {
        switch kind {
        case .entity:
            if let e = fetchEntity(id: id) {
                EntityDetailView(entity: e)
            } else {
                NodeMissingView(title: "Entität nicht gefunden")
            }
        case .attribute:
            if let a = fetchAttribute(id: id) {
                AttributeDetailView(attribute: a)
            } else {
                NodeMissingView(title: "Attribut nicht gefunden")
            }
        }
    }

    private func fetchEntity(id: UUID) -> MetaEntity? {
        let nodeID = id
        let fd = FetchDescriptor<MetaEntity>(predicate: #Predicate { e in e.id == nodeID })
        return (try? modelContext.fetch(fd).first)
    }

    private func fetchAttribute(id: UUID) -> MetaAttribute? {
        let nodeID = id
        let fd = FetchDescriptor<MetaAttribute>(predicate: #Predicate { a in a.id == nodeID })
        return (try? modelContext.fetch(fd).first)
    }
}

struct NodeMissingView: View {
    let title: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)

            Text("Der Datensatz scheint nicht mehr zu existieren oder ist nicht synchronisiert.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
    }
}