//
//  GraphChatFoundationalIntentCompiler.swift
//  BrainMesh
//
//  Narrow schema-oriented recognition of foundational graph questions.
//

import Foundation

nonisolated struct GraphChatFoundationalIntentCompiler: Sendable {
    private struct SingleCandidate: Hashable, Sendable {
        let entity: GraphSchemaEntityResolution
        let node: GraphSchemaNodeResolution
        let field: GraphSchemaFieldResolution
        let aliasOrigin: GraphMentionAliasOrigin
        let quality: GraphMentionResolutionQuality
    }

    private let mentionResolver: GraphMentionResolver
    private let shellExtractor: GraphMentionShellExtractor

    init(
        mentionResolver: GraphMentionResolver =
            GraphMentionResolver(),
        shellExtractor: GraphMentionShellExtractor =
            GraphMentionShellExtractor()
    ) {
        self.mentionResolver = mentionResolver
        self.shellExtractor = shellExtractor
    }

    func compile(
        _ input: GraphChatFoundationalIntentCompilerInput,
        mentionCatalog: GraphMentionCatalog? = nil
    ) -> GraphChatFoundationalIntentCompilation {
        guard input.graphScope == input.schemaContext.graphScope,
              input.schemaContext.aliases.graphScope == input.graphScope,
              input.schemaContext.foundationalAliases
                .graphScope == input.graphScope
        else {
            return .rejected(.graphScopeMismatch)
        }
        guard input.chatScope.graphScope == input.graphScope,
              input.conversationState.graphScope == input.graphScope,
              input.conversationState.chatScope == input.chatScope else {
            return .rejected(.chatScopeMismatch)
        }
        guard schemaIsInternallyConsistent(input.schemaContext) else {
            return .rejected(.schemaIntegrityViolation)
        }
        let catalog = mentionCatalog ?? GraphMentionCatalog(
            schemaContext: input.schemaContext
        )
        guard catalog.graphScope == input.graphScope else {
            return .rejected(.graphScopeMismatch)
        }

        let normalizedQuestion = Self.normalized(input.question)
        guard normalizedQuestion.isEmpty == false else {
            return .notRecognized
        }

        if let extraction = shellExtractor.extract(
            from: input.question,
            family: .entityCollection,
            language: input.responseLanguage
        ) {
            let collection = compileCollection(
                input,
                entityMention: extraction.mention,
                mentionCatalog: catalog
            )
            if collection != .notRecognized {
                return collection
            }
        }

        if let extraction = shellExtractor.extract(
            from: input.question,
            family: .nodeDetails,
            language: input.responseLanguage
        ) {
            let nodeDetails = compileNodeDetails(
                input,
                nodeMention: extraction.mention,
                mentionCatalog: catalog
            )
            if nodeDetails != .notRecognized {
                return nodeDetails
            }
        }

        guard isSingleFieldShell(
            normalizedQuestion,
            language: input.responseLanguage
        ) else {
            return input.selectedCandidate == nil
                ? .notRecognized
                : .rejected(.staleClarification)
        }
        return compileSingleField(
            input,
            normalizedQuestion: normalizedQuestion,
            mentionCatalog: catalog
        )
    }

    private func compileCollection(
        _ input: GraphChatFoundationalIntentCompilerInput,
        entityMention: String,
        mentionCatalog: GraphMentionCatalog
    ) -> GraphChatFoundationalIntentCompilation {
        if input.selectedCandidate?.node != nil
            || input.selectedCandidate?.fieldID != nil {
            return .rejected(.staleClarification)
        }
        let result = mentionResolver.resolve(
            GraphMentionResolverInput(
                mention: entityMention,
                kind: .entity,
                language: input.responseLanguage,
                graphScope: input.graphScope,
                catalog: mentionCatalog,
                constraints:
                    GraphMentionResolutionConstraints(
                        chatScope: input.chatScope,
                        allowedEntityIDs:
                            input.selectedCandidate.map {
                                Set([$0.entityID])
                            }
                    )
            )
        )
        let resolution: GraphMentionResolution
        switch result {
        case .success(let value):
            resolution = value
        case .failure(.ambiguous(let alternatives)):
            let candidates = alternatives.compactMap {
                alternative
                    -> GraphSchemaEntityResolution? in
                guard case .entity(let value) =
                        alternative.candidate.identity else {
                    return nil
                }
                return value
            }
            return .clarification(
                clarification(
                    candidates: candidates,
                    language: input.responseLanguage,
                    selection: {
                        GraphChatFoundationalIntentSelection(
                            entityID: $0.entityID
                        )
                    },
                    title: { candidate, index in
                        disambiguatedTitle(
                            candidate.name,
                            detail: nil,
                            index: index,
                            duplicateCount: candidates.count
                        )
                    }
                )
            )
        case .failure(.scopeViolation),
            .failure(.ownerEntityMismatch):
            return .rejected(.unauthorizedSelection)
        case .failure(.staleSelection):
            return .rejected(.staleClarification)
        case .failure(.graphScopeMismatch):
            return .rejected(.graphScopeMismatch)
        case .failure(.noCandidates),
            .failure(.emptyMention),
            .failure(.notFound):
            return input.selectedCandidate == nil
                ? .notRecognized
                : .rejected(.staleClarification)
        }
        guard case .entity(let entity) =
                resolution.candidate.identity else {
            return .rejected(.schemaIntegrityViolation)
        }
        guard let scope = queryScope(
            for: entity.entityID,
            within: input.chatScope,
            schemaContext: input.schemaContext
        ) else {
            return .rejected(.unauthorizedSelection)
        }

        return .compiled(
            GraphChatFoundationalIntent(
                kind: .entityAttributeCollection,
                graphScope: input.graphScope,
                chatScope: input.chatScope,
                queryScope: scope,
                responseLanguage: input.responseLanguage,
                entity: GraphChatFoundationalEntityIdentity(
                    id: entity.entityID,
                    alias: entity.alias,
                    displayName: entity.name
                ),
                field: nil,
                node: nil,
                expectedCardinality: .zeroOrMore,
                resultLimit: GraphQueryPlanLimits.maximumResultLimit,
                origin: input.selectedCandidate == nil
                    ? foundationalOrigin(resolution)
                    : .clarificationSelection,
                confidence: input.selectedCandidate == nil
                    ? foundationalConfidence(resolution)
                    : .revalidatedClarification,
                binding: binding(input)
            )
        )
    }

    private func compileNodeDetails(
        _ input: GraphChatFoundationalIntentCompilerInput,
        nodeMention: String,
        mentionCatalog: GraphMentionCatalog
    ) -> GraphChatFoundationalIntentCompilation {
        if input.selectedCandidate?.fieldID != nil {
            return .rejected(.staleClarification)
        }
        let selected = input.selectedCandidate
        let result = mentionResolver.resolve(
            GraphMentionResolverInput(
                mention: nodeMention,
                kind: .node,
                language: input.responseLanguage,
                graphScope: input.graphScope,
                catalog: mentionCatalog,
                constraints:
                    GraphMentionResolutionConstraints(
                        chatScope: input.chatScope,
                        ownerEntityID:
                            selected?.entityID,
                        allowedNodes:
                            selected?.node.map {
                                Set([$0])
                            }
                    )
            )
        )
        let resolution: GraphMentionResolution
        switch result {
        case .success(let value):
            resolution = value
        case .failure(.ambiguous(let alternatives)):
            let candidates = alternatives.compactMap {
                alternative
                    -> GraphSchemaNodeResolution? in
                guard case .node(let value) =
                        alternative.candidate.identity else {
                    return nil
                }
                return value
            }
            return .clarification(
                clarification(
                    candidates: candidates,
                    language: input.responseLanguage,
                    selection: {
                        GraphChatFoundationalIntentSelection(
                            entityID: $0.ownerEntityID,
                            node: $0.node
                        )
                    },
                    title: { candidate, index in
                        let owner =
                            input.schemaContext.foundationalAliases
                                .entity(
                                    id:
                                        candidate
                                            .ownerEntityID
                                )?.name
                        return disambiguatedTitle(
                            candidate.displayName,
                            detail: owner,
                            index: index,
                            duplicateCount:
                                candidates.count
                        )
                    }
                )
            )
        case .failure(.scopeViolation),
            .failure(.ownerEntityMismatch):
            return .rejected(.unauthorizedSelection)
        case .failure(.staleSelection):
            return .rejected(.staleClarification)
        case .failure(.graphScopeMismatch):
            return .rejected(.graphScopeMismatch)
        case .failure(.noCandidates),
            .failure(.emptyMention),
            .failure(.notFound):
            return selected == nil
                ? .notRecognized
                : .rejected(.staleClarification)
        }
        guard case .node(let node) =
                resolution.candidate.identity,
              let entity =
                input.schemaContext.foundationalAliases.entity(
                    id: node.ownerEntityID
                ) else {
            return .rejected(.schemaIntegrityViolation)
        }
        return .compiled(
            GraphChatFoundationalIntent(
                kind: .nodeDetails,
                graphScope: input.graphScope,
                chatScope: input.chatScope,
                queryScope: .node(
                    node.node,
                    in: input.graphScope
                ),
                responseLanguage:
                    input.responseLanguage,
                entity:
                    GraphChatFoundationalEntityIdentity(
                        id: entity.entityID,
                        alias: entity.alias,
                        displayName: entity.name
                    ),
                field: nil,
                node:
                    GraphChatFoundationalNodeIdentity(
                        node: node.node,
                        displayName:
                            node.displayName,
                        ownerEntityID:
                            node.ownerEntityID
                    ),
                expectedCardinality: .zeroOrOne,
                resultLimit: 1,
                origin: selected == nil
                    ? foundationalOrigin(resolution)
                    : .clarificationSelection,
                confidence: selected == nil
                    ? foundationalConfidence(
                        resolution
                    )
                    : .revalidatedClarification,
                binding: binding(input)
            )
        )
    }

    private func compileSingleField(
        _ input: GraphChatFoundationalIntentCompilerInput,
        normalizedQuestion: String,
        mentionCatalog: GraphMentionCatalog
    ) -> GraphChatFoundationalIntentCompilation {
        _ = normalizedQuestion
        let selected = input.selectedCandidate
        let attributeNodes = Set(
            input.schemaContext.foundationalAliases
                .nodesByKey.values
                .filter {
                    $0.node.kind == .attribute
                }
                .map(\.node)
        )
        let nodeResult = mentionResolver.resolve(
            GraphMentionResolverInput(
                mention: input.question,
                kind: .node,
                language: input.responseLanguage,
                graphScope: input.graphScope,
                catalog: mentionCatalog,
                constraints:
                    GraphMentionResolutionConstraints(
                        chatScope: input.chatScope,
                        ownerEntityID:
                            selected?.entityID,
                        allowedNodes:
                            selected?.node.map {
                                Set([$0])
                            } ?? attributeNodes
                    ),
                matchingMode: .containedPhrase
            )
        )
        let fieldResult = mentionResolver.resolve(
            GraphMentionResolverInput(
                mention: input.question,
                kind: .field,
                language: input.responseLanguage,
                graphScope: input.graphScope,
                catalog: mentionCatalog,
                constraints:
                    GraphMentionResolutionConstraints(
                        chatScope: input.chatScope,
                        ownerEntityID:
                            selected?.entityID,
                        allowedFieldIDs:
                            selected?.fieldID.map {
                                Set([$0])
                            }
                    ),
                matchingMode: .containedPhrase
            )
        )

        let nodeMatches: [GraphMentionResolution]
        switch nodeResult {
        case .success(let value):
            nodeMatches = [value]
        case .failure(.ambiguous(let alternatives)):
            nodeMatches = alternatives.map(
                resolution(from:)
            )
        case .failure(.scopeViolation),
            .failure(.ownerEntityMismatch):
            return .rejected(.unauthorizedSelection)
        case .failure(.graphScopeMismatch):
            return .rejected(.graphScopeMismatch)
        case .failure(.noCandidates),
            .failure(.staleSelection):
            return selected == nil
                ? .notRecognized
                : .rejected(.staleClarification)
        case .failure(.emptyMention),
            .failure(.notFound):
            return selected == nil
                ? .notRecognized
                : .rejected(.staleClarification)
        }

        let fieldMatches: [GraphMentionResolution]
        switch fieldResult {
        case .success(let value):
            fieldMatches = [value]
        case .failure(.ambiguous(let alternatives)):
            fieldMatches = alternatives.map(
                resolution(from:)
            )
        case .failure(.scopeViolation),
            .failure(.ownerEntityMismatch):
            return .rejected(.unauthorizedSelection)
        case .failure(.graphScopeMismatch):
            return .rejected(.graphScopeMismatch)
        case .failure(.noCandidates),
            .failure(.staleSelection):
            return selected == nil
                ? .notRecognized
                : .rejected(.staleClarification)
        case .failure(.emptyMention),
            .failure(.notFound):
            return selected == nil
                ? .notRecognized
                : .rejected(.staleClarification)
        }

        let candidates = nodeMatches.flatMap {
            nodeMatch -> [SingleCandidate] in
            guard case .node(let node) =
                    nodeMatch.candidate.identity else {
                return []
            }
            return fieldMatches.compactMap {
                fieldMatch -> SingleCandidate? in
                guard case .field(let field) =
                        fieldMatch.candidate.identity,
                      node.ownerEntityID
                        == field.entityID,
                      let entity =
                        input.schemaContext.foundationalAliases
                            .entity(
                                id:
                                    node
                                        .ownerEntityID
                            ),
                      hasSafeSingleRemainder(
                        input.question,
                        nodeRange:
                            nodeMatch.matchedRange,
                        fieldRange:
                            fieldMatch.matchedRange,
                        language:
                            input.responseLanguage
                      )
                else {
                    return nil
                }
                let quality =
                    nodeMatch.quality.rawValue
                        >= fieldMatch.quality.rawValue
                    ? nodeMatch.quality
                    : fieldMatch.quality
                let aliasOrigin:
                    GraphMentionAliasOrigin =
                    fieldMatch.aliasOrigin
                        != .displayName
                    ? fieldMatch.aliasOrigin
                    : nodeMatch.aliasOrigin
                return SingleCandidate(
                    entity: entity,
                    node: node,
                    field: field,
                    aliasOrigin: aliasOrigin,
                    quality: quality
                )
            }
        }.sorted(by: Self.singleCandidateSort)

        guard candidates.isEmpty == false else {
            return selected == nil
                ? .notRecognized
                : .rejected(.staleClarification)
        }
        guard candidates.count == 1, let candidate = candidates.first else {
            return .clarification(
                clarification(
                    candidates: candidates,
                    language: input.responseLanguage,
                    selection: {
                        GraphChatFoundationalIntentSelection(
                            entityID: $0.entity.entityID,
                            node: $0.node.node,
                            fieldID: $0.field.fieldID
                        )
                    },
                    title: { value, index in
                        disambiguatedTitle(
                            value.node.displayName,
                            detail:
                                "\(value.entity.name) · \(value.field.name)",
                            index: index,
                            duplicateCount: candidates.count
                        )
                    }
                )
            )
        }

        let queryScope = GraphChatScope.node(
            candidate.node.node,
            in: input.graphScope
        )
        let origin: GraphChatFoundationalResolutionOrigin
        let confidence: GraphChatFoundationalResolutionConfidence
        if selected != nil {
            origin = .clarificationSelection
            confidence = .revalidatedClarification
        } else if candidate.aliasOrigin
            == .localizedFieldSynonym {
            origin = .localizedFieldSynonym
            confidence = .constrainedSynonym
        } else {
            origin = .schemaDisplayName
            confidence =
                candidate.quality == .exact
                    || candidate.quality
                        == .canonical
                ? .exact
                : .constrainedSynonym
        }

        return .compiled(
            GraphChatFoundationalIntent(
                kind: .singleNodeFieldValue,
                graphScope: input.graphScope,
                chatScope: input.chatScope,
                queryScope: queryScope,
                responseLanguage: input.responseLanguage,
                entity: GraphChatFoundationalEntityIdentity(
                    id: candidate.entity.entityID,
                    alias: candidate.entity.alias,
                    displayName: candidate.entity.name
                ),
                field: GraphChatFoundationalFieldIdentity(
                    id: candidate.field.fieldID,
                    alias: candidate.field.alias,
                    displayName: candidate.field.name,
                    type: candidate.field.type,
                    unit: candidate.field.unit
                ),
                node: GraphChatFoundationalNodeIdentity(
                    node: candidate.node.node,
                    displayName: candidate.node.displayName,
                    ownerEntityID: candidate.node.ownerEntityID
                ),
                expectedCardinality: .zeroOrOne,
                resultLimit: 1,
                origin: origin,
                confidence: confidence,
                binding: binding(input)
            )
        )
    }

    private func hasSafeSingleRemainder(
        _ question: String,
        nodeRange: GraphMentionTextRange,
        fieldRange: GraphMentionTextRange,
        language: GraphChatResponseLanguage
    ) -> Bool {
        let tokens =
            GraphMentionTextNormalization.tokens(
                question
            )
        let nodeEndToken =
            nodeRange.startToken
            + nodeRange.tokenCount
        let nodeIndices = Set<Int>(
            nodeRange.startToken..<nodeEndToken
        )
        let fieldEndToken =
            fieldRange.startToken
            + fieldRange.tokenCount
        let fieldIndices = Set<Int>(
            fieldRange.startToken..<fieldEndToken
        )
        guard nodeIndices.isDisjoint(
            with: fieldIndices
        ) else {
            return false
        }
        let remainder = tokens.indices.compactMap {
            index -> String? in
            nodeIndices.contains(index)
                || fieldIndices.contains(index)
                ? nil
                : tokens[index]
        }

        let allowed: Set<String>
        switch language {
        case .german:
            allowed = [
                "das",
                "den",
                "der",
                "die",
                "hat",
                "hoch",
                "ist",
                "von",
                "wann",
                "was",
                "welche",
                "welchen",
                "welches",
                "wie",
            ]
        case .english:
            allowed = [
                "does",
                "have",
                "high",
                "how",
                "is",
                "much",
                "of",
                "s",
                "the",
                "what",
                "when",
                "which",
            ]
        }
        return remainder.allSatisfy(
            allowed.contains
        )
    }

    private func isSingleFieldShell(
        _ question: String,
        language: GraphChatResponseLanguage
    ) -> Bool {
        switch language {
        case .german:
            return Self.startsWithAny(
                question,
                phrases: [
                    "wann ",
                    "was ist ",
                    "welchen ",
                    "welche ",
                    "welches ",
                    "wie hoch ",
                ]
            )
        case .english:
            return Self.startsWithAny(
                question,
                phrases: [
                    "what is ",
                    "when is ",
                    "which ",
                    "how high ",
                    "how much ",
                ]
            )
        }
    }

    private func schemaIsInternallyConsistent(
        _ context: GraphSchemaContext
    ) -> Bool {
        let aliases = context.foundationalAliases
        let entities = Array(aliases.entitiesByAlias.values)
        let entityIDs = Set(entities.map(\.entityID))
        guard entityIDs.count == entities.count else {
            return false
        }
        let fields = Array(aliases.fieldsByAlias.values)
        guard Set(fields.map(\.fieldID)).count == fields.count,
              fields.allSatisfy({ field in
                aliases.entity(for: field.entityAlias)?
                    .entityID == field.entityID
                    && entityIDs.contains(field.entityID)
              }) else {
            return false
        }
        return aliases.nodesByKey.allSatisfy {
            node, resolution in
            node == resolution.node
                && entityIDs.contains(resolution.ownerEntityID)
                && (
                    aliases.nodeEntityIDs[node].map {
                        $0 == resolution.ownerEntityID
                    } ?? true
                )
                && aliases.owningEntityID(for: node)
                    == resolution.ownerEntityID
        }
    }

    private func queryScope(
        for entityID: UUID,
        within scope: GraphChatScope,
        schemaContext: GraphSchemaContext
    ) -> GraphChatScope? {
        switch scope.target {
        case .graph:
            return .entity(entityID, in: scope.graphScope)
        case .entity(let scopedEntityID):
            return scopedEntityID == entityID ? scope : nil
        case .node(let node):
            return schemaContext.foundationalAliases
                .owningEntityID(for: node) == entityID
                ? scope
                : nil
        case .selection(let nodes):
            let matchingNodes = nodes.filter {
                schemaContext.foundationalAliases
                    .owningEntityID(for: $0) == entityID
            }
            guard matchingNodes.isEmpty == false else {
                return nil
            }
            return try? .selection(
                matchingNodes,
                in: scope.graphScope
            )
        }
    }

    private func clarification<Candidate>(
        candidates: [Candidate],
        language: GraphChatResponseLanguage,
        selection: (Candidate) -> GraphChatFoundationalIntentSelection,
        title: (Candidate, Int) -> String
    ) -> GraphChatFoundationalClarification {
        let question: String
        switch language {
        case .german:
            question = "Welchen fachlichen Eintrag meinst du?"
        case .english:
            question = "Which domain item do you mean?"
        }
        return GraphChatFoundationalClarification(
            question: question,
            options: candidates.prefix(
                GraphChatIntentLimitPolicy
                    .default.maximumClarificationOptionCount
            ).enumerated().map { index, candidate in
                GraphChatFoundationalClarificationOption(
                    id: "FOUNDATIONAL_\(index + 1)",
                    title: title(candidate, index),
                    selection: selection(candidate)
                )
            }
        )
    }

    private func disambiguatedTitle(
        _ primary: String,
        detail: String?,
        index: Int,
        duplicateCount: Int
    ) -> String {
        var value = primary
        if let detail, detail.isEmpty == false {
            value += " — \(detail)"
        }
        if duplicateCount > 1 {
            value += " · \(index + 1)"
        }
        return value
    }

    private func resolution(
        from alternative:
            GraphMentionResolutionAlternative
    ) -> GraphMentionResolution {
        GraphMentionResolution(
            version: .v1,
            candidate: alternative.candidate,
            aliasOrigin:
                alternative.aliasOrigin,
            quality: alternative.quality,
            matchedRange:
                alternative.matchedRange,
            editDistance:
                alternative.editDistance
        )
    }

    private func foundationalOrigin(
        _ resolution: GraphMentionResolution
    ) -> GraphChatFoundationalResolutionOrigin {
        switch resolution.aliasOrigin {
        case .localizedFieldSynonym:
            return .localizedFieldSynonym
        case .displayName, .appOwnedAlias:
            return .schemaDisplayName
        }
    }

    private func foundationalConfidence(
        _ resolution: GraphMentionResolution
    ) -> GraphChatFoundationalResolutionConfidence {
        switch resolution.quality {
        case .exact, .canonical:
            return resolution.aliasOrigin
                == .displayName
                ? .exact
                : .constrainedSynonym
        case .umlautEquivalent,
            .languageVariant,
            .conservativeTypo:
            return .constrainedSynonym
        }
    }

    private func binding(
        _ input: GraphChatFoundationalIntentCompilerInput
    ) -> GraphChatFoundationalIntentBinding {
        GraphChatFoundationalIntentBinding(
            requestID: input.requestID,
            conversationID: input.conversationState.conversationID,
            sourceTurnID: input.sourceTurnID,
            clarificationID: input.clarificationID
        )
    }

    private static func normalized(_ value: String) -> String {
        BMSearch.fold(value)
            .components(
                separatedBy: CharacterSet.alphanumerics.inverted
            )
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
    }

    private static func startsWithAny(
        _ value: String,
        phrases: [String]
    ) -> Bool {
        phrases.contains { value.hasPrefix($0) }
    }

    private static func singleCandidateSort(
        _ lhs: SingleCandidate,
        _ rhs: SingleCandidate
    ) -> Bool {
        let left = [
            normalized(lhs.node.displayName),
            normalized(lhs.entity.name),
            normalized(lhs.field.name),
            lhs.node.node.id.uuidString,
            lhs.field.fieldID.uuidString,
        ]
        let right = [
            normalized(rhs.node.displayName),
            normalized(rhs.entity.name),
            normalized(rhs.field.name),
            rhs.node.node.id.uuidString,
            rhs.field.fieldID.uuidString,
        ]
        return left.lexicographicallyPrecedes(right)
    }
}
