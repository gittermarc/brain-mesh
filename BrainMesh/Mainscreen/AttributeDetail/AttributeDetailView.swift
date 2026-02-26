//
//  AttributeDetailView.swift
//  BrainMesh
//
//  P0.3a Split: Host view (state + queries + layout skeleton)
//

import SwiftUI
import SwiftData

struct AttributeDetailView: View {
    @Environment(\.modelContext) var modelContext
    @Environment(\.dismiss) var dismiss

    // NOTE: Must not be `private` because AttributeDetailView is split across multiple files via extensions.
    @EnvironmentObject var display: DisplaySettingsStore

    @Bindable var attribute: MetaAttribute

    @Query var outgoingLinks: [MetaLink]
    @Query var incomingLinks: [MetaLink]

    // Media preview + counts (fetch-limited, no full-load @Query).
    @State var mediaPreview: NodeMediaPreview = .empty

    @State var segment: NodeLinkDirectionSegment = .outgoing

    @State var showNotesEditor: Bool = false

    // Details
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

    // Quick "Anpassen…" sheet (DisplaySettings).
    @State var showCustomizeSheet: Bool = false

    @State var isImportingFile: Bool = false
    @State var isPickingVideo: Bool = false

    @State var errorMessage: String? = nil

    // runtime-expand state for sections that start collapsed (non-persistent).
    @State var expandedSectionIDs: Set<String> = []

    // focus-mode temporary collapse (non-persistent, does not touch DisplaySettingsStore).
    @State var focusCollapsedSections: Set<AttributeDetailSection> = []

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
                        headerSection(proxy: proxy)
                        sectionsList
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
}
