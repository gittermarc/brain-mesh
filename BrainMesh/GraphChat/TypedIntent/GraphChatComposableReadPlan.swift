//
//  GraphChatComposableReadPlan.swift
//  BrainMesh
//
//  Versioned, value-only execution semantics compiled exclusively by the app.
//

import Foundation

nonisolated enum GraphChatComposableReadPlanVersion:
    Int,
    CaseIterable,
    Hashable,
    Sendable
{
    case v1 = 1
    case v2 = 2

    static let current =
        GraphChatComposableReadPlanVersion.v2
}

nonisolated struct GraphChatComposableReadStepID:
    RawRepresentable,
    Comparable,
    Hashable,
    Sendable
{
    let rawValue: Int

    init(rawValue: Int) {
        self.rawValue = rawValue
    }

    static func < (
        lhs: GraphChatComposableReadStepID,
        rhs: GraphChatComposableReadStepID
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

nonisolated struct GraphChatComposableReadEntityReference:
    Hashable,
    Sendable
{
    let alias: GraphEntityAlias
    let identity: GraphChatTypedEntityIdentity?
}

nonisolated struct GraphChatComposableReadFieldReference:
    Hashable,
    Sendable
{
    let alias: GraphFieldAlias
    let identity: GraphChatTypedFieldIdentity?
}

nonisolated struct GraphChatComposableReadConversationSelection:
    Hashable,
    Sendable
{
    let sourceResultContextID: UUID
    let source: GraphChatResolvedConversationScope
    let entity: GraphChatComposableReadEntityReference
    let nodes: [GraphChatTypedNodeIdentity]
}

nonisolated enum GraphChatComposableReadSelection:
    Hashable,
    Sendable
{
    case scope(GraphChatScope)
    case entity(GraphChatComposableReadEntityReference)
    case node(
        entity: GraphChatTypedEntityIdentity,
        node: GraphChatTypedNodeIdentity
    )
    case nodes(
        entities: [GraphChatTypedEntityIdentity],
        nodes: [GraphChatTypedNodeIdentity]
    )
    case conversationResult(
        GraphChatComposableReadConversationSelection
    )
}

nonisolated struct GraphChatComposableReadSearch:
    Hashable,
    Sendable
{
    let query: String
    let target: GraphChatLocalSearchTarget
    let entityID: UUID?
}

nonisolated struct GraphChatComposableReadPredicate:
    Hashable,
    Sendable
{
    let field: GraphChatComposableReadFieldReference
    let operation: GraphQueryFilterOperator
    let value: GraphQueryFilterValue
}

nonisolated struct GraphChatComposableReadFilter:
    Hashable,
    Sendable
{
    let predicates: [GraphChatComposableReadPredicate]
}

nonisolated struct GraphChatComposableReadProjection:
    Hashable,
    Sendable
{
    let includesNodeIdentity: Bool
    let fields: [GraphChatComposableReadFieldReference]
}

nonisolated enum GraphChatComposableReadSortKey:
    Hashable,
    Sendable
{
    case nodeName
    case field(GraphChatComposableReadFieldReference)
    case stableNodeID
    case counterpartDisplayName
    case counterpartKind
    case counterpartNodeID
    case relationshipDirection
    case linkCreatedAt
    case stableLinkID
}

nonisolated struct GraphChatComposableReadSortDescriptor:
    Hashable,
    Sendable
{
    let key: GraphChatComposableReadSortKey
    let direction: GraphQuerySortDirection
}

nonisolated struct GraphChatComposableReadSort:
    Hashable,
    Sendable
{
    let descriptors:
        [GraphChatComposableReadSortDescriptor]
}

nonisolated enum GraphChatComposableReadAggregation:
    Hashable,
    Sendable
{
    case count
    case groupCount(
        GraphChatComposableReadFieldReference
    )
    case unsupportedMinimum(
        GraphChatComposableReadFieldReference
    )
    case unsupportedMaximum(
        GraphChatComposableReadFieldReference
    )
}

nonisolated struct GraphChatComposableReadNodeDescription:
    Hashable,
    Sendable
{
    let node: GraphChatTypedNodeIdentity
    let compatibilityLimit: Int
    let profileLimits: GraphNodeProfileLimits
}

nonisolated struct GraphChatComposableReadComparison:
    Hashable,
    Sendable
{
    let kind: GraphChatComparisonKind
    let features: [GraphChatComparisonFeature]
    let relatedLimit: Int
    let policy: GraphChatAdvancedIntentPolicy
}

nonisolated struct GraphChatComposableReadGraphState:
    Hashable,
    Sendable
{
    let aspect: GraphChatGraphStateAspect
    let hubLimit: Int
}

nonisolated struct GraphChatComposableReadTraversal:
    Hashable,
    Sendable
{
    let request: GraphChatRelationshipRequestKind
    let centerEntity: GraphChatTypedEntityIdentity
    let centerNode: GraphChatTypedNodeIdentity
    let direction: GraphChatRelationshipDirection
    let counterpartEntity: GraphChatTypedEntityIdentity?
    let counterpartNode: GraphChatTypedNodeIdentity?
    let notePredicate: GraphChatRelationshipNotePredicate?
    let hopCount: Int
    let sourceRelationshipContextID: UUID?
}

nonisolated struct GraphChatComposableReadTraversalStage:
    Hashable,
    Sendable
{
    let counterpartEntity:
        GraphChatTypedEntityIdentity
    let counterpartNode:
        GraphChatTypedNodeIdentity?
    let direction:
        GraphChatRelationshipDirection
    let notePredicate:
        GraphChatRelationshipNotePredicate?
    let nodePredicates:
        [GraphChatComposableReadPredicate]
}

nonisolated enum GraphChatComposableReadTraversalResultTarget:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case startNodes
    case terminalNodes
}

nonisolated struct GraphChatComposableReadTraversalProjection:
    Hashable,
    Sendable
{
    let target:
        GraphChatComposableReadTraversalResultTarget
    let deduplicatesNodes: Bool
}

nonisolated struct GraphChatComposableReadRelationshipProjection:
    Hashable,
    Sendable
{
    let includesCounterpartNode: Bool
    let includesDirection: Bool
    let includesLinkNote: Bool
}

nonisolated struct GraphChatComposableReadLimit:
    Hashable,
    Sendable
{
    let resultLimit: Int
    let intermediateResultLimit: Int
}

nonisolated enum GraphChatComposableReadOperationPayload:
    Hashable,
    Sendable
{
    case select(GraphChatComposableReadSelection)
    case search(GraphChatComposableReadSearch)
    case filter(GraphChatComposableReadFilter)
    case project(GraphChatComposableReadProjection)
    case sort(GraphChatComposableReadSort)
    case aggregate(GraphChatComposableReadAggregation)
    case describeNode(
        GraphChatComposableReadNodeDescription
    )
    case compareNodes(
        GraphChatComposableReadComparison
    )
    case inspectGraphState(
        GraphChatComposableReadGraphState
    )
    case traverseDirectRelationships(
        GraphChatComposableReadTraversal
    )
    case traverseRelationships(
        GraphChatComposableReadTraversalStage
    )
    case projectTraversalNodes(
        GraphChatComposableReadTraversalProjection
    )
    case projectRelationships(
        GraphChatComposableReadRelationshipProjection
    )
    case limit(GraphChatComposableReadLimit)
}

nonisolated struct GraphChatComposableReadOperation:
    Hashable,
    Sendable
{
    let id: GraphChatComposableReadStepID
    let input: GraphChatComposableReadStepID?
    let payload: GraphChatComposableReadOperationPayload
}

nonisolated enum GraphChatComposableReadResultContract:
    Hashable,
    Sendable
{
    case authoritativeSingleField(
        node: GraphChatTypedNodeIdentity,
        field: GraphChatTypedFieldIdentity
    )
    case entityCollection
    case compiledCollection
    case count
    case groupCount
    case refinement
    case search
    case nodeProfile
    case comparison
    case graphState
    case relationships
    case composableNodeCollection
}

nonisolated enum GraphChatComposableReadEvidenceRequirement:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case searchIdentity
    case nodeIdentity
    case authoritativeDetailValue
    case nodeProfileAreas
    case comparisonFeatureValues
    case graphStateSnapshot
    case directRelationshipBinding
    case composableTraversalPath
}

