//
//  NodeDetailShared+Media.swift
//  BrainMesh
//
//  Shared media UI for Entity/Attribute detail screens.
//

import SwiftUI
import SwiftData
import UIKit

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
                .stroke(Color.secondary.opacity(0.12))
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

    @MainActor
    private func loadThumbnailIfNeeded() async {
        if thumbnail != nil { return }
        guard let url = AttachmentStore.materializeFileURLForThumbnailIfNeeded(for: attachment) else { return }

        let scale = UIScreen.main.scale
        let requestSize = CGSize(width: 420, height: 420)

        let img = await AttachmentThumbnailStore.shared.thumbnail(
            attachmentID: attachment.id,
            fileURL: url,
            isVideo: false,
            requestSize: requestSize,
            scale: scale
        )

        thumbnail = img
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
            VStack(alignment: .leading, spacing: 14) {
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
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Anhänge")
                            .font(.headline)

                        ForEach(attachments) { att in
                            AttachmentCardRow(attachment: att)
                                .onTapGesture { openAttachment(att) }
                        }
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
