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
    @EnvironmentObject private var display: DisplaySettingsStore

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

    @State var attachmentPreviewSheet: NodeAttachmentPreviewSheetState? = nil
    @State var videoPlayback: VideoPlaybackRequest? = nil

    @State var showNotesEditor: Bool = false

    @State var confirmDelete: Bool = false

    @State var showRenameSheet: Bool = false
    // PR 02: Quick "Anpassen…" sheet (DisplaySettings).
    @State var showCustomizeSheet: Bool = false
    @State var errorMessage: String? = nil

    @State var connectionsSegment: NodeLinkDirectionSegment = .outgoing

    // PR 01: runtime-expand state for sections that start collapsed (non-persistent).
    @State private var expandedSectionIDs: Set<String> = []

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
                            heroImageStyle: display.entityDetail.heroImageStyle,
                            title: Binding(
                                get: { entity.name },
                                set: { entity.name = $0 }
                            ),
                            pills: heroPills,
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

                        ForEach(display.entityDetail.sectionOrder, id: \.rawValue) { section in
                            entitySection(section, scrollProxy: proxy)
                        }

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

    // MARK: - Hero pills

    private var heroPills: [NodeStatPill] {
        let base: [NodeStatPill] = [
            NodeStatPill(title: "\(entity.attributesList.count)", systemImage: "tag"),
            NodeStatPill(title: "\(outgoingLinks.count)", systemImage: "arrow.up.right"),
            NodeStatPill(title: "\(incomingLinks.count)", systemImage: "arrow.down.left"),
            NodeStatPill(title: "\(mediaPreview.totalCount)", systemImage: "photo.on.rectangle")
        ]

        let settings = display.entityDetail
        guard settings.showHeroPills else { return [] }

        let limit = settings.heroPillLimit
        if limit <= 0 { return base }
        return Array(base.prefix(limit))
    }

    // MARK: - Sections (order / hidden / collapsed)

    @ViewBuilder
    private func entitySection(_ section: EntityDetailSection, scrollProxy: ScrollViewProxy) -> some View {
        let settings = display.entityDetail

        if settings.hiddenSections.contains(section) {
            EmptyView()
        } else if settings.collapsedSections.contains(section) && !expandedSectionIDs.contains(section.rawValue) {
            let card = NodeCollapsedSectionCard(
                title: entitySectionTitle(section),
                systemImage: entitySectionSystemImage(section),
                subtitle: entitySectionSubtitle(section),
                actionTitle: "Anzeigen"
            ) {
                withAnimation(.snappy) {
                    _ = expandedSectionIDs.insert(section.rawValue)
                }
            }

            if let anchor = entitySectionAnchor(section) {
                card.id(anchor)
            } else {
                card
            }
        } else {
            entitySectionContent(section, scrollProxy: scrollProxy)
        }
    }

    private func entitySectionTitle(_ section: EntityDetailSection) -> String {
        switch section {
        case .attributesPreview: return "Attribute"
        case .detailsFields: return "Details"
        case .notes: return "Notizen"
        case .media: return "Medien"
        case .connections: return "Verbindungen"
        }
    }

    private func entitySectionSystemImage(_ section: EntityDetailSection) -> String {
        switch section {
        case .attributesPreview: return "tag"
        case .detailsFields: return "list.bullet.rectangle"
        case .notes: return "note.text"
        case .media: return "photo.on.rectangle"
        case .connections: return "link"
        }
    }

    private func entitySectionAnchor(_ section: EntityDetailSection) -> String? {
        switch section {
        case .notes: return NodeDetailAnchor.notes.rawValue
        case .media: return NodeDetailAnchor.media.rawValue
        case .connections: return NodeDetailAnchor.connections.rawValue
        case .attributesPreview: return NodeDetailAnchor.attributes.rawValue
        case .detailsFields: return nil
        }
    }

    private func entitySectionSubtitle(_ section: EntityDetailSection) -> String? {
        switch section {
        case .attributesPreview:
            let n = entity.attributesList.count
            return "\(n) \(n == 1 ? "Attribut" : "Attribute")"

        case .detailsFields:
            let n = entity.detailFieldsList.count
            return "\(n) \(n == 1 ? "Feld" : "Felder")"

        case .notes:
            let trimmed = entity.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return nil }
            return trimmed.count > 40 ? String(trimmed.prefix(40)) + " (gekürzt)" : trimmed

        case .media:
            let g = mediaPreview.galleryCount
            let a = mediaPreview.attachmentCount
            if g == 0 && a == 0 { return nil }
            return "\(g) Fotos · \(a) Dateien"

        case .connections:
            let out = outgoingLinks.count
            let inc = incomingLinks.count
            if out == 0 && inc == 0 { return nil }
            return "\(out) ausgehend · \(inc) eingehend"
        }
    }

    @ViewBuilder
    private func entitySectionContent(_ section: EntityDetailSection, scrollProxy: ScrollViewProxy) -> some View {
        switch section {
        case .notes:
            NodeNotesCard(
                notes: Binding(
                    get: { entity.notes },
                    set: { entity.notes = $0 }
                ),
                onEdit: { showNotesEditor = true }
            )
            .id(NodeDetailAnchor.notes.rawValue)

        case .connections:
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

        case .media:
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

        case .detailsFields:
            NodeDetailsSchemaCard(entity: entity)

        case .attributesPreview:
            NodeEntityAttributesCard(entity: entity)
                .id(NodeDetailAnchor.attributes.rawValue)
        }
    }
}
