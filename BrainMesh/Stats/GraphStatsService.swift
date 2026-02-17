//
//  GraphStatsService.swift
//  BrainMesh
//
//  Counts are computed via `fetchCount` to avoid loading full model objects.
//
//  IMPORTANT:
//  SwiftData `#Predicate` + optional String comparisons can trigger
//  "unable to type-check this expression in reasonable time" in Xcode/Swift.
//  To keep builds stable, this service avoids predicates that touch `imagePath`
//  (a derived local cache field). Image presence is counted via `imageData`,
//  which is the authoritative, synced storage.
//

import Foundation
import SwiftData

/// Aggregated counters for a graph (or totals / legacy).
struct GraphCounts: Equatable, Sendable {
    let entities: Int
    let attributes: Int
    let links: Int
    let notes: Int
    let images: Int
    let attachments: Int
    let attachmentBytes: Int64

    static let zero = GraphCounts(
        entities: 0,
        attributes: 0,
        links: 0,
        notes: 0,
        images: 0,
        attachments: 0,
        attachmentBytes: 0
    )

    var isEmpty: Bool {
        entities == 0
            && attributes == 0
            && links == 0
            && notes == 0
            && images == 0
            && attachments == 0
            && attachmentBytes == 0
    }
}

// MARK: - P0 Stats Extensions (Dashboard + Media + Structure)

/// Small label/value pair for rankings (e.g. top file extensions).
struct GraphTopItem: Equatable, Sendable {
    let label: String
    let count: Int
}

/// Lightweight view model for the largest attachments list.
struct GraphLargestAttachment: Equatable, Sendable {
    let id: UUID
    let title: String
    let byteCount: Int
    let contentKind: AttachmentContentKind
    let fileExtension: String
}

/// Ranking item for "Top nodes with media".
///
/// Media count is computed as: attachments + headerImage(0/1)
struct GraphMediaNodeItem: Equatable, Sendable {
    let id: UUID
    let label: String
    let kind: NodeKind
    let attachmentCount: Int
    let headerImageCount: Int

    var mediaCount: Int {
        attachmentCount + headerImageCount
    }
}

/// Media breakdown (attachments) + rankings for a given graph.
struct GraphMediaSnapshot: Equatable, Sendable {
    let headerImages: Int

    let attachmentsTotal: Int
    let attachmentsFile: Int
    let attachmentsVideo: Int
    let attachmentsGalleryImages: Int

    let topFileExtensions: [GraphTopItem]
    let largestAttachments: [GraphLargestAttachment]

    let topMediaNodes: [GraphMediaNodeItem]
}

// MARK: - P1: Trends (7 days)

struct GraphTrendDelta: Equatable, Sendable {
    let current: Int
    let previous: Int
}

struct GraphTrendsSnapshot: Equatable, Sendable {
    /// Labels for the last N days (oldest -> newest).
    let dayLabels: [String]

    /// Counts for last N days (oldest -> newest).
    let linkCounts: [Int]
    let attachmentCounts: [Int]

    /// Delta: last N days vs previous N days.
    let linkDelta: GraphTrendDelta
    let attachmentDelta: GraphTrendDelta

    /// Link density over the last N days (approx. links-per-node over time).
    let linkDensitySeries: [Double]
}

/// Top hub node (highest degree) derived from links.
struct GraphHubItem: Equatable, Sendable {
    let id: UUID
    let label: String
    let kind: NodeKind
    let degree: Int
}

/// Graph structure snapshot derived from nodes + links.
struct GraphStructureSnapshot: Equatable, Sendable {
    let nodeCount: Int
    let linkCount: Int
    let isolatedNodeCount: Int
    let topHubs: [GraphHubItem]
}

