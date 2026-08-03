//
//  GraphChatTypedIntent.swift
//  BrainMesh
//
//  Versioned, value-only intent contracts resolved by the app.
//

import Foundation

nonisolated enum GraphChatTypedIntentDomainVersion:
    Int,
    CaseIterable,
    Hashable,
    Sendable
{
    case v1 = 1
    case v2 = 2

    static let current =
        GraphChatTypedIntentDomainVersion.v2
}

nonisolated enum GraphChatTypedIntentKind:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case findNodes
    case entityCollection
    case countOrGroup
    case nodeDetails
    case narrowResultSet
    case compareNodes
    case inspectGraphState
    case relationships
}

nonisolated enum GraphChatTypedIntentResolutionSource:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case foundationalFastPath
    case appSemanticResolution
    case conversationContinuation
}

nonisolated enum GraphChatTypedIntentResolutionOrigin:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case schemaDisplayName
    case localizedFieldSynonym
    case clarificationSelection
    case conversationReference
    case appRule
}

nonisolated enum GraphChatTypedIntentResolutionQuality:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case exact
    case constrainedSynonym
    case revalidatedClarification
    case revalidatedConversationReference
}

nonisolated enum GraphChatTypedIntentExpectedCardinality:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case zeroOrOne
    case exactlyOne
    case zeroOrMore
    case twoOrMore
}

nonisolated enum GraphChatTypedIntentFactExpectation:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case none
    case authoritativeSingleField
}

nonisolated struct GraphChatTypedIntentBinding: Hashable, Sendable {
    let requestID: UUID
    let conversationID: UUID
    let turnID: UUID
    let sourceTurnID: UUID?
    let clarificationID: UUID?
}

nonisolated struct GraphChatTypedIntentScope: Hashable, Sendable {
    let graphScope: GraphScope
    let chatScope: GraphChatScope
    let queryScope: GraphChatScope
}

nonisolated struct GraphChatTypedIntentResolution: Hashable, Sendable {
    let source: GraphChatTypedIntentResolutionSource
    let origin: GraphChatTypedIntentResolutionOrigin
    let quality: GraphChatTypedIntentResolutionQuality
}

nonisolated struct GraphChatTypedIntentLimits: Hashable, Sendable {
    let resultLimit: Int
    let maximumResultLimit: Int
    let maximumEvidenceCount: Int
    let maximumArtifactCount: Int
}

nonisolated struct GraphChatTypedEntityIdentity: Hashable, Sendable {
    let id: UUID
    let alias: GraphEntityAlias
    let displayName: String
}

nonisolated struct GraphChatTypedFieldIdentity: Hashable, Sendable {
    let id: UUID
    let alias: GraphFieldAlias
    let displayName: String
    let ownerEntityID: UUID
    let type: DetailFieldType
    let unit: String?
}

nonisolated struct GraphChatTypedNodeIdentity: Hashable, Sendable {
    let node: NodeRefKey
    let displayName: String
    let ownerEntityID: UUID
}

nonisolated struct GraphChatTypedFindNodesIntent: Hashable, Sendable {
    let entity: GraphChatTypedEntityIdentity?
    let fields: [GraphChatTypedFieldIdentity]
    let nodeScope: [GraphChatTypedNodeIdentity]
}

nonisolated struct GraphChatTypedEntityCollectionIntent:
    Hashable,
    Sendable
{
    let entity: GraphChatTypedEntityIdentity
    let relatedEntities: [GraphChatTypedEntityIdentity]
    let relatedNodes: [GraphChatTypedNodeIdentity]
    let projectedFields: [GraphChatTypedFieldIdentity]
    let referencedFields: [GraphChatTypedFieldIdentity]

    init(
        entity: GraphChatTypedEntityIdentity,
        relatedEntities: [GraphChatTypedEntityIdentity] = [],
        relatedNodes: [GraphChatTypedNodeIdentity] = [],
        projectedFields: [GraphChatTypedFieldIdentity],
        referencedFields: [GraphChatTypedFieldIdentity]? = nil
    ) {
        self.entity = entity
        self.relatedEntities = relatedEntities
        self.relatedNodes = relatedNodes
        self.projectedFields = projectedFields
        self.referencedFields =
            referencedFields ?? projectedFields
    }
}

nonisolated enum GraphChatTypedCountOrGroupOperation:
    Hashable,
    Sendable
{
    case count
    case group(field: GraphChatTypedFieldIdentity)
}

