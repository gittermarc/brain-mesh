//
//  GraphChatComposableReadPlanCompiler.swift
//  BrainMesh
//
//  Lossless app-owned compilation from existing typed local contracts into
//  the shared composable read-plan semantics.
//

import Foundation

nonisolated enum GraphChatComposableReadPlanCompiler {
    static func compile(
        intent: GraphChatTypedIntent,
        action: GraphChatLocalIntentAction,
        policy: GraphChatIntentLimitPolicy = .default
    ) -> GraphChatComposableReadPlan {
        var builder = OperationBuilder()
        let resultContract: GraphChatComposableReadResultContract
        let evidence:
            [GraphChatComposableReadEvidenceRequirement]
        let artifact:
            GraphChatComposableReadArtifactContract
        let queryPlanVersion: Int
        let queryReferenceDate: Date?
        let intermediateLimit: Int
        let compiledScope: GraphChatScope
        let compiledResultLimit: Int

        switch action {
        case .queryDetailValues(let query):
            queryPlanVersion =
                query.plan.version
            builder.append(
                .select(
                    querySelection(
                        intent: intent,
                        action: query
                    )
                )
            )
            if query.plan.filters.isEmpty == false {
                builder.append(
                    .filter(
                        GraphChatComposableReadFilter(
                            predicates:
                                query.plan.filters.map {
                                    GraphChatComposableReadPredicate(
                                        field:
                                            fieldReference(
                                                alias:
                                                    $0.fieldAlias,
                                                intent:
                                                    intent
                                            ),
                                        operation:
                                            $0.operation,
                                        value: $0.value
                                    )
                                }
                        )
                    )
                )
            }
            builder.append(
                .project(
                    GraphChatComposableReadProjection(
                        includesNodeIdentity:
                            query.plan.projection
                                .contains(
                                    .nodeIdentity
                                ),
                        fields:
                            query.plan.projection
                                .compactMap {
                                    projection in
                                    guard case .field(
                                        let alias
                                    ) = projection
                                    else {
                                        return nil
                                    }
                                    return fieldReference(
                                        alias: alias,
                                        intent: intent
                                    )
                                }
                    )
                )
            )
            if query.plan.sorting.isEmpty == false {
                builder.append(
                    .sort(
                        GraphChatComposableReadSort(
                            descriptors:
                                query.plan.sorting
                                    .map {
                                        sortDescriptor(
                                            $0,
                                            intent: intent
                                        )
                                    }
                                + [
                                    GraphChatComposableReadSortDescriptor(
                                        key:
                                            .stableNodeID,
                                        direction:
                                            .ascending
                                    ),
                                ]
                        )
                    )
                )
            }
            if let aggregation =
                    query.plan.aggregation {
                builder.append(
                    .aggregate(
                        readAggregation(
                            aggregation,
                            intent: intent
                        )
                    )
                )
            }
            resultContract =
                readResultContract(
                    query.resultContract
                )
            evidence =
                queryEvidenceRequirements(
                    query.resultContract
                )
            artifact = query.resultContract
                == .comparison
                ? .comparison
                : .queryResult
            queryReferenceDate =
                query.compilationReferenceDate
            intermediateLimit = max(
                intent.limits.resultLimit,
                query.refinementSource?
                    .nodes.count ?? 0
            )
            compiledScope =
                query.plan.scope
                ?? .entireGraph(
                    intent.scope.graphScope
                )
            compiledResultLimit =
                query.plan.limit
                ?? GraphQueryPlanLimits
                    .defaultResultLimit

        case .searchGraph(let search):
            queryPlanVersion =
                GraphQueryPlan.currentVersion
            builder.append(
                .select(
                    searchSelection(
                        intent: intent,
                        action: search
                    )
                )
            )
            builder.append(
                .search(
                    GraphChatComposableReadSearch(
                        query: search.query,
                        target: search.target,
                        entityID:
                            search.entityID
                    )
                )
            )
            resultContract = .search
            evidence = [.searchIdentity]
            artifact = .searchResults
            queryReferenceDate = nil
            intermediateLimit = search.limit
            compiledScope = search.scope
            compiledResultLimit = search.limit

        case .nodeDetails(let node):
            queryPlanVersion =
                GraphQueryPlan.currentVersion
            builder.append(
                .select(
                    nodeSelection(
                        intent: intent,
                        node: node.node
                    )
                )
            )
            builder.append(
                .describeNode(
                    GraphChatComposableReadNodeDescription(
                        node: node.node,
                        compatibilityLimit:
                            node.relatedLimit,
                        profileLimits:
                            policy.nodeProfileLimits(
                                compatibilityLimit:
                                    node.relatedLimit
                            )
                    )
                )
            )
            resultContract = .nodeProfile
            evidence = [
                .nodeIdentity,
                .nodeProfileAreas,
            ]
            artifact = .nodeProfile
            queryReferenceDate = nil
            intermediateLimit = 1
            compiledScope =
                intent.scope.queryScope
            compiledResultLimit = 1

        case .compareNodes(let comparison):
            queryPlanVersion =
                comparison.selectionQuery?
                    .version
                ?? GraphQueryPlan.currentVersion
            builder.append(
                .select(
                    .nodes(
                        entities:
                            intent.payload.entities,
                        nodes:
                            comparison.nodes
                    )
                )
            )
            if let selectionQuery =
                    comparison.selectionQuery {
                builder.append(
                    .project(
                        GraphChatComposableReadProjection(
                            includesNodeIdentity:
                                selectionQuery
                                    .projection
                                    .contains(
                                        .nodeIdentity
                                    ),
                            fields:
                                selectionQuery
                                    .projection
                                    .compactMap {
                                        projection in
                                        guard case .field(
                                            let alias
                                        ) = projection
                                        else {
                                            return nil
                                        }
                                        return fieldReference(
                                            alias: alias,
                                            intent: intent
                                        )
                                    }
                        )
                    )
                )
                if selectionQuery.sorting
                    .isEmpty == false
                {
                    builder.append(
                        .sort(
                            GraphChatComposableReadSort(
                                descriptors:
                                    selectionQuery
                                        .sorting
                                        .map {
                                            sortDescriptor(
                                                $0,
                                                intent:
                                                    intent
                                            )
                                        }
                                    + [
                                        GraphChatComposableReadSortDescriptor(
                                            key:
                                                .stableNodeID,
                                            direction:
                                                .ascending
                                        ),
                                    ]
                            )
                        )
                    )
                }
            }
            builder.append(
                .compareNodes(
                    GraphChatComposableReadComparison(
                        kind: comparison.kind,
                        features:
                            comparison.features,
                        relatedLimit:
                            comparison.relatedLimit,
                        policy:
                            comparison.policy
                    )
                )
            )
            resultContract = .comparison
            evidence = [
                .nodeIdentity,
                .comparisonFeatureValues,
            ]
            artifact = .comparison
            queryReferenceDate = nil
            intermediateLimit =
                comparison.nodes.count
            compiledScope =
                comparison.selectionQuery?
                    .scope
                ?? intent.scope.queryScope
            compiledResultLimit =
                comparison.nodes.count

        case .inspectGraphState(let state):
            queryPlanVersion =
                GraphQueryPlan.currentVersion
            builder.append(
                .select(
                    .scope(
                        intent.scope.queryScope
                    )
                )
            )
            builder.append(
                .inspectGraphState(
                    GraphChatComposableReadGraphState(
                        aspect: state.aspect,
                        hubLimit: state.hubLimit
                    )
                )
            )
            resultContract = .graphState
            evidence = [.graphStateSnapshot]
            artifact = .graphState
            queryReferenceDate = nil
            intermediateLimit = max(
                1,
                state.hubLimit
            )
            compiledScope =
                intent.scope.queryScope
            compiledResultLimit =
                max(1, state.hubLimit)

        case .relationships(let relationship):
            queryPlanVersion =
                GraphQueryPlan.currentVersion
            builder.append(
                .select(
                    .node(
                        entity:
                            relationship.centerEntity,
                        node:
                            relationship.centerNode
                    )
                )
            )
            builder.append(
                .traverseDirectRelationships(
                    GraphChatComposableReadTraversal(
                        request:
                            relationship.request,
                        centerEntity:
                            relationship.centerEntity,
                        centerNode:
                            relationship.centerNode,
                        direction:
                            relationship.direction,
                        counterpartEntity:
                            relationship
                                .counterpartEntity,
                        counterpartNode:
                            relationship
                                .counterpartNode,
                        notePredicate:
                            relationship
                                .notePredicate,
                        hopCount: 1,
                        sourceRelationshipContextID:
                            relationship
                                .sourceRelationshipContextID
                    )
                )
            )
            builder.append(
                .projectRelationships(
                    GraphChatComposableReadRelationshipProjection(
                        includesCounterpartNode: true,
                        includesDirection: true,
                        includesLinkNote: true
                    )
                )
            )
            builder.append(
                .sort(
                    GraphChatComposableReadSort(
                        descriptors: [
                            GraphChatComposableReadSortDescriptor(
                                key:
                                    .counterpartDisplayName,
                                direction:
                                    .ascending
                            ),
                            GraphChatComposableReadSortDescriptor(
                                key:
                                    .counterpartKind,
                                direction:
                                    .ascending
                            ),
                            GraphChatComposableReadSortDescriptor(
                                key:
                                    .counterpartNodeID,
                                direction:
                                    .ascending
                            ),
                            GraphChatComposableReadSortDescriptor(
                                key:
                                    .relationshipDirection,
                                direction:
                                    .ascending
                            ),
                            GraphChatComposableReadSortDescriptor(
                                key:
                                    .linkCreatedAt,
                                direction:
                                    .ascending
                            ),
                            GraphChatComposableReadSortDescriptor(
                                key:
                                    .stableLinkID,
                                direction:
                                    .ascending
                            ),
                        ]
                    )
                )
            )
            resultContract = .relationships
            evidence = [
                .nodeIdentity,
                .directRelationshipBinding,
            ]
            artifact = .relationships
            queryReferenceDate = nil
            intermediateLimit =
                relationship.limits
                    .maximumResultLimit
            compiledScope =
                relationship.queryScope
            compiledResultLimit =
                relationship.limits
                    .resultLimit
        }

        builder.append(
            .limit(
                GraphChatComposableReadLimit(
                    resultLimit:
                        compiledResultLimit,
                    intermediateResultLimit:
                        intermediateLimit
                )
            )
        )

        return GraphChatComposableReadPlan(
            version: .current,
            queryPlanVersion:
                queryPlanVersion,
            graphScope:
                intent.scope.graphScope,
            chatScope:
                intent.scope.chatScope,
            queryScope:
                intent.scope.queryScope,
            compiledScope: compiledScope,
            binding: intent.binding,
            responseLanguage:
                intent.responseLanguage,
            intentKind: intent.kind,
            operations: builder.operations,
            resultContract: resultContract,
            evidenceRequirements:
                deduplicated(evidence),
            artifactContract: artifact,
            limits:
                GraphChatComposableReadLimits(
                    resultLimit:
                        intent.limits
                            .resultLimit,
                    maximumResultLimit:
                        intent.limits
                            .maximumResultLimit,
                    intermediateResultLimit:
                        intermediateLimit,
                    maximumEvidenceCount:
                        intent.limits
                            .maximumEvidenceCount,
                    maximumArtifactCount:
                        intent.limits
                            .maximumArtifactCount,
                    maximumOperationCount:
                        policy
                            .maximumComposableReadOperationCount,
                    maximumTraversalHopCount:
                        policy
                            .maximumComposableReadTraversalHopCount
                ),
            queryReferenceDate:
                queryReferenceDate
        )
    }

    private struct OperationBuilder {
        private(set) var operations:
            [GraphChatComposableReadOperation] = []

        mutating func append(
            _ payload:
                GraphChatComposableReadOperationPayload
        ) {
            let id = GraphChatComposableReadStepID(
                rawValue: operations.count
            )
            operations.append(
                GraphChatComposableReadOperation(
                    id: id,
                    input:
                        operations.last?.id,
                    payload: payload
                )
            )
        }
    }

    private static func querySelection(
        intent: GraphChatTypedIntent,
        action: GraphChatLocalQueryAction
    ) -> GraphChatComposableReadSelection {
        let entity = entityReference(
            alias: action.plan.entityAlias,
            intent: intent
        )
        if let source = action.refinementSource {
            let resultContextID =
                source.revision.sourceResultID
                ?? narrowResultContextID(
                    intent
                )
                ?? zeroUUID
            return .conversationResult(
                GraphChatComposableReadConversationSelection(
                    sourceResultContextID:
                        resultContextID,
                    source: source,
                    entity: entity,
                    nodes:
                        intent.payload.nodes
                )
            )
        }
        if case .authoritativeSingleField(
            let node,
            _
        ) = action.resultContract,
           let identity = entity.identity {
            return .node(
                entity: identity,
                node: node
            )
        }
        return .entity(entity)
    }

    private static func searchSelection(
        intent: GraphChatTypedIntent,
        action: GraphChatLocalSearchAction
    ) -> GraphChatComposableReadSelection {
        guard
            let entityID = action.entityID,
            let entity = intent.payload.entities
                .first(
                    where: {
                        $0.id == entityID
                    }
                )
        else {
            return .scope(action.scope)
        }
        return .entity(
            GraphChatComposableReadEntityReference(
                alias: entity.alias,
                identity: entity
            )
        )
    }

    private static func nodeSelection(
        intent: GraphChatTypedIntent,
        node: GraphChatTypedNodeIdentity
    ) -> GraphChatComposableReadSelection {
        guard let entity =
                intent.payload.entities.first(
                    where: {
                        $0.id
                            == node.ownerEntityID
                    }
                )
        else {
            return .nodes(
                entities:
                    intent.payload.entities,
                nodes: [node]
            )
        }
        return .node(
            entity: entity,
            node: node
        )
    }

    private static func entityReference(
        alias: GraphEntityAlias,
        intent: GraphChatTypedIntent
    ) -> GraphChatComposableReadEntityReference {
        GraphChatComposableReadEntityReference(
            alias: alias,
            identity:
                intent.payload.entities.first(
                    where: {
                        $0.alias == alias
                    }
                )
        )
    }

    private static func fieldReference(
        alias: GraphFieldAlias,
        intent: GraphChatTypedIntent
    ) -> GraphChatComposableReadFieldReference {
        GraphChatComposableReadFieldReference(
            alias: alias,
            identity:
                intent.payload.fields.first(
                    where: {
                        $0.alias == alias
                    }
                )
        )
    }

    private static func sortDescriptor(
        _ value: GraphQuerySort,
        intent: GraphChatTypedIntent
    ) -> GraphChatComposableReadSortDescriptor {
        let key: GraphChatComposableReadSortKey
        switch value.key {
        case .nodeName:
            key = .nodeName
        case .field(let alias):
            key = .field(
                fieldReference(
                    alias: alias,
                    intent: intent
                )
            )
        }
        return GraphChatComposableReadSortDescriptor(
            key: key,
            direction: value.direction
        )
    }

    private static func readAggregation(
        _ value: GraphQueryAggregation,
        intent: GraphChatTypedIntent
    ) -> GraphChatComposableReadAggregation {
        switch value {
        case .count:
            return .count
        case .groupCount(let alias):
            return .groupCount(
                fieldReference(
                    alias: alias,
                    intent: intent
                )
            )
        case .minimum(let alias):
            return .unsupportedMinimum(
                fieldReference(
                    alias: alias,
                    intent: intent
                )
            )
        case .maximum(let alias):
            return .unsupportedMaximum(
                fieldReference(
                    alias: alias,
                    intent: intent
                )
            )
        }
    }

    private static func readResultContract(
        _ value: GraphChatLocalQueryResultContract
    ) -> GraphChatComposableReadResultContract {
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
        }
    }

    private static func queryEvidenceRequirements(
        _ value: GraphChatLocalQueryResultContract
    ) -> [GraphChatComposableReadEvidenceRequirement] {
        switch value {
        case .authoritativeSingleField:
            return [
                .nodeIdentity,
                .authoritativeDetailValue,
            ]
        case .comparison:
            return [
                .nodeIdentity,
                .comparisonFeatureValues,
            ]
        case .entityCollection, .compiledCollection,
            .count, .groupCount, .refinement:
            return [.nodeIdentity]
        }
    }

    private static func narrowResultContextID(
        _ intent: GraphChatTypedIntent
    ) -> UUID? {
        guard case .narrowResultSet(let value) =
                intent.payload else {
            return nil
        }
        return value.sourceResultContextID
    }

    private static func deduplicated(
        _ values:
            [GraphChatComposableReadEvidenceRequirement]
    ) -> [GraphChatComposableReadEvidenceRequirement] {
        var seen =
            Set<GraphChatComposableReadEvidenceRequirement>()
        return values.filter {
            seen.insert($0).inserted
        }
    }

    private static let zeroUUID = UUID(
        uuidString:
            "00000000-0000-0000-0000-000000000000"
    )!
}
