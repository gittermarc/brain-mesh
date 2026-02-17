//
//  NodeDetailShared+SheetsSupport.swift
//  BrainMesh
//
//  Shared sheet helpers used by multiple detail screens.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

struct AttachmentPreviewSheetState: Identifiable {
    let url: URL
    let title: String
    let contentTypeIdentifier: String
    let fileExtension: String

    var id: String { url.absoluteString }
}

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

private struct AttachmentManageRow: View {
    let item: AttachmentListItem
    let onOpen: () -> Void
    let onDelete: () -> Void

    @State private var thumbnail: UIImage? = nil

    var body: some View {
        HStack(spacing: 12) {
            thumbnailTile

            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayTitle)
                    .lineLimit(1)

                HStack(spacing: 0) {
                    Text(kindLabel)
                    Text(" · ")

                    if item.byteCount > 0 {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(item.byteCount), countStyle: .file))
                        Text(" · ")
                    }

                    Text(item.createdAt, format: .dateTime.day(.twoDigits).month(.twoDigits).year().hour().minute())
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
        .contextMenu {
            Button {
                onOpen()
            } label: {
                Label("Öffnen", systemImage: "eye")
            }

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Löschen", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Löschen", systemImage: "trash")
            }
        }
        .task(id: item.id) {
            await resetStateForNewItem()
            await loadThumbnailIfPossible()
        }
    }

    @MainActor
    private func resetStateForNewItem() {
        thumbnail = nil
    }

    // MARK: - Thumbnail

    private var thumbnailTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.quaternary)

            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Image(systemName: iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.tint)
            }

            if isVideo {
                Image(systemName: "play.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(.black.opacity(0.55))
                    .clipShape(Circle())
            }

            Text(typeBadge)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .padding(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .frame(width: thumbSize.width, height: thumbSize.height)
        .clipped()
    }

    private var thumbSize: CGSize {
        if isVideo {
            let width = round(54 * 16.0 / 9.0)
            return CGSize(width: width, height: 54)
        }
        return CGSize(width: 54, height: 54)
    }

    private func loadThumbnailIfPossible() async {
        if thumbnail != nil { return }

        guard let fileURL = await resolveFileURLForThumbnail() else {
            return
        }

        let scale = UIScreen.main.scale
        let requestSize: CGSize = isVideo ? CGSize(width: 320, height: 180) : CGSize(width: 220, height: 220)

        let image = await AttachmentThumbnailStore.shared.thumbnail(
            attachmentID: item.id,
            fileURL: fileURL,
            isVideo: isVideo,
            requestSize: requestSize,
            scale: scale
        )

        await MainActor.run {
            thumbnail = image
        }
    }

    private func resolveFileURLForThumbnail() async -> URL? {
        if let localPath = item.localPath,
           let url = AttachmentStore.url(forLocalPath: localPath),
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }

        return await AttachmentHydrator.shared.ensureFileURL(
            attachmentID: item.id,
            fileExtension: item.fileExtension,
            localPath: item.localPath
        )
    }

    // MARK: - Metadata

    private var iconName: String {
        AttachmentStore.iconName(
            contentTypeIdentifier: item.contentTypeIdentifier,
            fileExtension: item.fileExtension
        )
    }

    private var isVideo: Bool {
        if AttachmentStore.isVideo(contentTypeIdentifier: item.contentTypeIdentifier) { return true }
        return ["mov", "mp4", "m4v"].contains(item.fileExtension.lowercased())
    }

    private var kindLabel: String {
        if let type = UTType(item.contentTypeIdentifier) {
            if type.conforms(to: .pdf) { return "PDF" }
            if type.conforms(to: .image) { return "Bild" }
            if type.conforms(to: .audio) { return "Audio" }
            if type.conforms(to: .movie) || type.conforms(to: .video) { return "Video" }
            if type.conforms(to: .archive) { return "Archiv" }
            if type.conforms(to: .text) { return "Text" }
        }

        let ext = item.fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: ".")).uppercased()
        if !ext.isEmpty { return ext }
        return "Datei"
    }

    private var typeBadge: String {
        let ext = item.fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: ".")).uppercased()
        if !ext.isEmpty { return ext }
        return kindLabel.uppercased()
    }
}
