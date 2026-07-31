//
//  GraphChatComposableReadPlanLegacyActionAdapter.swift
//  BrainMesh
//
//  Temporary bounded adapter into the existing result/evidence/artifact
//  executors. The composable plan remains the only stored execution truth.
//

import Foundation

nonisolated enum GraphChatComposableReadPlanLegacyActionAdapterError:
    Error,
    Hashable,
    Sendable
{
    case malformedPlan
}

nonisolated enum GraphChatComposableReadPlanLegacyActionAdapter {
    static func action(
        from plan: GraphChatComposableReadPlan
    ) -> GraphChatLocalIntentAction {
        do {
            return try validatedAction(
                from: plan
            )
        } catch {
            preconditionFailure(
                "A validated composable read plan could not be adapted: \(error)"
            )
        }
    }

    static func validatedAction(
        from plan: GraphChatComposableReadPlan
    ) throws -> GraphChatLocalIntentAction {
        if let search = operation(
            in: plan,
            extract: {
                (
                    payload:
                        GraphChatComposableReadOperationPayload
                ) -> GraphChatComposableReadSearch? in
                guard case .search(let value) =
                        payload else {
                    return nil
                }
                return value
            }
        ) {
            return .searchGraph(
                GraphChatLocalSearchAction(
                    query: search.query,
                    limit:
                        try finalLimit(
                            in: plan
                        ),
                    scope: plan.compiledScope,
                    target: search.target,
                    entityID: search.entityID
                )
            )
        }
        if let description = operation(
            in: plan,
            extract: {
                (
                    payload:
                        GraphChatComposableReadOperationPayload
                ) -> GraphChatComposableReadNodeDescription? in
                guard case .describeNode(
                    let value
                ) = payload else {
                    return nil
                }
                return value
            }
        ) {
            return .nodeDetails(
                GraphChatLocalNodeDetailsAction(
                    node: description.node,
                    relatedLimit:
                        description
                            .compatibilityLimit
                )
            )
        }
        if let comparison = operation(
            in: plan,
            extract: {
                (
                    payload:
                        GraphChatComposableReadOperationPayload
                ) -> GraphChatComposableReadComparison? in
                guard case .compareNodes(
                    let value
                ) = payload else {
                    return nil
                }
                return value
            }
        ) {
            return .compareNodes(
                try comparisonPlan(
                    plan,
                    comparison: comparison
                )
            )
        }
        if let graphState = operation(
            in: plan,
            extract: {
                (
                    payload:
                        GraphChatComposableReadOperationPayload
                ) -> GraphChatComposableReadGraphState? in
                guard case .inspectGraphState(
                    let value
                ) = payload else {
                    return nil
                }
                return value
            }
        ) {
            return .inspectGraphState(
                GraphChatLocalGraphStateAction(
                    aspect: graphState.aspect,
                    hubLimit:
                        graphState.hubLimit
                )
            )
        }
        if let traversal = operation(
            in: plan,
            extract: {
                (
                    payload:
                        GraphChatComposableReadOperationPayload
                ) -> GraphChatComposableReadTraversal? in
                guard case
                        .traverseDirectRelationships(
                            let value
                        ) = payload else {
                    return nil
                }
                return value
            }
        ) {
            return .relationships(
                try relationshipPlan(
                    plan,
                    traversal: traversal
                )
            )
        }
        return .queryDetailValues(
            try queryAction(plan)
        )
    }

    private static func queryAction(
        _ plan: GraphChatComposableReadPlan
    ) throws -> GraphChatLocalQueryAction {
        let entity = try queryEntity(
            in: plan
        )
        let source = try conversationSelection(
            in: plan
        )?.source
        return GraphChatLocalQueryAction(
            plan:
                try queryPlan(
                    plan,
                    entity: entity
                ),
            resultContract:
                try queryResultContract(
                    plan.resultContract
                ),
            refinementSource: source,
            compilationReferenceDate:
                plan.queryReferenceDate
        )
    }

    private static func queryPlan(
        _ plan: GraphChatComposableReadPlan,
        entity:
            GraphChatComposableReadEntityReference
    ) throws -> GraphQueryPlan {
        GraphQueryPlan(
            version: plan.queryPlanVersion,
            entityAlias: entity.alias,
            scope: plan.compiledScope,
            filters:
                filter(in: plan)?
                    .predicates.map {
                        GraphQueryFilter(
                            fieldAlias:
                                $0.field.alias,
                            operation:
                                $0.operation,
                            value: $0.value
                        )
                    } ?? [],
            sorting: querySorting(in: plan),
            projection:
                queryProjection(in: plan),
            aggregation:
                queryAggregation(in: plan),
            limit:
                try finalLimit(
                    in: plan
                )
        )
    }

    private static func comparisonPlan(
        _ plan: GraphChatComposableReadPlan,
        comparison:
            GraphChatComposableReadComparison
    ) throws -> GraphChatComparisonPlan {
        let selection = try nodesSelection(
            in: plan
        )
        let selectionQuery:
            GraphQueryPlan?
        switch comparison.kind {
        case .sameEntityAttributes:
            guard let entity =
                    selection.entities.first else {
                throw GraphChatComposableReadPlanLegacyActionAdapterError
                    .malformedPlan
            }
            selectionQuery = try queryPlan(
                plan,
                entity:
                    GraphChatComposableReadEntityReference(
                        alias: entity.alias,
                        identity: entity
                    )
            )
        case .structural:
            selectionQuery = nil
        }
        return try GraphChatComparisonPlan(
            graphScope: plan.graphScope,
            chatScope: plan.chatScope,
            binding: plan.binding,
            nodes: selection.nodes,
            kind: comparison.kind,
            features: comparison.features,
            selectionQuery: selectionQuery,
            relatedLimit:
                comparison.relatedLimit,
            responseLanguage:
                plan.responseLanguage,
            policy: comparison.policy
        )
    }

    private static func relationshipPlan(
        _ plan: GraphChatComposableReadPlan,
        traversal:
            GraphChatComposableReadTraversal
    ) throws -> GraphChatRelationshipPlan {
        try GraphChatRelationshipPlan(
            graphScope: plan.graphScope,
            chatScope: plan.chatScope,
            queryScope:
                plan.compiledScope,
            binding: plan.binding,
            request: traversal.request,
            centerEntity:
                traversal.centerEntity,
            centerNode:
                traversal.centerNode,
            direction:
                traversal.direction,
            counterpartEntity:
                traversal
                    .counterpartEntity,
            counterpartNode:
                traversal
                    .counterpartNode,
            notePredicate:
                traversal.notePredicate,
            limits:
                typedLimits(plan),
            responseLanguage:
                plan.responseLanguage,
            sourceRelationshipContextID:
                traversal
                    .sourceRelationshipContextID
        )
    }

    private static func typedLimits(
        _ plan: GraphChatComposableReadPlan
    ) -> GraphChatTypedIntentLimits {
        GraphChatTypedIntentLimits(
            resultLimit:
                plan.limits.resultLimit,
            maximumResultLimit:
                plan.limits.maximumResultLimit,
            maximumEvidenceCount:
                plan.limits.maximumEvidenceCount,
            maximumArtifactCount:
                plan.limits.maximumArtifactCount
        )
    }

    private static func queryResultContract(
        _ value:
            GraphChatComposableReadResultContract
    ) throws -> GraphChatLocalQueryResultContract {
        switch value {
        case .authoritativeSingleField(
            let node,
            let field
        ):
            return .authoritativeSingleField(
                node: node,
                field: field
            )
        case .entityCollection:
            return .entityCollection
        case .compiledCollection:
            return .compiledCollection
        case .count:
            return .count
        case .groupCount:
            return .groupCount
        case .refinement:
            return .refinement
        case .comparison:
            return .comparison
        case .search, .nodeProfile,
            .graphState, .relationships:
            throw GraphChatComposableReadPlanLegacyActionAdapterError
                .malformedPlan
        }
    }

    private static func queryEntity(
        in plan: GraphChatComposableReadPlan
    ) throws -> GraphChatComposableReadEntityReference {
        let selection = try selection(
            in: plan
        )
        switch selection {
        case .entity(let entity):
            return entity
        case .node(let entity, _):
            return GraphChatComposableReadEntityReference(
                alias: entity.alias,
                identity: entity
            )
        case .nodes(let entities, _):
            guard let entity = entities.first else {
                throw GraphChatComposableReadPlanLegacyActionAdapterError
                    .malformedPlan
            }
            return GraphChatComposableReadEntityReference(
                alias: entity.alias,
                identity: entity
            )
        case .conversationResult(let value):
            return value.entity
        case .scope:
            throw GraphChatComposableReadPlanLegacyActionAdapterError
                .malformedPlan
        }
    }

    private static func queryProjection(
        in plan: GraphChatComposableReadPlan
    ) -> [GraphQueryProjection] {
        guard let projection = operation(
            in: plan,
            extract: {
                (
                    payload:
                        GraphChatComposableReadOperationPayload
                ) -> GraphChatComposableReadProjection? in
                guard case .project(let value) =
                        payload else {
                    return nil
                }
                return value
            }
        ) else {
            return []
        }
        return (
            projection.includesNodeIdentity
            ? [GraphQueryProjection.nodeIdentity]
            : []
        ) + projection.fields.map {
            GraphQueryProjection.field(
                $0.alias
            )
        }
    }

    private static func querySorting(
        in plan: GraphChatComposableReadPlan
    ) -> [GraphQuerySort] {
        guard let sort = operation(
            in: plan,
            extract: {
                (
                    payload:
                        GraphChatComposableReadOperationPayload
                ) -> GraphChatComposableReadSort? in
                guard case .sort(let value) =
                        payload else {
                    return nil
                }
                return value
            }
        ) else {
            return []
        }
        return sort.descriptors.compactMap {
            descriptor in
            let key: GraphQuerySortKey
            switch descriptor.key {
            case .nodeName:
                key = .nodeName
            case .field(let field):
                key = .field(field.alias)
            case .stableNodeID:
                return nil
            case .counterpartDisplayName,
                .counterpartKind,
                .counterpartNodeID,
                .relationshipDirection,
                .linkCreatedAt,
                .stableLinkID:
                return nil
            }
            return GraphQuerySort(
                key: key,
                direction:
                    descriptor.direction
            )
        }
    }

    private static func queryAggregation(
        in plan: GraphChatComposableReadPlan
    ) -> GraphQueryAggregation? {
        guard let aggregation = operation(
            in: plan,
            extract: {
                (
                    payload:
                        GraphChatComposableReadOperationPayload
                ) -> GraphChatComposableReadAggregation? in
                guard case .aggregate(let value) =
                        payload else {
                    return nil
                }
                return value
            }
        ) else {
            return nil
        }
        switch aggregation {
        case .count:
            return .count
        case .groupCount(let field):
            return .groupCount(field.alias)
        case .unsupportedMinimum(let field):
            return .minimum(field.alias)
        case .unsupportedMaximum(let field):
            return .maximum(field.alias)
        }
    }

    private static func finalLimit(
        in plan: GraphChatComposableReadPlan
    ) throws -> Int {
        guard let value = operation(
            in: plan,
            extract: {
                (
                    payload:
                        GraphChatComposableReadOperationPayload
                ) -> GraphChatComposableReadLimit? in
                guard case .limit(let limit) =
                        payload else {
                    return nil
                }
                return limit
            }
        ) else {
            throw GraphChatComposableReadPlanLegacyActionAdapterError
                .malformedPlan
        }
        return value.resultLimit
    }

    private static func filter(
        in plan: GraphChatComposableReadPlan
    ) -> GraphChatComposableReadFilter? {
        operation(
            in: plan,
            extract: {
                (
                    payload:
                        GraphChatComposableReadOperationPayload
                ) -> GraphChatComposableReadFilter? in
                guard case .filter(let value) =
                        payload else {
                    return nil
                }
                return value
            }
        )
    }

    private static func selection(
        in plan: GraphChatComposableReadPlan
    ) throws -> GraphChatComposableReadSelection {
        guard let value = operation(
            in: plan,
            extract: {
                (
                    payload:
                        GraphChatComposableReadOperationPayload
                ) -> GraphChatComposableReadSelection? in
                guard case .select(let selection) =
                        payload else {
                    return nil
                }
                return selection
            }
        ) else {
            throw GraphChatComposableReadPlanLegacyActionAdapterError
                .malformedPlan
        }
        return value
    }

    private static func nodesSelection(
        in plan: GraphChatComposableReadPlan
    ) throws -> (
        entities: [GraphChatTypedEntityIdentity],
        nodes: [GraphChatTypedNodeIdentity]
    ) {
        guard case .nodes(
            let entities,
            let nodes
        ) = try selection(in: plan) else {
            throw GraphChatComposableReadPlanLegacyActionAdapterError
                .malformedPlan
        }
        return (entities, nodes)
    }

    private static func conversationSelection(
        in plan: GraphChatComposableReadPlan
    ) throws -> GraphChatComposableReadConversationSelection? {
        guard case .conversationResult(let value) =
                try selection(in: plan) else {
            return nil
        }
        return value
    }

    private static func operation<Value>(
        in plan: GraphChatComposableReadPlan,
        extract: (
            GraphChatComposableReadOperationPayload
        ) -> Value?
    ) -> Value? {
        for operation in plan.operations {
            if let value = extract(
                operation.payload
            ) {
                return value
            }
        }
        return nil
    }
}
