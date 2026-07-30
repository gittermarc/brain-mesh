//
//  GraphChatIntentInterpretationBuilder.swift
//  BrainMesh
//
//  Deterministic derivation from revalidated typed intents and execution plans.
//

import Foundation

nonisolated enum GraphChatIntentInterpretationExecutionWitness:
    Hashable,
    Sendable
{
    case query(ValidatedGraphQueryPlan)
    case search
    case node(GraphChatTypedNodeIdentity)
    case comparison([NodeRefKey])
    case graphState(GraphChatGraphStateAspect)
    case relationship(GraphChatRelationshipPlan)
}

nonisolated struct GraphChatIntentInterpretationBuilder:
    Sendable
{
    private let timeZone: TimeZone

    init(timeZone: TimeZone) {
        self.timeZone = timeZone
    }

    func executionInterpretation(
        intent: GraphChatTypedIntent,
        witness:
            GraphChatIntentInterpretationExecutionWitness,
        correctionOrigin:
            GraphChatInterpretationCorrectionOrigin? = nil
    ) -> GraphChatIntentInterpretation? {
        switch witness {
        case .query(let plan):
            return queryInterpretation(
                intent: intent,
                plan: plan,
                correctionOrigin:
                    correctionOrigin
            )
        case .search:
            guard intent.kind == .findNodes else {
                return nil
            }
            return makeSearchInterpretation(
                intent: intent,
                correctionOrigin:
                    correctionOrigin
            )
        case .node(let node):
            guard
                intent.kind == .nodeDetails,
                intent.expectedCardinality
                    == .zeroOrOne,
                intent.factExpectation == .none,
                intent.limits.resultLimit == 1,
                case .nodeDetails(let details) =
                    intent.payload,
                details.node == node,
                intent.scope.queryScope
                    == GraphChatScope.node(
                        node.node,
                        in:
                            intent.scope
                                .graphScope
                    )
            else {
                return nil
            }
            return makeNodeInterpretation(
                intent: intent,
                details: details,
                correctionOrigin:
                    correctionOrigin
            )
        case .comparison(let nodes):
            guard
                intent.kind == .compareNodes,
                case .compareNodes(
                    let comparison
                ) = intent.payload,
                comparison.nodes.map(\.node)
                    == nodes,
                let comparisonScope =
                    try? GraphChatScope.selection(
                        nodes,
                        in:
                            intent.scope
                                .graphScope
                    ),
                intent.scope.queryScope
                    == comparisonScope
            else {
                return nil
            }
            return makeComparisonInterpretation(
                intent: intent,
                comparison: comparison,
                correctionOrigin:
                    correctionOrigin
            )
        case .graphState(let aspect):
            guard
                intent.kind == .inspectGraphState,
                intent.expectedCardinality
                    == .exactlyOne,
                intent.factExpectation == .none,
                case .inspectGraphState(
                    let graphState
                ) = intent.payload,
                graphState.entity == nil,
                graphState.aspect == aspect,
                intent.scope.chatScope
                    == GraphChatScope.entireGraph(
                        intent.scope
                            .graphScope
                    ),
                intent.scope.queryScope
                    == intent.scope.chatScope,
                intent.limits.resultLimit
                    == max(
                        1,
                        GraphChatAdvancedIntentPolicy
                            .default
                            .graphHubLimit
                    )
            else {
                return nil
            }
            return makeGraphStateInterpretation(
                intent: intent,
                graphState: graphState,
                aspect: aspect,
                correctionOrigin:
                    correctionOrigin
            )
        case .relationship(let plan):
            guard
                intent.kind
                    == .relationships,
                case .relationships(
                    let payloadPlan
                ) = intent.payload,
                payloadPlan == plan,
                plan.binding
                    == intent.binding,
                plan.graphScope
                    == intent.scope.graphScope,
                plan.chatScope
                    == intent.scope.chatScope,
                plan.queryScope
                    == intent.scope.queryScope
            else {
                return nil
            }
            return makeRelationshipInterpretation(
                intent: intent,
                plan: plan,
                correctionOrigin:
                    correctionOrigin
            )
        }
    }

    func queryInterpretation(
        intent: GraphChatTypedIntent,
        plan: ValidatedGraphQueryPlan,
        correctionOrigin:
            GraphChatInterpretationCorrectionOrigin? = nil
    ) -> GraphChatIntentInterpretation? {
        guard
            plan.version
                == GraphQueryPlan.currentVersion,
            plan.graphScope
                == intent.scope.graphScope,
            plan.entityID
                == intent.payload.entities.first?.id,
            plan.scope
                == resolvedQueryScope(
                    intent.scope.queryScope
                ),
            plan.limit
                == intent.limits.resultLimit,
            let entity = intent.payload.entities.first,
            intent.payload.entities.count == 1
        else {
            return nil
        }

        let fields = uniqueFields(
            intent.payload.fields
        )
        let fieldByID = Dictionary(
            uniqueKeysWithValues:
                fields.map { ($0.id, $0) }
        )
        let filters = plan.filters.compactMap {
            filter
            -> GraphChatIntentInterpretationFilter? in
            guard let field =
                    fieldByID[filter.fieldID],
                  field.type
                    == filter.fieldType
            else {
                return nil
            }
            return GraphChatIntentInterpretationFilter(
                field: field,
                operation: filter.operation,
                value: filter.value
            )
        }
        guard filters.count == plan.filters.count else {
            return nil
        }

        let sorting = plan.sorting.compactMap {
            sort
            -> GraphChatIntentInterpretationSort? in
            switch sort.key {
            case .nodeName:
                return GraphChatIntentInterpretationSort(
                    key: .nodeName,
                    direction: sort.direction
                )
            case .field(let fieldID):
                guard let field =
                        fieldByID[fieldID]
                else {
                    return nil
                }
                return GraphChatIntentInterpretationSort(
                    key: .field(field),
                    direction: sort.direction
                )
            }
        }
        guard sorting.count == plan.sorting.count else {
            return nil
        }

        let projectedFields =
            plan.projection.compactMap {
                projection
                -> GraphChatIntentInterpretationField? in
                guard case .field(let fieldID) =
                        projection
                else {
                    return nil
                }
                return fieldByID[fieldID]
            }
        let projectedFieldCount =
            plan.projection.reduce(
                into: 0
            ) { count, projection in
                if case .field = projection {
                    count += 1
                }
            }
        guard projectedFields.count
                == projectedFieldCount
        else {
            return nil
        }

        let aggregation:
            GraphChatIntentInterpretationAggregation?
        let grouping:
            GraphChatIntentInterpretationGrouping?
        switch plan.aggregation {
        case .count:
            aggregation = .count
            grouping = nil
        case .groupCount(let fieldID):
            guard let field =
                    fieldByID[fieldID]
            else {
                return nil
            }
            aggregation = .groupCount(field)
            grouping =
                GraphChatIntentInterpretationGrouping(
                    field: field
                )
        case .minimum, .maximum:
            return nil
        case nil:
            aggregation = nil
            grouping = nil
        }

        let extentKind:
            GraphChatIntentInterpretationResultExtentKind
        switch intent.kind {
        case .nodeDetails, .countOrGroup:
            extentKind =
                intent.expectedCardinality == .exactlyOne
                || intent.expectedCardinality == .zeroOrOne
                ? .singleResult
                : .boundedCollection
        case .narrowResultSet:
            extentKind = .refinedCollection
        case .compareNodes:
            extentKind = .comparison
        case .entityCollection:
            extentKind =
                plan.limit
                    == intent.limits.maximumResultLimit
                ? .completeAuthorizedCollection
                : .boundedCollection
        case .findNodes:
            extentKind = .boundedCollection
        case .inspectGraphState:
            extentKind = .graphState
        case .relationships:
            extentKind = .relationship
        }

        let interpretation =
            GraphChatIntentInterpretation(
                version: .v1,
                intentKind: intent.kind,
                scopeBinding: scopeBinding(intent),
                turnBinding: turnBinding(intent),
                responseLanguage:
                    intent.responseLanguage,
                entities: [
                    GraphChatIntentInterpretationEntity(
                        entity
                    ),
                ],
                nodes: intent.payload.nodes.map(
                    GraphChatIntentInterpretationNode
                        .init
                ),
                fields: fields,
                projectedFields:
                    projectedFields,
                filters: filters,
                sorting: sorting,
                grouping: grouping,
                aggregation: aggregation,
                resultExtent: resultExtent(
                    intent: intent,
                    kind: extentKind,
                    resultLimit: plan.limit,
                    subjectCount:
                        intent.payload.nodes.isEmpty
                        ? nil
                        : intent.payload.nodes.count,
                    includesAllAuthorizedResults:
                        extentKind
                            == .completeAuthorizedCollection
                ),
                graphStateAspect: nil,
                relationship: nil,
                resolutionSource:
                    intent.resolution.source,
                resolutionOrigin:
                    intent.resolution.origin,
                resolutionQuality:
                    intent.resolution.quality,
                editableComponents:
                    editableComponents(
                        for: intent,
                        hasFilters:
                            filters.isEmpty == false,
                        hasSorting:
                            sorting.isEmpty == false,
                        hasGrouping:
                            grouping != nil
                    ),
                formattingTimeZoneIdentifier:
                    timeZone.identifier,
                correctionOrigin:
                    correctionOrigin
            )
        return interpretation
            .isInternallyConsistent
            ? interpretation
            : nil
    }

    func searchInterpretation(
        intent: GraphChatTypedIntent,
        action: GraphChatLocalSearchAction,
        correctionOrigin:
            GraphChatInterpretationCorrectionOrigin? = nil
    ) -> GraphChatIntentInterpretation? {
        guard
            intent.kind == .findNodes,
            action.scope
                == intent.scope.queryScope,
            action.limit
                == intent.limits.resultLimit,
            action.entityID
                == intent.payload.entities.first?.id
        else {
            return nil
        }
        return makeSearchInterpretation(
            intent: intent,
            correctionOrigin:
                correctionOrigin
        )
    }

    func nodeInterpretation(
        intent: GraphChatTypedIntent,
        action: GraphChatLocalNodeDetailsAction,
        correctionOrigin:
            GraphChatInterpretationCorrectionOrigin? = nil
    ) -> GraphChatIntentInterpretation? {
        guard
            intent.kind == .nodeDetails,
            intent.expectedCardinality
                == .zeroOrOne,
            intent.factExpectation == .none,
            intent.limits.resultLimit == 1,
            case .nodeDetails(let details) =
                intent.payload,
            details.node == action.node,
            intent.scope.queryScope
                == GraphChatScope.node(
                    action.node.node,
                    in:
                        intent.scope
                            .graphScope
                )
        else {
            return nil
        }
        return makeNodeInterpretation(
            intent: intent,
            details: details,
            correctionOrigin:
                correctionOrigin
        )
    }

    func comparisonInterpretation(
        intent: GraphChatTypedIntent,
        plan: GraphChatComparisonPlan,
        correctionOrigin:
            GraphChatInterpretationCorrectionOrigin? = nil
    ) -> GraphChatIntentInterpretation? {
        guard
            intent.kind == .compareNodes,
            case .compareNodes(let comparison) =
                intent.payload,
            plan.binding == intent.binding,
            plan.graphScope
                == intent.scope.graphScope,
            plan.chatScope
                == intent.scope.chatScope,
            plan.nodes == comparison.nodes,
            plan.responseLanguage
                == intent.responseLanguage,
            plan.expectedCardinality
                == intent.expectedCardinality
        else {
            return nil
        }
        switch plan.kind {
        case .sameEntityAttributes:
            let plannedFields =
                plan.features.compactMap {
                    feature
                    -> GraphChatTypedFieldIdentity? in
                    if case .field(let field) =
                        feature {
                        return field
                    }
                    return nil
                }
            guard
                plannedFields
                    == comparison.fields,
                plannedFields.count
                    == plan.features.count
            else {
                return nil
            }
        case .structural:
            guard comparison.fields.isEmpty,
                  plan.features.allSatisfy({
                      feature in
                      if case .structure = feature {
                          return true
                      }
                      return false
                  })
            else {
                return nil
            }
        }
        return makeComparisonInterpretation(
            intent: intent,
            comparison: comparison,
            correctionOrigin:
                correctionOrigin
        )
    }

    func graphStateInterpretation(
        intent: GraphChatTypedIntent,
        action: GraphChatLocalGraphStateAction,
        correctionOrigin:
            GraphChatInterpretationCorrectionOrigin? = nil
    ) -> GraphChatIntentInterpretation? {
        guard
            intent.kind == .inspectGraphState,
            intent.expectedCardinality
                == .exactlyOne,
            intent.factExpectation == .none,
            case .inspectGraphState(let graphState) =
                intent.payload,
            graphState.entity == nil,
            graphState.aspect == action.aspect,
            action.hubLimit
                == GraphChatAdvancedIntentPolicy
                    .default
                    .graphHubLimit,
            intent.limits.resultLimit
                == max(1, action.hubLimit),
            intent.scope.chatScope
                == GraphChatScope.entireGraph(
                    intent.scope.graphScope
                ),
            intent.scope.queryScope
                == intent.scope.chatScope
        else {
            return nil
        }
        return makeGraphStateInterpretation(
            intent: intent,
            graphState: graphState,
            aspect: action.aspect,
            correctionOrigin:
                correctionOrigin
        )
    }

    private func makeSearchInterpretation(
        intent: GraphChatTypedIntent,
        correctionOrigin:
            GraphChatInterpretationCorrectionOrigin?
    ) -> GraphChatIntentInterpretation? {
        let interpretation =
            GraphChatIntentInterpretation(
                version: .v1,
                intentKind: intent.kind,
                scopeBinding: scopeBinding(intent),
                turnBinding: turnBinding(intent),
                responseLanguage:
                    intent.responseLanguage,
                entities: intent.payload.entities.map(
                    GraphChatIntentInterpretationEntity
                        .init
                ),
                nodes: intent.payload.nodes.map(
                    GraphChatIntentInterpretationNode
                        .init
                ),
                fields: uniqueFields(
                    intent.payload.fields
                ),
                projectedFields: [],
                filters: [],
                sorting: [],
                grouping: nil,
                aggregation: nil,
                resultExtent: resultExtent(
                    intent: intent,
                    kind: .boundedCollection,
                    resultLimit:
                        intent.limits.resultLimit,
                    subjectCount: nil,
                    includesAllAuthorizedResults:
                        false
                ),
                graphStateAspect: nil,
                relationship: nil,
                resolutionSource:
                    intent.resolution.source,
                resolutionOrigin:
                    intent.resolution.origin,
                resolutionQuality:
                    intent.resolution.quality,
                editableComponents: [
                    .entity,
                    .resultExtent,
                ],
                formattingTimeZoneIdentifier:
                    timeZone.identifier,
                correctionOrigin:
                    correctionOrigin
            )
        return valid(interpretation)
    }

    private func makeNodeInterpretation(
        intent: GraphChatTypedIntent,
        details: GraphChatTypedNodeDetailsIntent,
        correctionOrigin:
            GraphChatInterpretationCorrectionOrigin?
    ) -> GraphChatIntentInterpretation? {
        let fields = uniqueFields(
            details.fields
        )
        let interpretation =
            GraphChatIntentInterpretation(
                version: .v1,
                intentKind: intent.kind,
                scopeBinding: scopeBinding(intent),
                turnBinding: turnBinding(intent),
                responseLanguage:
                    intent.responseLanguage,
                entities: [
                    GraphChatIntentInterpretationEntity(
                        details.entity
                    ),
                ],
                nodes: [
                    GraphChatIntentInterpretationNode(
                        details.node
                    ),
                ],
                fields: fields,
                projectedFields: fields,
                filters: [],
                sorting: [],
                grouping: nil,
                aggregation: nil,
                resultExtent: resultExtent(
                    intent: intent,
                    kind: .singleResult,
                    resultLimit:
                        intent.limits.resultLimit,
                    subjectCount: 1,
                    includesAllAuthorizedResults:
                        false
                ),
                graphStateAspect: nil,
                relationship: nil,
                resolutionSource:
                    intent.resolution.source,
                resolutionOrigin:
                    intent.resolution.origin,
                resolutionQuality:
                    intent.resolution.quality,
                editableComponents: [
                    .nodes,
                    .fields,
                ],
                formattingTimeZoneIdentifier:
                    timeZone.identifier,
                correctionOrigin:
                    correctionOrigin
            )
        return valid(interpretation)
    }

    private func makeComparisonInterpretation(
        intent: GraphChatTypedIntent,
        comparison: GraphChatTypedCompareNodesIntent,
        correctionOrigin:
            GraphChatInterpretationCorrectionOrigin?
    ) -> GraphChatIntentInterpretation? {
        let fields = uniqueFields(
            comparison.fields
        )
        let interpretation =
            GraphChatIntentInterpretation(
                version: .v1,
                intentKind: intent.kind,
                scopeBinding: scopeBinding(intent),
                turnBinding: turnBinding(intent),
                responseLanguage:
                    intent.responseLanguage,
                entities: comparison.entities.map(
                    GraphChatIntentInterpretationEntity
                        .init
                ),
                nodes: comparison.nodes.map(
                    GraphChatIntentInterpretationNode
                        .init
                ),
                fields: fields,
                projectedFields: fields,
                filters: [],
                sorting: [],
                grouping: nil,
                aggregation: nil,
                resultExtent: resultExtent(
                    intent: intent,
                    kind: .comparison,
                    resultLimit:
                        comparison.nodes.count,
                    subjectCount:
                        comparison.nodes.count,
                    includesAllAuthorizedResults:
                        false
                ),
                graphStateAspect: nil,
                relationship: nil,
                resolutionSource:
                    intent.resolution.source,
                resolutionOrigin:
                    intent.resolution.origin,
                resolutionQuality:
                    intent.resolution.quality,
                editableComponents: [
                    .nodes,
                    .fields,
                ],
                formattingTimeZoneIdentifier:
                    timeZone.identifier,
                correctionOrigin:
                    correctionOrigin
            )
        return valid(interpretation)
    }

    private func makeGraphStateInterpretation(
        intent: GraphChatTypedIntent,
        graphState:
            GraphChatTypedInspectGraphStateIntent,
        aspect: GraphChatGraphStateAspect,
        correctionOrigin:
            GraphChatInterpretationCorrectionOrigin?
    ) -> GraphChatIntentInterpretation? {
        let interpretation =
            GraphChatIntentInterpretation(
                version: .v1,
                intentKind: intent.kind,
                scopeBinding: scopeBinding(intent),
                turnBinding: turnBinding(intent),
                responseLanguage:
                    intent.responseLanguage,
                entities: graphState.entity.map {
                    [
                        GraphChatIntentInterpretationEntity(
                            $0
                        ),
                    ]
                } ?? [],
                nodes: [],
                fields: [],
                projectedFields: [],
                filters: [],
                sorting: [],
                grouping: nil,
                aggregation: nil,
                resultExtent: resultExtent(
                    intent: intent,
                    kind: .graphState,
                    resultLimit:
                        intent.limits.resultLimit,
                    subjectCount: 1,
                    includesAllAuthorizedResults:
                        true
                ),
                graphStateAspect: aspect,
                relationship: nil,
                resolutionSource:
                    intent.resolution.source,
                resolutionOrigin:
                    intent.resolution.origin,
                resolutionQuality:
                    intent.resolution.quality,
                editableComponents: [
                    .graphStateAspect,
                ],
                formattingTimeZoneIdentifier:
                    timeZone.identifier,
                correctionOrigin:
                    correctionOrigin
            )
        return valid(interpretation)
    }

    private func makeRelationshipInterpretation(
        intent: GraphChatTypedIntent,
        plan: GraphChatRelationshipPlan,
        correctionOrigin:
            GraphChatInterpretationCorrectionOrigin?
    ) -> GraphChatIntentInterpretation? {
        let entities =
            intent.payload.entities.map(
                GraphChatIntentInterpretationEntity
                    .init
            )
        let nodes =
            intent.payload.nodes.map(
                GraphChatIntentInterpretationNode
                    .init
            )
        let center =
            GraphChatIntentInterpretationNode(
                plan.centerNode
            )
        let counterpartEntity =
            plan.counterpartEntity.map(
                GraphChatIntentInterpretationEntity
                    .init
            )
        let counterpartNode =
            plan.counterpartNode.map(
                GraphChatIntentInterpretationNode
                    .init
            )
        let interpretation =
            GraphChatIntentInterpretation(
                version: .v1,
                intentKind: .relationships,
                scopeBinding:
                    scopeBinding(intent),
                turnBinding:
                    turnBinding(intent),
                responseLanguage:
                    intent.responseLanguage,
                entities: entities,
                nodes: nodes,
                fields: [],
                projectedFields: [],
                filters: [],
                sorting: [],
                grouping: nil,
                aggregation: nil,
                resultExtent:
                    resultExtent(
                        intent: intent,
                        kind: .relationship,
                        resultLimit:
                            plan.limits
                                .resultLimit,
                        subjectCount: 1,
                        includesAllAuthorizedResults:
                            false
                    ),
                graphStateAspect: nil,
                relationship:
                    GraphChatIntentInterpretationRelationship(
                        request:
                            plan.request,
                        direction:
                            plan.direction,
                        center: center,
                        counterpartEntity:
                            counterpartEntity,
                        counterpartNode:
                            counterpartNode,
                        notePredicate:
                            plan.notePredicate
                    ),
                resolutionSource:
                    intent.resolution.source,
                resolutionOrigin:
                    intent.resolution.origin,
                resolutionQuality:
                    intent.resolution.quality,
                editableComponents: [
                    .relationshipDirection,
                    .relationshipCounterpartEntity,
                    .relationshipCounterpartNode,
                    .relationshipNotePredicate,
                ],
                formattingTimeZoneIdentifier:
                    timeZone.identifier,
                correctionOrigin:
                    correctionOrigin
            )
        return valid(interpretation)
    }

    private func valid(
        _ interpretation:
            GraphChatIntentInterpretation
    ) -> GraphChatIntentInterpretation? {
        interpretation.isInternallyConsistent
            ? interpretation
            : nil
    }

    private func scopeBinding(
        _ intent: GraphChatTypedIntent
    ) -> GraphChatIntentInterpretationScopeBinding {
        GraphChatIntentInterpretationScopeBinding(
            graphScope: intent.scope.graphScope,
            chatScope: intent.scope.chatScope,
            queryScope: intent.scope.queryScope
        )
    }

    private func resolvedQueryScope(
        _ scope: GraphChatScope
    ) -> GraphResolvedQueryScope {
        switch scope.target {
        case .graph:
            return .graph
        case .entity(let entityID):
            return .entity(entityID)
        case .node(let node):
            return .node(node)
        case .selection(let nodes):
            return .selection(nodes)
        }
    }

    private func turnBinding(
        _ intent: GraphChatTypedIntent
    ) -> GraphChatIntentInterpretationTurnBinding {
        GraphChatIntentInterpretationTurnBinding(
            requestID: intent.binding.requestID,
            conversationID:
                intent.binding.conversationID,
            turnID: intent.binding.turnID,
            sourceTurnID:
                intent.binding.sourceTurnID
        )
    }

    private func resultExtent(
        intent: GraphChatTypedIntent,
        kind:
            GraphChatIntentInterpretationResultExtentKind,
        resultLimit: Int,
        subjectCount: Int?,
        includesAllAuthorizedResults: Bool
    ) -> GraphChatIntentInterpretationResultExtent {
        GraphChatIntentInterpretationResultExtent(
            kind: kind,
            expectedCardinality:
                intent.expectedCardinality,
            resultLimit: resultLimit,
            maximumResultLimit:
                intent.limits.maximumResultLimit,
            subjectCount: subjectCount,
            includesAllAuthorizedResults:
                includesAllAuthorizedResults
        )
    }

    private func uniqueFields(
        _ fields: [GraphChatTypedFieldIdentity]
    ) -> [GraphChatIntentInterpretationField] {
        var seen = Set<UUID>()
        return fields.compactMap { field in
            guard seen.insert(field.id).inserted else {
                return nil
            }
            return GraphChatIntentInterpretationField(
                field
            )
        }
    }

    private func editableComponents(
        for intent: GraphChatTypedIntent,
        hasFilters: Bool,
        hasSorting: Bool,
        hasGrouping: Bool
    ) -> [
        GraphChatIntentInterpretationEditableComponent
    ] {
        var components:
            [GraphChatIntentInterpretationEditableComponent]
        switch intent.kind {
        case .findNodes:
            components = [
                .entity,
                .resultExtent,
            ]
        case .entityCollection:
            components = [
                .entity,
                .fields,
                .filters,
                .sorting,
                .resultExtent,
            ]
        case .countOrGroup:
            components = [
                .entity,
                .filters,
                .aggregation,
            ]
        case .nodeDetails:
            components = [
                .nodes,
                .fields,
            ]
        case .narrowResultSet:
            components = [
                .sourceResultSet,
                .nodes,
                .fields,
                .filters,
                .sorting,
                .resultExtent,
            ]
        case .compareNodes:
            components = [
                .nodes,
                .fields,
            ]
        case .inspectGraphState:
            components = [
                .graphStateAspect,
            ]
        case .relationships:
            components = [
                .relationshipDirection,
                .relationshipCounterpartEntity,
                .relationshipCounterpartNode,
                .relationshipNotePredicate,
            ]
        }
        if hasFilters == false {
            components.removeAll {
                $0 == .filters
            }
        }
        if hasSorting == false {
            components.removeAll {
                $0 == .sorting
            }
        }
        if hasGrouping {
            components.append(.grouping)
        }
        return components
    }
}
