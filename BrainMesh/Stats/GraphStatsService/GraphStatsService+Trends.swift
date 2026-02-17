//
//  GraphStatsService+Trends.swift
//  BrainMesh
//

import Foundation
import SwiftData

extension GraphStatsService {
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
}

private extension GraphStatsService {
    func nodeCount(for graphID: UUID?) throws -> Int {
        let entities = try context.fetchCount(
            FetchDescriptor<MetaEntity>(predicate: entityGraphPredicate(for: graphID))
        )
        let attributes = try context.fetchCount(
            FetchDescriptor<MetaAttribute>(predicate: attributeGraphPredicate(for: graphID))
        )
        return entities + attributes
    }

    func makeDayLabels(start: Date, days: Int, calendar: Calendar) -> [String] {
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

    func bucketCounts14(start: Date, days: Int, calendar: Calendar, dates: [Date]) -> [Int] {
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

    func linkTrendsPredicate(for graphID: UUID?, start: Date, end: Date) -> Predicate<MetaLink> {
        if let graphID {
            return #Predicate<MetaLink> { $0.graphID == graphID && $0.createdAt >= start && $0.createdAt < end }
        }
        return #Predicate<MetaLink> { $0.graphID == nil && $0.createdAt >= start && $0.createdAt < end }
    }

    func attachmentTrendsPredicate(for graphID: UUID?, start: Date, end: Date) -> Predicate<MetaAttachment> {
        if let graphID {
            return #Predicate<MetaAttachment> { $0.graphID == graphID && $0.createdAt >= start && $0.createdAt < end }
        }
        return #Predicate<MetaAttachment> { $0.graphID == nil && $0.createdAt >= start && $0.createdAt < end }
    }
}
