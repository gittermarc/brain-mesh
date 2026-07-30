//
//  GraphChatFoundationalIntent.swift
//  BrainMesh
//
//  Value-only contracts for narrowly compiled, provider-free graph questions.
//

import Foundation

nonisolated enum GraphChatFoundationalIntentKind: String, CaseIterable, Hashable, Sendable {
    case singleNodeFieldValue
    case entityAttributeCollection
    case nodeDetails
}

nonisolated enum GraphChatFoundationalExpectedCardinality:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case zeroOrOne
    case zeroOrMore
}

nonisolated enum GraphChatFoundationalResolutionOrigin:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case schemaDisplayName
    case localizedFieldSynonym
    case clarificationSelection
}

nonisolated enum GraphChatFoundationalResolutionConfidence:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case exact
    case constrainedSynonym
    case revalidatedClarification
}

nonisolated struct GraphChatFoundationalIntentBinding: Hashable, Sendable {
    let requestID: UUID
    let conversationID: UUID
    let sourceTurnID: UUID?
    let clarificationID: UUID?
}

nonisolated struct GraphChatFoundationalEntityIdentity: Hashable, Sendable {
    let id: UUID
    let alias: GraphEntityAlias
    let displayName: String
}

nonisolated struct GraphChatFoundationalFieldIdentity: Hashable, Sendable {
    let id: UUID
    let alias: GraphFieldAlias
    let displayName: String
    let type: DetailFieldType
    let unit: String?
}

nonisolated struct GraphChatFoundationalNodeIdentity: Hashable, Sendable {
    let node: NodeRefKey
    let displayName: String
    let ownerEntityID: UUID
}

nonisolated struct GraphChatFoundationalIntent: Hashable, Sendable {
    let kind: GraphChatFoundationalIntentKind
    let graphScope: GraphScope
    let chatScope: GraphChatScope
    let queryScope: GraphChatScope
    let responseLanguage: GraphChatResponseLanguage
    let entity: GraphChatFoundationalEntityIdentity
    let field: GraphChatFoundationalFieldIdentity?
    let node: GraphChatFoundationalNodeIdentity?
    let expectedCardinality: GraphChatFoundationalExpectedCardinality
    let resultLimit: Int
    let origin: GraphChatFoundationalResolutionOrigin
    let confidence: GraphChatFoundationalResolutionConfidence
    let binding: GraphChatFoundationalIntentBinding
}

nonisolated struct GraphChatFoundationalIntentSelection: Hashable, Sendable {
    let entityID: UUID
    let node: NodeRefKey?
    let fieldID: UUID?

    init(
        entityID: UUID,
        node: NodeRefKey? = nil,
        fieldID: UUID? = nil
    ) {
        self.entityID = entityID
        self.node = node
        self.fieldID = fieldID
    }
}

nonisolated struct GraphChatFoundationalClarificationOption:
    Hashable,
    Sendable,
    Identifiable
{
    let id: String
    let title: String
    let selection: GraphChatFoundationalIntentSelection
}

nonisolated struct GraphChatFoundationalClarification: Hashable, Sendable {
    let question: String
    let options: [GraphChatFoundationalClarificationOption]
}

nonisolated enum GraphChatFoundationalIntentRejection:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case graphScopeMismatch
    case chatScopeMismatch
    case staleClarification
    case unauthorizedSelection
    case schemaIntegrityViolation
}

nonisolated enum GraphChatFoundationalIntentCompilation: Hashable, Sendable {
    case compiled(GraphChatFoundationalIntent)
    case clarification(GraphChatFoundationalClarification)
    case notRecognized
    case rejected(GraphChatFoundationalIntentRejection)
}

nonisolated struct GraphChatFoundationalIntentCompilerInput: Sendable {
    let requestID: UUID
    let question: String
    let graphScope: GraphScope
    let chatScope: GraphChatScope
    let responseLanguage: GraphChatResponseLanguage
    let conversationState: GraphChatConversationState
    let schemaContext: GraphSchemaContext
    let selectedCandidate: GraphChatFoundationalIntentSelection?
    let sourceTurnID: UUID?
    let clarificationID: UUID?
}

nonisolated struct GraphChatFoundationalIntentContinuation: Hashable, Sendable {
    let selection: GraphChatFoundationalIntentSelection
    let sourceTurnID: UUID?
    let clarificationID: UUID
}
