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
    @Environment(\.modelContext) private var modelContext

    let ownerKind: NodeKind
    let ownerID: UUID
    let graphID: UUID?

    @State private var attachments: [AttachmentListItem] = []
    @State private var totalCount: Int = 0
    @State private var isLoading: Bool = false
    @State private var hasMore: Bool = true
    @State private var offset: Int = 0
    @State private var didLoadOnce: Bool = false

    @StateObject private var importProgress = ImportProgressState()

    @State private var isImportingFile: Bool = false
    @State private var isPickingVideo: Bool = false

    @State private var videoPlayback: VideoPlaybackRequest? = nil
    @State private var attachmentPreviewSheet: AttachmentPreviewSheetState? = nil

    @State private var infoMessage: String? = nil
    @State private var errorMessage: String? = nil

    private let pageSize: Int = 40
    private let maxBytes: Int = 25 * 1024 * 1024

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
            Image(systemName: "paperclip.badge.plus")
        }
        .accessibilityLabel("Anhang hinzufügen")
    }

    private var videoPickerBackground: some View {
        VideoPickerPresenter(isPresented: $isPickingVideo) { result in
            Task { @MainActor in
                await handlePickedVideo(result)
            }
        }
    }

    private var videoPlaybackBackground: some View {
        VideoPlaybackPresenter(request: $videoPlayback)
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

    // MARK: - Loading

    @MainActor
    private func loadInitialIfNeeded() async {
        if didLoadOnce { return }
        didLoadOnce = true

        await MediaAllLoader.shared.migrateLegacyGraphIDIfNeeded(
            ownerKindRaw: ownerKind.rawValue,
            ownerID: ownerID,
            graphID: graphID
        )

        await refresh()
    }

    @MainActor
    private func refresh() async {
        isLoading = true
        offset = 0
        hasMore = true
        attachments = []

        let counts = await MediaAllLoader.shared.fetchCounts(
            ownerKindRaw: ownerKind.rawValue,
            ownerID: ownerID,
            graphID: graphID
        )

        totalCount = counts.attachments
        await loadMore(force: true)

        isLoading = false
    }

    @MainActor
    private func loadMore(force: Bool = false) async {
        if isLoading && !force { return }
        if !hasMore { return }

        isLoading = true

        let page = await MediaAllLoader.shared.fetchAttachmentPage(
            ownerKindRaw: ownerKind.rawValue,
            ownerID: ownerID,
            graphID: graphID,
            offset: offset,
            limit: pageSize
        )

        let existing = Set(attachments.map(\.id))
        let filtered = page.filter { !existing.contains($0.id) }

        if filtered.isEmpty {
            hasMore = false
            isLoading = false
            return
        }

        attachments.append(contentsOf: filtered)
        offset += page.count
        hasMore = attachments.count < totalCount

        isLoading = false
    }

    // MARK: - Open

    @MainActor
    private func openAttachment(_ item: AttachmentListItem) async {
        guard let url = await AttachmentHydrator.shared.ensureFileURL(
            attachmentID: item.id,
            fileExtension: item.fileExtension,
            localPath: item.localPath
        ) else {
            errorMessage = "Vorschau ist nicht verfügbar (keine Datei gefunden)."
            return
        }

        let isVideo = AttachmentStore.isVideo(contentTypeIdentifier: item.contentTypeIdentifier)
            || ["mov", "mp4", "m4v"].contains(item.fileExtension.lowercased())

        if isVideo {
            videoPlayback = VideoPlaybackRequest(url: url, title: item.title)
            return
        }

        attachmentPreviewSheet = AttachmentPreviewSheetState(
            url: url,
            title: item.title,
            contentTypeIdentifier: item.contentTypeIdentifier,
            fileExtension: item.fileExtension
        )
    }

    // MARK: - Delete

    @MainActor
    private func deleteAttachment(attachmentID: UUID) {
        let id = attachmentID
        let fd = FetchDescriptor<MetaAttachment>(predicate: #Predicate { a in
            a.id == id
        })

        guard let att = (try? modelContext.fetch(fd))?.first else {
            errorMessage = "Anhang konnte nicht gefunden werden."
            return
        }

        AttachmentCleanup.deleteCachedFiles(for: att)
        modelContext.delete(att)
        try? modelContext.save()

        attachments.removeAll { $0.id == attachmentID }
        totalCount = max(0, totalCount - 1)
        hasMore = attachments.count < totalCount
    }

    // MARK: - Import

    private func requestFileImport() {
        if isImportingFile { return }
        isImportingFile = true
    }

    private func requestVideoPick() {
        if isPickingVideo { return }
        isPickingVideo = true
    }

    private func importFile(from url: URL) {
        Task { @MainActor in
            importProgress.begin(
                title: "Importiere Datei…",
                subtitle: url.lastPathComponent,
                totalUnitCount: 2,
                indeterminate: false
            )
            await Task.yield()

            do {
                let attachmentID = UUID()

                importProgress.updateSubtitle("Vorbereiten…")
                let prepared = try await Task.detached(priority: .userInitiated) {
                    try AttachmentImportPipeline.prepareFileImport(
                        from: url,
                        attachmentID: attachmentID,
                        maxBytes: maxBytes
                    )
                }.value

                importProgress.setCompleted(1)

                let att = MetaAttachment(
                    id: prepared.id,
                    ownerKind: ownerKind,
                    ownerID: ownerID,
                    graphID: graphID,
                    contentKind: prepared.inferredKind,
                    title: prepared.title,
                    originalFilename: prepared.originalFilename,
                    contentTypeIdentifier: prepared.contentTypeIdentifier,
                    fileExtension: prepared.fileExtension,
                    byteCount: prepared.byteCount,
                    fileData: prepared.fileData,
                    localPath: prepared.localPath
                )

                modelContext.insert(att)
                try? modelContext.save()

                if prepared.isGalleryImage {
                    infoMessage = "Dieses Bild wurde zur Galerie einsortiert. Öffne „Bilder verwalten“, um es zu sehen."
                }

                importProgress.setCompleted(2)
                importProgress.finish(finalSubtitle: "Fertig")

                await refresh()
            } catch {
                importProgress.finish(finalSubtitle: "Fehlgeschlagen")
                errorMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    private func handlePickedVideo(_ result: Result<PickedVideo, Error>) async {
        isPickingVideo = false

        switch result {
        case .success(let picked):
            await importVideoFromURL(
                picked.url,
                suggestedFilename: picked.suggestedFilename,
                contentTypeIdentifier: picked.contentTypeIdentifier,
                fileExtension: picked.fileExtension
            )
        case .failure(let error):
            if let pickerError = error as? VideoPickerError, pickerError == .cancelled {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func importVideoFromURL(
        _ url: URL,
        suggestedFilename: String,
        contentTypeIdentifier: String,
        fileExtension: String
    ) async {
        importProgress.begin(
            title: "Importiere Video…",
            subtitle: suggestedFilename.isEmpty ? "Video" : suggestedFilename,
            totalUnitCount: 2,
            indeterminate: false
        )
        await Task.yield()

        do {
            let attachmentID = UUID()

            importProgress.updateSubtitle("Vorbereiten…")
            let prepared = try await Task.detached(priority: .userInitiated) {
                try AttachmentImportPipeline.prepareVideoImport(
                    from: url,
                    attachmentID: attachmentID,
                    suggestedFilename: suggestedFilename,
                    contentTypeIdentifier: contentTypeIdentifier,
                    fileExtension: fileExtension,
                    maxBytes: maxBytes
                )
            }.value

            importProgress.setCompleted(1)

            let att = MetaAttachment(
                id: prepared.id,
                ownerKind: ownerKind,
                ownerID: ownerID,
                graphID: graphID,
                contentKind: prepared.inferredKind,
                title: prepared.title,
                originalFilename: prepared.originalFilename,
                contentTypeIdentifier: prepared.contentTypeIdentifier,
                fileExtension: prepared.fileExtension,
                byteCount: prepared.byteCount,
                fileData: prepared.fileData,
                localPath: prepared.localPath
            )

            modelContext.insert(att)
            try? modelContext.save()

            importProgress.setCompleted(2)
            importProgress.finish(finalSubtitle: "Fertig")

            await refresh()
        } catch {
            importProgress.finish(finalSubtitle: "Fehlgeschlagen")
            errorMessage = error.localizedDescription
        }
    }
}
