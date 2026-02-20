//
//  NodeDetailShared+Sheets.Attachments.swift
//  BrainMesh
//
//  Attachment management sheet used by Entity/Attribute detail screens.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct NodeAttachmentsManageView: View {
    // NOTE: Kept non-private because this view is split across multiple files.
    // Swift `private` is file-scoped, and extensions in other files would not be able to access it.
    @Environment(\.modelContext) var modelContext

    let ownerKind: NodeKind
    let ownerID: UUID
    let graphID: UUID?

    // NOTE: These are intentionally not `private` because the implementation is split into
    // multiple files via extensions (Loading / Actions / Import).
    @State var attachments: [AttachmentListItem] = []
    @State var totalCount: Int = 0
    @State var isLoading: Bool = false
    @State var hasMore: Bool = true
    @State var offset: Int = 0
    @State var didLoadOnce: Bool = false

    @StateObject var importProgress = ImportProgressState()

    @State var isImportingFile: Bool = false
    @State var isPickingVideo: Bool = false

    @State var videoPlayback: VideoPlaybackRequest? = nil
    @State var attachmentPreviewSheet: NodeAttachmentPreviewSheetState? = nil

    @State var infoMessage: String? = nil
    @State var errorMessage: String? = nil

    // NOTE: Used by split extensions.
    let pageSize: Int = 40
    let maxBytes: Int = 25 * 1024 * 1024

    var body: some View {
        listView
            .safeAreaInset(edge: .bottom) {
                ImportProgressCard(progress: importProgress)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }
            .navigationTitle("Anhänge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .task(id: ownerID) {
                await loadInitialIfNeeded()
            }
            .refreshable {
                await refresh()
            }
            .fileImporter(
                isPresented: $isImportingFile,
                allowedContentTypes: [.item],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    importFile(from: url)
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
            .background(videoPickerBackground)
            .background(videoPlaybackBackground)
            .sheet(item: $attachmentPreviewSheet) { sheet in
                AttachmentPreviewSheet(
                    title: sheet.title, url: sheet.url,
                    contentTypeIdentifier: sheet.contentTypeIdentifier,
                    fileExtension: sheet.fileExtension
                )
            }
            .alert("Hinweis", isPresented: infoAlertPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(infoMessage ?? "")
            }
            .alert("Anhänge", isPresented: errorAlertPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
    }

    // MARK: - View Pieces

    private var listView: some View {
        List {
            listContent
        }
    }

    @ViewBuilder
    private var listContent: some View {
        if attachments.isEmpty && !isLoading {
            emptyStateRow
        } else {
            attachmentsSection
        }
    }

    private var emptyStateRow: some View {
        ContentUnavailableView {
            Label("Keine Anhänge", systemImage: "paperclip")
        } description: {
            Text("Füge Dateien oder Videos hinzu, um sie hier zu verwalten.")
        }
        .listRowBackground(Color.clear)
    }

    private var attachmentsSection: some View {
        Section {
            attachmentsRows
        } header: {
            attachmentsHeader
        }
    }

    @ViewBuilder
    private var attachmentsRows: some View {
        ForEach(attachments) { item in
            AttachmentManageRow(item: item) {
                Task { @MainActor in
                    await openAttachment(item)
                }
            } onDelete: {
                Task { @MainActor in
                    deleteAttachment(attachmentID: item.id)
                }
            }
        }

        if hasMore {
            loadMoreRow
        }
    }

    private var loadMoreRow: some View {
        Button {
            Task { @MainActor in
                await loadMore()
            }
        } label: {
            HStack {
                Spacer(minLength: 0)
                if isLoading {
                    ProgressView()
                } else {
                    Label("Mehr laden", systemImage: "arrow.down.circle")
                }
                Spacer(minLength: 0)
            }
        }
        .disabled(isLoading)
    }

    private var attachmentsHeader: some View {
        HStack {
            Text("Anhänge")
            Spacer(minLength: 0)
            Text("\(totalCount)")
                .foregroundStyle(.secondary)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            addAttachmentMenu
        }
    }

    private var addAttachmentMenu: some View {
        Menu {
            Button {
                requestFileImport()
            } label: {
                Label("Datei hinzufügen", systemImage: "doc.badge.plus")
            }

            Button {
                requestVideoPick()
            } label: {
                Label("Video hinzufügen", systemImage: "video.badge.plus")
            }
        } label: {
            Image(systemName: "plus.circle")
                .imageScale(.large)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Anhang hinzufügen")
    }

    private var videoPickerBackground: some View {
        VideoPickerPresenter(isPresented: $isPickingVideo) { result in
            Task { @MainActor in
                await handlePickedVideo(result)
            }
        }
        .frame(width: 0, height: 0)

    }

    private var videoPlaybackBackground: some View {
        VideoPlaybackPresenter(request: $videoPlayback)
        .frame(width: 0, height: 0)

    }

    private var infoAlertPresented: Binding<Bool> {
        Binding(
            get: { infoMessage != nil },
            set: { if !$0 { infoMessage = nil } }
        )
    }

    private var errorAlertPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    // MARK: - Implementation Split
    // The implementation of this view is split into separate files to keep this host view small.
    // - Loading: NodeAttachmentsManageView+Loading.swift
    // - Actions (open/delete): NodeAttachmentsManageView+Actions.swift
    // - Import (file/video): NodeAttachmentsManageView+Import.swift
}