nonisolated enum GraphChatComposableReadArtifactContract:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case searchResults
    case queryResult
    case nodeProfile
    case comparison
    case graphState
    case relationships
}

nonisolated struct GraphChatComposableReadLimits:
    Hashable,
    Sendable
{
    let resultLimit: Int
    let maximumResultLimit: Int
    let intermediateResultLimit: Int
    let maximumEvidenceCount: Int
    let maximumArtifactCount: Int
    let maximumOperationCount: Int
    let selectedStartNodeLimit: Int
    let visitedNodeLimit: Int
    let checkedLinkLimit: Int
    let maximumTraversalHopCount: Int

    init(
        resultLimit: Int,
        maximumResultLimit: Int,
        intermediateResultLimit: Int,
        maximumEvidenceCount: Int,
        maximumArtifactCount: Int,
        maximumOperationCount: Int,
        maximumTraversalHopCount: Int,
        selectedStartNodeLimit: Int =
            GraphChatIntentLimitPolicy.default
                .maximumComposableReadSelectedStartNodeCount,
        visitedNodeLimit: Int =
            GraphChatIntentLimitPolicy.default
                .maximumComposableReadVisitedNodeCount,
        checkedLinkLimit: Int =
            GraphChatIntentLimitPolicy.default
                .maximumComposableReadCheckedLinkCount
    ) {
        self.resultLimit = resultLimit
        self.maximumResultLimit = maximumResultLimit
        self.intermediateResultLimit = intermediateResultLimit
        self.maximumEvidenceCount = maximumEvidenceCount
        self.maximumArtifactCount = maximumArtifactCount
        self.maximumOperationCount = maximumOperationCount
        self.selectedStartNodeLimit = selectedStartNodeLimit
        self.visitedNodeLimit = visitedNodeLimit
        self.checkedLinkLimit = checkedLinkLimit
        self.maximumTraversalHopCount =
            maximumTraversalHopCount
    }
}

/// The semantic interpreter never creates this value. It is assembled only
/// after an app compiler has already resolved identities, scope and meaning.
nonisolated struct GraphChatComposableReadPlan:
    Hashable,
    Sendable
{
    let version: GraphChatComposableReadPlanVersion
    let queryPlanVersion: Int
    let graphScope: GraphScope
    let chatScope: GraphChatScope
    let queryScope: GraphChatScope
    let compiledScope: GraphChatScope
    let binding: GraphChatTypedIntentBinding
    let responseLanguage: GraphChatResponseLanguage
    let intentKind: GraphChatTypedIntentKind
    let operations: [GraphChatComposableReadOperation]
    let resultContract:
        GraphChatComposableReadResultContract
    let evidenceRequirements:
        [GraphChatComposableReadEvidenceRequirement]
    let artifactContract:
        GraphChatComposableReadArtifactContract
    let limits: GraphChatComposableReadLimits
    let queryReferenceDate: Date?
}