nonisolated struct GraphChatTypedCountOrGroupIntent: Hashable, Sendable {
    let entity: GraphChatTypedEntityIdentity
    let operation: GraphChatTypedCountOrGroupOperation
    let referencedFields: [GraphChatTypedFieldIdentity]

    init(
        entity: GraphChatTypedEntityIdentity,
        operation: GraphChatTypedCountOrGroupOperation,
        referencedFields: [GraphChatTypedFieldIdentity]? = nil
    ) {
        self.entity = entity
        self.operation = operation
        if let referencedFields {
            self.referencedFields = referencedFields
        } else if case .group(let field) = operation {
            self.referencedFields = [field]
        } else {
            self.referencedFields = []
        }
    }
}

nonisolated struct GraphChatTypedNodeDetailsIntent: Hashable, Sendable {
    let entity: GraphChatTypedEntityIdentity
    let node: GraphChatTypedNodeIdentity
    let fields: [GraphChatTypedFieldIdentity]
}

nonisolated struct GraphChatTypedNarrowResultSetIntent:
    Hashable,
    Sendable
{
    let sourceResultContextID: UUID
    let entity: GraphChatTypedEntityIdentity
    let nodes: [GraphChatTypedNodeIdentity]
    let fields: [GraphChatTypedFieldIdentity]
    let projectedFields: [GraphChatTypedFieldIdentity]

    init(
        sourceResultContextID: UUID,
        entity: GraphChatTypedEntityIdentity,
        nodes: [GraphChatTypedNodeIdentity],
        fields: [GraphChatTypedFieldIdentity],
        projectedFields: [GraphChatTypedFieldIdentity]? = nil
    ) {
        self.sourceResultContextID = sourceResultContextID
        self.entity = entity
        self.nodes = nodes
        self.fields = fields
        self.projectedFields =
            projectedFields ?? fields
    }
}

nonisolated struct GraphChatTypedCompareNodesIntent: Hashable, Sendable {
    let entities: [GraphChatTypedEntityIdentity]
    let nodes: [GraphChatTypedNodeIdentity]
    let fields: [GraphChatTypedFieldIdentity]
}

nonisolated struct GraphChatTypedInspectGraphStateIntent:
    Hashable,
    Sendable
{
    let entity: GraphChatTypedEntityIdentity?
    let aspect: GraphChatGraphStateAspect

    init(
        entity: GraphChatTypedEntityIdentity? = nil,
        aspect: GraphChatGraphStateAspect = .overview
    ) {
        self.entity = entity
        self.aspect = aspect
    }
}

nonisolated enum GraphChatTypedIntentPayload: Hashable, Sendable {
    case findNodes(GraphChatTypedFindNodesIntent)
    case entityCollection(GraphChatTypedEntityCollectionIntent)
    case countOrGroup(GraphChatTypedCountOrGroupIntent)
    case nodeDetails(GraphChatTypedNodeDetailsIntent)
    case narrowResultSet(GraphChatTypedNarrowResultSetIntent)
    case compareNodes(GraphChatTypedCompareNodesIntent)
    case inspectGraphState(GraphChatTypedInspectGraphStateIntent)
    case relationships(GraphChatRelationshipPlan)

    var kind: GraphChatTypedIntentKind {
        switch self {
        case .findNodes:
            return .findNodes
        case .entityCollection:
            return .entityCollection
        case .countOrGroup:
            return .countOrGroup
        case .nodeDetails:
            return .nodeDetails
        case .narrowResultSet:
            return .narrowResultSet
        case .compareNodes:
            return .compareNodes
        case .inspectGraphState:
            return .inspectGraphState
        case .relationships:
            return .relationships
        }
    }

    var entities: [GraphChatTypedEntityIdentity] {
        switch self {
        case .findNodes(let value):
            return value.entity.map { [$0] } ?? []
        case .entityCollection(let value):
            return [value.entity] + value.relatedEntities
        case .countOrGroup(let value):
            return [value.entity]
        case .nodeDetails(let value):
            return [value.entity]
        case .narrowResultSet(let value):
            return [value.entity]
        case .compareNodes(let value):
            return value.entities
        case .inspectGraphState(let value):
            return value.entity.map { [$0] } ?? []
        case .relationships(let value):
            var entities = [value.centerEntity]
            if let counterpart =
                    value.counterpartEntity,
               counterpart.id
                    != value.centerEntity.id {
                entities.append(counterpart)
            }
            return entities
        }
    }

    var fields: [GraphChatTypedFieldIdentity] {
        switch self {
        case .findNodes(let value):
            return value.fields
        case .entityCollection(let value):
            return value.referencedFields
        case .countOrGroup(let value):
            return value.referencedFields
        case .nodeDetails(let value):
            return value.fields
        case .narrowResultSet(let value):
            return value.fields
        case .compareNodes(let value):
            return value.fields
        case .inspectGraphState:
            return []
        case .relationships:
            return []
        }
    }

    var nodes: [GraphChatTypedNodeIdentity] {
        switch self {
        case .findNodes(let value):
            return value.nodeScope
        case .entityCollection(let value):
            return value.relatedNodes
        case .countOrGroup, .inspectGraphState:
            return []
        case .nodeDetails(let value):
            return [value.node]
        case .narrowResultSet(let value):
            return value.nodes
        case .compareNodes(let value):
            return value.nodes
        case .relationships(let value):
            if let counterpart =
                    value.counterpartNode,
               counterpart.node
                    != value.centerNode.node {
                return [
                    value.centerNode,
                    counterpart,
                ]
            }
            return [value.centerNode]
        }
    }
}

