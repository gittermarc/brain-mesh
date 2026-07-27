//
//  GraphChatLocalIntentSearchExecutionSupport.swift
//  BrainMesh
//
//  App-side scope filtering and artifact staging for semantic Find.
//

import Foundation

nonisolated struct GraphChatLocalPreparedSearchResult:
    Sendable
{
    let state: GraphChatToolResultState
    let output: SearchGraphOutput
    let evidence: [GraphEvidence]
}

nonisolated struct GraphChatLocalIntentSearchExecutionSupport:
    Sendable
{
    func validate(
        intent: GraphChatTypedIntent,
        action: GraphChatLocalSearchAction,
        schemaContext: GraphSchemaContext
    ) throws {
        guard intent.kind == .findNodes,
              intent.factExpectation == .none,
              intent.expectedCardinality
                == .zeroOrMore,
              intent.payload.fields.isEmpty,
              intent.payload.entities.count <= 1,
              action.scope == intent.scope.queryScope,
              action.limit == intent.limits.resultLimit,
              intent.limits.maximumResultLimit
                == SearchGraphTool.maximumResultCount,
              intent.limits.maximumEvidenceCount
                == action.limit,
              intent.limits.maximumArtifactCount == 1,
              action.limit > 0,
              action.limit
                <= SearchGraphTool.maximumResultCount,
              action.query.trimmingCharacters(
                in: .whitespacesAndNewlines
              ).isEmpty == false,
              GraphChatScopeAuthorization.allows(
                scope: action.scope,
                within: intent.scope.chatScope,
                aliases: schemaContext.aliases
              )
        else {
            throw GraphChatLocalIntentExecutionError
                .invalidCompiledAction
        }
        let intentEntityID =
            intent.payload.entities.first?.id
        guard intentEntityID == action.entityID else {
            throw GraphChatLocalIntentExecutionError
                .invalidCompiledAction
        }
        if action.target == .entityNodes {
            guard action.entityID != nil else {
                throw GraphChatLocalIntentExecutionError
                    .invalidCompiledAction
            }
        }
    }

    func normalizedResult(
        _ result: GraphChatToolResult<SearchGraphOutput>,
        action: GraphChatLocalSearchAction,
        schemaContext: GraphSchemaContext
    ) -> GraphChatLocalPreparedSearchResult {
        guard result.state == .success,
              let output = result.payload else {
            return noResults(
                query: action.query,
                limit: action.limit
            )
        }
        var seenSources =
            Set<GraphSourceReference>()
        var safeEvidence: [GraphEvidence] = []
        let hits = output.hits.compactMap {
            hit -> GraphChatSearchHit? in
            guard
                hit.sourceReference.graphID
                    == action.scope
                        .graphScope.graphID,
                result.evidence.contains(
                    where: {
                        $0.id == hit.evidenceID
                            && $0.sourceReference
                                == hit.sourceReference
                    }
                ),
                kind(
                    hit.kind,
                    matches:
                        hit.sourceReference
                            .sourceKind
                ),
                targetAllows(
                    hit.kind,
                    target: action.target
                ),
                source(
                    hit.sourceReference,
                    belongsTo: action.scope,
                    aliases:
                        schemaContext.aliases
                )
            else {
                return nil
            }
            if let entityID = action.entityID,
               ownerEntityID(
                    for: hit.sourceReference,
                    aliases:
                        schemaContext.aliases
               ) != entityID
            {
                return nil
            }
            guard seenSources
                    .insert(
                        hit.sourceReference
                    ).inserted else {
                return nil
            }
            let title = hit.title
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )
            guard title.isEmpty == false else {
                return nil
            }
            let evidence = GraphEvidence(
                sourceReference:
                    hit.sourceReference,
                summary: title,
                navigationTitle: title,
                identitySuffix:
                    "local-semantic-search"
            )
            safeEvidence.append(evidence)
            return GraphChatSearchHit(
                sourceReference:
                    hit.sourceReference,
                kind: hit.kind,
                title: title,
                subtitle: "",
                matchReason: "",
                evidenceID: evidence.id
            )
        }
        guard hits.isEmpty == false else {
            return noResults(
                query: output.query,
                limit: action.limit
            )
        }
        let evidence =
            GraphEvidenceCollection(
                safeEvidence
            ).values
        guard evidence.isEmpty == false else {
            return GraphChatLocalPreparedSearchResult(
                state: .noEvidence,
                output: SearchGraphOutput(
                    query: output.query,
                    hits: [],
                    resultWindow:
                        GraphChatResultWindow(
                            totalCount: nil,
                            returnedCount: 0,
                            limit: action.limit,
                            limitReached: false
                        )
                ),
                evidence: []
            )
        }
        let wasFiltered =
            hits.count != output.hits.count
        let window = GraphChatResultWindow(
            totalCount:
                wasFiltered
                ? nil
                : output.resultWindow
                    .totalCount,
            returnedCount: hits.count,
            limit: action.limit,
            limitReached:
                output.resultWindow.limitReached
                    || wasFiltered,
            limitSources:
                output.resultWindow.limitSources
                    + (wasFiltered ? [.source] : [])
        )
        return GraphChatLocalPreparedSearchResult(
            state: .success,
            output: SearchGraphOutput(
                query: output.query,
                hits: hits,
                resultWindow: window
            ),
            evidence: evidence
        )
    }

    func stageArtifacts(
        for result:
            GraphChatLocalPreparedSearchResult,
        action: GraphChatLocalSearchAction,
        intent: GraphChatTypedIntent,
        registry: GraphChatAnswerArtifactRegistry,
        evidenceRegistry: GraphChatEvidenceRegistry,
        presentationRegistry:
            GraphChatPresentationRegistry,
        transactionID:
            GraphChatAnswerArtifactTransactionID
    ) async throws -> [GraphChatAnswerArtifactID] {
        guard result.state == .success,
              let draft =
                GraphChatAnswerArtifactFactory
                    .searchResults(
                        output: result.output,
                        graphScope:
                            intent.scope.graphScope,
                        requestedLimit:
                            action.limit,
                        language:
                            intent
                                .responseLanguage,
                        budget:
                            GraphChatAnswerArtifactFactoryBudget(
                                maximumRows:
                                    SearchGraphTool
                                        .maximumResultCount,
                                maximumColumns:
                                    GraphChatAnswerArtifactFactoryBudget
                                        .default
                                        .maximumColumns
                            )
                    )
        else {
            return []
        }
        let artifactID = try await registry.stage(
            draft,
            transactionID: transactionID,
            evidenceRegistry: evidenceRegistry
        )
        await presentationRegistry
            .registerValidatedArtifact(
                id: artifactID,
                title: draft.title
            )
        return [artifactID]
    }

    private func noResults(
        query: String,
        limit: Int
    ) -> GraphChatLocalPreparedSearchResult {
        GraphChatLocalPreparedSearchResult(
            state: .noResults,
            output: SearchGraphOutput(
                query: query,
                hits: [],
                resultWindow:
                    GraphChatResultWindow(
                        totalCount: 0,
                        returnedCount: 0,
                        limit: limit,
                        limitReached: false
                    )
            ),
            evidence: []
        )
    }

    private func targetAllows(
        _ kind: BrainMeshSearchResultKind,
        target: GraphChatLocalSearchTarget
    ) -> Bool {
        switch target {
        case .anyEntry:
            return true
        case .entities:
            return kind == .entity
        case .attributes, .entityNodes:
            return kind == .attribute
        }
    }

    private func kind(
        _ kind: BrainMeshSearchResultKind,
        matches sourceKind: GraphSourceKind
    ) -> Bool {
        switch kind {
        case .entity:
            return sourceKind == .entity
        case .attribute:
            return sourceKind == .attribute
        case .link:
            return sourceKind == .link
        case .detail:
            return sourceKind == .detailField
                || sourceKind == .detailValue
        case .attachment:
            return sourceKind == .attachment
        }
    }

    private func source(
        _ source: GraphSourceReference,
        belongsTo scope: GraphChatScope,
        aliases: GraphSchemaAliasMap
    ) -> Bool {
        guard
            source.graphID
                == scope.graphScope.graphID
        else {
            return false
        }
        switch scope.target {
        case .graph:
            return true
        case .entity(let entityID):
            return ownerEntityID(
                for: source,
                aliases: aliases
            ) == entityID
        case .node(let node):
            return relatedNodes(
                for: source
            ).contains(node)
        case .selection(let nodes):
            return Set(nodes).isDisjoint(
                with: relatedNodes(for: source)
            ) == false
        }
    }

    private func relatedNodes(
        for source: GraphSourceReference
    ) -> Set<NodeRefKey> {
        var nodes = Set<NodeRefKey>()
        if let node = source.node?.nodeKey {
            nodes.insert(node)
        }
        if let owner = source.owner?.nodeKey {
            nodes.insert(owner)
        }
        switch source.sourceKind {
        case .entity:
            nodes.insert(
                NodeRefKey(
                    kind: .entity,
                    id: source.sourceID
                )
            )
        case .attribute:
            nodes.insert(
                NodeRefKey(
                    kind: .attribute,
                    id: source.sourceID
                )
            )
        case .graph, .detailField, .detailValue,
            .link, .attachment:
            break
        }
        return nodes
    }

    private func ownerEntityID(
        for source: GraphSourceReference,
        aliases: GraphSchemaAliasMap
    ) -> UUID? {
        if source.sourceKind == .entity {
            return source.sourceID
        }
        if let owner = source.owner?.nodeKey {
            return aliases.owningEntityID(
                for: owner
            )
        }
        if let node = source.node?.nodeKey {
            return aliases.owningEntityID(
                for: node
            )
        }
        if source.sourceKind == .attribute {
            return aliases.owningEntityID(
                for: NodeRefKey(
                    kind: .attribute,
                    id: source.sourceID
                )
            )
        }
        return nil
    }
}
