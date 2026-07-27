//
//  GraphChatAuthoritativeFact.swift
//  BrainMesh
//
//  Value-only contracts for one revalidated graph fact.
//

import Foundation

nonisolated enum GraphChatAuthoritativeFactCardinality:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case exactlyOne
}

nonisolated struct GraphChatAuthoritativeFactBinding: Hashable, Sendable {
    let graphScope: GraphScope
    let chatScope: GraphChatScope
    let requestID: UUID
    let sessionID: GraphChatAnswerArtifactSessionID
    let transactionID: GraphChatAnswerArtifactTransactionID
    let turnID: UUID

    init(
        graphScope: GraphScope,
        chatScope: GraphChatScope,
        requestID: UUID,
        sessionID: GraphChatAnswerArtifactSessionID,
        transactionID: GraphChatAnswerArtifactTransactionID,
        turnID: UUID
    ) {
        precondition(graphScope == chatScope.graphScope)
        self.graphScope = graphScope
        self.chatScope = chatScope
        self.requestID = requestID
        self.sessionID = sessionID
        self.transactionID = transactionID
        self.turnID = turnID
    }
}

nonisolated struct GraphChatAuthoritativeFact: Hashable, Sendable {
    let binding: GraphChatAuthoritativeFactBinding
    let node: NodeRefKey
    let nodeDisplayName: String
    let entityID: UUID
    let entityDisplayName: String
    let fieldID: UUID
    let fieldDisplayName: String
    let fieldType: DetailFieldType
    let value: GraphChatAnswerArtifactValue
    let unit: String?
    let evidenceIDs: [GraphEvidenceID]
    let artifactIDs: [GraphChatAnswerArtifactID]
    let cardinality: GraphChatAuthoritativeFactCardinality
    let dateTimeZoneIdentifier: String

    var hasExactlyOneValue: Bool {
        cardinality == .exactlyOne && value != .missing
    }
}

nonisolated struct GraphChatAuthoritativeFactExpectation:
    Hashable,
    Sendable
{
    let graphScope: GraphScope
    let chatScope: GraphChatScope
    let requestID: UUID
    let turnID: UUID
    let conversationID: UUID
    let node: NodeRefKey
    let nodeDisplayName: String
    let entityID: UUID
    let entityDisplayName: String
    let fieldID: UUID
    let fieldDisplayName: String
    let fieldType: DetailFieldType
    let unit: String?
    let dateTimeZoneIdentifier: String
    let hasIntegrityConflict: Bool
    let hasAmbiguousCardinality: Bool

    init(
        graphScope: GraphScope,
        chatScope: GraphChatScope,
        requestID: UUID,
        turnID: UUID,
        conversationID: UUID,
        node: NodeRefKey,
        nodeDisplayName: String,
        entityID: UUID,
        entityDisplayName: String,
        fieldID: UUID,
        fieldDisplayName: String,
        fieldType: DetailFieldType,
        unit: String?,
        dateTimeZoneIdentifier: String,
        hasIntegrityConflict: Bool = false,
        hasAmbiguousCardinality: Bool = false
    ) {
        precondition(graphScope == chatScope.graphScope)
        self.graphScope = graphScope
        self.chatScope = chatScope
        self.requestID = requestID
        self.turnID = turnID
        self.conversationID = conversationID
        self.node = node
        self.nodeDisplayName = nodeDisplayName
        self.entityID = entityID
        self.entityDisplayName = entityDisplayName
        self.fieldID = fieldID
        self.fieldDisplayName = fieldDisplayName
        self.fieldType = fieldType
        self.unit = unit
        self.dateTimeZoneIdentifier = dateTimeZoneIdentifier
        self.hasIntegrityConflict = hasIntegrityConflict
        self.hasAmbiguousCardinality = hasAmbiguousCardinality
    }

    init?(
        intent: GraphChatTypedIntent,
        result: GraphChatQueryResult,
        timeZone: TimeZone
    ) {
        guard intent.factExpectation
                == .authoritativeSingleField,
              case .nodeDetails(let details) =
                intent.payload,
              details.fields.count == 1,
              let field = details.fields.first else {
            return nil
        }
        let node = details.node
        let key = DetailValueAuthorityKey(
            graphID: intent.scope.graphScope.graphID,
            attributeID: node.node.id,
            fieldID: field.id
        )
        self.graphScope = intent.scope.graphScope
        self.chatScope = intent.scope.chatScope
        self.requestID = intent.binding.requestID
        self.turnID = intent.binding.turnID
        self.conversationID =
            intent.binding.conversationID
        self.node = node.node
        self.nodeDisplayName = node.displayName
        self.entityID = details.entity.id
        self.entityDisplayName =
            details.entity.displayName
        self.fieldID = field.id
        self.fieldDisplayName = field.displayName
        self.fieldType = field.type
        self.unit = field.unit
        self.dateTimeZoneIdentifier = timeZone.identifier
        self.hasIntegrityConflict =
            result.integrityConflictedValueKeys.contains(key)
        self.hasAmbiguousCardinality =
            result.rows.count > 1
            || result.rows.contains { row in
                row.cells.count > 1
                    || row.cells.filter {
                        $0.fieldID == field.id
                    }.count > 1
            }
    }
}

nonisolated enum GraphChatAuthoritativeFactRejection:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case missingValue
    case ambiguousCardinality
    case integrityConflict
    case revalidationRejected
    case searchOnlyResult
}

nonisolated enum GraphChatAuthoritativeFactResolution:
    Hashable,
    Sendable
{
    case fact(GraphChatAuthoritativeFact)
    case rejected(GraphChatAuthoritativeFactRejection)
}