nonisolated enum GraphChatTypedIntentValidationError:
    Error,
    LocalizedError,
    Hashable,
    Sendable
{
    case unsupportedDomainVersion
    case graphScopeMismatch
    case invalidLimits
    case invalidEntityBinding
    case invalidFieldBinding
    case invalidNodeBinding
    case invalidCardinality
    case invalidFactExpectation
    case invalidRelationshipPlan

    var errorDescription: String? {
        switch self {
        case .unsupportedDomainVersion:
            return "Die Typed-Intent-Domainversion wird nicht unterstützt."
        case .graphScopeMismatch:
            return "Der Typed Intent enthält widersprüchliche Graph-Scopes."
        case .invalidLimits:
            return "Der Typed Intent enthält ungültige Ergebnis- oder Sicherheitslimits."
        case .invalidEntityBinding:
            return "Der Typed Intent enthält keine eindeutige Entity-Bindung."
        case .invalidFieldBinding:
            return "Ein Feld des Typed Intent gehört nicht zur validierten Entity."
        case .invalidNodeBinding:
            return "Ein Node des Typed Intent gehört nicht zu einer validierten Entity."
        case .invalidCardinality:
            return "Die erwartete Kardinalität passt nicht zur Intent-Art."
        case .invalidFactExpectation:
            return "Die Fact-Erwartung passt nicht zum Typed Intent."
        case .invalidRelationshipPlan:
            return "Der Relationship-Plan stimmt nicht mit dem versionierten Typed-Intent-Vertrag überein."
        }
    }
}

