//
//  GraphChatConversationReferenceResolver.swift
//  BrainMesh
//
//  Central app-side resolver and repository revalidation for all multi-turn references.
//

import Foundation

nonisolated struct GraphChatRevalidatedConversationNode: Hashable, Sendable {
    let node: NodeRefKey
    let label: String
    let ownerEntityID: UUID?
}

nonisolated struct GraphChatRevalidatedConversationEntity: Hashable, Sendable {
    let entityID: UUID
    let label: String
}

nonisolated struct GraphChatRevalidatedConversationField: Hashable, Sendable {
    let fieldID: UUID
    let entityID: UUID
    let label: String
}

nonisolated struct GraphChatRevalidatedConversationGroup: Hashable, Sendable {
    let id: String
    let count: Int
    let nodes: [NodeRefKey]
}

nonisolated struct GraphChatRevalidatedConversationQuery: Hashable, Sendable {
    let state: GraphChatResultState
    let nodes: [NodeRefKey]
    let groups: [GraphChatRevalidatedConversationGroup]
}

nonisolated protocol GraphChatConversationReferenceRevalidating: Sendable {
    func node(
        _ node: NodeRefKey,
        in graphScope: GraphScope
    ) async throws -> GraphChatRevalidatedConversationNode?

    func entity(
        _ entityID: UUID,
        in graphScope: GraphScope
    ) async throws -> GraphChatRevalidatedConversationEntity?

    func field(
        _ fieldID: UUID,
        in graphScope: GraphScope
    ) async throws -> GraphChatRevalidatedConversationField?

    func queryResult(
        for plan: ValidatedGraphQueryPlan
    ) async throws -> GraphChatRevalidatedConversationQuery?
}

nonisolated struct GraphChatRepositoryConversationReferenceRevalidator:
    GraphChatConversationReferenceRevalidating
{
    let repository: GraphReadRepository
    let queryEngine: GraphChatQueryEngine

    init(
        repository: GraphReadRepository = .shared,
        queryEngine: GraphChatQueryEngine? = nil
    ) {
        self.repository = repository
        self.queryEngine =
            queryEngine
            ?? GraphChatQueryEngine(
                repository: repository,
                evidenceValidator: GraphEvidenceSourceValidator(repository: repository)
            )
    }

    func node(
        _ node: NodeRefKey,
        in graphScope: GraphScope
    ) async throws -> GraphChatRevalidatedConversationNode? {
        switch node.kind {
        case .entity:
            guard let value = try await repository.entity(id: node.id, in: graphScope) else {
                return nil
            }
            return GraphChatRevalidatedConversationNode(
                node: node,
                label: value.name,
                ownerEntityID: value.id
            )
        case .attribute:
            guard let value = try await repository.attribute(id: node.id, in: graphScope) else {
                return nil
            }
            return GraphChatRevalidatedConversationNode(
                node: node,
                label: value.displayLabel,
                ownerEntityID: value.ownerEntityID
            )
        }
    }

    func entity(
        _ entityID: UUID,
        in graphScope: GraphScope
    ) async throws -> GraphChatRevalidatedConversationEntity? {
        guard let value = try await repository.entity(id: entityID, in: graphScope) else {
            return nil
        }
        return GraphChatRevalidatedConversationEntity(
            entityID: value.id,
            label: value.name
        )
    }

    func field(
        _ fieldID: UUID,
        in graphScope: GraphScope
    ) async throws -> GraphChatRevalidatedConversationField? {
        guard
            let value = try await repository.detailFieldDefinition(
                id: fieldID,
                in: graphScope
            )
        else {
            return nil
        }
        return GraphChatRevalidatedConversationField(
            fieldID: value.id,
            entityID: value.entityID,
            label: value.name
        )
    }

    func queryResult(
        for plan: ValidatedGraphQueryPlan
    ) async throws -> GraphChatRevalidatedConversationQuery? {
        let result = try await queryEngine.execute(plan)
        let evidenceByID = Dictionary(
            uniqueKeysWithValues: result.evidence.map { ($0.id, $0) }
        )
        let groups: [GraphChatRevalidatedConversationGroup]
        if let aggregation = result.aggregation {
            groups = aggregation.groups.enumerated().map { index, group in
                let nodes = group.evidenceIDs.compactMap { evidenceID -> NodeRefKey? in
                    guard let reference = evidenceByID[evidenceID]?.sourceReference else {
                        return nil
                    }
                    switch reference.navigationTarget {
                    case .node(_, let node):
                        return node
                    case .graph, .none:
                        return nil
                    }
                }
                return GraphChatRevalidatedConversationGroup(
                    id: GraphChatConversationGroupIdentity.make(
                        fieldID: aggregation.fieldID,
                        value: group.value,
                        index: index
                    ),
                    count: group.count,
                    nodes: Self.uniqued(nodes)
                )
            }
        } else {
            groups = []
        }
        return GraphChatRevalidatedConversationQuery(
            state: result.state,
            nodes: result.rows.map(\.node),
            groups: groups
        )
    }

    private static func uniqued(_ nodes: [NodeRefKey]) -> [NodeRefKey] {
        var seen = Set<NodeRefKey>()
        return nodes.filter { seen.insert($0).inserted }
    }
}

