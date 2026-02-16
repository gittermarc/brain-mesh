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

    @Query var galleryImages: [MetaAttachment]
    @Query var attachments: [MetaAttachment]

    @State var segment: NodeLinkDirectionSegment = .outgoing

    @State var showNotesEditor: Bool = false

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

    @State var isImportingFile: Bool = false
    @State var isPickingVideo: Bool = false

    @State var errorMessage: String? = nil

    let maxBytes: Int = 25_000_000

    init(attribute: MetaAttribute) {
        self.attribute = attribute

        _outgoingLinks = NodeLinksQueryBuilder.outgoingLinksQuery(kind: .attribute, id: attribute.id, graphID: attribute.graphID)
        _incomingLinks = NodeLinksQueryBuilder.incomingLinksQuery(kind: .attribute, id: attribute.id, graphID: attribute.graphID)

        _galleryImages = PhotoGalleryQueryBuilder.galleryImagesQuery(ownerKind: .attribute, ownerID: attribute.id, graphID: attribute.graphID)

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
                            galleryImages: galleryImages,
                            attachments: attachments,
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
                            galleryImages: galleryImages,
                            attachments: attachments,
                            onOpenAll: {},
                            onManage: { showMediaManageChooser = true },
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
                }
            )
        }
    }

    private var heroPills: [NodeStatPill] {
        let linkCount = outgoingLinks.count + incomingLinks.count
        let mediaCount = galleryImages.count + attachments.count

        var pills: [NodeStatPill] = []
        pills.append(NodeStatPill(title: "\(linkCount)", systemImage: "link"))
        pills.append(NodeStatPill(title: "\(mediaCount)", systemImage: "photo.on.rectangle"))
        return pills
    }
}
