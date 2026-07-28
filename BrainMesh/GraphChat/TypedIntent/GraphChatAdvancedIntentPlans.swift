//
//  GraphChatAdvancedIntentPlans.swift
//  BrainMesh
//
//  Value-only, app-owned plans for node details, comparisons and graph state.
//

import Foundation

nonisolated enum GraphChatGraphStateAspect:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case overview
    case counts
    case structure
    case health
}

nonisolated enum GraphChatComparisonKind:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case sameEntityAttributes
    case structural
}

nonisolated enum GraphChatStructuralComparisonFeature:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case nodeKind
    case ownerDisplayName
    case directLinkCount
    case attachmentMetadataCount
    case hasNotes
    case authoritativeDetailValueCount
}

nonisolated enum GraphChatComparisonFeature:
    Hashable,
    Sendable
{
    case field(GraphChatTypedFieldIdentity)
    case structure(GraphChatStructuralComparisonFeature)
}

/// Every execution and presentation limit for INTENT-COMPILER-4 lives here.
/// The semantic model neither sees nor chooses any of these values.
nonisolated struct GraphChatAdvancedIntentPolicy:
    Hashable,
    Sendable
{
    let maximumComparisonNodeCount: Int
    let maximumComparisonFeatureCount: Int
    let defaultComparisonFeatureCount: Int
    let nodeDetailRelatedLimit: Int
    let structuralRelatedLimit: Int
    let graphHubLimit: Int
    let maximumEvidenceCount: Int
    let maximumArtifactCount: Int

    static let `default` = GraphChatAdvancedIntentPolicy(
        maximumComparisonNodeCount: 8,
        maximumComparisonFeatureCount: 8,
        defaultComparisonFeatureCount: 6,
        nodeDetailRelatedLimit: 20,
        structuralRelatedLimit: 0,
        graphHubLimit: 10,
        maximumEvidenceCount: 96,
        maximumArtifactCount: 4
    )

    init(
        maximumComparisonNodeCount: Int,
        maximumComparisonFeatureCount: Int,
        defaultComparisonFeatureCount: Int,
        nodeDetailRelatedLimit: Int,
        structuralRelatedLimit: Int,
        graphHubLimit: Int,
        maximumEvidenceCount: Int,
        maximumArtifactCount: Int
    ) {
        precondition(maximumComparisonNodeCount >= 2)
        precondition(maximumComparisonFeatureCount > 0)
        precondition(
            (1...maximumComparisonFeatureCount)
                .contains(defaultComparisonFeatureCount)
        )
        precondition(
            (0...GetNodeTool.maximumRelatedItemCount)
                .contains(nodeDetailRelatedLimit)
        )
        precondition(
            (0...GetNodeTool.maximumRelatedItemCount)
                .contains(structuralRelatedLimit)
        )
        precondition(
            (0...GraphStatsTool.maximumHubCount)
                .contains(graphHubLimit)
        )
        precondition(maximumEvidenceCount > 0)
        precondition(maximumArtifactCount > 0)

        self.maximumComparisonNodeCount =
            maximumComparisonNodeCount
        self.maximumComparisonFeatureCount =
            maximumComparisonFeatureCount
        self.defaultComparisonFeatureCount =
            defaultComparisonFeatureCount
        self.nodeDetailRelatedLimit =
            nodeDetailRelatedLimit
        self.structuralRelatedLimit =
            structuralRelatedLimit
        self.graphHubLimit = graphHubLimit
        self.maximumEvidenceCount =
            maximumEvidenceCount
        self.maximumArtifactCount =
            maximumArtifactCount
    }
}

nonisolated enum GraphChatComparisonPlanValidationError:
    Error,
    LocalizedError,
    Hashable,
    Sendable
{
    case invalidBinding
    case graphScopeMismatch
    case invalidNodeCount
    case invalidFeatureCount
    case invalidComparisonKind
    case invalidSelectionQuery
    case invalidLimit

    var errorDescription: String? {
        switch self {
        case .invalidBinding:
            return "Der Vergleich ist nicht eindeutig an den aktuellen Turn gebunden."
        case .graphScopeMismatch:
            return "Der Vergleich enthält Nodes oder Scopes aus unterschiedlichen Graphen."
        case .invalidNodeCount:
            return "Für diesen Vergleich ist die Node-Anzahl nicht zulässig."
        case .invalidFeatureCount:
            return "Für diesen Vergleich ist die Feature-Anzahl nicht zulässig."
        case .invalidComparisonKind:
            return "Die appseitig bestimmte Vergleichsart passt nicht zu den Subjects."
        case .invalidSelectionQuery:
            return "Der fachliche Vergleich enthält keine sichere Selection Query."
        case .invalidLimit:
            return "Der Vergleich enthält ein ungültiges gemeinsames Limit."
        }
    }
}

