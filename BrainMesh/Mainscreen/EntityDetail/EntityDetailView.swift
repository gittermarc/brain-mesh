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
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var display: DisplaySettingsStore
    @EnvironmentObject var recentNodeStore: RecentNodeStore
    @EnvironmentObject var graphChatLaunchCoordinator: GraphChatLaunchCoordinator
    @EnvironmentObject var tabRouter: RootTabRouter

    @AppStorage(BMAppStorageKeys.activeGraphID) var activeGraphIDString: String = ""

    @Bindable var entity: MetaEntity

    // P0.1: Links preview + counts (fetch-limited, no full-load @Query).
    @State var outgoingLinksPreview: [MetaLink] = []
    @State var incomingLinksPreview: [MetaLink] = []
    @State var outgoingLinksCount: Int = 0
    @State var incomingLinksCount: Int = 0

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
    @State var expandedSectionIDs: Set<String> = []

    // Limit attachments/videos to keep SwiftData/CloudKit records sane.
    let maxBytes: Int = 25 * 1024 * 1024

    init(entity: MetaEntity) {
        self.entity = entity
    }

    var body: some View {
        ScrollViewReader { proxy in
            decorate(
                ScrollView {
                    VStack(spacing: 14) {
                        headerSection(proxy: proxy)
                        sectionsList
                        appearanceSection
                        Spacer(minLength: 8)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 18)
                    .task(id: entity.id) {
                        await reloadMediaPreview()
                    }
                    .task(id: linksTaskKey) {
                        await reloadLinksPreview()
                    }
                    .onAppear {
                        recordRecentOpen()
                    }
                    .onChange(of: showAddLink) { _, isPresented in
                        handleLinkSheetPresentationChanged(isPresented)
                    }
                    .onChange(of: showBulkLink) { _, isPresented in
                        handleBulkLinkSheetPresentationChanged(isPresented)
                    }
                }
            )
        }
    }

    private func recordRecentOpen() {
        recentNodeStore.recordOpen(
            graphID: entity.graphID,
            nodeKind: .entity,
            nodeID: entity.id,
            label: entity.name,
            iconSymbolName: entity.iconSymbolName
        )
    }
}