@MainActor
final class GraphStatsService {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// Total counts across all graphs (including legacy / graphID == nil).
    func totalCounts() throws -> GraphCounts {
        let entities = try context.fetchCount(FetchDescriptor<MetaEntity>())
        let attributes = try context.fetchCount(FetchDescriptor<MetaAttribute>())
        let links = try context.fetchCount(FetchDescriptor<MetaLink>())

        let entityNotes = try context.fetchCount(
            FetchDescriptor<MetaEntity>(predicate: #Predicate { $0.notes != "" })
        )
        let attributeNotes = try context.fetchCount(
            FetchDescriptor<MetaAttribute>(predicate: #Predicate { $0.notes != "" })
        )
        let linkNotes = try context.fetchCount(
            FetchDescriptor<MetaLink>(predicate: #Predicate { $0.note != nil && $0.note != "" })
        )

        // Images: count via imageData (authoritative). Avoid `imagePath` in predicates to prevent type-check timeouts.
        let entityImages = try context.fetchCount(
            FetchDescriptor<MetaEntity>(predicate: #Predicate { $0.imageData != nil })
        )
        let attributeImages = try context.fetchCount(
            FetchDescriptor<MetaAttribute>(predicate: #Predicate { $0.imageData != nil })
        )

        // Attachments: count is cheap, bytes require a small fetch to sum byteCount.
        let attachments = try context.fetchCount(FetchDescriptor<MetaAttachment>())
        let attachmentBytes = try totalAttachmentBytes()

        return GraphCounts(
            entities: entities,
            attributes: attributes,
            links: links,
            notes: entityNotes + attributeNotes + linkNotes,
            images: entityImages + attributeImages,
            attachments: attachments,
            attachmentBytes: attachmentBytes
        )
    }

    /// Counts for a single graph. Pass `nil` to get legacy counts (graphID == nil).
    func counts(for graphID: UUID?) throws -> GraphCounts {
        let entities = try context.fetchCount(
            FetchDescriptor<MetaEntity>(predicate: entityGraphPredicate(for: graphID))
        )
        let attributes = try context.fetchCount(
            FetchDescriptor<MetaAttribute>(predicate: attributeGraphPredicate(for: graphID))
        )
        let links = try context.fetchCount(
            FetchDescriptor<MetaLink>(predicate: linkGraphPredicate(for: graphID))
        )

        let entityNotes = try context.fetchCount(
            FetchDescriptor<MetaEntity>(predicate: entityNotesPredicate(for: graphID))
        )
        let attributeNotes = try context.fetchCount(
            FetchDescriptor<MetaAttribute>(predicate: attributeNotesPredicate(for: graphID))
        )
        let linkNotes = try context.fetchCount(
            FetchDescriptor<MetaLink>(predicate: linkNotesPredicate(for: graphID))
        )

        // Images: count via imageData (authoritative). Avoid `imagePath` in predicates to prevent type-check timeouts.
        let entityImages = try context.fetchCount(
            FetchDescriptor<MetaEntity>(predicate: entityImageDataPredicate(for: graphID))
        )
        let attributeImages = try context.fetchCount(
            FetchDescriptor<MetaAttribute>(predicate: attributeImageDataPredicate(for: graphID))
        )

        let attachments = try context.fetchCount(
            FetchDescriptor<MetaAttachment>(predicate: attachmentGraphPredicate(for: graphID))
        )
        let attachmentBytes = try attachmentBytes(for: graphID)

        return GraphCounts(
            entities: entities,
            attributes: attributes,
            links: links,
            notes: entityNotes + attributeNotes + linkNotes,
            images: entityImages + attributeImages,
            attachments: attachments,
            attachmentBytes: attachmentBytes
        )
    }

    // MARK: - P0: Media breakdown

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

    private func topMediaNodes(for graphID: UUID?, attachments: [MetaAttachment]) throws -> [GraphMediaNodeItem] {
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

    // MARK: - P1: Trends (7 days)

    /// Trends for the last N days:
    /// - Links created per day
    /// - Attachments created per day
    /// - Delta last N days vs the previous N days
    /// - Link density mini-series (links-per-node over time, approximated)
    func trendsSnapshot(for graphID: UUID?, days: Int = 7) throws -> GraphTrendsSnapshot {
        let days = max(1, days)
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? Date()

        let startCurrent = calendar.date(byAdding: .day, value: -(days - 1), to: todayStart) ?? todayStart
        let startPrev = calendar.date(byAdding: .day, value: -(days * 2 - 1), to: todayStart) ?? startCurrent

        let dayLabels = makeDayLabels(start: startCurrent, days: days, calendar: calendar)

        let links14 = try context.fetch(
            FetchDescriptor<MetaLink>(predicate: linkTrendsPredicate(for: graphID, start: startPrev, end: tomorrowStart))
        )
        let attachments14 = try context.fetch(
            FetchDescriptor<MetaAttachment>(predicate: attachmentTrendsPredicate(for: graphID, start: startPrev, end: tomorrowStart))
        )

        let linkCounts14 = bucketCounts14(start: startPrev, days: days * 2, calendar: calendar, dates: links14.map { $0.createdAt })
        let attachmentCounts14 = bucketCounts14(start: startPrev, days: days * 2, calendar: calendar, dates: attachments14.map { $0.createdAt })

        let prevLinkTotal = linkCounts14.prefix(days).reduce(0, +)
        let currentLinkCounts = Array(linkCounts14.dropFirst(days).prefix(days))
        let currentLinkTotal = currentLinkCounts.reduce(0, +)

        let prevAttachmentTotal = attachmentCounts14.prefix(days).reduce(0, +)
        let currentAttachmentCounts = Array(attachmentCounts14.dropFirst(days).prefix(days))
        let currentAttachmentTotal = currentAttachmentCounts.reduce(0, +)

        let nodeCount = try nodeCount(for: graphID)
        let totalLinkCount = try context.fetchCount(
            FetchDescriptor<MetaLink>(predicate: linkGraphPredicate(for: graphID))
        )

        let baselineLinks = max(0, totalLinkCount - currentLinkTotal)
        var cumulative = 0
        var densitySeries: [Double] = []
        densitySeries.reserveCapacity(days)

        for c in currentLinkCounts {
            cumulative += c
            let linksAsOfDay = baselineLinks + cumulative
            let density = Double(linksAsOfDay) / Double(max(1, nodeCount))
            densitySeries.append(density)
        }

        return GraphTrendsSnapshot(
            dayLabels: dayLabels,
            linkCounts: currentLinkCounts,
            attachmentCounts: currentAttachmentCounts,
            linkDelta: GraphTrendDelta(current: currentLinkTotal, previous: prevLinkTotal),
            attachmentDelta: GraphTrendDelta(current: currentAttachmentTotal, previous: prevAttachmentTotal),
            linkDensitySeries: densitySeries
        )
    }

    private func nodeCount(for graphID: UUID?) throws -> Int {
        let entities = try context.fetchCount(
            FetchDescriptor<MetaEntity>(predicate: entityGraphPredicate(for: graphID))
        )
        let attributes = try context.fetchCount(
            FetchDescriptor<MetaAttribute>(predicate: attributeGraphPredicate(for: graphID))
        )
        return entities + attributes
    }

    private func makeDayLabels(start: Date, days: Int, calendar: Calendar) -> [String] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "E"

        var labels: [String] = []
        labels.reserveCapacity(days)
        for i in 0..<days {
            guard let d = calendar.date(byAdding: .day, value: i, to: start) else {
                labels.append("—")
                continue
            }
            let raw = formatter.string(from: d)
            labels.append(raw.replacingOccurrences(of: ".", with: ""))
        }
        return labels
    }

    private func bucketCounts14(start: Date, days: Int, calendar: Calendar, dates: [Date]) -> [Int] {
        var counts = Array(repeating: 0, count: days)
        for date in dates {
            let d = calendar.startOfDay(for: date)
            let idx = calendar.dateComponents([.day], from: start, to: d).day ?? -1
            if idx >= 0 && idx < days {
                counts[idx] += 1
            }
        }
        return counts
    }

    private func linkTrendsPredicate(for graphID: UUID?, start: Date, end: Date) -> Predicate<MetaLink> {
        if let graphID {
            return #Predicate<MetaLink> { $0.graphID == graphID && $0.createdAt >= start && $0.createdAt < end }
        }
        return #Predicate<MetaLink> { $0.graphID == nil && $0.createdAt >= start && $0.createdAt < end }
    }

    private func attachmentTrendsPredicate(for graphID: UUID?, start: Date, end: Date) -> Predicate<MetaAttachment> {
        if let graphID {
            return #Predicate<MetaAttachment> { $0.graphID == graphID && $0.createdAt >= start && $0.createdAt < end }
        }
        return #Predicate<MetaAttachment> { $0.graphID == nil && $0.createdAt >= start && $0.createdAt < end }
    }

    private func headerImagesCount(for graphID: UUID?) throws -> Int {
        let entityImages = try context.fetchCount(
            FetchDescriptor<MetaEntity>(predicate: entityImageDataPredicate(for: graphID))
        )
        let attributeImages = try context.fetchCount(
            FetchDescriptor<MetaAttribute>(predicate: attributeImageDataPredicate(for: graphID))
        )
        return entityImages + attributeImages
    }

    private func normalizeFileExtension(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "?" }
        if trimmed.hasPrefix(".") {
            let drop = String(trimmed.dropFirst())
            return drop.isEmpty ? "?" : drop.lowercased()
        }
        return trimmed.lowercased()
    }

    private func bestAttachmentTitle(_ a: MetaAttachment) -> String {
        let t = a.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty == false { return t }

        let n = a.originalFilename.trimmingCharacters(in: .whitespacesAndNewlines)
        if n.isEmpty == false { return n }

        let ext = normalizeFileExtension(a.fileExtension)
        if ext == "?" { return "Anhang" }
        return "Anhang .\(ext)"
    }

    // MARK: - P0: Graph structure (isolated nodes + top hubs)

    /// Structure snapshot for a graph:
    /// - nodeCount = entities + attributes
    /// - isolated nodes = nodes that do not appear as source/target in any link
    /// - top hubs = nodes with the highest degree (source + target occurrences)
    func structureSnapshot(for graphID: UUID?) throws -> GraphStructureSnapshot {
        let entities = try context.fetch(
            FetchDescriptor<MetaEntity>(predicate: entityGraphPredicate(for: graphID))
        )
        let attributes = try context.fetch(
            FetchDescriptor<MetaAttribute>(predicate: attributeGraphPredicate(for: graphID))
        )
        let links = try context.fetch(
            FetchDescriptor<MetaLink>(predicate: linkGraphPredicate(for: graphID))
        )

        var nodeLabelByID: [UUID: String] = [:]
        var nodeKindByID: [UUID: NodeKind] = [:]
        var allNodeIDs = Set<UUID>()

        for e in entities {
            nodeLabelByID[e.id] = e.name
            nodeKindByID[e.id] = .entity
            allNodeIDs.insert(e.id)
        }

        for a in attributes {
            nodeLabelByID[a.id] = a.displayName
            nodeKindByID[a.id] = .attribute
            allNodeIDs.insert(a.id)
        }

        var degreeByID: [UUID: Int] = [:]

        for l in links {
            degreeByID[l.sourceID, default: 0] += 1
            degreeByID[l.targetID, default: 0] += 1
        }

        let isolatedCount = allNodeIDs.reduce(into: 0) { partial, id in
            if degreeByID[id] == nil { partial += 1 }
        }

        let topHubs: [GraphHubItem] = degreeByID
            .map { (id: $0.key, degree: $0.value) }
            .sorted { lhs, rhs in
                if lhs.degree != rhs.degree { return lhs.degree > rhs.degree }
                let ln = nodeLabelByID[lhs.id] ?? ""
                let rn = nodeLabelByID[rhs.id] ?? ""
                return ln < rn
            }
            .prefix(10)
            .map { item in
                let label = nodeLabelByID[item.id] ?? fallbackLabel(for: item.id, links: links)
                let kind = nodeKindByID[item.id] ?? fallbackKind(for: item.id, links: links)
                return GraphHubItem(id: item.id, label: label, kind: kind, degree: item.degree)
            }

        return GraphStructureSnapshot(
            nodeCount: entities.count + attributes.count,
            linkCount: links.count,
            isolatedNodeCount: isolatedCount,
            topHubs: topHubs
        )
    }

    private func fallbackLabel(for id: UUID, links: [MetaLink]) -> String {
        for l in links {
            if l.sourceID == id {
                let s = l.sourceLabel.trimmingCharacters(in: .whitespacesAndNewlines)
                if s.isEmpty == false { return s }
            }
            if l.targetID == id {
                let t = l.targetLabel.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.isEmpty == false { return t }
            }
        }
        return shortID(id)
    }

    private func fallbackKind(for id: UUID, links: [MetaLink]) -> NodeKind {
        for l in links {
            if l.sourceID == id { return l.sourceKind }
            if l.targetID == id { return l.targetKind }
        }
        return .entity
    }

    private func shortID(_ id: UUID) -> String {
        let s = id.uuidString
        return String(s.prefix(8))
    }

    // MARK: - Graph predicates

    private func entityGraphPredicate(for graphID: UUID?) -> Predicate<MetaEntity> {
        if let graphID {
            return #Predicate<MetaEntity> { $0.graphID == graphID }
        }
        return #Predicate<MetaEntity> { $0.graphID == nil }
    }

    private func attributeGraphPredicate(for graphID: UUID?) -> Predicate<MetaAttribute> {
        if let graphID {
            return #Predicate<MetaAttribute> { $0.graphID == graphID }
        }
        return #Predicate<MetaAttribute> { $0.graphID == nil }
    }

    private func linkGraphPredicate(for graphID: UUID?) -> Predicate<MetaLink> {
        if let graphID {
            return #Predicate<MetaLink> { $0.graphID == graphID }
        }
        return #Predicate<MetaLink> { $0.graphID == nil }
    }

    private func attachmentGraphPredicate(for graphID: UUID?) -> Predicate<MetaAttachment> {
        if let graphID {
            return #Predicate<MetaAttachment> { $0.graphID == graphID }
        }
        return #Predicate<MetaAttachment> { $0.graphID == nil }
    }

    // MARK: - Notes predicates

    private func entityNotesPredicate(for graphID: UUID?) -> Predicate<MetaEntity> {
        if let graphID {
            return #Predicate<MetaEntity> { $0.graphID == graphID && $0.notes != "" }
        }
        return #Predicate<MetaEntity> { $0.graphID == nil && $0.notes != "" }
    }

    private func attributeNotesPredicate(for graphID: UUID?) -> Predicate<MetaAttribute> {
        if let graphID {
            return #Predicate<MetaAttribute> { $0.graphID == graphID && $0.notes != "" }
        }
        return #Predicate<MetaAttribute> { $0.graphID == nil && $0.notes != "" }
    }

    private func linkNotesPredicate(for graphID: UUID?) -> Predicate<MetaLink> {
        if let graphID {
            return #Predicate<MetaLink> { $0.graphID == graphID && $0.note != nil && $0.note != "" }
        }
        return #Predicate<MetaLink> { $0.graphID == nil && $0.note != nil && $0.note != "" }
    }

    // MARK: - Image predicates (imageData only)

    private func entityImageDataPredicate(for graphID: UUID?) -> Predicate<MetaEntity> {
        if let graphID {
            return #Predicate<MetaEntity> { $0.graphID == graphID && $0.imageData != nil }
        }
        return #Predicate<MetaEntity> { $0.graphID == nil && $0.imageData != nil }
    }

    private func attributeImageDataPredicate(for graphID: UUID?) -> Predicate<MetaAttribute> {
        if let graphID {
            return #Predicate<MetaAttribute> { $0.graphID == graphID && $0.imageData != nil }
        }
        return #Predicate<MetaAttribute> { $0.graphID == nil && $0.imageData != nil }
    }

    // MARK: - Attachment bytes

    private func totalAttachmentBytes() throws -> Int64 {
        let items = try context.fetch(FetchDescriptor<MetaAttachment>())
        var total: Int64 = 0
        for a in items {
            total += Int64(a.byteCount)
        }
        return total
    }

    private func attachmentBytes(for graphID: UUID?) throws -> Int64 {
        let items = try context.fetch(
            FetchDescriptor<MetaAttachment>(predicate: attachmentGraphPredicate(for: graphID))
        )
        var total: Int64 = 0
        for a in items {
            total += Int64(a.byteCount)
        }
        return total
    }
}
