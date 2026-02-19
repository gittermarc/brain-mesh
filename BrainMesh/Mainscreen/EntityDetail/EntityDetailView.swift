//
//  EntityDetailView.swift
//  BrainMesh
//
//  Created by Marc Fechner on 13.12.25.
//

import SwiftUI
import SwiftData

struct EntityDetailView: View {
    @Environment(\.modelContext) var modelContext

    @Bindable var entity: MetaEntity

    @Query var outgoingLinks: [MetaLink]
    @Query var incomingLinks: [MetaLink]

    // P0.2: Media preview + counts (fetch-limited, no full-load @Query).
    @State var mediaPreview: NodeMediaPreview = .empty

    @State var showAddAttribute = false

    @State var showAddLink = false
    @State var showBulkLink = false
    @State var showLinkChooser = false

    // Gallery presentation is owned by the screen (stable host).
    @State var showGalleryBrowser: Bool = false
    @State var galleryViewerRequest: PhotoGalleryViewerRequest? = nil

    // Attachments add / manage
    @State var showAttachmentChooser: Bool = false
    @State var showMediaManageChooser: Bool = false
    @State var showAttachmentsManager: Bool = false
    @State var isImportingFile: Bool = false
    @State var isPickingVideo: Bool = false

    @State var attachmentPreviewSheet: AttachmentPreviewSheetState? = nil
    @State var videoPlayback: VideoPlaybackRequest? = nil

    @State var showNotesEditor: Bool = false

    @State var confirmDelete: Bool = false

    @State var showRenameSheet: Bool = false
    @State var errorMessage: String? = nil

    @State var connectionsSegment: NodeLinkDirectionSegment = .outgoing

    // Limit attachments/videos to keep SwiftData/CloudKit records sane.
    let maxBytes: Int = 25 * 1024 * 1024

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
    }

    var body: some View {
        ScrollViewReader { proxy in
            decorate(
                ScrollView {
                    VStack(spacing: 14) {
                        EntityDetailHeroAndToolbelt(
                            kindTitle: "Entität",
                            placeholderIcon: entity.iconSymbolName ?? "cube",
                            imageData: entity.imageData,
                            imagePath: entity.imagePath,
                            title: Binding(
                                get: { entity.name },
                                set: { entity.name = $0 }
                            ),
                            pills: [
                                NodeStatPill(title: "\(entity.attributesList.count)", systemImage: "tag"),
                                NodeStatPill(title: "\(outgoingLinks.count)", systemImage: "arrow.up.right"),
                                NodeStatPill(title: "\(incomingLinks.count)", systemImage: "arrow.down.left"),
                                NodeStatPill(title: "\(mediaPreview.totalCount)", systemImage: "photo.on.rectangle")
                            ],
                            onAddLink: { showLinkChooser = true },
                            onAddAttribute: { showAddAttribute = true },
                            onAddPhoto: { showGalleryBrowser = true },
                            onAddFile: { showAttachmentChooser = true }
                        )

                        EntityDetailHighlightsRow(
                            notes: entity.notes,
                            outgoingLinks: outgoingLinks,
                            incomingLinks: incomingLinks,
                            galleryThumbs: mediaPreview.galleryPreview,
                            galleryCount: mediaPreview.galleryCount,
                            attachmentCount: mediaPreview.attachmentCount,
                            onEditNotes: { showNotesEditor = true },
                            onJumpToMedia: { proxy.scrollTo(NodeDetailAnchor.media.rawValue, anchor: .top) },
                            onJumpToConnections: { proxy.scrollTo(NodeDetailAnchor.connections.rawValue, anchor: .top) }
                        )

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
                            galleryImages: mediaPreview.galleryPreview,
                            attachments: mediaPreview.attachmentPreview,
                            galleryCount: mediaPreview.galleryCount,
                            attachmentCount: mediaPreview.attachmentCount,
                            onOpenAll: { showGalleryBrowser = true },
                            onManage: { showMediaManageChooser = true },
                            onManageGallery: { showGalleryBrowser = true },
                            onTapGallery: { id in
                                galleryViewerRequest = PhotoGalleryViewerRequest(startAttachmentID: id)
                            },
                            onTapAttachment: { att in
                                openAttachment(att)
                            }
                        )
                        .id(NodeDetailAnchor.media.rawValue)

                        NodeDetailsSchemaCard(entity: entity)

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
                    .onAppear {
                        Task { @MainActor in
                            await reloadMediaPreview()
                        }
                    }
                }
            )
        }
    }
}
