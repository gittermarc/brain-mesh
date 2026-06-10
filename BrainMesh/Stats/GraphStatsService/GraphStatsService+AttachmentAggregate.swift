//
//  GraphStatsService+AttachmentAggregate.swift
//  BrainMesh
//

import Foundation
import SwiftData

nonisolated extension GraphStatsService {
    func attachmentAggregate(for scope: GraphStatsCountScope) throws -> GraphStatsAttachmentAggregate {
        if let cached = cachedAttachmentAggregate(for: scope) {
            return cached
        }

        let count = try attachmentCount(for: scope)
        guard count > 0 else {
            let aggregate = GraphStatsAttachmentAggregate(count: 0, bytes: 0)
            storeAttachmentAggregate(aggregate, for: scope)
            return aggregate
        }

        let items = try attachmentAggregateItems(for: scope)
        let aggregate = makeAttachmentAggregate(count: count, from: items)
        storeAttachmentAggregate(aggregate, for: scope)
        return aggregate
    }

    func attachmentCount(for scope: GraphStatsCountScope) throws -> Int {
        switch scope {
        case .total:
            return try context.fetchCount(FetchDescriptor<MetaAttachment>())
        case let .graph(graphID):
            return try context.fetchCount(
                FetchDescriptor<MetaAttachment>(predicate: attachmentGraphPredicate(for: graphID))
            )
        }
    }

    func attachmentCount(for graphID: UUID?, contentKind: AttachmentContentKind) throws -> Int {
        let rawValue = contentKind.rawValue
        let descriptor: FetchDescriptor<MetaAttachment>
        if let graphID {
            descriptor = FetchDescriptor<MetaAttachment>(predicate: #Predicate<MetaAttachment> { attachment in
                attachment.graphID == graphID && attachment.contentKindRaw == rawValue
            })
        } else {
            descriptor = FetchDescriptor<MetaAttachment>(predicate: #Predicate<MetaAttachment> { attachment in
                attachment.graphID == nil && attachment.contentKindRaw == rawValue
            })
        }
        return try context.fetchCount(descriptor)
    }
}

private nonisolated struct GraphStatsAttachmentAggregateItem: Equatable, Sendable {
    let byteCount: Int
}

private nonisolated extension GraphStatsService {
    func attachmentAggregateItems(for scope: GraphStatsCountScope) throws -> [GraphStatsAttachmentAggregateItem] {
        let attachments: [MetaAttachment]
        switch scope {
        case .total:
            attachments = try context.fetch(FetchDescriptor<MetaAttachment>())
        case let .graph(graphID):
            attachments = try context.fetch(
                FetchDescriptor<MetaAttachment>(predicate: attachmentGraphPredicate(for: graphID))
            )
        }

        return attachments.map { attachment in
            GraphStatsAttachmentAggregateItem(byteCount: attachment.byteCount)
        }
    }

    func makeAttachmentAggregate(
        count: Int,
        from items: [GraphStatsAttachmentAggregateItem]
    ) -> GraphStatsAttachmentAggregate {
        let totalBytes = items.reduce(into: Int64.zero) { partialResult, item in
            partialResult += Int64(item.byteCount)
        }
        return GraphStatsAttachmentAggregate(count: count, bytes: totalBytes)
    }
}
