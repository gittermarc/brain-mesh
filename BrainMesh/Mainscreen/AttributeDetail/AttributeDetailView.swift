//
//  AttributeDetailView.swift
//  BrainMesh
//
//  P0.4 Split: Host view (state + queries + layout skeleton)
//

import SwiftUI
import SwiftData

struct AttributeDetailView: View {
    @Environment(\.modelContext) var modelContext
    @Environment(\.dismiss) var dismiss

    @Bindable var attribute: MetaAttribute

    @Query var outgoingLinks: [MetaLink]
    @Query var incomingLinks: [MetaLink]

    // P0.2: Media preview + counts (fetch-limited, no full-load @Query).
    @State var mediaPreview: NodeMediaPreview = .empty

    @State var segment: NodeLinkDirectionSegment = .outgoing

    @State var showNotesEditor: Bool = false

    // Phase 1: Details
    @State var detailsSchemaBuilderEntity: MetaEntity? = nil
    @State var detailsValueEditorField: MetaDetailFieldDefinition? = nil

    @State var showAddLink: Bool = false
    @State var showBulkLink: Bool = false
    @State var showLinkChooser: Bool = false

    @State var showGalleryBrowser: Bool = false
    @State var showAttachmentsManager: Bool = false

    @State var showAttachmentChooser: Bool = false
    @State var showMediaManageChooser: Bool = false

    @State var galleryViewerRequest: PhotoGalleryViewerRequest? = nil
    @State var attachmentPreviewSheet: AttachmentPreviewSheetState? = nil
    @State var videoPlayback: VideoPlaybackRequest? = nil

    @State var confirmDelete: Bool = false

    @State var showRenameSheet: Bool = false

    @State var isImportingFile: Bool = false
    @State var isPickingVideo: Bool = false

    @State var errorMessage: String? = nil

    let maxBytes: Int = 25_000_000

    init(attribute: MetaAttribute) {
        self.attribute = attribute

        _outgoingLinks = NodeLinksQueryBuilder.outgoingLinksQuery(kind: .attribute, id: attribute.id, graphID: attribute.graphID)
        _incomingLinks = NodeLinksQueryBuilder.incomingLinksQuery(kind: .attribute, id: attribute.id, graphID: attribute.graphID)
    }

    var body: some View {
        ScrollViewReader { proxy in
            decorate(
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        AttributeDetailHeroAndToolbelt(
                            kindTitle: "Attribut",
                            placeholderIcon: attribute.iconSymbolName ?? "tag",
                            imageData: attribute.imageData,
                            imagePath: attribute.imagePath,
                            title: Binding(
                                get: { attribute.name },
                                set: { attribute.name = $0 }
                            ),
                            subtitle: attribute.owner?.name,
                            pills: heroPills,
                            onAddLink: { showLinkChooser = true },
                            onAddPhoto: { showGalleryBrowser = true },
                            onAddFile: { showAttachmentChooser = true }
                        )

                        AttributeDetailHighlightsRow(
                            notes: attribute.notes,
                            outgoingLinks: outgoingLinks,
                            incomingLinks: incomingLinks,
                            galleryThumbs: mediaPreview.galleryPreview,
                            galleryCount: mediaPreview.galleryCount,
                            attachmentCount: mediaPreview.attachmentCount,
                            onEditNotes: { showNotesEditor = true },
                            onJumpToMedia: {
                                withAnimation(.snappy) {
                                    proxy.scrollTo(NodeDetailAnchor.media.rawValue, anchor: .top)
                                }
                            },
                            onJumpToConnections: {
                                withAnimation(.snappy) {
                                    proxy.scrollTo(NodeDetailAnchor.connections.rawValue, anchor: .top)
                                }
                            }
                        )

                        NodeNotesCard(
                            notes: Binding(
                                get: { attribute.notes },
                                set: { attribute.notes = $0 }
                            ),
                            onEdit: { showNotesEditor = true }
                        )
                        .id(NodeDetailAnchor.notes.rawValue)

                        if let owner = attribute.owner {
                            NodeDetailsValuesCard(
                                attribute: attribute,
                                owner: owner,
                                onConfigureSchema: {
                                    detailsSchemaBuilderEntity = owner
                                },
                                onEditValue: { field in
                                    detailsValueEditorField = field
                                }
                            )
                        }

                        if let owner = attribute.owner {
                            NodeOwnerCard(owner: owner)
                        }

                        NodeConnectionsCard(
                            ownerKind: .attribute,
                            ownerID: attribute.id,
                            graphID: attribute.graphID,
                            outgoing: outgoingLinks,
                            incoming: incomingLinks,
                            segment: $segment,
                            previewLimit: 4
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

                        NodeAppearanceCard(
                            iconSymbolName: Binding(
                                get: { attribute.iconSymbolName },
                                set: { attribute.iconSymbolName = $0 }
                            )
                        )

                        Spacer(minLength: 30)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 26)
                    .task(id: attribute.id) {
                        await reloadMediaPreview()
                    }
                }
            )
        }
    }

    private var heroPills: [NodeStatPill] {
        let linkCount = outgoingLinks.count + incomingLinks.count
        let mediaCount = mediaPreview.totalCount

        var pills: [NodeStatPill] = []

        if let owner = attribute.owner {
            let pinned = owner.detailFieldsList
                .filter { $0.isPinned }
                .sorted(by: { $0.sortIndex < $1.sortIndex })
                .prefix(3)

            for field in pinned {
                if let value = DetailsFormatting.shortPillValue(for: field, on: attribute) {
                    pills.append(NodeStatPill(title: value, systemImage: DetailsFormatting.systemImage(for: field)))
                }
            }
        }

        pills.append(NodeStatPill(title: "\(linkCount)", systemImage: "link"))
        pills.append(NodeStatPill(title: "\(mediaCount)", systemImage: "photo.on.rectangle"))
        return pills
    }
}
