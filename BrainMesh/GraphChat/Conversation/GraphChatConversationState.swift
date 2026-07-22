//
//  GraphChatConversationState.swift
//  BrainMesh
//
//  Bounded, value-only conversation state built exclusively from app-validated graph facts.
//

import Foundation

nonisolated enum GraphChatConversationResetReason: String, CaseIterable, Hashable, Sendable {
    case newConversation
    case graphChanged
    case scopeChanged
    case graphLocked
    case graphDeleted
    case accessRevoked
    case sessionDiscarded
}

nonisolated enum GraphChatConversationResultKind: String, CaseIterable, Hashable, Sendable {
    case schema
    case search
    case query
    case node
    case neighbors
    case stats
}

nonisolated enum GraphChatConversationReference: Hashable, Sendable {
    case node(NodeRefKey)
    case entity(UUID)
    case field(UUID)
    case result(UUID)
    case group(String)

    var stableKey: String {
        switch self {
        case .node(let node):
            return "node:\(node.kind.rawValue):\(node.id.uuidString)"
        case .entity(let entityID):
            return "entity:\(entityID.uuidString)"
        case .field(let fieldID):
            return "field:\(fieldID.uuidString)"
        case .result(let resultID):
            return "result:\(resultID.uuidString)"
        case .group(let groupID):
            return "group:\(groupID)"
        }
    }
}

nonisolated struct GraphChatConversationNodeReference: Hashable, Sendable, Identifiable {
    let node: NodeRefKey
    let label: String
    let ownerEntityID: UUID?
    let evidenceIDs: [GraphEvidenceID]

    var id: NodeRefKey {
        node
    }
}

nonisolated struct GraphChatConversationEntityReference: Hashable, Sendable, Identifiable {
    let entityID: UUID
    let name: String
    let alias: GraphEntityAlias?

    var id: UUID {
        entityID
    }
}

nonisolated struct GraphChatConversationFieldReference: Hashable, Sendable, Identifiable {
    let fieldID: UUID
    let entityID: UUID
    let name: String
    let type: DetailFieldType
    let unit: String?
    let alias: GraphFieldAlias?

    var id: UUID {
        fieldID
    }
}

nonisolated struct GraphChatConversationResultReference: Hashable, Sendable, Identifiable {
    let ordinal: Int
    let reference: GraphChatConversationReference
    let label: String
    let evidenceIDs: [GraphEvidenceID]

    var id: String {
        "\(ordinal):\(reference.stableKey)"
    }
}

nonisolated struct GraphChatConversationGroupReference: Hashable, Sendable, Identifiable {
    let id: String
    let fieldID: UUID?
    let fieldName: String?
    let valueDescription: String
    let count: Int
    let evidenceIDs: [GraphEvidenceID]
    let memberNodes: [NodeRefKey]
}

nonisolated struct GraphChatConversationResultContext: Hashable, Sendable, Identifiable {
    let id: UUID
    let kind: GraphChatConversationResultKind
    let state: GraphChatToolResultState
    let entityID: UUID?
    let references: [GraphChatConversationResultReference]
    let groupReferences: [GraphChatConversationGroupReference]
    let evidenceIDs: [GraphEvidenceID]
    let appliedFilters: [GraphChatAppliedFilter]
    let technicalDescription: String
}

nonisolated struct GraphChatConversationComparisonContext: Hashable, Sendable {
    let references: [GraphChatConversationReference]
    let technicalDescription: String
}

nonisolated struct GraphChatConversationReferenceTargets: Hashable, Sendable {
    let singular: GraphChatConversationReference?
    let plural: [GraphChatConversationReference]
    let ordinal: [GraphChatConversationReference]
    let group: GraphChatConversationReference?
    let compared: [GraphChatConversationReference]

    static let empty = GraphChatConversationReferenceTargets(
        singular: nil,
        plural: [],
        ordinal: [],
        group: nil,
        compared: []
    )
}

nonisolated struct GraphChatConversationTurnContext: Hashable, Sendable, Identifiable {
    let id: UUID
    let completedAt: Date
    let toolKinds: [GraphChatToolKind]
    let resultContextIDs: [UUID]
    let evidenceIDs: [GraphEvidenceID]
    let technicalDescription: String
}

nonisolated struct GraphChatConversationStateSnapshot: Hashable, Sendable {
    let conversationID: UUID
    let graphScope: GraphScope
    let chatScope: GraphChatScope
    let turnContexts: [GraphChatConversationTurnContext]
    let nodeReferences: [GraphChatConversationNodeReference]
    let entityReferences: [GraphChatConversationEntityReference]
    let fieldReferences: [GraphChatConversationFieldReference]
    let resultContexts: [GraphChatConversationResultContext]
    let groupReferences: [GraphChatConversationGroupReference]
    let lastValidatedQueryPlan: ValidatedGraphQueryPlan?
    let lastComparison: GraphChatConversationComparisonContext?
    let referenceTargets: GraphChatConversationReferenceTargets
    let pendingClarification: GraphChatPendingClarification?

    init(state: GraphChatConversationState) {
        self.conversationID = state.conversationID
        self.graphScope = state.graphScope
        self.chatScope = state.chatScope
        self.turnContexts = state.turnContexts
        self.nodeReferences = state.nodeReferences
        self.entityReferences = state.entityReferences
        self.fieldReferences = state.fieldReferences
        self.resultContexts = state.resultContexts
        self.groupReferences = state.groupReferences
        self.lastValidatedQueryPlan = state.lastValidatedQueryPlan
        self.lastComparison = state.lastComparison
        self.referenceTargets = state.referenceTargets
        self.pendingClarification = state.pendingClarification
    }
}

