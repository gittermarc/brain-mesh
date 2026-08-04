//
//  GraphSearchSourceReading.swift
//  BrainMesh
//
//  Value-only read boundary consumed by the local graph search indexer.
//

import Foundation

nonisolated protocol GraphSearchSourceReading: Sendable {
    /// Returns the authoritative graph revision using a graph-row-only read.
    /// `nil` means the source cannot provide a revision and forces reconciliation.
    func searchSourceRevision(in scope: GraphScope) async throws -> UUID?

    func sourceSnapshot(in scope: GraphScope) async throws -> GraphSourceSnapshotDTO

    func searchIndexSourcePage(
        in scope: GraphScope,
        cursor: GraphSearchIndexSourceCursor?,
        limit: Int
    ) async throws -> GraphSearchIndexSourcePage

    func entity(id: UUID, in scope: GraphScope) async throws -> GraphEntityDTO?

    func attribute(id: UUID, in scope: GraphScope) async throws -> GraphAttributeDTO?

    func attributes(
        ownerEntityID: UUID,
        in scope: GraphScope
    ) async throws -> [GraphAttributeDTO]

    func link(id: UUID, in scope: GraphScope) async throws -> GraphLinkDTO?

    func links(
        connectedTo node: NodeRefKey,
        in scope: GraphScope
    ) async throws -> [GraphLinkDTO]

    func detailFieldDefinition(
        id: UUID,
        in scope: GraphScope
    ) async throws -> GraphDetailFieldDefinitionDTO?

    func detailFieldDefinitions(
        ownerEntityID: UUID,
        in scope: GraphScope
    ) async throws -> [GraphDetailFieldDefinitionDTO]

    func detailValue(
        id: UUID,
        in scope: GraphScope
    ) async throws -> GraphDetailValueDTO?

    func detailValues(
        attributeID: UUID,
        in scope: GraphScope
    ) async throws -> [GraphDetailValueDTO]

    func detailValues(
        fieldID: UUID,
        in scope: GraphScope
    ) async throws -> [GraphDetailValueDTO]

    func attachmentMetadata(
        id: UUID,
        in scope: GraphScope
    ) async throws -> GraphAttachmentMetadataDTO?
}

extension GraphSearchSourceReading {
    func searchSourceRevision(in scope: GraphScope) async throws -> UUID? {
        nil
    }

    /// Compatibility adapter for small value-only test sources. Production
    /// `GraphReadRepository` supplies a genuinely paged implementation.
    func searchIndexSourcePage(
        in scope: GraphScope,
        cursor: GraphSearchIndexSourceCursor?,
        limit: Int
    ) async throws -> GraphSearchIndexSourcePage {
        let snapshot = try await sourceSnapshot(in: scope)
        var sources: [GraphSearchIndexSource] = []
        sources.reserveCapacity(
            snapshot.entities.count
                + snapshot.attributes.count
                + snapshot.links.count
                + snapshot.detailFieldDefinitions.count
                + snapshot.detailValues.count
                + snapshot.attachments.count
        )
        sources.append(contentsOf: snapshot.entities.map(GraphSearchIndexSource.entity))
        sources.append(contentsOf: snapshot.attributes.map(GraphSearchIndexSource.attribute))
        sources.append(contentsOf: snapshot.links.map(GraphSearchIndexSource.link))
        sources.append(
            contentsOf: snapshot.detailFieldDefinitions.map(
                GraphSearchIndexSource.detailFieldDefinition
            )
        )
        sources.append(contentsOf: snapshot.detailValues.map(GraphSearchIndexSource.detailValue))
        sources.append(contentsOf: snapshot.attachments.map(GraphSearchIndexSource.attachment))

        let safeLimit = max(1, limit)
        let offset = min(cursor?.offset ?? 0, sources.count)
        let end = min(sources.count, offset + safeLimit)
        return GraphSearchIndexSourcePage(
            sources: Array(sources[offset..<end]),
            nextCursor: end < sources.count
                ? GraphSearchIndexSourceCursor(offset: end)
                : nil,
            estimatedSourceCount: sources.count
        )
    }
}

extension GraphReadRepository: GraphSearchSourceReading {}