nonisolated struct GraphChatTypedIntent: Hashable, Sendable {
    let version: GraphChatTypedIntentDomainVersion
    let scope: GraphChatTypedIntentScope
    let responseLanguage: GraphChatResponseLanguage
    let binding: GraphChatTypedIntentBinding
    let resolution: GraphChatTypedIntentResolution
    let expectedCardinality: GraphChatTypedIntentExpectedCardinality
    let factExpectation: GraphChatTypedIntentFactExpectation
    let limits: GraphChatTypedIntentLimits
    let payload: GraphChatTypedIntentPayload

    var kind: GraphChatTypedIntentKind {
        payload.kind
    }

    init(
        version: GraphChatTypedIntentDomainVersion,
        scope: GraphChatTypedIntentScope,
        responseLanguage: GraphChatResponseLanguage,
        binding: GraphChatTypedIntentBinding,
        resolution: GraphChatTypedIntentResolution,
        expectedCardinality: GraphChatTypedIntentExpectedCardinality,
        factExpectation: GraphChatTypedIntentFactExpectation,
        limits: GraphChatTypedIntentLimits,
        payload: GraphChatTypedIntentPayload
    ) throws {
        guard Self.supports(
            version: version,
            payload: payload
        ) else {
            throw GraphChatTypedIntentValidationError
                .unsupportedDomainVersion
        }
        guard scope.graphScope == scope.chatScope.graphScope,
              scope.graphScope == scope.queryScope.graphScope else {
            throw GraphChatTypedIntentValidationError.graphScopeMismatch
        }
        guard limits.resultLimit > 0,
              limits.maximumResultLimit > 0,
              limits.resultLimit <= limits.maximumResultLimit,
              limits.maximumEvidenceCount > 0,
              limits.maximumArtifactCount > 0 else {
            throw GraphChatTypedIntentValidationError.invalidLimits
        }
        try Self.validateIdentities(in: payload)
        try Self.validateSemantics(
            payload: payload,
            expectedCardinality: expectedCardinality,
            factExpectation: factExpectation
        )
        if case .relationships(let plan) = payload {
            guard
                version == .v2,
                plan.graphScope == scope.graphScope,
                plan.chatScope == scope.chatScope,
                plan.queryScope == scope.queryScope,
                plan.binding == binding,
                plan.limits == limits,
                plan.responseLanguage == responseLanguage
            else {
                throw GraphChatTypedIntentValidationError
                    .invalidRelationshipPlan
            }
        }

        self.version = version
        self.scope = scope
        self.responseLanguage = responseLanguage
        self.binding = binding
        self.resolution = resolution
        self.expectedCardinality = expectedCardinality
        self.factExpectation = factExpectation
        self.limits = limits
        self.payload = payload
    }

    private static func validateIdentities(
        in payload: GraphChatTypedIntentPayload
    ) throws {
        let entities = payload.entities
        let entityIDs = Set(entities.map(\.id))
        guard entityIDs.count == entities.count else {
            throw GraphChatTypedIntentValidationError
                .invalidEntityBinding
        }
        let fields = payload.fields
        guard Set(fields.map(\.id)).count == fields.count,
              fields.allSatisfy({
            entityIDs.contains($0.ownerEntityID)
        }) else {
            throw GraphChatTypedIntentValidationError
                .invalidFieldBinding
        }
        let nodes = payload.nodes
        guard Set(nodes.map(\.node)).count == nodes.count,
              nodes.allSatisfy({
            entityIDs.contains($0.ownerEntityID)
        }) else {
            throw GraphChatTypedIntentValidationError
                .invalidNodeBinding
        }

        switch payload {
        case .entityCollection(let value):
            guard Set(
                value.projectedFields.map(\.id)
            ).isSubset(
                of: Set(
                    value.referencedFields.map(\.id)
                )
            ) else {
                throw GraphChatTypedIntentValidationError
                    .invalidFieldBinding
            }
        case .countOrGroup(let value):
            if case .group(let field) = value.operation {
                guard value.referencedFields.contains(
                    where: { $0.id == field.id }
                ) else {
                    throw GraphChatTypedIntentValidationError
                        .invalidFieldBinding
                }
            }
        case .nodeDetails:
            break
        case .narrowResultSet(let value):
            guard value.nodes.isEmpty == false else {
                throw GraphChatTypedIntentValidationError
                    .invalidNodeBinding
            }
            guard Set(
                value.projectedFields.map(\.id)
            ).isSubset(
                of: Set(value.fields.map(\.id))
            ) else {
                throw GraphChatTypedIntentValidationError
                    .invalidFieldBinding
            }
        case .compareNodes(let value):
            guard value.nodes.count >= 2 else {
                throw GraphChatTypedIntentValidationError
                    .invalidNodeBinding
            }
        case .findNodes, .inspectGraphState,
            .relationships:
            break
        }
    }

    private static func validateSemantics(
        payload: GraphChatTypedIntentPayload,
        expectedCardinality: GraphChatTypedIntentExpectedCardinality,
        factExpectation: GraphChatTypedIntentFactExpectation
    ) throws {
        if factExpectation == .authoritativeSingleField {
            guard case .nodeDetails(let details) = payload,
                  details.fields.count == 1,
                  expectedCardinality == .zeroOrOne else {
                throw GraphChatTypedIntentValidationError
                    .invalidFactExpectation
            }
        }
        if case .compareNodes = payload,
           expectedCardinality != .twoOrMore {
            throw GraphChatTypedIntentValidationError
                .invalidCardinality
        }
        if case .relationships(let plan) = payload {
            guard expectedCardinality
                    == .zeroOrMore,
                  factExpectation == .none,
                  plan.expectedCardinality
                    == expectedCardinality else {
                throw GraphChatTypedIntentValidationError
                    .invalidCardinality
            }
        }
    }

    private static func supports(
        version: GraphChatTypedIntentDomainVersion,
        payload: GraphChatTypedIntentPayload
    ) -> Bool {
        switch (version, payload) {
        case (.v1, .relationships):
            return false
        case (.v1, _), (.v2, _):
            return true
        }
    }
}
