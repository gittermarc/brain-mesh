//
//  GraphReadRepository.swift
//  BrainMesh
//
//  Central graph-scoped read boundary for Search, a future local index, and future chat features.
//

import Foundation
import SwiftData

nonisolated enum GraphReadRepositoryError: LocalizedError, Equatable, Sendable {
    case graphNotFound(GraphScope)
    case readinessCompletedWithoutRepositoryConfiguration

    var errorDescription: String? {
        switch self {
        case .graphNotFound:
            return "Der angeforderte Graph wurde nicht gefunden."
        case .readinessCompletedWithoutRepositoryConfiguration:
            return "GraphReadRepository wurde trotz abgeschlossener Service-Konfiguration nicht eingerichtet."
        }
    }
}

actor GraphReadRepository {
    static let shared = GraphReadRepository()

    private enum ContainerState {
        case awaitingConfiguration
        case ready(AnyModelContainer)
    }

    private var containerState: ContainerState
    let additionalCancellationCheck: @Sendable () throws -> Void

    init() {
        containerState = .awaitingConfiguration
        additionalCancellationCheck = {}
    }

    init(
        container: AnyModelContainer,
        cancellationCheck: @escaping @Sendable () throws -> Void = {}
    ) {
        containerState = .ready(container)
        additionalCancellationCheck = cancellationCheck
    }

    func configure(container: AnyModelContainer) {
        if case .ready(let current) = containerState,
            current.identity == container.identity
        {
            return
        }
        containerState = .ready(container)
    }

    func graphMetadata(in scope: GraphScope) async throws -> GraphMetadataDTO? {
        let context = try await makeReadContext()
        try checkCancellation()
        let graph = try context.fetch(GraphScopedFetches.graph(in: scope)).first
        try checkCancellation()
        return graph.map { GraphReadDTOMapper.graph($0, scope: scope) }
    }

    func entities(in scope: GraphScope) async throws -> [GraphEntityDTO] {
        let context = try await makeReadContext()
        return try fetchEntities(in: scope, context: context)
    }

    func entity(
        id: UUID,
        in scope: GraphScope
    ) async throws -> GraphEntityDTO? {
        let context = try await makeReadContext()
        try checkCancellation()
        let model = try context.fetch(
            GraphScopedFetches.entity(id: id, in: scope)
        ).first
        try checkCancellation()
        return model.map { GraphReadDTOMapper.entity($0, scope: scope) }
    }

    func attributes(in scope: GraphScope) async throws -> [GraphAttributeDTO] {
        let context = try await makeReadContext()
        return try fetchAttributes(in: scope, context: context)
    }

    func attribute(
        id: UUID,
        in scope: GraphScope
    ) async throws -> GraphAttributeDTO? {
        let context = try await makeReadContext()
        try checkCancellation()
        let model = try context.fetch(
            GraphScopedFetches.attribute(id: id, in: scope)
        ).first
        try checkCancellation()
        return model.map { GraphReadDTOMapper.attribute($0, scope: scope) }
    }

    func attributes(
        ownerEntityID: UUID,
        in scope: GraphScope
    ) async throws -> [GraphAttributeDTO] {
        let context = try await makeReadContext()
        try checkCancellation()
        guard let owner = try context.fetch(
            GraphScopedFetches.entity(id: ownerEntityID, in: scope)
        ).first else {
            return []
        }
        let models = owner.attributesList.filter { $0.graphID == scope.graphID }
        try checkCancellation()
        let values = try mapAttributes(models, scope: scope)
        try checkCancellation()
        return values.sorted(by: Self.attributeSort)
    }

    func links(in scope: GraphScope) async throws -> [GraphLinkDTO] {
        let context = try await makeReadContext()
        return try fetchLinks(in: scope, context: context)
    }

    func link(
        id: UUID,
        in scope: GraphScope
    ) async throws -> GraphLinkDTO? {
        let context = try await makeReadContext()
        try checkCancellation()
        let model = try context.fetch(
            GraphScopedFetches.link(id: id, in: scope)
        ).first
        try checkCancellation()
        return model.map { GraphReadDTOMapper.link($0, scope: scope) }
    }

    func links(
        connectedTo node: NodeRefKey,
        in scope: GraphScope
    ) async throws -> [GraphLinkDTO] {
        let context = try await makeReadContext()
        try checkCancellation()
        let outgoing = try context.fetch(
            GraphScopedFetches.outgoingLinks(from: node, in: scope)
        )
        try checkCancellation()
        let incoming = try context.fetch(
            GraphScopedFetches.incomingLinks(to: node, in: scope)
        )
        try checkCancellation()

        var seen = Set<UUID>()
        let models = (outgoing + incoming).filter { link in
            seen.insert(link.id).inserted
        }
        var values: [GraphLinkDTO] = []
        values.reserveCapacity(models.count)
        for (index, model) in models.enumerated() {
            try checkCancellation(at: index)
            values.append(GraphReadDTOMapper.link(model, scope: scope))
        }
        try checkCancellation()
        return values.sorted(by: Self.linkSort)
    }

    func detailFieldDefinitions(
        in scope: GraphScope
    ) async throws -> [GraphDetailFieldDefinitionDTO] {
        let context = try await makeReadContext()
        return try fetchDetailFieldDefinitions(in: scope, context: context)
    }

    func detailFieldDefinition(
        id: UUID,
        in scope: GraphScope
    ) async throws -> GraphDetailFieldDefinitionDTO? {
        let context = try await makeReadContext()
        try checkCancellation()
        let model = try context.fetch(
            GraphScopedFetches.detailFieldDefinition(id: id, in: scope)
        ).first
        try checkCancellation()
        guard let model else { return nil }
        let snapshot = DetailDataModelSnapshotMapper.field(model)
        guard snapshot.graphID == scope.graphID,
              DetailDataIntegrityPolicy.fieldViolations(snapshot).isEmpty else {
            return nil
        }
        return GraphReadDTOMapper.detailFieldDefinition(model, scope: scope)
    }

    func detailFieldDefinitions(
        ownerEntityID: UUID,
        in scope: GraphScope
    ) async throws -> [GraphDetailFieldDefinitionDTO] {
        let context = try await makeReadContext()
        try checkCancellation()
        let models = try context.fetch(
            GraphScopedFetches.detailFieldDefinitions(
                entityID: ownerEntityID,
                in: scope
            )
        )
        try checkCancellation()
        let values = try mapDetailFieldDefinitions(models, scope: scope)
        try checkCancellation()
        return values.sorted(by: Self.detailFieldSort)
    }

    func detailValues(in scope: GraphScope) async throws -> [GraphDetailValueDTO] {
        let context = try await makeReadContext()
        return try fetchDetailValues(in: scope, context: context)
    }

    func detailValue(
        id: UUID,
        in scope: GraphScope
    ) async throws -> GraphDetailValueDTO? {
        let context = try await makeReadContext()
        try checkCancellation()
        guard
            let model = try context.fetch(
                GraphScopedFetches.detailValue(id: id, in: scope)
            ).first
        else {
            return nil
        }
        try checkCancellation()
        let siblingModels = try context.fetch(
            GraphScopedFetches.detailValues(
                attributeID: model.attributeID,
                fieldID: model.fieldID,
                in: scope
            )
        )
        let resolved = try fetchDetailValues(
            in: scope,
            context: context,
            models: siblingModels
        )
        return resolved.first { $0.id == model.id }
    }

    func detailValueAuthority(
        attributeID: UUID,
        fieldID: UUID,
        in scope: GraphScope
    ) async throws -> GraphDetailValueAuthorityDTO {
        let context = try await makeReadContext()
        try checkCancellation()
        let models = try context.fetch(
            GraphScopedFetches.detailValues(
                attributeID: attributeID,
                fieldID: fieldID,
                in: scope
            )
        )
        try checkCancellation()
        let authority = try fetchDetailValueAuthority(
            in: scope,
            context: context,
            models: models
        )
        let key = DetailValueAuthorityKey(
            graphID: scope.graphID,
            attributeID: attributeID,
            fieldID: fieldID
        )
        if authority.conflictedKeys.contains(key)
            || authority.values.count > 1
            || (
                models.isEmpty == false
                    && authority.values.isEmpty
            )
        {
            return .conflicted
        }
        guard let value = authority.values.first else {
            return .missing
        }
        guard
            value.attributeID == attributeID,
            value.fieldID == fieldID
        else {
            return .conflicted
        }
        return .authoritative(value)
    }

    func detailValues(
        attributeID: UUID,
        in scope: GraphScope
    ) async throws -> [GraphDetailValueDTO] {
        let context = try await makeReadContext()
        try checkCancellation()
        let models = try context.fetch(
            GraphScopedFetches.detailValues(
                attributeID: attributeID,
                in: scope
            )
        )
        try checkCancellation()
        return try fetchDetailValues(
            in: scope,
            context: context,
            models: models
        )
    }

    func detailValues(
        fieldID: UUID,
        in scope: GraphScope
    ) async throws -> [GraphDetailValueDTO] {
        let context = try await makeReadContext()
        try checkCancellation()
        let models = try context.fetch(
            GraphScopedFetches.detailValues(fieldID: fieldID, in: scope)
        )
        try checkCancellation()
        return try fetchDetailValues(
            in: scope,
            context: context,
            models: models
        )
    }

    func attachmentMetadata(
        in scope: GraphScope
    ) async throws -> [GraphAttachmentMetadataDTO] {
        let context = try await makeReadContext()
        return try fetchAttachmentMetadata(in: scope, context: context)
    }

    func attachmentMetadata(
        id: UUID,
        in scope: GraphScope
    ) async throws -> GraphAttachmentMetadataDTO? {
        let context = try await makeReadContext()
        try checkCancellation()
        guard
            let model = try context.fetch(
                GraphScopedFetches.attachment(id: id, in: scope)
            ).first
        else {
            return nil
        }
        try checkCancellation()
        return try fetchAttachmentMetadata(
            in: scope,
            context: context,
            models: [model]
        ).first
    }

    func attachmentMetadata(
        owner: NodeRefKey,
        in scope: GraphScope
    ) async throws -> [GraphAttachmentMetadataDTO] {
        let context = try await makeReadContext()
        try checkCancellation()
        let models = try context.fetch(
            GraphScopedFetches.attachments(owner: owner, in: scope)
        )
        try checkCancellation()
        return try fetchAttachmentMetadata(
            in: scope,
            context: context,
            models: models
        )
    }

    func sourceSnapshot(in scope: GraphScope) async throws -> GraphSourceSnapshotDTO {
        let context = try await makeReadContext()
        try checkCancellation()

        guard
            let graphModel = try context.fetch(
                GraphScopedFetches.graph(in: scope)
            ).first
        else {
            throw GraphReadRepositoryError.graphNotFound(scope)
        }
        try checkCancellation()

        let entities = try fetchEntities(in: scope, context: context)
        try checkCancellation()
        let attributes = try fetchAttributes(in: scope, context: context)
        try checkCancellation()
        let links = try fetchLinks(in: scope, context: context)
        try checkCancellation()
        let definitions = try fetchDetailFieldDefinitions(in: scope, context: context)
        try checkCancellation()
        let valueAuthority = try fetchDetailValueAuthority(
            in: scope,
            context: context,
            prefetchedDefinitions: definitions,
            prefetchedAttributes: attributes
        )
        try checkCancellation()
        let attachments = try fetchAttachmentMetadata(
            in: scope,
            context: context,
            prefetchedEntities: entities,
            prefetchedAttributes: attributes
        )
        try checkCancellation()

        return GraphSourceSnapshotDTO(
            scope: scope,
            graph: GraphReadDTOMapper.graph(graphModel, scope: scope),
            entities: entities,
            attributes: attributes,
            links: links,
            detailFieldDefinitions: definitions,
            detailValues: valueAuthority.values,
            attachments: attachments,
            integrityConflictedValueKeys:
                valueAuthority.conflictedKeys
        )
    }

    func makeReadContext() async throws -> ModelContext {
        let serviceContainerID: ObjectIdentifier?
        switch containerState {
        case .awaitingConfiguration:
            serviceContainerID = nil
        case .ready(let container):
            serviceContainerID = container.identity
        }

        try await AppLoadersConfigurator.waitUntilReadyIfNeeded(
            serviceContainerID: serviceContainerID
        )
        guard case .ready(let configuredContainer) = containerState else {
            throw GraphReadRepositoryError.readinessCompletedWithoutRepositoryConfiguration
        }

        try checkCancellation()
        let context = ModelContext(configuredContainer.container)
        context.autosaveEnabled = false
        try checkCancellation()
        return context
    }

    func checkCancellation(at index: Int) throws {
        if index.isMultiple(of: 64) {
            try checkCancellation()
        }
    }

    func checkCancellation() throws {
        try Task.checkCancellation()
        try additionalCancellationCheck()
    }
}
