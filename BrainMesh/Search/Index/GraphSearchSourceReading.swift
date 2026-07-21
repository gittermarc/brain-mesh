//
//  GraphSearchSourceReading.swift
//  BrainMesh
//
//  Value-only read boundary consumed by the local graph search indexer.
//

import Foundation

nonisolated protocol GraphSearchSourceReading: Sendable {
    func sourceSnapshot(in scope: GraphScope) async throws -> GraphSourceSnapshotDTO

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

extension GraphReadRepository: GraphSearchSourceReading {}