nonisolated struct GraphChatConversationState: Hashable, Sendable {
    let conversationID: UUID
    let graphScope: GraphScope
    let chatScope: GraphChatScope
    var turnContexts: [GraphChatConversationTurnContext]
    var nodeReferences: [GraphChatConversationNodeReference]
    var entityReferences: [GraphChatConversationEntityReference]
    var fieldReferences: [GraphChatConversationFieldReference]
    var resultContexts: [GraphChatConversationResultContext]
    var groupReferences: [GraphChatConversationGroupReference]
    var lastValidatedQueryPlan: ValidatedGraphQueryPlan?
    var lastComparison: GraphChatConversationComparisonContext?
    var referenceTargets: GraphChatConversationReferenceTargets
    var pendingClarification: GraphChatPendingClarification?
    var lastResetReason: GraphChatConversationResetReason?
    var budgetEvictionCount: Int

    static func initial(
        graphScope: GraphScope,
        chatScope: GraphChatScope,
        conversationID: UUID = UUID(),
        resetReason: GraphChatConversationResetReason = .newConversation
    ) -> GraphChatConversationState {
        precondition(graphScope == chatScope.graphScope)
        return GraphChatConversationState(
            conversationID: conversationID,
            graphScope: graphScope,
            chatScope: chatScope,
            turnContexts: [],
            nodeReferences: [],
            entityReferences: [],
            fieldReferences: [],
            resultContexts: [],
            groupReferences: [],
            lastValidatedQueryPlan: nil,
            lastComparison: nil,
            referenceTargets: .empty,
            pendingClarification: nil,
            lastResetReason: resetReason,
            budgetEvictionCount: 0
        )
    }

    var snapshot: GraphChatConversationStateSnapshot {
        GraphChatConversationStateSnapshot(state: self)
    }
}

nonisolated struct GraphChatConversationStatePolicy: Hashable, Sendable {
    let maximumTurnContexts: Int
    let maximumNodeReferences: Int
    let maximumEntityReferences: Int
    let maximumFieldReferences: Int
    let maximumResultContexts: Int
    let maximumResultReferences: Int
    let maximumGroupReferences: Int
    let maximumComparisonReferences: Int
    let maximumEvidenceIDsPerReference: Int
    let maximumTechnicalDescriptionLength: Int
    let maximumLabelLength: Int

    static let `default` = GraphChatConversationStatePolicy(
        maximumTurnContexts: 8,
        maximumNodeReferences: 48,
        maximumEntityReferences: 24,
        maximumFieldReferences: 64,
        maximumResultContexts: 8,
        maximumResultReferences: 64,
        maximumGroupReferences: 24,
        maximumComparisonReferences: 12,
        maximumEvidenceIDsPerReference: 12,
        maximumTechnicalDescriptionLength: 180,
        maximumLabelLength: 160
    )

    init(
        maximumTurnContexts: Int,
        maximumNodeReferences: Int,
        maximumEntityReferences: Int,
        maximumFieldReferences: Int,
        maximumResultContexts: Int,
        maximumResultReferences: Int,
        maximumGroupReferences: Int,
        maximumComparisonReferences: Int,
        maximumEvidenceIDsPerReference: Int,
        maximumTechnicalDescriptionLength: Int,
        maximumLabelLength: Int
    ) {
        precondition(maximumTurnContexts > 0)
        precondition(maximumNodeReferences > 0)
        precondition(maximumEntityReferences > 0)
        precondition(maximumFieldReferences > 0)
        precondition(maximumResultContexts > 0)
        precondition(maximumResultReferences > 0)
        precondition(maximumGroupReferences > 0)
        precondition(maximumComparisonReferences > 0)
        precondition(maximumEvidenceIDsPerReference > 0)
        precondition(maximumTechnicalDescriptionLength > 0)
        precondition(maximumLabelLength > 0)

        self.maximumTurnContexts = maximumTurnContexts
        self.maximumNodeReferences = maximumNodeReferences
        self.maximumEntityReferences = maximumEntityReferences
        self.maximumFieldReferences = maximumFieldReferences
        self.maximumResultContexts = maximumResultContexts
        self.maximumResultReferences = maximumResultReferences
        self.maximumGroupReferences = maximumGroupReferences
        self.maximumComparisonReferences = maximumComparisonReferences
        self.maximumEvidenceIDsPerReference = maximumEvidenceIDsPerReference
        self.maximumTechnicalDescriptionLength = maximumTechnicalDescriptionLength
        self.maximumLabelLength = maximumLabelLength
    }
}
