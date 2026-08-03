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
        chatScope: GraphChatScope
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
            chatScope: chatScope
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
        chatScope: GraphChatScope
    ) -> [GraphSchemaEntityResolution] {
        let catalog = GraphMentionCatalog(
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
                matches.append(
                    Match(
                        entity: entity,
                        range: resolution.matchedRange
                    )
                )
                remaining.remove(entity.entityID)
            case .failure(.emptyMention),
                .failure(.noCandidates),
                .failure(.notFound):
                break entitySearch
            case .failure:
                return []
            }
        }
        let sortedMatches = matches.sorted(
            by: { lhs, rhs in
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
        )
        return sortedMatches.map(\.entity)
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
        let canonical = BMSearch.fold(question)
        let terms: [String]
        switch language {
        case .german:
            terms = [
                " nehmen ",
                " nimmt ",
                " einnehmen ",
                " erhalten ",
                " bekommt ",
                " verbunden ",
                " verknupft ",
            ]
        case .english:
            terms = [
                " take ",
                " takes ",
                " receive ",
                " receives ",
                " connected ",
                " linked ",
            ]
        }
        let padded = " \(canonical) "
        return terms.contains {
            padded.contains($0)
        }
    }
}
