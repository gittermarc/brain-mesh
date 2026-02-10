//
//  AttachmentsSection.swift
//  BrainMesh
//
//  Created by Marc Fechner on 10.02.26.
//

import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

struct AttachmentsSection: View {
    @Environment(\.modelContext) private var modelContext

    let ownerKind: NodeKind
    let ownerID: UUID
    let graphID: UUID?

    @Query private var attachments: [MetaAttachment]

    @State private var isImportingFile = false
    @State private var activeSheet: ActiveSheet? = nil

    @State private var errorMessage: String? = nil

    /// Keep it sane: this is meant for small files.
    private let maxBytes: Int = 25 * 1024 * 1024

    init(ownerKind: NodeKind, ownerID: UUID, graphID: UUID?) {
        self.ownerKind = ownerKind
        self.ownerID = ownerID
        self.graphID = graphID

        let kindRaw = ownerKind.rawValue
        let oid = ownerID
        let gid = graphID

        _attachments = Query(
            filter: #Predicate<MetaAttachment> { a in
                a.ownerKindRaw == kindRaw && a.ownerID == oid && (gid == nil || a.graphID == gid)
            },
            sort: [SortDescriptor(\MetaAttachment.createdAt, order: .reverse)]
        )
    }

    var body: some View {
        Section {
            if attachments.isEmpty {
                Text("Keine Anhänge hinzugefügt.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(attachments) { att in
                    Button {
                        openPreview(for: att)
                    } label: {
                        AttachmentRow(attachment: att)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: deleteAttachments)
            }

            Menu {
                Button {
                    isImportingFile = true
                } label: {
                    Label("Datei auswählen", systemImage: "doc")
                }

                Button {
                    activeSheet = .videoPicker
                } label: {
                    Label("Video aus Fotos", systemImage: "video")
                }
            } label: {
                Label("Anhang hinzufügen", systemImage: "paperclip.badge.plus")
            }
        } header: {
            DetailSectionHeader(
                title: "Anhänge",
                systemImage: "paperclip",
                subtitle: "Dateien & Videos (klein halten – maximal \(ByteCountFormatter.string(fromByteCount: Int64(maxBytes), countStyle: .file)))."
            )
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
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .preview(let state):
                AttachmentPreviewSheet(
                    title: state.title,
                    url: state.url,
                    contentTypeIdentifier: state.contentTypeIdentifier,
                    fileExtension: state.fileExtension
                )
            case .videoPicker:
                VideoPicker { result in
                    Task { @MainActor in
                        await handlePickedVideo(result)
                    }
                }
            }
        }
        .alert("Anhang konnte nicht hinzugefügt werden", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Preview

    private func openPreview(for attachment: MetaAttachment) {
        guard let url = AttachmentStore.ensurePreviewURL(for: attachment) else {
            errorMessage = "Vorschau ist nicht verfügbar (keine Daten/Datei gefunden)."
            return
        }

        // Persist localPath if we had to materialize the cache from synced data.
        try? modelContext.save()
        activeSheet = .preview(PreviewState(
            url: url,
            title: attachment.title.isEmpty ? attachment.originalFilename : attachment.title,
            contentTypeIdentifier: attachment.contentTypeIdentifier,
            fileExtension: attachment.fileExtension
        ))
    }

    // MARK: - Delete

    private func deleteAttachments(at offsets: IndexSet) {
        for index in offsets {
            let att = attachments[index]
            AttachmentStore.delete(localPath: att.localPath)
            modelContext.delete(att)
        }
        try? modelContext.save()
    }

    // MARK: - Import (Files)

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
            // Copy to sandbox first (security scoped URLs are not stable).
            let copiedName = try AttachmentStore.copyIntoCache(from: url, attachmentID: attachmentID, fileExtension: ext)
            guard let copiedURL = AttachmentStore.url(forLocalPath: copiedName) else {
                errorMessage = "Lokale Datei konnte nicht erstellt werden."
                return
            }

            let data = try Data(contentsOf: copiedURL, options: [.mappedIfSafe])
            if data.count > maxBytes {
                // Just in case fileSizeKey was missing.
                AttachmentStore.delete(localPath: copiedName)
                errorMessage = "Datei ist zu groß (\(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))). Bitte nur kleine Anhänge hinzufügen."
                return
            }

            let title = url.deletingPathExtension().lastPathComponent

            let att = MetaAttachment(
                id: attachmentID,
                ownerKind: ownerKind,
                ownerID: ownerID,
                graphID: graphID,
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
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Import (Photos videos)

    @MainActor
    private func handlePickedVideo(_ result: Result<PickedVideo, Error>) async {
        defer { activeSheet = nil }

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

            // The picker may hand us a stable temp URL; we don't need it after copying.
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
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct AttachmentRow: View {

    let attachment: MetaAttachment

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: AttachmentStore.iconName(contentTypeIdentifier: attachment.contentTypeIdentifier, fileExtension: attachment.fileExtension))
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 22)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayTitle)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if !attachment.contentTypeIdentifier.isEmpty {
                        Text(attachment.contentTypeIdentifier)
                            .lineLimit(1)
                    }
                    if attachment.byteCount > 0 {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.byteCount), countStyle: .file))
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    private var displayTitle: String {
        if !attachment.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return attachment.title
        }
        if !attachment.originalFilename.isEmpty {
            return attachment.originalFilename
        }
        return "Anhang"
    }
}

private struct PreviewState: Identifiable {
    let url: URL
    let title: String
    let contentTypeIdentifier: String
    let fileExtension: String
    var id: String { url.absoluteString }
}

private enum ActiveSheet: Identifiable {
    case preview(PreviewState)
    case videoPicker

    var id: String {
        switch self {
        case .preview(let p):
            return "preview-\(p.id)"
        case .videoPicker:
            return "videoPicker"
        }
    }
}
