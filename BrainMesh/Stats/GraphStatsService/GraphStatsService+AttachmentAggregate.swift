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

        let items = try attachmentAggregateItems(for: scope)
        let aggregate = makeAttachmentAggregate(from: items)
        storeAttachmentAggregate(aggregate, for: scope)
        return aggregate
    }
}

private nonisolated extension GraphStatsService {
    func attachmentAggregateItems(for scope: GraphStatsCountScope) throws -> [MetaAttachment] {
        switch scope {
        case .total:
            return try context.fetch(FetchDescriptor<MetaAttachment>())
        case let .graph(graphID):
            return try context.fetch(
                FetchDescriptor<MetaAttachment>(predicate: attachmentGraphPredicate(for: graphID))
            )
        }
    }

    func makeAttachmentAggregate(from items: [MetaAttachment]) -> GraphStatsAttachmentAggregate {
        let totalBytes = items.reduce(into: Int64.zero) { partialResult, item in
            partialResult += Int64(item.byteCount)
        }
        return GraphStatsAttachmentAggregate(count: items.count, bytes: totalBytes)
    }
}
