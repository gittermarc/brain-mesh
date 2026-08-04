//
//  GraphSearchIndexSourcePage.swift
//  BrainMesh
//
//  Bounded value-only pages used by memory-safe index rebuilds.
//

import Foundation

nonisolated struct GraphSearchIndexSourceCursor: Equatable, Sendable {
    let kindIndex: Int
    let offset: Int

    init(kindIndex: Int = 0, offset: Int = 0) {
        self.kindIndex = max(0, kindIndex)
        self.offset = max(0, offset)
    }
}

nonisolated enum GraphSearchIndexSource: Sendable {
    case entity(GraphEntityDTO)
    case attribute(GraphAttributeDTO)
    case link(GraphLinkDTO)
    case detailFieldDefinition(GraphDetailFieldDefinitionDTO)
    case detailValue(GraphDetailValueDTO)
    case attachment(GraphAttachmentMetadataDTO)

    var scope: GraphScope {
        switch self {
        case .entity(let value): value.scope
        case .attribute(let value): value.scope
        case .link(let value): value.scope
        case .detailFieldDefinition(let value): value.scope
        case .detailValue(let value): value.scope
        case .attachment(let value): value.scope
        }
    }
}

nonisolated struct GraphSearchIndexSourcePage: Sendable {
    let sources: [GraphSearchIndexSource]
    let nextCursor: GraphSearchIndexSourceCursor?
    let estimatedSourceCount: Int?

    init(
        sources: [GraphSearchIndexSource],
        nextCursor: GraphSearchIndexSourceCursor?,
        estimatedSourceCount: Int? = nil
    ) {
        self.sources = sources
        self.nextCursor = nextCursor
        self.estimatedSourceCount = estimatedSourceCount.map { max(0, $0) }
    }
}

extension GraphSearchDocumentBuilder {
    nonisolated func sourceBuild(
        for source: GraphSearchIndexSource
    ) throws -> GraphSearchSourceBuild {
        switch source {
        case .entity(let value):
            return try sourceBuild(for: value)
        case .attribute(let value):
            return try sourceBuild(for: value)
        case .link(let value):
            return try sourceBuild(for: value)
        case .detailFieldDefinition(let value):
            return try sourceBuild(for: value)
        case .detailValue(let value):
            return try sourceBuild(for: value)
        case .attachment(let value):
            return try sourceBuild(for: value)
        }
    }
}