/// Central value-only comparison contract. It binds scope, request,
/// conversation and turn; no provider-selected execution detail is accepted.
nonisolated struct GraphChatComparisonPlan:
    Hashable,
    Sendable
{
    let graphScope: GraphScope
    let chatScope: GraphChatScope
    let binding: GraphChatTypedIntentBinding
    let nodes: [GraphChatTypedNodeIdentity]
    let kind: GraphChatComparisonKind
    let features: [GraphChatComparisonFeature]
    let selectionQuery: GraphQueryPlan?
    let relatedLimit: Int
    let responseLanguage: GraphChatResponseLanguage
    let expectedCardinality:
        GraphChatTypedIntentExpectedCardinality
    let policy: GraphChatAdvancedIntentPolicy

    init(
        graphScope: GraphScope,
        chatScope: GraphChatScope,
        binding: GraphChatTypedIntentBinding,
        nodes: [GraphChatTypedNodeIdentity],
        kind: GraphChatComparisonKind,
        features: [GraphChatComparisonFeature],
        selectionQuery: GraphQueryPlan?,
        relatedLimit: Int,
        responseLanguage: GraphChatResponseLanguage,
        expectedCardinality:
            GraphChatTypedIntentExpectedCardinality = .twoOrMore,
        policy: GraphChatAdvancedIntentPolicy = .default
    ) throws {
        guard binding.requestID == binding.turnID else {
            throw GraphChatComparisonPlanValidationError
                .invalidBinding
        }
        guard graphScope == chatScope.graphScope else {
            throw GraphChatComparisonPlanValidationError
                .graphScopeMismatch
        }
        guard
            (2...policy.maximumComparisonNodeCount)
                .contains(nodes.count),
            Set(nodes.map(\.node)).count == nodes.count
        else {
            throw GraphChatComparisonPlanValidationError
                .invalidNodeCount
        }
        guard
            (1...policy.maximumComparisonFeatureCount)
                .contains(features.count),
            Set(features).count == features.count
        else {
            throw GraphChatComparisonPlanValidationError
                .invalidFeatureCount
        }
        guard expectedCardinality == .twoOrMore else {
            throw GraphChatComparisonPlanValidationError
                .invalidNodeCount
        }
        guard
            (0...GetNodeTool.maximumRelatedItemCount)
                .contains(relatedLimit)
        else {
            throw GraphChatComparisonPlanValidationError
                .invalidLimit
        }

        switch kind {
        case .sameEntityAttributes:
            let fieldFeatures =
                features.compactMap {
                    feature
                    -> GraphChatTypedFieldIdentity? in
                    if case .field(let field) =
                        feature {
                        return field
                    }
                    return nil
                }
            guard let expectedScope =
                    try? GraphChatScope.selection(
                    nodes.map(\.node),
                    in: graphScope
                )
            else {
                throw GraphChatComparisonPlanValidationError
                    .invalidSelectionQuery
            }
            let expectedProjection:
                [GraphQueryProjection] =
                    [.nodeIdentity]
                    + fieldFeatures.map {
                        .field($0.alias)
                    }
            guard
                nodes.allSatisfy({
                    $0.node.kind == .attribute
                }),
                Set(nodes.map(\.ownerEntityID))
                    .count == 1,
                fieldFeatures.count
                    == features.count,
                fieldFeatures.allSatisfy({
                    $0.ownerEntityID
                        == nodes[0]
                            .ownerEntityID
                }),
                relatedLimit == 0
            else {
                throw GraphChatComparisonPlanValidationError
                    .invalidComparisonKind
            }
            guard
                let selectionQuery,
                selectionQuery.version
                    == GraphQueryPlan
                        .currentVersion,
                selectionQuery.scope
                    == expectedScope,
                selectionQuery.filters.isEmpty,
                selectionQuery.sorting
                    == [
                        GraphQuerySort(
                            key: .nodeName,
                            direction: .ascending
                        ),
                    ],
                selectionQuery.projection
                    == expectedProjection,
                selectionQuery.aggregation
                    == nil,
                selectionQuery.limit
                    == nodes.count
            else {
                throw GraphChatComparisonPlanValidationError
                    .invalidSelectionQuery
            }
        case .structural:
            guard selectionQuery == nil,
                  relatedLimit
                    == policy.structuralRelatedLimit,
                  features.allSatisfy({ feature in
                      if case .structure = feature {
                          return true
                      }
                      return false
                  }) else {
                throw GraphChatComparisonPlanValidationError
                    .invalidComparisonKind
            }
        }

        self.graphScope = graphScope
        self.chatScope = chatScope
        self.binding = binding
        self.nodes = nodes
        self.kind = kind
        self.features = features
        self.selectionQuery = selectionQuery
        self.relatedLimit = relatedLimit
        self.responseLanguage = responseLanguage
        self.expectedCardinality =
            expectedCardinality
        self.policy = policy
    }
}
