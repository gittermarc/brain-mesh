//
//  GraphChatComposableReadFastPathCompiler.swift
//  BrainMesh
//
//  Conservative deterministic fast path for explicit frequency-bearing
//  entity relationship questions.
//

import Foundation

nonisolated struct GraphChatComposableReadFastPathCompiler:
    Hashable,
    Sendable
{
    private let mentionResolver: GraphMentionResolver

    init(
        mentionResolver: GraphMentionResolver =
            GraphMentionResolver()
    ) {
        self.mentionResolver = mentionResolver
    }

    func compile(
        question: String,
        language: GraphChatResponseLanguage,
        schemaContext: GraphSchemaContext,
        chatScope: GraphChatScope,
        mentionCatalog: GraphMentionCatalog? = nil
    ) -> GraphChatUntrustedSemanticIntentDraft? {
        guard
            chatScope
                == .entireGraph(schemaContext.graphScope),
            let frequency =
                GraphChatComposableReadTextNormalizer
                    .frequencyLiteral(in: question),
            hasExplicitRelationshipCue(
                question,
                language: language
            )
        else {
            return nil
        }
        let entities = resolvedEntities(
            in: question,
            language: language,
            schemaContext: schemaContext,
            chatScope: chatScope,
            mentionCatalog: mentionCatalog
        )
        guard (2...3).contains(entities.count) else {
            return nil
        }
        let counterpartNode: GraphSchemaNodeResolution?
        switch exactCounterpartNode(
            in: question,
            ownerEntity:
                entities[entities.count - 1],
            schemaContext: schemaContext
        ) {
        case .none:
            counterpartNode = nil
        case .exact(let node):
            counterpartNode = node
        case .ambiguous:
            return nil
        }
        return GraphChatUntrustedSemanticIntentDraft(
            family: .relationships,
            entityTerm: entities[0].name,
            nodeTerms: [],
            findTarget: .anyEntry,
            resultAmount: .standard,
            conversationReference: .none,
            filters: [],
            sorting: GraphChatSemanticSortDraft(
                target: .nodeName,
                fieldTerm: nil,
                direction: .ascending
            ),
            projectionTerms: [],
            groupFieldTerm: nil,
            relationshipRequest: .connections,
            relationshipDirection: .both,
            relationshipCounterpartEntityTerm:
                entities[entities.count - 1].name,
            relationshipCounterpartNodeTerm:
                counterpartNode?.displayName,
            relationshipIntermediateEntityTerm:
                entities.count == 3
                ? entities[1].name
                : nil,
            relationshipNoteEntityTerm:
                entities[entities.count - 1].name,
            relationshipNotePredicate: .contains,
            relationshipNoteTerm: frequency,
            relationshipResultTarget: .startNodes,
            responseLanguage: language
        )
    }

    private struct Match: Hashable {
        let entity: GraphSchemaEntityResolution
        let range: GraphMentionTextRange
    }

    private func resolvedEntities(
        in question: String,
        language: GraphChatResponseLanguage,
        schemaContext: GraphSchemaContext,
        chatScope: GraphChatScope,
        mentionCatalog: GraphMentionCatalog?
    ) -> [GraphSchemaEntityResolution] {
        let catalog = mentionCatalog ?? GraphMentionCatalog(
            schemaContext: schemaContext
        )
        var remaining = Set(
            schemaContext.foundationalAliases
                .entitiesByAlias.values
                .map(\.entityID)
        )
        var matches: [Match] = []
        entitySearch: while remaining.isEmpty == false,
              matches.count < 4 {
            let result = mentionResolver.resolve(
                GraphMentionResolverInput(
                    mention: question,
                    kind: .entity,
                    language: language,
                    graphScope: schemaContext.graphScope,
                    catalog: catalog,
                    constraints:
                        GraphMentionResolutionConstraints(
                            chatScope: chatScope,
                            allowedEntityIDs: remaining
                        ),
                    matchingMode: .containedPhrase
                )
            )
            switch result {
            case .success(let resolution):
                guard case .entity(let entity) =
                        resolution.candidate.identity else {
                    return []
                }
                guard let merged = mergedMatches(
                    matches,
                    adding: [
                        Match(
                            entity: entity,
                            range: resolution.matchedRange
                        ),
                    ]
                ) else {
                    return []
                }
                matches = merged
                remaining.remove(entity.entityID)
            case .failure(.ambiguous(let alternatives)):
                let additional = alternatives.compactMap {
                    alternative -> Match? in
                    guard case .entity(let entity) =
                            alternative.candidate.identity else {
                        return nil
                    }
                    return Match(
                        entity: entity,
                        range: alternative.matchedRange
                    )
                }
                guard
                    additional.count == alternatives.count,
                    let merged = mergedMatches(
                        matches,
                        adding: additional
                    )
                else {
                    return []
                }
                matches = merged
                for match in additional {
                    remaining.remove(match.entity.entityID)
                }
            case .failure(.emptyMention),
                .failure(.noCandidates),
                .failure(.notFound):
                break entitySearch
            case .failure(.staleSelection):
                guard matches.isEmpty == false else {
                    return []
                }
                break entitySearch
            case .failure:
                return []
            }
        }
        return matches.map(\.entity)
    }

    private func mergedMatches(
        _ existing: [Match],
        adding additional: [Match]
    ) -> [Match]? {
        let merged = (existing + additional).sorted(
            by: matchOrder
        )
        guard
            merged.isEmpty == false,
            merged.count <= 4,
            Set(merged.map { $0.entity.entityID }).count
                == merged.count,
            merged.allSatisfy({
                $0.range.tokenCount > 0
            })
        else {
            return nil
        }
        for index in 1..<merged.count {
            let previous = merged[index - 1].range
            let current = merged[index].range
            let previousEndToken =
                previous.startToken + previous.tokenCount
            guard previousEndToken <= current.startToken else {
                return nil
            }
        }
        return merged
    }

    private func matchOrder(
        _ lhs: Match,
        _ rhs: Match
    ) -> Bool {
        if lhs.range.startToken
            != rhs.range.startToken {
            return lhs.range.startToken < rhs.range.startToken
        }
        if lhs.range.tokenCount
            != rhs.range.tokenCount {
            return lhs.range.tokenCount > rhs.range.tokenCount
        }
        return lhs.entity.entityID.uuidString < rhs.entity.entityID.uuidString
    }

    private enum CounterpartNodeMatch {
        case none
        case exact(GraphSchemaNodeResolution)
        case ambiguous
    }

    private func exactCounterpartNode(
        in question: String,
        ownerEntity: GraphSchemaEntityResolution,
        schemaContext: GraphSchemaContext
    ) -> CounterpartNodeMatch {
        let questionTokens =
            GraphMentionTextNormalization.tokens(
                question
            )
        let entityTokens =
            GraphMentionTextNormalization.tokens(
                ownerEntity.name
            )
        let candidates = schemaContext.foundationalAliases
            .nodesByKey.values
            .filter { node in
                guard
                    node.ownerEntityID
                        == ownerEntity.entityID,
                    node.node.kind == .attribute
                else {
                    return false
                }
                return containsExactPhrase(
                    GraphMentionTextNormalization
                        .tokens(node.displayName),
                    in: questionTokens
                )
            }
        guard candidates.allSatisfy({
            GraphMentionTextNormalization.tokens(
                $0.displayName
            ) != entityTokens
        }) else {
            return .ambiguous
        }
        switch candidates.count {
        case 0:
            return .none
        case 1:
            return .exact(candidates[0])
        default:
            return .ambiguous
        }
    }

    private func containsExactPhrase(
        _ phrase: [String],
        in tokens: [String]
    ) -> Bool {
        guard phrase.isEmpty == false,
              phrase.count <= tokens.count else {
            return false
        }
        for start in 0...(tokens.count - phrase.count) {
            let end = start + phrase.count
            if Array(tokens[start..<end]) == phrase {
                return true
            }
        }
        return false
    }

    private func hasExplicitRelationshipCue(
        _ question: String,
        language: GraphChatResponseLanguage
    ) -> Bool {
        let terms: Set<String>
        switch language {
        case .german:
            terms = [
                "nehmen",
                "nimmt",
                "einnehmen",
                "erhalten",
                "bekommt",
                "verbunden",
                "verknupft",
            ]
        case .english:
            terms = [
                "take",
                "takes",
                "receive",
                "receives",
                "connected",
                "linked",
            ]
        }
        let tokens = GraphMentionTextNormalization.tokens(
            BMSearch.fold(question)
        )
        return tokens.contains {
            terms.contains($0)
        }
    }
}
