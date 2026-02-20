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
    @EnvironmentObject private var display: DisplaySettingsStore

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
    @State var attachmentPreviewSheet: NodeAttachmentPreviewSheetState? = nil
    @State var videoPlayback: VideoPlaybackRequest? = nil

    @State var confirmDelete: Bool = false

    @State var showRenameSheet: Bool = false

    // PR 02: Quick "Anpassen…" sheet (DisplaySettings).
    @State var showCustomizeSheet: Bool = false

    @State var isImportingFile: Bool = false
    @State var isPickingVideo: Bool = false

    @State var errorMessage: String? = nil

    // PR 01: runtime-expand state for sections that start collapsed (non-persistent).
    @State private var expandedSectionIDs: Set<String> = []

    // PR 03: focus-mode temporary collapse (non-persistent, does not touch DisplaySettingsStore).
    @State private var focusCollapsedSections: Set<AttributeDetailSection> = []

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

                        ForEach(display.attributeDetail.sectionOrder, id: \.rawValue) { section in
                            attributeSection(section)
                        }

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
                    .task(id: focusTaskKey) {
                        await applyFocusModeIfNeeded(proxy)
                    }
                }
            )
        }
    }

    private var focusTaskKey: String {
        attribute.id.uuidString + "|" + display.attributeDetail.focusMode.rawValue
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

    // MARK: - Sections (order / hidden / collapsed)

    @ViewBuilder
    private func attributeSection(_ section: AttributeDetailSection) -> some View {
        let settings = display.attributeDetail

        let isCollapsedBySettings = settings.collapsedSections.contains(section)
        let isCollapsedByFocus = focusCollapsedSections.contains(section)
        let isExpandedAtRuntime = expandedSectionIDs.contains(section.rawValue)

        if settings.hiddenSections.contains(section) {
            EmptyView()
        } else if (isCollapsedBySettings || isCollapsedByFocus) && !isExpandedAtRuntime {
            let card = NodeCollapsedSectionCard(
                title: attributeSectionTitle(section),
                systemImage: attributeSectionSystemImage(section),
                subtitle: attributeSectionSubtitle(section),
                actionTitle: "Anzeigen"
            ) {
                withAnimation(.snappy) {
                    _ = expandedSectionIDs.insert(section.rawValue)
                    focusCollapsedSections.remove(section)
                }
            }

            if let anchor = attributeSectionAnchor(section) {
                card.id(anchor)
            } else {
                card
            }
        } else {
            attributeSectionContent(section)
        }
    }

    private func attributeSectionTitle(_ section: AttributeDetailSection) -> String {
        switch section {
        case .detailsFields: return "Details"
        case .notes: return "Notizen"
        case .media: return "Medien"
        case .connections: return "Verbindungen"
        }
    }

    private func attributeSectionSystemImage(_ section: AttributeDetailSection) -> String {
        switch section {
        case .detailsFields: return "list.bullet.rectangle"
        case .notes: return "note.text"
        case .media: return "photo.on.rectangle"
        case .connections: return "link"
        }
    }

    private func attributeSectionAnchor(_ section: AttributeDetailSection) -> String? {
        switch section {
        case .detailsFields: return NodeDetailAnchor.details.rawValue
        case .notes: return NodeDetailAnchor.notes.rawValue
        case .media: return NodeDetailAnchor.media.rawValue
        case .connections: return NodeDetailAnchor.connections.rawValue
        }
    }

    private func attributeSectionSubtitle(_ section: AttributeDetailSection) -> String? {
        switch section {
        case .detailsFields:
            guard let owner = attribute.owner else { return nil }
            let n = owner.detailFieldsList.count
            return "\(n) \(n == 1 ? "Feld" : "Felder")"

        case .notes:
            let trimmed = attribute.notes.trimmingCharacters(in: .whitespacesAndNewlines)
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
    private func attributeSectionContent(_ section: AttributeDetailSection) -> some View {
        switch section {
        case .notes:
            NodeNotesCard(
                notes: Binding(
                    get: { attribute.notes },
                    set: { attribute.notes = $0 }
                ),
                onEdit: { showNotesEditor = true }
            )
            .id(NodeDetailAnchor.notes.rawValue)

        case .detailsFields:
            if let owner = attribute.owner {
                NodeDetailsValuesCard(
                    attribute: attribute,
                    owner: owner,
                    layout: display.attributeDetail.detailsLayout,
                    hideEmpty: display.attributeDetail.hideEmptyDetails,
                    onConfigureSchema: {
                        detailsSchemaBuilderEntity = owner
                    },
                    onEditValue: { field in
                        detailsValueEditorField = field
                    }
                )
                .id(NodeDetailAnchor.details.rawValue)

                NodeOwnerCard(owner: owner)
            }

        case .connections:
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

        case .media:
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
        }
    }

    // MARK: - Focus Mode

    private func focusTargetSection(for mode: AttributeDetailFocusMode) -> AttributeDetailSection? {
        switch mode {
        case .auto:
            return nil
        case .writing:
            return .notes
        case .data:
            return .detailsFields
        case .linking:
            return .connections
        case .media:
            return .media
        }
    }

    private func applyFocusModeIfNeeded(_ proxy: ScrollViewProxy) async {
        let mode = display.attributeDetail.focusMode

        guard let target = focusTargetSection(for: mode) else {
            await MainActor.run {
                focusCollapsedSections = []
            }
            return
        }

        let settings = display.attributeDetail

        if settings.hiddenSections.contains(target) {
            await MainActor.run {
                focusCollapsedSections = []
            }
            return
        }

        await MainActor.run {
            let ordered = settings.sectionOrder.filter { !settings.hiddenSections.contains($0) }
            focusCollapsedSections = Set(ordered.filter { $0 != target })
            _ = expandedSectionIDs.insert(target.rawValue)
        }

        // Give SwiftUI a beat to lay out the collapsed cards / anchors before scrolling.
        try? await Task.sleep(nanoseconds: 120_000_000)

        guard let anchor = attributeSectionAnchor(target) else { return }

        await MainActor.run {
            withAnimation(.snappy) {
                proxy.scrollTo(anchor, anchor: .top)
            }
        }
    }
}
