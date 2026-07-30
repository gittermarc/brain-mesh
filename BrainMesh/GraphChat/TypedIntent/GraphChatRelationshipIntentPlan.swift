//
//  GraphChatRelationshipIntentPlan.swift
//  BrainMesh
//
//  App-owned, versioned execution contract for direct graph relationships.
//

import Foundation

nonisolated enum GraphChatRelationshipPlanVersion:
    Int,
    CaseIterable,
    Hashable,
    Sendable
{
    case v1 = 1

    static let current = GraphChatRelationshipPlanVersion.v1
}

nonisolated enum GraphChatRelationshipRequestKind:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case connections
    case linkNotesBetweenNodes
}

nonisolated enum GraphChatRelationshipDirection:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case incoming
    case outgoing
    case both
}

nonisolated enum GraphChatRelationshipNotePredicate:
    Hashable,
    Sendable
{
    case present
    case missing
    case contains(String)
}

nonisolated enum GraphChatRelationshipPlanValidationError:
    Error,
    LocalizedError,
    Hashable,
    Sendable
{
    case unsupportedVersion
    case invalidBinding
    case graphScopeMismatch
    case invalidQueryScope
    case invalidCenterBinding
    case invalidCounterpartBinding
    case invalidNotePredicate
    case invalidLimits
    case invalidCardinality

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion:
            return "Die Relationship-Plan-Version wird nicht unterstützt."
        case .invalidBinding:
            return "Der Relationship-Plan ist nicht eindeutig an den aktuellen Turn gebunden."
        case .graphScopeMismatch:
            return "Der Relationship-Plan enthält widersprüchliche Graph-Scopes."
        case .invalidQueryScope:
            return "Der Relationship-Plan ist nicht auf den gebundenen Center-Node begrenzt."
        case .invalidCenterBinding:
            return "Der Center-Node gehört nicht zur gebundenen Entity."
        case .invalidCounterpartBinding:
            return "Der Gegenknoten gehört nicht zur gebundenen Gegen-Entity."
        case .invalidNotePredicate:
            return "Der Relationship-Plan enthält ein ungültiges Link-Notiz-Prädikat."
        case .invalidLimits:
            return "Der Relationship-Plan enthält ungültige appseitige Limits."
        case .invalidCardinality:
            return "Der Relationship-Plan enthält eine ungültige Kardinalität."
        }
    }
}

/// A value-only plan compiled exclusively by the app. Semantic interpreters
/// never create this value and therefore cannot choose identities, scope,
/// limits or execution details.
nonisolated struct GraphChatRelationshipPlan:
    Hashable,
    Sendable
{
    let version: GraphChatRelationshipPlanVersion
    let graphScope: GraphScope
    let chatScope: GraphChatScope
    let queryScope: GraphChatScope
    let binding: GraphChatTypedIntentBinding
    let request: GraphChatRelationshipRequestKind
    let centerEntity: GraphChatTypedEntityIdentity
    let centerNode: GraphChatTypedNodeIdentity
    let direction: GraphChatRelationshipDirection
    let counterpartEntity: GraphChatTypedEntityIdentity?
    let counterpartNode: GraphChatTypedNodeIdentity?
    let notePredicate: GraphChatRelationshipNotePredicate?
    let limits: GraphChatTypedIntentLimits
    let responseLanguage: GraphChatResponseLanguage
    let expectedCardinality:
        GraphChatTypedIntentExpectedCardinality
    let sourceRelationshipContextID: UUID?

    init(
        version:
            GraphChatRelationshipPlanVersion = .current,
        graphScope: GraphScope,
        chatScope: GraphChatScope,
        queryScope: GraphChatScope,
        binding: GraphChatTypedIntentBinding,
        request: GraphChatRelationshipRequestKind,
        centerEntity: GraphChatTypedEntityIdentity,
        centerNode: GraphChatTypedNodeIdentity,
        direction: GraphChatRelationshipDirection,
        counterpartEntity:
            GraphChatTypedEntityIdentity? = nil,
        counterpartNode:
            GraphChatTypedNodeIdentity? = nil,
        notePredicate:
            GraphChatRelationshipNotePredicate? = nil,
        limits: GraphChatTypedIntentLimits,
        responseLanguage: GraphChatResponseLanguage,
        expectedCardinality:
            GraphChatTypedIntentExpectedCardinality = .zeroOrMore,
        sourceRelationshipContextID: UUID? = nil
    ) throws {
        guard version == .current else {
            throw GraphChatRelationshipPlanValidationError
                .unsupportedVersion
        }
        guard binding.requestID == binding.turnID else {
            throw GraphChatRelationshipPlanValidationError
                .invalidBinding
        }
        guard graphScope == chatScope.graphScope,
              graphScope == queryScope.graphScope else {
            throw GraphChatRelationshipPlanValidationError
                .graphScopeMismatch
        }
        guard queryScope
                == .node(
                    centerNode.node,
                    in: graphScope
                ) else {
            throw GraphChatRelationshipPlanValidationError
                .invalidQueryScope
        }
        guard centerNode.ownerEntityID
                == centerEntity.id else {
            throw GraphChatRelationshipPlanValidationError
                .invalidCenterBinding
        }
        if let counterpartNode {
            guard let counterpartEntity,
                  counterpartNode.ownerEntityID
                    == counterpartEntity.id else {
                throw GraphChatRelationshipPlanValidationError
                    .invalidCounterpartBinding
            }
        }
        if case .contains(let term)? = notePredicate {
            let normalized = term.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard normalized.isEmpty == false,
                  normalized.count
                    <= GraphChatIntentLimitPolicy
                        .default
                        .maximumFilterValueLength,
                  GraphChatSemanticSafety
                    .containsTechnicalIdentifier(normalized)
                    == false else {
                throw GraphChatRelationshipPlanValidationError
                    .invalidNotePredicate
            }
        }
        guard limits.resultLimit > 0,
              limits.maximumResultLimit
                == GraphChatIntentLimitPolicy
                    .default.maximumNeighborCount,
              limits.resultLimit
                <= limits.maximumResultLimit,
              limits.maximumEvidenceCount
                >= limits.resultLimit + 1,
              limits.maximumArtifactCount == 1 else {
            throw GraphChatRelationshipPlanValidationError
                .invalidLimits
        }
        guard expectedCardinality == .zeroOrMore else {
            throw GraphChatRelationshipPlanValidationError
                .invalidCardinality
        }
        if request == .linkNotesBetweenNodes {
            guard counterpartNode != nil,
                  direction == .both,
                  notePredicate == nil else {
                throw GraphChatRelationshipPlanValidationError
                    .invalidCounterpartBinding
            }
        }

        self.version = version
        self.graphScope = graphScope
        self.chatScope = chatScope
        self.queryScope = queryScope
        self.binding = binding
        self.request = request
        self.centerEntity = centerEntity
        self.centerNode = centerNode
        self.direction = direction
        self.counterpartEntity = counterpartEntity
        self.counterpartNode = counterpartNode
        self.notePredicate = notePredicate
        self.limits = limits
        self.responseLanguage = responseLanguage
        self.expectedCardinality = expectedCardinality
        self.sourceRelationshipContextID =
            sourceRelationshipContextID
    }
}
