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
    @EnvironmentObject var recentNodeStore: RecentNodeStore
    @EnvironmentObject var graphChatLaunchCoordinator: GraphChatLaunchCoordinator
    @EnvironmentObject var tabRouter: RootTabRouter

    @AppStorage(BMAppStorageKeys.activeGraphID) var activeGraphIDString: String = ""

    @Bindable var attribute: MetaAttribute

    // PR 9: Value-only links preview + exact counts from the background loader.
    @State var linksPreview: NodeConnectionsPreviewSnapshot = .empty

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

    @State private var linksPreviewLoadTriggerPolicy =
        NodeConnectionsPreviewLoadTriggerPolicy()

    // runtime-expand state for sections that start collapsed (non-persistent).
    @State var expandedSectionIDs: Set<String> = []

    // focus-mode temporary collapse (non-persistent, does not touch DisplaySettingsStore).
    @State var focusCollapsedSections: Set<AttributeDetailSection> = []

    let maxBytes: Int = 25_000_000

    init(attribute: MetaAttribute) {
        self.attribute = attribute
    }

    private var linksPreviewLoadIdentity:
        NodeConnectionsPreviewLoadIdentity
    {
        NodeConnectionsPreviewLoadIdentity(
            ownerKind: .attribute,
            ownerID: attribute.id,
            graphID: attribute.graphID ?? attribute.owner?.graphID
        )
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
                    .task(id: linksPreviewLoadIdentity) {
                        guard linksPreviewLoadTriggerPolicy
                            .registerTaskIdentity(
                                linksPreviewLoadIdentity
                            )
                        else {
                            return
                        }
                        linksPreview = .empty
                        await reloadLinksPreview()
                    }
                    .task(id: focusTaskKey) {
                        await applyFocusModeIfNeeded(proxy)
                    }
                    .onAppear {
                        recordRecentOpen()
                    }
                    .onDisappear {
                        linksPreviewLoadTriggerPolicy.resetTaskLifecycle()
                    }
                    .onChange(of: showAddLink) { _, isPresented in
                        guard linksPreviewLoadTriggerPolicy.registerAddLinkPresentation(isPresented) else {
                            return
                        }
                        Task { @MainActor in
                            await reloadLinksPreview()
                        }
                    }
                    .onChange(of: showBulkLink) { _, isPresented in
                        guard linksPreviewLoadTriggerPolicy.registerBulkLinkPresentation(isPresented) else {
                            return
                        }
                        Task { @MainActor in
                            await reloadLinksPreview()
                        }
                    }
                }
            )
        }
    }

    private func recordRecentOpen() {
        recentNodeStore.recordOpen(
            graphID: attribute.graphID,
            nodeKind: .attribute,
            nodeID: attribute.id,
            label: attribute.displayName,
            iconSymbolName: attribute.iconSymbolName
        )
    }

    // MARK: - Connections Preview (PR 9)

    @MainActor
    private func reloadLinksPreview() async {
        let identity = linksPreviewLoadIdentity
        let token = linksPreviewLoadTriggerPolicy.beginLoad(for: identity)

        guard let graphID = identity.graphID else {
            if linksPreviewLoadTriggerPolicy.accepts(
                token,
                currentIdentity: linksPreviewLoadIdentity
            ) {
                linksPreview = .empty
            }
            return
        }

        do {
            let snapshot =
                try await BMNodeConnectionsPreviewLoadInstrumentation
                .measure(
                    ownerKind: .attribute,
                    counts: { snapshot in
                        (
                            outgoing: snapshot.outgoingCount,
                            incoming: snapshot.incomingCount
                        )
                    },
                    operation: {
                        try await NodeConnectionsLoader.shared
                            .loadPreviewSnapshot(
                                ownerKind: .attribute,
                                ownerID: identity.ownerID,
                                graphID: graphID,
                                previewLimit: 12
                            )
                    }
                )

            guard linksPreviewLoadTriggerPolicy.accepts(
                token,
                currentIdentity: linksPreviewLoadIdentity
            ) else {
                return
            }
            linksPreview = snapshot
        } catch is CancellationError {
            // Task replacement and navigation cancellation are expected.
        } catch {
            // Keep the last known value-only state. Preview failures are not user-facing.
        }
    }
}
