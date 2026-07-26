//
//  GraphChatModelToolRunner.swift
//  BrainMesh
//
//  Provider-independent compact tool requests and bounded responses.
//

import Foundation

nonisolated struct GraphChatModelQueryFilterRequest: Hashable, Sendable {
    let fieldAlias: String
    let operation: String
    let value: String?
    let secondValue: String?
    let values: [String]
}

nonisolated struct GraphChatModelQueryRequest: Hashable, Sendable {
    let entityAlias: String
    let conversationReferenceAlias: String?
    let filters: [GraphChatModelQueryFilterRequest]
    let sortFieldAlias: String?
    let sortDirection: String?
    let projectionFieldAliases: [String]
    let aggregation: String?
    let aggregationFieldAlias: String?
    let limit: Int

    init(
        entityAlias: String,
        conversationReferenceAlias: String? = nil,
        filters: [GraphChatModelQueryFilterRequest],
        sortFieldAlias: String?,
        sortDirection: String?,
        projectionFieldAliases: [String],
        aggregation: String?,
        aggregationFieldAlias: String?,
        limit: Int
    ) {
        self.entityAlias = entityAlias
        self.conversationReferenceAlias = conversationReferenceAlias
        self.filters = filters
        self.sortFieldAlias = sortFieldAlias
        self.sortDirection = sortDirection
        self.projectionFieldAliases = projectionFieldAliases
        self.aggregation = aggregation
        self.aggregationFieldAlias = aggregationFieldAlias
        self.limit = limit
    }
}

nonisolated enum GraphChatModelToolRequest: Hashable, Sendable {
    case describeSchema(exampleFieldAliases: [String])
    case searchGraph(query: String, limit: Int)
    case queryDetailValues(GraphChatModelQueryRequest)
    case getNode(nodeAlias: String, relatedLimit: Int)
    case getNeighbors(nodeAlias: String, limit: Int)
    case graphStats(hubLimit: Int)

    var kind: GraphChatToolKind {
        switch self {
        case .describeSchema:
            return .describeGraphSchema
        case .searchGraph:
            return .searchGraph
        case .queryDetailValues:
            return .queryDetailValues
        case .getNode:
            return .getNode
        case .getNeighbors:
            return .getNeighbors
        case .graphStats:
            return .graphStats
        }
    }
}

nonisolated struct GraphChatModelToolResponse: Hashable, Sendable {
    let tool: GraphChatToolKind
    let state: GraphChatToolResultState
    let content: String
    let evidenceIDs: [GraphEvidenceID]
    let artifactIDs: [GraphChatAnswerArtifactID]

    var artifactID: GraphChatAnswerArtifactID? {
        artifactIDs.first
    }

    var modelContent: String {
        guard artifactIDs.isEmpty == false else {
            return content
        }
        let references = artifactIDs.map {
            "artifactID=\($0.rawValue.uuidString)"
        }
        return ([content] + references).joined(separator: "\n")
    }

    init(
        tool: GraphChatToolKind,
        state: GraphChatToolResultState,
        content: String,
        evidenceIDs: [GraphEvidenceID],
        artifactID: GraphChatAnswerArtifactID? = nil,
        artifactIDs: [GraphChatAnswerArtifactID] = []
    ) {
        self.tool = tool
        self.state = state
        self.content = content
        self.evidenceIDs = evidenceIDs
        var seen = Set<GraphChatAnswerArtifactID>()
        let candidateArtifactIDs = artifactIDs + (artifactID.map { [$0] } ?? [])
        self.artifactIDs = candidateArtifactIDs.filter {
            seen.insert($0).inserted
        }
    }
}

nonisolated struct GraphChatModelToolOutputBudget: Hashable, Sendable {
    let maximumSchemaCharacters: Int
    let maximumCollectionCharacters: Int
    let maximumValueCharacters: Int
    let maximumNotesCharacters: Int

    static let `default` = GraphChatModelToolOutputBudget(
        maximumSchemaCharacters: 2_400,
        maximumCollectionCharacters: 3_200,
        maximumValueCharacters: 400,
        maximumNotesCharacters: 700
    )

    init(
        maximumSchemaCharacters: Int,
        maximumCollectionCharacters: Int,
        maximumValueCharacters: Int,
        maximumNotesCharacters: Int
    ) {
        precondition(maximumSchemaCharacters > 0)
        precondition(maximumCollectionCharacters > 0)
        precondition(maximumValueCharacters > 0)
        precondition(maximumNotesCharacters > 0)
        self.maximumSchemaCharacters = maximumSchemaCharacters
        self.maximumCollectionCharacters = maximumCollectionCharacters
        self.maximumValueCharacters = maximumValueCharacters
        self.maximumNotesCharacters = maximumNotesCharacters
    }
}

nonisolated protocol GraphChatModelToolRunning: Sendable {
    func registeredToolKinds() async -> Set<GraphChatToolKind>

    func registeredToolIdentifiers() async -> Set<String>

    func run(
        _ request: GraphChatModelToolRequest
    ) async throws -> GraphChatModelToolResponse
}

extension GraphChatModelToolRunning {
    func registeredToolIdentifiers() async -> Set<String> {
        let kinds = await registeredToolKinds()
        return Set(kinds.map(\.rawValue))
    }
}

nonisolated protocol GraphChatModelToolRunnerFactory: Sendable {
    func makeRunner(
        scope: GraphChatScope,
        schemaContext: GraphSchemaContext,
        budget: GraphChatToolBudget,
        evidenceRegistry: GraphChatEvidenceRegistry,
        presentationRegistry: GraphChatPresentationRegistry,
        artifactRegistry: GraphChatAnswerArtifactRegistry,
        artifactTransactionID: GraphChatAnswerArtifactTransactionID,
        conversationTransaction: GraphChatConversationStateTransaction,
        conversationContext: GraphChatConversationContextSnapshot,
        referenceResolver: GraphChatConversationReferenceResolver,
        responseLanguage: GraphChatResponseLanguage,
        referenceDate: Date,
        calendar: Calendar,
        timeZone: TimeZone
    ) -> any GraphChatModelToolRunning
}
