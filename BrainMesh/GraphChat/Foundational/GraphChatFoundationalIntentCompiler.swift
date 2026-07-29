//
//  GraphChatFoundationalIntentCompiler.swift
//  BrainMesh
//
//  Narrow schema-oriented recognition of foundational graph questions.
//

import Foundation

nonisolated struct GraphChatFoundationalIntentCompiler: Sendable {
    private struct FieldMatch: Hashable, Sendable {
        let field: GraphSchemaFieldResolution
        let usedSynonym: Bool
    }

    private struct SingleCandidate: Hashable, Sendable {
        let entity: GraphSchemaEntityResolution
        let node: GraphSchemaNodeResolution
        let field: GraphSchemaFieldResolution
        let usedSynonym: Bool
    }

    func compile(
        _ input: GraphChatFoundationalIntentCompilerInput
    ) -> GraphChatFoundationalIntentCompilation {
        guard input.graphScope == input.schemaContext.graphScope,
              input.schemaContext.aliases.graphScope == input.graphScope else {
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

        let normalizedQuestion = Self.normalized(input.question)
        guard normalizedQuestion.isEmpty == false else {
            return .notRecognized
        }

        if isCollectionShell(
            normalizedQuestion,
            language: input.responseLanguage
        ),
            containsUnsupportedCollectionModifier(
                normalizedQuestion,
                language: input.responseLanguage
            ) == false
        {
            let collection = compileCollection(
                input,
                normalizedQuestion: normalizedQuestion
            )
            if collection != .notRecognized {
                return collection
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
            normalizedQuestion: normalizedQuestion
        )
    }

    private func compileCollection(
        _ input: GraphChatFoundationalIntentCompilerInput,
        normalizedQuestion: String
    ) -> GraphChatFoundationalIntentCompilation {
        let selectedEntityID = input.selectedCandidate?.entityID
        let namedCandidates =
            input.schemaContext.aliases.entitiesByAlias.values
            .filter { resolution in
                selectedEntityID.map { $0 == resolution.entityID } ?? true
            }
            .filter {
                Self.containsPhrase(
                    Self.normalized($0.name),
                    in: normalizedQuestion
                )
            }
            .filter {
                Self.hasSafeCollectionRemainder(
                    normalizedQuestion,
                    entityName: $0.name,
                    language: input.responseLanguage
                )
            }
            .sorted(by: Self.entitySort)
        let candidates = namedCandidates.filter {
            queryScope(
                for: $0.entityID,
                within: input.chatScope,
                schemaContext: input.schemaContext
            ) != nil
        }

        if candidates.isEmpty, namedCandidates.isEmpty == false {
            return .rejected(.unauthorizedSelection)
        }
        guard candidates.isEmpty == false else {
            return input.selectedCandidate == nil
                ? .notRecognized
                : .rejected(.staleClarification)
        }
        guard candidates.count == 1, let entity = candidates.first else {
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
                    ? .schemaDisplayName
                    : .clarificationSelection,
                confidence: input.selectedCandidate == nil
                    ? .exact
                    : .revalidatedClarification,
                binding: binding(input)
            )
        )
    }

    private func compileSingleField(
        _ input: GraphChatFoundationalIntentCompilerInput,
        normalizedQuestion: String
    ) -> GraphChatFoundationalIntentCompilation {
        let allowedNodes = allowedAttributeNodes(
            in: input.chatScope,
            schemaContext: input.schemaContext
        )
        let selected = input.selectedCandidate
        let namedNodes = input.schemaContext.aliases.nodesByKey.values
            .filter { $0.node.kind == .attribute }
            .filter { candidate in
                selected?.node.map { $0 == candidate.node } ?? true
            }
            .filter {
                matchesNodeName(
                    $0.displayName,
                    in: normalizedQuestion,
                    language: input.responseLanguage
                )
            }
        let strongestNodes = Self.strongestNodeMatches(
            namedNodes.filter { allowedNodes.contains($0.node) }
        )

        let fieldMatches = input.schemaContext.aliases.fieldsByAlias.values
            .compactMap {
                fieldMatch(
                    $0,
                    in: normalizedQuestion,
                    language: input.responseLanguage
                )
            }
        let exactFieldMatches = fieldMatches.filter { $0.usedSynonym == false }
        let strongestFields = exactFieldMatches.isEmpty
            ? fieldMatches
            : exactFieldMatches

        func makeCandidates(
            for nodes: [GraphSchemaNodeResolution]
        ) -> [SingleCandidate] {
            nodes.flatMap { node in
                strongestFields.compactMap {
                    fieldMatch -> SingleCandidate? in
                    guard
                        node.ownerEntityID
                            == fieldMatch.field.entityID,
                        selected?.entityID == nil
                            || selected?.entityID
                                == node.ownerEntityID,
                        selected?.node == nil
                            || selected?.node == node.node,
                        selected?.fieldID == nil
                            || selected?.fieldID
                                == fieldMatch.field.fieldID,
                        let entity =
                            input.schemaContext.aliases.entity(
                                id: node.ownerEntityID
                            ),
                        hasSafeSingleRemainder(
                            normalizedQuestion,
                            nodeName: node.displayName,
                            field: fieldMatch.field,
                            language: input.responseLanguage
                        )
                    else {
                        return nil
                    }
                    return SingleCandidate(
                        entity: entity,
                        node: node,
                        field: fieldMatch.field,
                        usedSynonym: fieldMatch.usedSynonym
                    )
                }
            }
            .sorted(by: Self.singleCandidateSort)
        }
        let candidates = makeCandidates(for: strongestNodes)

        guard candidates.isEmpty == false else {
            let unauthorizedNodes = Self.strongestNodeMatches(
                namedNodes.filter {
                    allowedNodes.contains($0.node) == false
                }
            )
            if makeCandidates(for: unauthorizedNodes).isEmpty == false {
                return .rejected(.unauthorizedSelection)
            }
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
        } else if candidate.usedSynonym {
            origin = .localizedFieldSynonym
            confidence = .constrainedSynonym
        } else {
            origin = .schemaDisplayName
            confidence = .exact
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

    private func fieldMatch(
        _ field: GraphSchemaFieldResolution,
        in normalizedQuestion: String,
        language: GraphChatResponseLanguage
    ) -> FieldMatch? {
        let normalizedName = Self.normalized(field.name)
        if Self.containsPhrase(normalizedName, in: normalizedQuestion) {
            return FieldMatch(field: field, usedSynonym: false)
        }

        let synonyms = localizedSynonyms(
            forCanonicalFieldName: normalizedName,
            language: language
        )
        guard synonyms.contains(where: {
            Self.containsPhrase($0, in: normalizedQuestion)
        }) else {
            return nil
        }
        return FieldMatch(field: field, usedSynonym: true)
    }

    private func localizedSynonyms(
        forCanonicalFieldName fieldName: String,
        language: GraphChatResponseLanguage
    ) -> [String] {
        let birthdayFieldNames = [
            "geburtsdatum",
            "geburtstag",
            "birth date",
            "date of birth",
            "birthday",
        ]
        guard birthdayFieldNames.contains(fieldName) else {
            return []
        }
        switch language {
        case .german:
            return ["geburtstag", "geburtsdatum"]
        case .english:
            return ["birthday", "birth date", "date of birth"]
        }
    }

    private func hasSafeSingleRemainder(
        _ question: String,
        nodeName: String,
        field: GraphSchemaFieldResolution,
        language: GraphChatResponseLanguage
    ) -> Bool {
        var tokens = question.split(separator: " ").map(String.init)
        guard let matchedNodePhrase = nodeMatchPhrases(
            for: nodeName,
            language: language
        ).first(where: {
            Self.containsPhrase($0, in: question)
        }),
            Self.removePhrase(matchedNodePhrase, from: &tokens)
        else {
            return false
        }
        let fieldName = Self.normalized(field.name)
        if Self.removePhrase(fieldName, from: &tokens) == false {
            let synonym = localizedSynonyms(
                forCanonicalFieldName: fieldName,
                language: language
            ).first {
                Self.containsPhrase($0, in: tokens.joined(separator: " "))
            }
            guard let synonym,
                  Self.removePhrase(synonym, from: &tokens) else {
                return false
            }
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
        return tokens.allSatisfy(allowed.contains)
    }

    private func matchesNodeName(
        _ nodeName: String,
        in normalizedQuestion: String,
        language: GraphChatResponseLanguage
    ) -> Bool {
        nodeMatchPhrases(
            for: nodeName,
            language: language
        ).contains {
            Self.containsPhrase($0, in: normalizedQuestion)
        }
    }

    private func nodeMatchPhrases(
        for nodeName: String,
        language: GraphChatResponseLanguage
    ) -> [String] {
        let normalizedName = Self.normalized(nodeName)
        var phrases = [normalizedName]
        let prefixTranslation: (source: String, target: String)?
        switch language {
        case .german:
            prefixTranslation = ("project", "projekt")
        case .english:
            prefixTranslation = ("projekt", "project")
        }
        if let prefixTranslation,
           normalizedName == prefixTranslation.source
            || normalizedName.hasPrefix("\(prefixTranslation.source) ") {
            let suffix = normalizedName.dropFirst(
                prefixTranslation.source.count
            )
            phrases.append(prefixTranslation.target + String(suffix))
        }
        return phrases
    }

    private func isCollectionShell(
        _ question: String,
        language: GraphChatResponseLanguage
    ) -> Bool {
        switch language {
        case .german:
            return Self.startsWithAny(
                question,
                phrases: [
                    "welche ",
                    "zeige mir alle ",
                    "zeig mir alle ",
                    "liste alle ",
                    "alle ",
                ]
            )
        case .english:
            return Self.startsWithAny(
                question,
                phrases: [
                    "which ",
                    "show me all ",
                    "list all ",
                    "what ",
                ]
            ) && (
                question.contains(" all ")
                    || question.hasPrefix("which ")
                    || question.contains(" have i ")
                    || question.contains(" are there")
            )
        }
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

    private func containsUnsupportedCollectionModifier(
        _ question: String,
        language: GraphChatResponseLanguage
    ) -> Bool {
        let phrases: [String]
        switch language {
        case .german:
            phrases = [
                " durchschnitt ",
                " durchschnittlich ",
                " hochste ",
                " niedrigste ",
                " summe ",
                " gruppier",
                " sortier",
                " filter",
                " mit status ",
                " deren ",
                " pro ",
                " je ",
                " warum ",
            ]
        case .english:
            phrases = [
                " average ",
                " highest ",
                " lowest ",
                " sum ",
                " group",
                " sort",
                " filter",
                " with status ",
                " whose ",
                " per ",
                " why ",
            ]
        }
        let padded = " \(question) "
        return phrases.contains { padded.contains($0) }
    }

    private func allowedAttributeNodes(
        in scope: GraphChatScope,
        schemaContext: GraphSchemaContext
    ) -> Set<NodeRefKey> {
        let allAttributes = schemaContext.aliases.nodesByKey.values
            .filter { $0.node.kind == .attribute }
        switch scope.target {
        case .graph:
            return Set(allAttributes.map(\.node))
        case .entity(let entityID):
            return Set(
                allAttributes
                    .filter { $0.ownerEntityID == entityID }
                    .map(\.node)
            )
        case .node(let node):
            return node.kind == .attribute ? [node] : []
        case .selection(let nodes):
            return Set(nodes.filter { $0.kind == .attribute })
        }
    }

    private func schemaIsInternallyConsistent(
        _ context: GraphSchemaContext
    ) -> Bool {
        let entities = Array(context.aliases.entitiesByAlias.values)
        let entityIDs = Set(entities.map(\.entityID))
        guard entityIDs.count == entities.count else {
            return false
        }
        let fields = Array(context.aliases.fieldsByAlias.values)
        guard Set(fields.map(\.fieldID)).count == fields.count,
              fields.allSatisfy({ field in
                context.aliases.entity(for: field.entityAlias)?
                    .entityID == field.entityID
                    && entityIDs.contains(field.entityID)
              }) else {
            return false
        }
        return context.aliases.nodesByKey.allSatisfy {
            node, resolution in
            node == resolution.node
                && entityIDs.contains(resolution.ownerEntityID)
                && (
                    context.aliases.nodeEntityIDs[node].map {
                        $0 == resolution.ownerEntityID
                    } ?? true
                )
                && context.aliases.owningEntityID(for: node)
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
            return schemaContext.aliases.owningEntityID(for: node) == entityID
                ? scope
                : nil
        case .selection(let nodes):
            let matchingNodes = nodes.filter {
                schemaContext.aliases.owningEntityID(for: $0) == entityID
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

    private static func strongestNodeMatches(
        _ values: [GraphSchemaNodeResolution]
    ) -> [GraphSchemaNodeResolution] {
        guard let maximumTokenCount = values.map({
            normalized($0.displayName).split(separator: " ").count
        }).max() else {
            return []
        }
        return values.filter {
            normalized($0.displayName).split(separator: " ").count
                == maximumTokenCount
        }
    }

    private static func normalized(_ value: String) -> String {
        BMSearch.fold(value)
            .components(
                separatedBy: CharacterSet.alphanumerics.inverted
            )
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
    }

    private static func containsPhrase(
        _ phrase: String,
        in value: String
    ) -> Bool {
        let phraseTokens = phrase.split(separator: " ")
        let valueTokens = value.split(separator: " ")
        guard phraseTokens.isEmpty == false,
              phraseTokens.count <= valueTokens.count else {
            return false
        }
        if phraseTokens.count == 1 {
            return valueTokens.contains(phraseTokens[0])
        }
        for start in 0...(valueTokens.count - phraseTokens.count) {
            let end = start + phraseTokens.count
            if Array(valueTokens[start..<end]) == phraseTokens {
                return true
            }
        }
        return false
    }

    private static func hasSafeCollectionRemainder(
        _ question: String,
        entityName: String,
        language: GraphChatResponseLanguage
    ) -> Bool {
        var questionTokens = question.split(separator: " ").map(String.init)
        let entityTokens = normalized(entityName)
            .split(separator: " ")
            .map(String.init)
        guard entityTokens.isEmpty == false,
              entityTokens.count <= questionTokens.count else {
            return false
        }
        var matchRange: Range<Int>?
        for start in 0...(questionTokens.count - entityTokens.count) {
            let end = start + entityTokens.count
            if Array(questionTokens[start..<end]) == entityTokens {
                matchRange = start..<end
                break
            }
        }
        guard let matchRange else {
            return false
        }
        questionTokens.removeSubrange(matchRange)
        let allowed: Set<String>
        switch language {
        case .german:
            allowed = [
                "alle",
                "es",
                "gemacht",
                "gibt",
                "habe",
                "ich",
                "liste",
                "mir",
                "auf",
                "welche",
                "zeig",
                "zeige",
            ]
        case .english:
            allowed = [
                "all",
                "are",
                "do",
                "exist",
                "have",
                "i",
                "list",
                "me",
                "show",
                "taken",
                "there",
                "which",
            ]
        }
        return questionTokens.allSatisfy(allowed.contains)
    }

    private static func removePhrase(
        _ phrase: String,
        from tokens: inout [String]
    ) -> Bool {
        let phraseTokens = phrase.split(separator: " ").map(String.init)
        guard phraseTokens.isEmpty == false,
              phraseTokens.count <= tokens.count else {
            return false
        }
        for start in 0...(tokens.count - phraseTokens.count) {
            let end = start + phraseTokens.count
            if Array(tokens[start..<end]) == phraseTokens {
                tokens.removeSubrange(start..<end)
                return true
            }
        }
        return false
    }

    private static func startsWithAny(
        _ value: String,
        phrases: [String]
    ) -> Bool {
        phrases.contains { value.hasPrefix($0) }
    }

    private static func entitySort(
        _ lhs: GraphSchemaEntityResolution,
        _ rhs: GraphSchemaEntityResolution
    ) -> Bool {
        if normalized(lhs.name) != normalized(rhs.name) {
            return normalized(lhs.name) < normalized(rhs.name)
        }
        return lhs.entityID.uuidString < rhs.entityID.uuidString
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
