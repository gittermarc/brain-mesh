//
//  GraphStatsService+Media.swift
//  BrainMesh
//

import Foundation
import SwiftData

nonisolated extension GraphStatsService {
    /// Media breakdown for a single graph.
    /// Notes:
    /// - "Header images" are counted via `imageData` (entities + attributes).
    /// - Attachment kinds are derived from `contentKindRaw`.
    func mediaSnapshot(for graphID: UUID?) throws -> GraphMediaSnapshot {
        let headerImages = try headerImagesCount(for: graphID)

        let attachments = try context.fetch(
            FetchDescriptor<MetaAttachment>(predicate: attachmentGraphPredicate(for: graphID))
        )

        var fileCount = 0
        var videoCount = 0
        var galleryCount = 0

        var fileExtCounts: [String: Int] = [:]

        for a in attachments {
            switch a.contentKind {
            case .file:
                fileCount += 1
                let ext = normalizeFileExtension(a.fileExtension)
                fileExtCounts[ext, default: 0] += 1
            case .video:
                videoCount += 1
            case .galleryImage:
                galleryCount += 1
            }
        }

        let topFileExtensions = fileExtCounts
            .map { GraphTopItem(label: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.label < rhs.label
            }
            .prefix(8)
            .map { $0 }

        let largestAttachments = attachments
            .sorted { $0.byteCount > $1.byteCount }
            .prefix(8)
            .map {
                GraphLargestAttachment(
                    id: $0.id,
                    title: bestAttachmentTitle($0),
                    byteCount: $0.byteCount,
                    contentKind: $0.contentKind,
                    fileExtension: normalizeFileExtension($0.fileExtension)
                )
            }

        let topMediaNodes = try topMediaNodes(for: graphID, attachments: attachments)

        return GraphMediaSnapshot(
            headerImages: headerImages,
            attachmentsTotal: attachments.count,
            attachmentsFile: fileCount,
            attachmentsVideo: videoCount,
            attachmentsGalleryImages: galleryCount,
            topFileExtensions: topFileExtensions,
            largestAttachments: largestAttachments,
            topMediaNodes: topMediaNodes
        )
    }
}

private nonisolated extension GraphStatsService {
    func headerImagesCount(for graphID: UUID?) throws -> Int {
        let entityImages = try context.fetchCount(
            FetchDescriptor<MetaEntity>(predicate: entityImageDataPredicate(for: graphID))
        )
        let attributeImages = try context.fetchCount(
            FetchDescriptor<MetaAttribute>(predicate: attributeImageDataPredicate(for: graphID))
        )
        return entityImages + attributeImages
    }

    func normalizeFileExtension(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "?" }
        if trimmed.hasPrefix(".") {
            let drop = String(trimmed.dropFirst())
            return drop.isEmpty ? "?" : drop.lowercased()
        }
        return trimmed.lowercased()
    }

    func bestAttachmentTitle(_ a: MetaAttachment) -> String {
        let t = a.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty == false { return t }

        let n = a.originalFilename.trimmingCharacters(in: .whitespacesAndNewlines)
        if n.isEmpty == false { return n }

        let ext = normalizeFileExtension(a.fileExtension)
        if ext == "?" { return "Anhang" }
        return "Anhang .\(ext)"
    }

    func topMediaNodes(for graphID: UUID?, attachments: [MetaAttachment]) throws -> [GraphMediaNodeItem] {
        var attachmentCountByID: [UUID: Int] = [:]
        var kindByID: [UUID: NodeKind] = [:]

        for a in attachments {
            attachmentCountByID[a.ownerID, default: 0] += 1
            kindByID[a.ownerID] = a.ownerKind
        }

        // Fetch nodes (for labels + header image presence).
        let entities = try context.fetch(
            FetchDescriptor<MetaEntity>(predicate: entityGraphPredicate(for: graphID))
        )
        let attributes = try context.fetch(
            FetchDescriptor<MetaAttribute>(predicate: attributeGraphPredicate(for: graphID))
        )

        var labelByID: [UUID: String] = [:]
        var headerImageCountByID: [UUID: Int] = [:]

        for e in entities {
            let hasAttachment = attachmentCountByID[e.id] != nil
            let hasHeader = (e.imageData != nil)
            if hasAttachment || hasHeader {
                labelByID[e.id] = e.name
                headerImageCountByID[e.id] = hasHeader ? 1 : 0
                kindByID[e.id] = .entity
            }
        }

        for a in attributes {
            let hasAttachment = attachmentCountByID[a.id] != nil
            let hasHeader = (a.imageData != nil)
            if hasAttachment || hasHeader {
                labelByID[a.id] = a.displayName
                headerImageCountByID[a.id] = hasHeader ? 1 : 0
                kindByID[a.id] = .attribute
            }
        }

        let candidateIDs = Set(attachmentCountByID.keys).union(headerImageCountByID.keys)

        let items = candidateIDs
            .map { id -> GraphMediaNodeItem in
                let label = labelByID[id] ?? shortID(id)
                let kind = kindByID[id] ?? .entity
                let attachmentCount = attachmentCountByID[id] ?? 0
                let headerCount = headerImageCountByID[id] ?? 0
                return GraphMediaNodeItem(
                    id: id,
                    label: label,
                    kind: kind,
                    attachmentCount: attachmentCount,
                    headerImageCount: headerCount
                )
            }
            .filter { $0.mediaCount > 0 }
            .sorted { lhs, rhs in
                if lhs.mediaCount != rhs.mediaCount { return lhs.mediaCount > rhs.mediaCount }
                if lhs.attachmentCount != rhs.attachmentCount { return lhs.attachmentCount > rhs.attachmentCount }
                return lhs.label < rhs.label
            }

        return Array(items.prefix(10))
    }
}
