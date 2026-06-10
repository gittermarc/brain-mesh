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
        let attachmentCounts = try mediaAttachmentCounts(for: graphID)

        guard attachmentCounts.total > 0 || headerImages > 0 else {
            return GraphMediaSnapshot(
                headerImages: 0,
                attachmentsTotal: 0,
                attachmentsFile: 0,
                attachmentsVideo: 0,
                attachmentsGalleryImages: 0,
                topFileExtensions: [],
                largestAttachments: [],
                topMediaNodes: []
            )
        }

        let attachmentItems: [GraphStatsMediaAttachmentItem]
        let largestAttachmentItems: [GraphLargestAttachment]
        if attachmentCounts.total > 0 {
            attachmentItems = try mediaAttachmentItems(for: graphID)
            largestAttachmentItems = try largestAttachments(for: graphID)
        } else {
            attachmentItems = []
            largestAttachmentItems = []
        }

        let topFileExtensions = makeTopFileExtensions(from: attachmentItems)
        let topMediaNodes = try topMediaNodes(for: graphID, attachmentItems: attachmentItems)

        return GraphMediaSnapshot(
            headerImages: headerImages,
            attachmentsTotal: attachmentCounts.total,
            attachmentsFile: attachmentCounts.files,
            attachmentsVideo: attachmentCounts.videos,
            attachmentsGalleryImages: attachmentCounts.galleryImages,
            topFileExtensions: topFileExtensions,
            largestAttachments: largestAttachmentItems,
            topMediaNodes: topMediaNodes
        )
    }
}

private nonisolated struct GraphStatsMediaAttachmentCounts: Equatable, Sendable {
    let total: Int
    let files: Int
    let videos: Int
    let galleryImages: Int
}

private nonisolated struct GraphStatsMediaAttachmentItem: Equatable, Sendable {
    let ownerID: UUID
    let ownerKind: NodeKind
    let contentKind: AttachmentContentKind
    let fileExtension: String
}

private nonisolated struct GraphStatsLargestAttachmentCandidate: Equatable, Sendable {
    let id: UUID
    let title: String
    let originalFilename: String
    let byteCount: Int
    let contentKind: AttachmentContentKind
    let fileExtension: String
}