nonisolated struct GraphChatConversationReferenceResolver: Sendable {
    private let revalidator: any GraphChatConversationReferenceRevalidating

    init(
        revalidator: any GraphChatConversationReferenceRevalidating =
            GraphChatRepositoryConversationReferenceRevalidator()
    ) {
        self.revalidator = revalidator
    }

    func resolve(
        _ proposal: GraphChatConversationReferenceProposal,
        in context: GraphChatConversationContextSnapshot,
        expectedGraphScope: GraphScope,
        expectedChatScope: GraphChatScope,
        expectedEntityID: UUID? = nil
    ) async throws -> GraphChatConversationReferenceResolution {
        guard context.graphScope == expectedGraphScope,
            expectedChatScope.graphScope == expectedGraphScope
        else {
            return .rejected(.graphMismatch)
        }
        guard context.chatScope == expectedChatScope else {
            return .rejected(.scopeMismatch)
        }

        switch proposal {
        case .alias(let alias):
            guard let value = context.alias(alias) else {
                return .clarification(
                    GraphChatConversationReferenceClarification(
                        issue: .missingContext,
                        options: clarificationOptions(from: context.aliases)
                    )
                )
            }
            return try await resolve(
                value,
                in: context,
                expectedChatScope: expectedChatScope,
                expectedEntityID: expectedEntityID
            )
        case .latestResults:
            guard let alias = context.latestResultAlias,
                let value = context.alias(alias)
            else {
                return .clarification(
                    GraphChatConversationReferenceClarification(
                        issue: .missingContext,
                        options: []
                    )
                )
            }
            return try await resolve(
                value,
                in: context,
                expectedChatScope: expectedChatScope,
                expectedEntityID: expectedEntityID
            )
        case .latestResultsSubset(let offset, let limit):
            guard offset >= 0, limit > 0 else {
                return .rejected(.ordinalOutOfBounds)
            }
            guard let alias = context.latestResultAlias,
                let value = context.alias(alias)
            else {
                return .clarification(
                    GraphChatConversationReferenceClarification(
                        issue: .missingContext,
                        options: []
                    )
                )
            }
            if let issue = try await staleIssue(for: value, in: context) {
                return .rejected(issue)
            }
            guard case .resultSet(_, let nodes, let entityID) = value.target else {
                return .rejected(.staleResults)
            }
            guard nodes.isEmpty == false else {
                return .noResults(.emptyResults)
            }
            guard offset < nodes.count else {
                return .clarification(
                    GraphChatConversationReferenceClarification(
                        issue: .ordinalOutOfBounds,
                        options: ordinalOptions(for: value, in: context)
                    )
                )
            }
            let upperBound = min(nodes.count, offset + limit)
            return try await resolveNodes(
                Array(nodes[offset..<upperBound]),
                alias: "\(value.alias)_SUBSET_\(offset + 1)_\(upperBound)",
                label: value.label,
                kind: .resultSubset,
                entityID: entityID,
                fieldID: nil,
                groupID: nil,
                expectedChatScope: expectedChatScope,
                expectedEntityID: expectedEntityID
            )
        case .ordinal(let ordinal):
            guard ordinal > 0 else {
                return .rejected(.ordinalOutOfBounds)
            }
            guard let latestAlias = context.latestResultAlias,
                let latest = context.results.first(where: { $0.alias == latestAlias }),
                let latestValue = context.alias(latestAlias)
            else {
                return .clarification(
                    GraphChatConversationReferenceClarification(
                        issue: .missingContext,
                        options: []
                    )
                )
            }
            if let issue = try await staleIssue(for: latestValue, in: context) {
                return .rejected(issue)
            }
            guard latest.itemAliases.isEmpty == false else {
                return .noResults(.emptyResults)
            }
            guard latest.itemAliases.indices.contains(ordinal - 1),
                let value = context.alias(latest.itemAliases[ordinal - 1])
            else {
                return .clarification(
                    GraphChatConversationReferenceClarification(
                        issue: .ordinalOutOfBounds,
                        options: latest.itemAliases.compactMap(context.alias).map(option)
                    )
                )
            }
            return try await resolve(
                value,
                in: context,
                expectedChatScope: expectedChatScope,
                expectedEntityID: expectedEntityID
            )
        case .lastEntity:
            return try await resolveReservedAlias(
                context.lastEntityAlias,
                in: context,
                expectedChatScope: expectedChatScope,
                expectedEntityID: expectedEntityID
            )
        case .lastField:
            return try await resolveReservedAlias(
                context.lastFieldAlias,
                in: context,
                expectedChatScope: expectedChatScope,
                expectedEntityID: expectedEntityID
            )
        case .lastGroup:
            return try await resolveReservedAlias(
                context.lastGroupAlias,
                in: context,
                expectedChatScope: expectedChatScope,
                expectedEntityID: expectedEntityID
            )
        case .lastNode:
            if let alias = context.lastNodeAlias {
                return try await resolveReservedAlias(
                    alias,
                    in: context,
                    expectedChatScope: expectedChatScope,
                    expectedEntityID: expectedEntityID
                )
            }
            let candidates = context.aliases.filter { alias in
                if case .node = alias.target { return true }
                return false
            }
            return .clarification(
                GraphChatConversationReferenceClarification(
                    issue: candidates.count > 1 ? .ambiguous : .missingContext,
                    options: clarificationOptions(from: candidates)
                )
            )
        case .lastCompared:
            return try await resolveReservedAlias(
                context.lastComparisonAlias,
                in: context,
                expectedChatScope: expectedChatScope,
                expectedEntityID: expectedEntityID
            )
        }
    }

    private func resolveReservedAlias(
        _ alias: String?,
        in context: GraphChatConversationContextSnapshot,
        expectedChatScope: GraphChatScope,
        expectedEntityID: UUID?
    ) async throws -> GraphChatConversationReferenceResolution {
        guard let alias, let value = context.alias(alias) else {
            return .clarification(
                GraphChatConversationReferenceClarification(
                    issue: .missingContext,
                    options: []
                )
            )
        }
        return try await resolve(
            value,
            in: context,
            expectedChatScope: expectedChatScope,
            expectedEntityID: expectedEntityID
        )
    }

    private func resolve(
        _ value: GraphChatConversationContextAlias,
        in context: GraphChatConversationContextSnapshot,
        expectedChatScope: GraphChatScope,
        expectedEntityID: UUID?
    ) async throws -> GraphChatConversationReferenceResolution {
        if let issue = try await staleIssue(for: value, in: context) {
            return .rejected(issue)
        }

        switch value.target {
        case .node(let node, let ownerEntityID):
            guard
                let revalidated = try await revalidator.node(
                    node,
                    in: context.graphScope
                )
            else {
                return .rejected(.deletedReference)
            }
            let entityID = revalidated.ownerEntityID ?? ownerEntityID
            guard allows(node: node, ownerEntityID: entityID, in: expectedChatScope) else {
                return .rejected(.scopeMismatch)
            }
            guard expectedEntityID == nil || expectedEntityID == entityID || node.id == expectedEntityID
            else {
                return .rejected(.entityMismatch)
            }
            return .resolved(
                GraphChatResolvedConversationReference(
                    kind: .node,
                    alias: value.alias,
                    nodes: [node],
                    entityID: entityID,
                    fieldID: nil,
                    groupID: nil,
                    label: revalidated.label
                )
            )
        case .entity(let entityID):
            guard
                let revalidated = try await revalidator.entity(
                    entityID,
                    in: context.graphScope
                )
            else {
                return .rejected(.deletedReference)
            }
            guard try await allows(entityID: entityID, in: expectedChatScope) else {
                return .rejected(.scopeMismatch)
            }
            guard expectedEntityID == nil || expectedEntityID == entityID else {
                return .rejected(.entityMismatch)
            }
            return .resolved(
                GraphChatResolvedConversationReference(
                    kind: .entity,
                    alias: value.alias,
                    nodes: [NodeRefKey(kind: .entity, id: entityID)],
                    entityID: entityID,
                    fieldID: nil,
                    groupID: nil,
                    label: revalidated.label
                )
            )
        case .field(let fieldID, let entityID):
            guard
                let revalidated = try await revalidator.field(
                    fieldID,
                    in: context.graphScope
                )
            else {
                return .rejected(.deletedReference)
            }
            guard revalidated.entityID == entityID else {
                return .rejected(.staleResults)
            }
            guard try await allows(entityID: entityID, in: expectedChatScope) else {
                return .rejected(.scopeMismatch)
            }
            guard expectedEntityID == nil || expectedEntityID == entityID else {
                return .rejected(.entityMismatch)
            }
            return .resolved(
                GraphChatResolvedConversationReference(
                    kind: .field,
                    alias: value.alias,
                    nodes: [],
                    entityID: entityID,
                    fieldID: fieldID,
                    groupID: nil,
                    label: revalidated.label
                )
            )
        case .resultSet(_, let nodes, let entityID):
            guard nodes.isEmpty == false else {
                return .noResults(.emptyResults)
            }
            return try await resolveNodes(
                nodes,
                alias: value.alias,
                label: value.label,
                kind: .resultSet,
                entityID: entityID,
                fieldID: nil,
                groupID: nil,
                expectedChatScope: expectedChatScope,
                expectedEntityID: expectedEntityID
            )
        case .group(let groupID, let nodes, let fieldID, _):
            guard nodes.isEmpty == false else {
                return .noResults(.emptyResults)
            }
            return try await resolveNodes(
                nodes,
                alias: value.alias,
                label: value.label,
                kind: .group,
                entityID: nil,
                fieldID: fieldID,
                groupID: groupID,
                expectedChatScope: expectedChatScope,
                expectedEntityID: expectedEntityID
            )
        case .comparison(let references):
            guard
                let nodes = comparisonNodes(
                    for: references,
                    in: context
                ), nodes.isEmpty == false
            else {
                return .clarification(
                    GraphChatConversationReferenceClarification(
                        issue: .staleResults,
                        options: []
                    )
                )
            }
            return try await resolveNodes(
                nodes,
                alias: value.alias,
                label: value.label,
                kind: .comparison,
                entityID: nil,
                fieldID: nil,
                groupID: nil,
                expectedChatScope: expectedChatScope,
                expectedEntityID: expectedEntityID
            )
        }
    }

    private func staleIssue(
        for alias: GraphChatConversationContextAlias,
        in context: GraphChatConversationContextSnapshot
    ) async throws -> GraphChatConversationReferenceIssue? {
        guard
            let revalidation = context.resultRevalidations.first(where: {
                $0.contains(alias: alias.alias)
            }), let current = try await revalidator.queryResult(for: revalidation.plan)
        else {
            return nil
        }

        if case .group(let groupID, let storedNodes, _, let expectedCount) = alias.target {
            guard let currentGroup = current.groups.first(where: { $0.id == groupID }) else {
                return .staleResults
            }
            guard currentGroup.count == expectedCount,
                Array(currentGroup.nodes.prefix(storedNodes.count)) == storedNodes
            else {
                return .staleResults
            }
            return nil
        }

        let storedNodes = revalidation.itemAliases.compactMap { itemAlias -> NodeRefKey? in
            guard let value = context.alias(itemAlias) else {
                return nil
            }
            switch value.target {
            case .node(let node, _):
                return node
            default:
                return nil
            }
        }
        guard current.nodes.count == revalidation.sourceReferenceCount,
            Array(current.nodes.prefix(storedNodes.count)) == storedNodes
        else {
            return .staleResults
        }
        return nil
    }

    private func comparisonNodes(
        for references: [GraphChatConversationReference],
        in context: GraphChatConversationContextSnapshot
    ) -> [NodeRefKey]? {
        var nodes: [NodeRefKey] = []
        var seen = Set<NodeRefKey>()

        func append(_ values: [NodeRefKey]) {
            for node in values where seen.insert(node).inserted {
                nodes.append(node)
            }
        }

        for reference in references {
            switch reference {
            case .node(let node):
                append([node])
            case .entity(let entityID):
                append([NodeRefKey(kind: .entity, id: entityID)])
            case .result(let resultID):
                guard
                    let value = context.aliases.first(where: { alias in
                        guard case .resultSet(let candidateID, _, _) = alias.target else {
                            return false
                        }
                        return candidateID == resultID
                    }), case .resultSet(_, let resultNodes, _) = value.target
                else {
                    return nil
                }
                append(resultNodes)
            case .group(let groupID):
                guard
                    let value = context.aliases.first(where: { alias in
                        guard case .group(let candidateID, _, _, _) = alias.target else {
                            return false
                        }
                        return candidateID == groupID
                    }), case .group(_, let groupNodes, _, _) = value.target
                else {
                    return nil
                }
                append(groupNodes)
            case .field:
                return nil
            }
        }
        return nodes
    }

    private func resolveNodes(
        _ nodes: [NodeRefKey],
        alias: String,
        label: String,
        kind: GraphChatResolvedConversationReferenceKind,
        entityID: UUID?,
        fieldID: UUID?,
        groupID: String?,
        expectedChatScope: GraphChatScope,
        expectedEntityID: UUID?
    ) async throws -> GraphChatConversationReferenceResolution {
        var revalidated: [GraphChatRevalidatedConversationNode] = []
        revalidated.reserveCapacity(nodes.count)

        for node in nodes {
            try Task.checkCancellation()
            guard
                let current = try await revalidator.node(
                    node,
                    in: expectedChatScope.graphScope
                )
            else {
                return .rejected(.deletedReference)
            }
            guard
                allows(
                    node: node,
                    ownerEntityID: current.ownerEntityID,
                    in: expectedChatScope
                )
            else {
                return .rejected(.scopeMismatch)
            }
            guard
                expectedEntityID == nil
                    || current.ownerEntityID == expectedEntityID
                    || (node.kind == .entity && node.id == expectedEntityID)
            else {
                return .rejected(.entityMismatch)
            }
            revalidated.append(current)
        }

        let inferredEntities = Set(
            revalidated.compactMap { item in
                item.node.kind == .entity ? item.node.id : item.ownerEntityID
            })
        return .resolved(
            GraphChatResolvedConversationReference(
                kind: kind,
                alias: alias,
                nodes: revalidated.map(\.node),
                entityID: entityID ?? (inferredEntities.count == 1 ? inferredEntities.first : nil),
                fieldID: fieldID,
                groupID: groupID,
                label: label
            )
        )
    }

    private func allows(
        node: NodeRefKey,
        ownerEntityID: UUID?,
        in scope: GraphChatScope
    ) -> Bool {
        switch scope.target {
        case .graph:
            return true
        case .entity(let entityID):
            return node.kind == .entity ? node.id == entityID : ownerEntityID == entityID
        case .node(let scopedNode):
            return node == scopedNode
        case .selection(let nodes):
            return nodes.contains(node)
        }
    }

    private func allows(
        entityID: UUID,
        in scope: GraphChatScope
    ) async throws -> Bool {
        switch scope.target {
        case .graph:
            return true
        case .entity(let scopedEntityID):
            return scopedEntityID == entityID
        case .node(let node):
            if node.kind == .entity {
                return node.id == entityID
            }
            return try await revalidator.node(
                node,
                in: scope.graphScope
            )?.ownerEntityID == entityID
        case .selection(let nodes):
            for node in nodes {
                if node.kind == .entity, node.id == entityID {
                    return true
                }
                if node.kind == .attribute,
                    try await revalidator.node(
                        node,
                        in: scope.graphScope
                    )?.ownerEntityID == entityID
                {
                    return true
                }
            }
            return false
        }
    }

    private func clarificationOptions(
        from aliases: [GraphChatConversationContextAlias]
    ) -> [GraphChatPendingClarificationOption] {
        Array(aliases.prefix(8)).map(option)
    }

    private func ordinalOptions(
        for resultAlias: GraphChatConversationContextAlias,
        in context: GraphChatConversationContextSnapshot
    ) -> [GraphChatPendingClarificationOption] {
        guard let result = context.results.first(where: { $0.alias == resultAlias.alias }) else {
            return []
        }
        return result.itemAliases.compactMap(context.alias).map(option)
    }

    private func option(
        _ alias: GraphChatConversationContextAlias
    ) -> GraphChatPendingClarificationOption {
        GraphChatPendingClarificationOption(
            id: alias.alias,
            title: alias.label,
            proposal: .alias(alias.alias)
        )
    }
}
