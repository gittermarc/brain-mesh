//
//  NodeRepository.swift
//  BrainMesh
//
//  Graph-scoped node lookup and direct-neighborhood reads.
//

import Foundation
import SwiftData

nonisolated enum NodeRepositoryError: LocalizedError, Equatable, Sendable {
    case readinessCompletedWithoutRepositoryConfiguration

    var errorDescription: String? {
        switch self {
        case .readinessCompletedWithoutRepositoryConfiguration:
            return "NodeRepository wurde trotz abgeschlossener Service-Konfiguration nicht eingerichtet."
        }
    }
}

actor NodeRepository {
    static let shared = NodeRepository()

    private enum ContainerState {
        case awaitingConfiguration
        case ready(AnyModelContainer)
    }

    private var containerState: ContainerState
    private let additionalCancellationCheck: @Sendable () throws -> Void

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

    func entity(id: UUID, in scope: GraphScope) async throws -> GraphEntityDTO? {
        let context = try await makeReadContext()
        try checkCancellation()
        let model = try context.fetch(GraphScopedFetches.entity(id: id, in: scope)).first
        try checkCancellation()
        return model.map { GraphReadDTOMapper.entity($0, scope: scope) }
    }

    func attribute(id: UUID, in scope: GraphScope) async throws -> GraphAttributeDTO? {
        let context = try await makeReadContext()
        try checkCancellation()
        let model = try context.fetch(GraphScopedFetches.attribute(id: id, in: scope)).first
        try checkCancellation()
        return model.map { GraphReadDTOMapper.attribute($0, scope: scope) }
    }

    func node(
        _ nodeKey: NodeRefKey,
        in scope: GraphScope
    ) async throws -> GraphNodeSummaryDTO? {
        let context = try await makeReadContext()
        return try fetchNodeSummary(nodeKey, in: scope, context: context)
    }

    func nodeSummaries(
        for nodeKeys: Set<NodeRefKey>,
        in scope: GraphScope
    ) async throws -> [GraphNodeSummaryDTO] {
        let context = try await makeReadContext()
        return try fetchNodeSummaries(for: nodeKeys, in: scope, context: context)
    }

    func directNeighborhood(
        of nodeKey: NodeRefKey,
        in scope: GraphScope
    ) async throws -> GraphDirectNeighborhoodDTO? {
        let context = try await makeReadContext()
        try checkCancellation()

        guard let center = try fetchNodeSummary(nodeKey, in: scope, context: context) else {
            return nil
        }
        try checkCancellation()

        let outgoingModels = try context.fetch(
            GraphScopedFetches.outgoingLinks(from: nodeKey, in: scope)
        )
        try checkCancellation()
        let incomingModels = try context.fetch(
            GraphScopedFetches.incomingLinks(to: nodeKey, in: scope)
        )
        try checkCancellation()

        let outgoing = try mapLinks(outgoingModels, scope: scope)
        let incoming = try mapLinks(incomingModels, scope: scope)
        try checkCancellation()

        var neighborKeys = Set<NodeRefKey>()
        neighborKeys.reserveCapacity(outgoing.count + incoming.count)
        for (index, link) in outgoing.enumerated() {
            try checkCancellation(at: index)
            if let targetNodeRefKey = link.targetNodeKey, targetNodeRefKey != nodeKey {
                neighborKeys.insert(targetNodeRefKey)
            }
        }
        for (index, link) in incoming.enumerated() {
            try checkCancellation(at: index)
            if let sourceNodeRefKey = link.sourceNodeKey, sourceNodeRefKey != nodeKey {
                neighborKeys.insert(sourceNodeRefKey)
            }
        }
        try checkCancellation()

        let neighbors = try fetchNodeSummaries(
            for: neighborKeys,
            in: scope,
            context: context
        )
        try checkCancellation()

        return GraphDirectNeighborhoodDTO(
            scope: scope,
            center: center,
            outgoingLinks: outgoing,
            incomingLinks: incoming,
            neighbors: neighbors
        )
    }

    private func makeReadContext() async throws -> ModelContext {
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
            throw NodeRepositoryError.readinessCompletedWithoutRepositoryConfiguration
        }

        try checkCancellation()
        let context = ModelContext(configuredContainer.container)
        context.autosaveEnabled = false
        try checkCancellation()
        return context
    }

    private func fetchNodeSummary(
        _ nodeKey: NodeRefKey,
        in scope: GraphScope,
        context: ModelContext
    ) throws -> GraphNodeSummaryDTO? {
        try checkCancellation()
        switch nodeKey.kind {
        case .entity:
            let model = try context.fetch(
                GraphScopedFetches.entity(id: nodeKey.id, in: scope)
            ).first
            try checkCancellation()
            return model.map { GraphReadDTOMapper.entity($0, scope: scope).nodeSummary }
        case .attribute:
            let model = try context.fetch(
                GraphScopedFetches.attribute(id: nodeKey.id, in: scope)
            ).first
            try checkCancellation()
            return model.map { GraphReadDTOMapper.attribute($0, scope: scope).nodeSummary }
        }
    }

    private func fetchNodeSummaries(
        for nodeKeys: Set<NodeRefKey>,
        in scope: GraphScope,
        context: ModelContext
    ) throws -> [GraphNodeSummaryDTO] {
        guard nodeKeys.isEmpty == false else { return [] }
        try checkCancellation()

        let entityIDs = nodeKeys.compactMap { key in
            key.kind == .entity ? key.id : nil
        }
        let attributeIDs = nodeKeys.compactMap { key in
            key.kind == .attribute ? key.id : nil
        }

        var summaries: [GraphNodeSummaryDTO] = []
        summaries.reserveCapacity(nodeKeys.count)

        if entityIDs.isEmpty == false {
            let entities = try context.fetch(
                GraphScopedFetches.entities(ids: entityIDs, in: scope)
            )
            for (index, entity) in entities.enumerated() {
                try checkCancellation(at: index)
                summaries.append(
                    GraphReadDTOMapper.entity(entity, scope: scope).nodeSummary
                )
            }
        }
        try checkCancellation()

        if attributeIDs.isEmpty == false {
            let attributes = try context.fetch(
                GraphScopedFetches.attributes(ids: attributeIDs, in: scope)
            )
            for (index, attribute) in attributes.enumerated() {
                try checkCancellation(at: index)
                summaries.append(
                    GraphReadDTOMapper.attribute(attribute, scope: scope).nodeSummary
                )
            }
        }
        try checkCancellation()

        return summaries.sorted {
            if $0.nodeKey.kind.rawValue != $1.nodeKey.kind.rawValue {
                return $0.nodeKey.kind.rawValue < $1.nodeKey.kind.rawValue
            }
            return $0.nodeKey.id.uuidString < $1.nodeKey.id.uuidString
        }
    }

    private func mapLinks(
        _ models: [MetaLink],
        scope: GraphScope
    ) throws -> [GraphLinkDTO] {
        var values: [GraphLinkDTO] = []
        values.reserveCapacity(models.count)
        for (index, model) in models.enumerated() {
            try checkCancellation(at: index)
            values.append(GraphReadDTOMapper.link(model, scope: scope))
        }
        try checkCancellation()
        return values.sorted(by: Self.neighborhoodLinkSort)
    }

    private func checkCancellation(at index: Int) throws {
        if index.isMultiple(of: 64) {
            try checkCancellation()
        }
    }

    private func checkCancellation() throws {
        try Task.checkCancellation()
        try additionalCancellationCheck()
    }

    private nonisolated static func neighborhoodLinkSort(
        lhs: GraphLinkDTO,
        rhs: GraphLinkDTO
    ) -> Bool {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