private nonisolated extension GraphStatsService {
    func mediaAttachmentCounts(for graphID: UUID?) throws -> GraphStatsMediaAttachmentCounts {
        GraphStatsMediaAttachmentCounts(
            total: try attachmentCount(for: .graph(graphID)),
            files: try attachmentCount(for: graphID, contentKind: .file),
            videos: try attachmentCount(for: graphID, contentKind: .video),
            galleryImages: try attachmentCount(for: graphID, contentKind: .galleryImage)
        )
    }

    func mediaAttachmentItems(for graphID: UUID?) throws -> [GraphStatsMediaAttachmentItem] {
        let attachments = try context.fetch(
            FetchDescriptor<MetaAttachment>(predicate: attachmentGraphPredicate(for: graphID))
        )

        return attachments.map { attachment in
            GraphStatsMediaAttachmentItem(
                ownerID: attachment.ownerID,
                ownerKind: attachment.ownerKind,
                contentKind: attachment.contentKind,
                fileExtension: normalizeFileExtension(attachment.fileExtension)
            )
        }
    }

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

    func bestAttachmentTitle(_ item: GraphStatsLargestAttachmentCandidate) -> String {
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty == false { return title }

        let filename = item.originalFilename.trimmingCharacters(in: .whitespacesAndNewlines)
        if filename.isEmpty == false { return filename }

        if item.fileExtension == "?" { return "Anhang" }
        return "Anhang .\(item.fileExtension)"
    }

    func makeTopFileExtensions(from items: [GraphStatsMediaAttachmentItem]) -> [GraphTopItem] {
        let fileExtCounts = items.reduce(into: [String: Int]()) { partialResult, item in
            guard item.contentKind == .file else { return }
            partialResult[item.fileExtension, default: 0] += 1
        }

        return fileExtCounts
            .map { GraphTopItem(label: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.label < rhs.label
            }
            .prefix(8)
            .map { $0 }
    }

    func largestAttachments(for graphID: UUID?) throws -> [GraphLargestAttachment] {
        var descriptor = FetchDescriptor<MetaAttachment>(
            predicate: attachmentGraphPredicate(for: graphID),
            sortBy: [SortDescriptor(\MetaAttachment.byteCount, order: .reverse)]
        )
        descriptor.fetchLimit = 8

        let candidates = try context.fetch(descriptor).map { attachment in
            GraphStatsLargestAttachmentCandidate(
                id: attachment.id,
                title: attachment.title,
                originalFilename: attachment.originalFilename,
                byteCount: attachment.byteCount,
                contentKind: attachment.contentKind,
                fileExtension: normalizeFileExtension(attachment.fileExtension)
            )
        }

        return candidates.map { item in
            GraphLargestAttachment(
                id: item.id,
                title: bestAttachmentTitle(item),
                byteCount: item.byteCount,
                contentKind: item.contentKind,
                fileExtension: item.fileExtension
            )
        }
    }

    func topMediaNodes(
        for graphID: UUID?,
        attachmentItems: [GraphStatsMediaAttachmentItem]
    ) throws -> [GraphMediaNodeItem] {
        var attachmentCountByID: [UUID: Int] = [:]
        var kindByID: [UUID: NodeKind] = [:]
        var attachmentEntityIDs = Set<UUID>()
        var attachmentAttributeIDs = Set<UUID>()

        for item in attachmentItems {
            attachmentCountByID[item.ownerID, default: 0] += 1
            kindByID[item.ownerID] = item.ownerKind
            switch item.ownerKind {
            case .entity:
                attachmentEntityIDs.insert(item.ownerID)
            case .attribute:
                attachmentAttributeIDs.insert(item.ownerID)
            }
        }

        var labelByID: [UUID: String] = [:]
        var headerImageCountByID: [UUID: Int] = [:]

        let attachmentOwnerEntities = try entities(for: graphID, ids: attachmentEntityIDs)
        let attachmentOwnerAttributes = try attributes(for: graphID, ids: attachmentAttributeIDs)
        let headerImageEntities = try headerImageEntities(for: graphID)
        let headerImageAttributes = try headerImageAttributes(for: graphID)

        for entity in attachmentOwnerEntities {
            labelByID[entity.id] = entity.name
            kindByID[entity.id] = .entity
        }

        for attribute in attachmentOwnerAttributes {
            labelByID[attribute.id] = attribute.displayName
            kindByID[attribute.id] = .attribute
        }

        for entity in headerImageEntities {
            labelByID[entity.id] = entity.name
            headerImageCountByID[entity.id] = 1
            kindByID[entity.id] = .entity
        }

        for attribute in headerImageAttributes {
            labelByID[attribute.id] = attribute.displayName
            headerImageCountByID[attribute.id] = 1
            kindByID[attribute.id] = .attribute
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

    func entities(for graphID: UUID?, ids: Set<UUID>) throws -> [MetaEntity] {
        guard ids.isEmpty == false else { return [] }
        let entityIDs = Array(ids)
        let descriptor: FetchDescriptor<MetaEntity>
        if let graphID {
            descriptor = FetchDescriptor<MetaEntity>(predicate: #Predicate<MetaEntity> { entity in
                entityIDs.contains(entity.id) && entity.graphID == graphID
            })
        } else {
            descriptor = FetchDescriptor<MetaEntity>(predicate: #Predicate<MetaEntity> { entity in
                entityIDs.contains(entity.id) && entity.graphID == nil
            })
        }
        return try context.fetch(descriptor)
    }

    func attributes(for graphID: UUID?, ids: Set<UUID>) throws -> [MetaAttribute] {
        guard ids.isEmpty == false else { return [] }
        let attributeIDs = Array(ids)
        let descriptor: FetchDescriptor<MetaAttribute>
        if let graphID {
            descriptor = FetchDescriptor<MetaAttribute>(predicate: #Predicate<MetaAttribute> { attribute in
                attributeIDs.contains(attribute.id) && attribute.graphID == graphID
            })
        } else {
            descriptor = FetchDescriptor<MetaAttribute>(predicate: #Predicate<MetaAttribute> { attribute in
                attributeIDs.contains(attribute.id) && attribute.graphID == nil
            })
        }
        return try context.fetch(descriptor)
    }

    func headerImageEntities(for graphID: UUID?) throws -> [MetaEntity] {
        try context.fetch(FetchDescriptor<MetaEntity>(predicate: entityImageDataPredicate(for: graphID)))
    }

    func headerImageAttributes(for graphID: UUID?) throws -> [MetaAttribute] {
        try context.fetch(FetchDescriptor<MetaAttribute>(predicate: attributeImageDataPredicate(for: graphID)))
    }
}
