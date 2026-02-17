//
//  NodeDetailShared+SheetsSupport.swift
//  BrainMesh
//
//  Shared sheet helpers used by multiple detail screens.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

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
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }

        let fileName = url.lastPathComponent
        let ext = url.pathExtension

        let contentType = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)?.identifier ?? ""
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0

        if fileSize > maxBytes {
            errorMessage = "Datei ist zu groß (\(ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file))). Bitte nur kleine Anhänge hinzufügen."
            return
        }

        let attachmentID = UUID()

        do {
            let copiedName = try AttachmentStore.copyIntoCache(from: url, attachmentID: attachmentID, fileExtension: ext)
            guard let copiedURL = AttachmentStore.url(forLocalPath: copiedName) else {
                errorMessage = "Lokale Datei konnte nicht erstellt werden."
                return
            }

            let data = try Data(contentsOf: copiedURL, options: [.mappedIfSafe])
            if data.count > maxBytes {
                AttachmentStore.delete(localPath: copiedName)
                errorMessage = "Datei ist zu groß (\(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))). Bitte nur kleine Anhänge hinzufügen."
                return
            }

            let title = url.deletingPathExtension().lastPathComponent

            let inferredKind: AttachmentContentKind
            if let t = UTType(contentType) {
                if t.conforms(to: .image) {
                    inferredKind = .galleryImage
                } else if t.conforms(to: .movie) || t.conforms(to: .video) {
                    inferredKind = .video
                } else {
                    inferredKind = .file
                }
            } else {
                inferredKind = .file
            }

            let att = MetaAttachment(
                id: attachmentID,
                ownerKind: ownerKind,
                ownerID: ownerID,
                graphID: graphID,
                contentKind: inferredKind,
                title: title,
                originalFilename: fileName,
                contentTypeIdentifier: contentType,
                fileExtension: ext,
                byteCount: data.count,
                fileData: data,
                localPath: copiedName
            )

            modelContext.insert(att)
            try? modelContext.save()

            if inferredKind == .galleryImage {
                infoMessage = "Dieses Bild wurde zur Galerie einsortiert. Öffne „Bilder verwalten“, um es zu sehen."
            }

            Task { @MainActor in
                await refresh()
            }
        } catch {
            errorMessage = error.localizedDescription
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
        do {
            let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if fileSize > maxBytes {
                errorMessage = "Video ist zu groß (\(ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file))). Bitte nur kleine Videos hinzufügen."
                return
            }

            let attachmentID = UUID()
            let ext = fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: ".")).isEmpty ? "mov" : fileExtension

            let cachedFilename = try AttachmentStore.copyIntoCache(from: url, attachmentID: attachmentID, fileExtension: ext)
            guard let cachedURL = AttachmentStore.url(forLocalPath: cachedFilename) else {
                errorMessage = "Lokale Videodatei konnte nicht erstellt werden."
                return
            }

            try? FileManager.default.removeItem(at: url)

            let data = try Data(contentsOf: cachedURL, options: [.mappedIfSafe])
            if data.count > maxBytes {
                AttachmentStore.delete(localPath: cachedFilename)
                errorMessage = "Video ist zu groß (\(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))). Bitte nur kleine Videos hinzufügen."
                return
            }

            let title = URL(fileURLWithPath: suggestedFilename).deletingPathExtension().lastPathComponent
            let originalName = suggestedFilename.isEmpty ? "Video.\(ext)" : suggestedFilename

            let typeID: String
            if !contentTypeIdentifier.isEmpty {
                typeID = contentTypeIdentifier
            } else if let t = UTType(filenameExtension: ext)?.identifier {
                typeID = t
            } else {
                typeID = UTType.movie.identifier
            }

            let att = MetaAttachment(
                id: attachmentID,
                ownerKind: ownerKind,
                ownerID: ownerID,
                graphID: graphID,
                contentKind: .video,
                title: title.isEmpty ? "Video" : title,
                originalFilename: originalName,
                contentTypeIdentifier: typeID,
                fileExtension: ext,
                byteCount: data.count,
                fileData: data,
                localPath: cachedFilename
            )

            modelContext.insert(att)
            try? modelContext.save()

            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct AttachmentManageRow: View {
    let item: AttachmentListItem
    let onOpen: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.quaternary)

                Image(systemName: iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.tint)

                Text(typeBadge)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
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
    }

    private var iconName: String {
        AttachmentStore.iconName(
            contentTypeIdentifier: item.contentTypeIdentifier,
            fileExtension: item.fileExtension
        )
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
