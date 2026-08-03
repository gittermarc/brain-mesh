//
//  GraphChatContextualSuggestionRanking.swift
//  BrainMesh
//
//  Production validation, deterministic ranking, and full-catalog lookups.
//

import Foundation

nonisolated extension GraphChatEmptyStateSuggestionBuilder {
    static func ranked(
        _ candidates: [Candidate],
        context: GraphChatSuggestionContext
    ) -> [GraphChatEmptyStateSuggestion] {
        let validator =
            GraphChatCapabilityQuestionValidator()
        let verified = toolEligibleCandidates(
            candidates,
            context: context
        ).compactMap { candidate
            -> VerifiedCandidate? in
            guard let capability =
                    GraphChatCapabilityCatalog.capability(
                        withID: candidate.capabilityID
                    ),
                  capability.placements.contains(
                    .starterQuestion
                  ),
                  let validation = validator.validate(
                    question: candidate.prompt,
                    capability: capability,
                    schemaContext: context.schema,
                    chatScope: context.scope,
                    language: context.language
                  ) else {
                return nil
            }
            return VerifiedCandidate(
                candidate: candidate,
                validation: validation
            )
        }
        let selected = selectedCandidates(
            verified.map(\.candidate)
        )
        let text = Texts(context.language)
        return selected.compactMap { candidate in
            guard let capability =
                    GraphChatCapabilityCatalog.capability(
                        withID: candidate.capabilityID
                    ),
                  let validation = verified.first(
                    where: {
                        $0.candidate.id == candidate.id
                    }
                  )?.validation else {
                return nil
            }
            let title = text.title(for: capability)
            return GraphChatEmptyStateSuggestion(
                id: candidate.id,
                capabilityID: capability.id,
                title: title,
                prompt: candidate.prompt,
                kind: candidate.kind,
                accessibilityLabel:
                    "\(title): \(candidate.prompt)",
                accessibilityHint:
                    text.suggestionAccessibilityHint,
                validation: validation
            )
        }
    }

    static func selectedCandidates(
        _ candidates: [Candidate]
    ) -> [Candidate] {
        let sorted = candidates.sorted {
            if $0.priority != $1.priority {
                return $0.priority < $1.priority
            }
            if $0.kind.rawValue != $1.kind.rawValue {
                return $0.kind.rawValue < $1.kind.rawValue
            }
            return $0.id < $1.id
        }

        var seenSemanticKeys = Set<String>()
        var seenPrompts = Set<String>()
        var unique: [Candidate] = []
        for candidate in sorted {
            let promptKey = BMSearch.fold(
                candidate.prompt
            )
            guard seenSemanticKeys.insert(
                candidate.semanticKey
            ).inserted,
            seenPrompts.insert(promptKey).inserted else {
                continue
            }
            unique.append(candidate)
        }

        var selected: [Candidate] = []
        var selectedKinds =
            Set<GraphChatSuggestionKind>()
        for candidate in unique
        where selected.count < maximumSuggestions {
            guard selectedKinds.insert(
                candidate.kind
            ).inserted else {
                continue
            }
            selected.append(candidate)
        }
        for candidate in unique
        where selected.count < maximumSuggestions {
            guard selected.contains(
                where: { $0.id == candidate.id }
            ) == false else {
                continue
            }
            selected.append(candidate)
        }
        return selected
    }

    static func toolEligibleCandidates(
        _ candidates: [Candidate],
        context: GraphChatSuggestionContext
    ) -> [Candidate] {
        candidates.filter { candidate in
            guard let capability =
                    GraphChatCapabilityCatalog.capability(
                        withID: candidate.capabilityID
                    ) else {
                return false
            }
            return capability.productionPath
                .requiredTools.isSubset(
                    of: context.availableTools
                )
        }
    }

    static func candidate(
        id: String,
        capabilityID: GraphChatCapabilityID,
        priority: Int,
        kind: GraphChatSuggestionKind,
        prompt: String,
        semanticKey: String? = nil
    ) -> Candidate? {
        guard let capability =
                GraphChatCapabilityCatalog.capability(
                    withID: capabilityID
                ),
              capability.placements.contains(
                .starterQuestion
              ) else {
            return nil
        }
        return Candidate(
            id: id,
            semanticKey:
                semanticKey ?? capabilityID.rawValue,
            priority: priority,
            kind: kind,
            capabilityID: capabilityID,
            prompt: prompt
        )
    }

    static func entity(
        id: UUID,
        in schema: GraphSchemaContext
    ) -> GraphSchemaEntityResolution? {
        schema.foundationalAliases.entity(id: id)
    }

    static func node(
        _ key: NodeRefKey,
        in schema: GraphSchemaContext
    ) -> GraphSchemaNodeResolution? {
        schema.foundationalAliases.nodesByKey[key]
    }

    static func sortedEntities(
        in schema: GraphSchemaContext
    ) -> [GraphSchemaEntityResolution] {
        let attributeCounts = Dictionary(
            grouping: schema.foundationalAliases
                .nodesByKey.values.filter {
                    $0.node.kind == .attribute
                },
            by: \.ownerEntityID
        ).mapValues(\.count)
        return schema.foundationalAliases
            .entitiesByAlias.values.sorted {
                let lhsCount =
                    attributeCounts[$0.entityID] ?? 0
                let rhsCount =
                    attributeCounts[$1.entityID] ?? 0
                if lhsCount != rhsCount {
                    return lhsCount > rhsCount
                }
                let lhsName = BMSearch.fold($0.name)
                let rhsName = BMSearch.fold($1.name)
                if lhsName != rhsName {
                    return lhsName < rhsName
                }
                return $0.entityID.uuidString <
                    $1.entityID.uuidString
            }
    }

    static func sortedNodes(
        in schema: GraphSchemaContext,
        allowed allowedNodes: Set<NodeRefKey>? = nil,
        ownerEntityID: UUID? = nil
    ) -> [GraphSchemaNodeResolution] {
        schema.foundationalAliases.nodesByKey
            .values.filter { resolution in
                if let allowedNodes,
                   allowedNodes.contains(
                    resolution.node
                   ) == false {
                    return false
                }
                if let ownerEntityID,
                   resolution.ownerEntityID
                    != ownerEntityID {
                    return false
                }
                return true
            }
            .sorted(by: nodeSort)
    }

    static func nodeSort(
        _ lhs: GraphSchemaNodeResolution,
        _ rhs: GraphSchemaNodeResolution
    ) -> Bool {
        let lhsKind = lhs.node.kind == .attribute
            ? 0
            : 1
        let rhsKind = rhs.node.kind == .attribute
            ? 0
            : 1
        if lhsKind != rhsKind {
            return lhsKind < rhsKind
        }
        let lhsName = BMSearch.fold(lhs.displayName)
        let rhsName = BMSearch.fold(rhs.displayName)
        if lhsName != rhsName {
            return lhsName < rhsName
        }
        if lhs.ownerEntityID != rhs.ownerEntityID {
            return lhs.ownerEntityID.uuidString <
                rhs.ownerEntityID.uuidString
        }
        return lhs.node.id.uuidString <
            rhs.node.id.uuidString
    }

    struct Candidate: Sendable {
        let id: String
        let semanticKey: String
        let priority: Int
        let kind: GraphChatSuggestionKind
        let capabilityID: GraphChatCapabilityID
        let prompt: String
    }

    private struct VerifiedCandidate: Sendable {
        let candidate: Candidate
        let validation:
            GraphChatCapabilityQuestionValidation
    }
}
