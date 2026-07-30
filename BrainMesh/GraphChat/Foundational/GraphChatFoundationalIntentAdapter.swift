//
//  GraphChatFoundationalIntentAdapter.swift
//  BrainMesh
//
//  Lossless bridge from the narrow foundational fast path into the
//  versioned Typed-Intent domain and its precompiled local action.
//

import Foundation

nonisolated enum GraphChatFoundationalIntentAdapterError:
    Error,
    LocalizedError,
    Hashable,
    Sendable
{
    case invalidScope
    case invalidSingleFieldContract
    case invalidCollectionContract
    case invalidNodeDetailsContract

    var errorDescription: String? {
        switch self {
        case .invalidScope:
            return "Der Foundational Intent enthält widersprüchliche Scopes."
        case .invalidSingleFieldContract:
            return "Der Foundational Single-Field-Intent ist nicht vollständig gebunden."
        case .invalidCollectionContract:
            return "Der Foundational Collection-Intent ist nicht vollständig gebunden."
        case .invalidNodeDetailsContract:
            return "Der Foundational Node-Details-Intent ist nicht vollständig gebunden."
        }
    }
}

nonisolated struct GraphChatFoundationalIntentAdapter:
    Hashable,
    Sendable
{
    func adapt(
        _ source: GraphChatFoundationalIntent
    ) throws -> GraphChatTypedIntentAdaptation {
        guard source.graphScope == source.chatScope.graphScope,
              source.graphScope == source.queryScope.graphScope else {
            throw GraphChatFoundationalIntentAdapterError.invalidScope
        }

        let entity = GraphChatTypedEntityIdentity(
            id: source.entity.id,
            alias: source.entity.alias,
            displayName: source.entity.displayName
        )
        let binding = GraphChatTypedIntentBinding(
            requestID: source.binding.requestID,
            conversationID: source.binding.conversationID,
            turnID: source.binding.requestID,
            sourceTurnID: source.binding.sourceTurnID,
            clarificationID: source.binding.clarificationID
        )
        let scope = GraphChatTypedIntentScope(
            graphScope: source.graphScope,
            chatScope: source.chatScope,
            queryScope: source.queryScope
        )
        let resolution = GraphChatTypedIntentResolution(
            source: .foundationalFastPath,
            origin: resolutionOrigin(source.origin),
            quality: resolutionQuality(source.confidence)
        )
        switch source.kind {
        case .singleNodeFieldValue:
            guard source.expectedCardinality == .zeroOrOne,
                  source.resultLimit == 1,
                  let sourceField = source.field,
                  let sourceNode = source.node,
                  sourceNode.ownerEntityID == source.entity.id else {
                throw GraphChatFoundationalIntentAdapterError
                    .invalidSingleFieldContract
            }
            let field = GraphChatTypedFieldIdentity(
                id: sourceField.id,
                alias: sourceField.alias,
                displayName: sourceField.displayName,
                ownerEntityID: source.entity.id,
                type: sourceField.type,
                unit: sourceField.unit
            )
            let node = GraphChatTypedNodeIdentity(
                node: sourceNode.node,
                displayName: sourceNode.displayName,
                ownerEntityID: sourceNode.ownerEntityID
            )
            let intent = try GraphChatTypedIntent(
                version: .v1,
                scope: scope,
                responseLanguage: source.responseLanguage,
                binding: binding,
                resolution: resolution,
                expectedCardinality: .zeroOrOne,
                factExpectation: .authoritativeSingleField,
                limits: GraphChatTypedIntentLimits(
                    resultLimit: source.resultLimit,
                    maximumResultLimit:
                        GraphQueryPlanLimits
                            .maximumResultLimit,
                    maximumEvidenceCount: 2,
                    maximumArtifactCount: 1
                ),
                payload: .nodeDetails(
                    GraphChatTypedNodeDetailsIntent(
                        entity: entity,
                        node: node,
                        fields: [field]
                    )
                )
            )
            return GraphChatTypedIntentAdaptation(
                intent: intent,
                action: .queryDetailValues(
                    GraphChatLocalQueryAction(
                        plan: GraphQueryPlan(
                            entityAlias: entity.alias,
                            scope: source.queryScope,
                            filters: [],
                            sorting: [
                                GraphQuerySort(
                                    key: .nodeName,
                                    direction: .ascending
                                )
                            ],
                            projection: [
                                .nodeIdentity,
                                .field(field.alias),
                            ],
                            aggregation: nil,
                            limit: source.resultLimit
                        ),
                        resultContract:
                            .authoritativeSingleField(
                                node: node,
                                field: field
                            )
                    )
                )
            )

        case .entityAttributeCollection:
            guard source.expectedCardinality == .zeroOrMore,
                  source.resultLimit
                    == GraphQueryPlanLimits.maximumResultLimit,
                  source.field == nil,
                  source.node == nil else {
                throw GraphChatFoundationalIntentAdapterError
                    .invalidCollectionContract
            }
            let intent = try GraphChatTypedIntent(
                version: .v1,
                scope: scope,
                responseLanguage: source.responseLanguage,
                binding: binding,
                resolution: resolution,
                expectedCardinality: .zeroOrMore,
                factExpectation: .none,
                limits: GraphChatTypedIntentLimits(
                    resultLimit: source.resultLimit,
                    maximumResultLimit:
                        GraphQueryPlanLimits
                            .maximumResultLimit,
                    maximumEvidenceCount:
                        source.resultLimit,
                    maximumArtifactCount: 1
                ),
                payload: .entityCollection(
                    GraphChatTypedEntityCollectionIntent(
                        entity: entity,
                        projectedFields: []
                    )
                )
            )
            return GraphChatTypedIntentAdaptation(
                intent: intent,
                action: .queryDetailValues(
                    GraphChatLocalQueryAction(
                        plan: GraphQueryPlan(
                            entityAlias: entity.alias,
                            scope: source.queryScope,
                            filters: [],
                            sorting: [
                                GraphQuerySort(
                                    key: .nodeName,
                                    direction: .ascending
                                )
                            ],
                            projection: [.nodeIdentity],
                            aggregation: nil,
                            limit: source.resultLimit
                        ),
                        resultContract: .entityCollection
                    )
                )
            )

        case .nodeDetails:
            guard source.expectedCardinality == .zeroOrOne,
                  source.resultLimit == 1,
                  source.field == nil,
                  let sourceNode = source.node,
                  sourceNode.ownerEntityID == source.entity.id,
                  source.queryScope == .node(
                    sourceNode.node,
                    in: source.graphScope
                  ) else {
                throw GraphChatFoundationalIntentAdapterError
                    .invalidNodeDetailsContract
            }
            let node = GraphChatTypedNodeIdentity(
                node: sourceNode.node,
                displayName: sourceNode.displayName,
                ownerEntityID: sourceNode.ownerEntityID
            )
            let policy = GraphChatAdvancedIntentPolicy.default
            let intent = try GraphChatTypedIntent(
                version: .v1,
                scope: scope,
                responseLanguage: source.responseLanguage,
                binding: binding,
                resolution: resolution,
                expectedCardinality: .zeroOrOne,
                factExpectation: .none,
                limits: GraphChatTypedIntentLimits(
                    resultLimit: 1,
                    maximumResultLimit:
                        GraphQueryPlanLimits
                            .maximumResultLimit,
                    maximumEvidenceCount:
                        policy.maximumEvidenceCount,
                    maximumArtifactCount:
                        policy.maximumArtifactCount
                ),
                payload: .nodeDetails(
                    GraphChatTypedNodeDetailsIntent(
                        entity: entity,
                        node: node,
                        fields: []
                    )
                )
            )
            return GraphChatTypedIntentAdaptation(
                intent: intent,
                action: .nodeDetails(
                    GraphChatLocalNodeDetailsAction(
                        node: node,
                        relatedLimit:
                            policy.nodeDetailRelatedLimit
                    )
                )
            )
        }
    }

    private func resolutionOrigin(
        _ value: GraphChatFoundationalResolutionOrigin
    ) -> GraphChatTypedIntentResolutionOrigin {
        switch value {
        case .schemaDisplayName:
            return .schemaDisplayName
        case .localizedFieldSynonym:
            return .localizedFieldSynonym
        case .clarificationSelection:
            return .clarificationSelection
        }
    }

    private func resolutionQuality(
        _ value: GraphChatFoundationalResolutionConfidence
    ) -> GraphChatTypedIntentResolutionQuality {
        switch value {
        case .exact:
            return .exact
        case .constrainedSynonym:
            return .constrainedSynonym
        case .revalidatedClarification:
            return .revalidatedClarification
        }
    }
}
