//
//  GraphChatProviderRequestBuilder.swift
//  BrainMesh
//
//  Pure construction and deterministic reduction of provider requests.
//

import Foundation

nonisolated struct GraphChatProviderRequestBuilder: Hashable, Sendable {
    func makeRequest(
        resources: GraphChatProviderSessionResources,
        question: String,
        continuationOperation: GraphChatConversationContinuationOperation?,
        contextProfile: GraphChatModelContextProfile,
        toolRepairContext: GraphChatToolRepairResult? = nil
    ) -> GraphChatModelRequest {
        GraphChatModelRequest(
            question: boundedQuestion(
                question,
                maximumLength: contextProfile.maximumQuestionCharacters,
                language: resources.responseLanguage
            ),
            schemaPrompt: schemaPrompt(
                from: resources.schemaContext,
                chatScope: resources.key.chatScope,
                language: resources.responseLanguage,
                profile: contextProfile
            ),
            conversationContext: reducedConversationContext(
                resources.conversationContext,
                profile: contextProfile
            ),
            responseLanguage: resources.responseLanguage,
            continuationOperation: continuationOperation,
            contextProfile: contextProfile,
            toolRepairContext: toolRepairContext
        )
    }

    func initialContextProfile(
        schemaContext: GraphSchemaContext,
        chatScope: GraphChatScope,
        conversationContext: GraphChatConversationContextSnapshot,
        question: String,
        responseLanguage: GraphChatResponseLanguage,
        planner: GraphChatInitialContextProfilePlanner
    ) -> GraphChatModelContextProfile {
        let standardSchema = schemaPrompt(
            from: schemaContext,
            chatScope: chatScope,
            language: responseLanguage,
            profile: .standard
        )
        let standardConversation = GraphChatConversationContextFormatter().format(
            conversationContext,
            language: responseLanguage,
            maximumCharacters:
                GraphChatModelContextProfile.standard.maximumConversationCharacters
        )
        return planner.profile(
            for: GraphChatInitialContextProfileInput(
                schemaPrompt: standardSchema,
                conversationContext: standardConversation,
                question: question,
                systemInstructions: systemInstructions(
                    for: chatScope,
                    language: responseLanguage
                )
            )
        )
    }

    func reducedConversationContext(
        _ context: GraphChatConversationContextSnapshot,
        profile: GraphChatModelContextProfile
    ) -> GraphChatConversationContextSnapshot {
        guard profile != .standard else {
            return context
        }

        let resultLimit = profile == .compact ? 2 : 1
        let itemLimit = profile == .compact ? 16 : 6
        let groupLimit = profile == .compact ? 6 : 2
        let supplementalAliasLimit = profile == .compact ? 16 : 4
        let retainedResults = context.results.suffix(resultLimit).map { result in
            GraphChatConversationContextResult(
                id: result.id,
                alias: result.alias,
                kind: result.kind,
                state: result.state,
                entityAlias: result.entityAlias,
                itemAliases: Array(result.itemAliases.prefix(itemLimit)),
                groupAliases: Array(result.groupAliases.prefix(groupLimit)),
                sourceReferenceCount: result.sourceReferenceCount,
                appliedFilters: Array(result.appliedFilters.prefix(4)),
                technicalDescription: bounded(
                    result.technicalDescription,
                    limit: 120
                )
            )
        }

        var requiredAliases = Set<String>()
        for result in retainedResults {
            requiredAliases.insert(result.alias)
            if let entityAlias = result.entityAlias {
                requiredAliases.insert(entityAlias)
            }
            requiredAliases.formUnion(result.itemAliases)
            requiredAliases.formUnion(result.groupAliases)
        }
        [
            context.latestResultAlias,
            context.lastEntityAlias,
            context.lastFieldAlias,
            context.lastGroupAlias,
            context.lastNodeAlias,
            context.lastComparisonAlias,
            context.currentReferenceAlias,
        ].compactMap { $0 }.forEach { requiredAliases.insert($0) }

        let supplementalAliases = context.aliases.reversed().filter {
            requiredAliases.contains($0.alias) == false
        }.prefix(supplementalAliasLimit).map(\.alias)
        requiredAliases.formUnion(supplementalAliases)

        let aliases = context.aliases.compactMap {
            alias -> GraphChatConversationContextAlias? in
            guard requiredAliases.contains(alias.alias) else {
                return nil
            }
            return compactAlias(
                alias,
                itemLimit: itemLimit,
                comparisonLimit: profile == .compact ? 6 : 2
            )
        }
        let availableAliases = Set(aliases.map(\.alias))

        return GraphChatConversationContextSnapshot(
            conversationID: context.conversationID,
            graphScope: context.graphScope,
            chatScope: context.chatScope,
            aliases: aliases,
            results: retainedResults,
            turns: profile == .compact ? Array(context.turns.suffix(1)) : [],
            latestResultAlias: retainedAlias(
                context.latestResultAlias,
                in: availableAliases
            ),
            lastEntityAlias: retainedAlias(
                context.lastEntityAlias,
                in: availableAliases
            ),
            lastFieldAlias: retainedAlias(
                context.lastFieldAlias,
                in: availableAliases
            ),
            lastGroupAlias: retainedAlias(
                context.lastGroupAlias,
                in: availableAliases
            ),
            lastNodeAlias: retainedAlias(
                context.lastNodeAlias,
                in: availableAliases
            ),
            lastComparisonAlias: retainedAlias(
                context.lastComparisonAlias,
                in: availableAliases
            ),
            currentReferenceAlias: retainedAlias(
                context.currentReferenceAlias,
                in: availableAliases
            ),
            currentResolvedScope:
                retainedAlias(
                    context.currentReferenceAlias,
                    in: availableAliases
                ) == nil
                ? nil
                : context.currentResolvedScope,
            lastValidatedQuery: profile == .compact
                ? context.lastValidatedQuery
                : nil,
            resultRevalidations: context.resultRevalidations.filter { revalidation in
                retainedResults.contains { result in
                    result.alias == revalidation.resultAlias
                }
            },
            pendingClarificationID: context.pendingClarificationID
        )
    }

    func schemaPrompt(
        from context: GraphSchemaContext,
        chatScope: GraphChatScope,
        language: GraphChatResponseLanguage,
        profile: GraphChatModelContextProfile
    ) -> String {
        var lines: [String]
        switch language {
        case .german:
            lines = [
                "Graph: \(context.snapshot.graphName)",
                "Schema-Version: \(context.snapshot.version)",
                "Scope: \(scopeDescription(chatScope.target, language: language))",
            ]
        case .english:
            lines = [
                "Graph: \(context.snapshot.graphName)",
                "Schema version: \(context.snapshot.version)",
                "Scope: \(scopeDescription(chatScope.target, language: language))",
            ]
        }

        for entity in context.snapshot.entities {
            lines.append("\(entity.alias.rawValue): \(entity.name)")
            for field in entity.fields {
                var details =
                    "  \(field.alias.rawValue): \(field.name) [\(field.type.rawValue)]"
                if profile != .recovery,
                    let unit = field.unit,
                    unit.isEmpty == false
                {
                    details += " unit=\(unit)"
                }
                if profile == .standard, field.choiceOptions.isEmpty == false {
                    let choices = field.choiceOptions.prefix(6).joined(separator: ", ")
                    details += " choices=\(choices)"
                }
                lines.append(details)
            }
        }
        if context.snapshot.truncation.isTruncated {
            switch language {
            case .german:
                lines.append(
                    "Schema begrenzt; nutze describeGraphSchema für Details."
                )
            case .english:
                lines.append(
                    "Schema is bounded; use describeGraphSchema for details."
                )
            }
        }
        return bounded(
            lines.joined(separator: "\n"),
            limit: profile.maximumSchemaCharacters
        )
    }

    func systemInstructions(
        for scope: GraphChatScope,
        language: GraphChatResponseLanguage
    ) -> String {
        switch language {
        case .german:
            return """
                \(GraphChatResponseLocalizer(language: language).providerInstruction())
                Beantworte nur Fragen zum aktiven BrainMesh-Graphen und Scope mit den registrierten read-only Tools.
                Graph-Fakten dürfen ausschließlich aus Tool-Ergebnissen dieser Anfrage stammen. Benenne fehlende oder mehrdeutige Daten; rate niemals.
                Evidence- und Artifact-UUIDs dürfen nur unverändert aus Tool-Ergebnissen übernommen werden. Erfinde keine IDs oder strukturierten Werte.
                Tabellen, Rankings, Gruppen, Kennzahlen und Ergebniszeilen gehören in Artifacts; erkläre sie knapp, ohne sämtliche Zeilen zu wiederholen.
                Biete keine Schreib-, Änderungs-, Lösch-, Import-, Upload- oder sonstige Mutationsaktion an.
                Attachments liefern nur Metadaten. Behaupte niemals, Datei-, Bild-, PDF- oder Binärinhalte gelesen zu haben.
                Nutze ausschließlich Aliase aus Schema, vertrauenswürdigem Konversations-Snapshot oder Tool-Ergebnissen. Aliase sind opak und werden appseitig revalidiert.
                Ein Tool-Ergebnis mit status repairRequired erlaubt genau einen vollständigen Korrekturaufruf mit ausschließlich den darin validierten Optionen. Zitiere Repair-Metadaten niemals in der sichtbaren Antwort. Bei repairFailed oder repairBudgetExhausted darf kein weiterer Repair-Aufruf erfolgen; stelle stattdessen eine fachliche Rückfrage.
                Konversationsreferenzen sind Vorschläge. Nutze clarification nur bei echter Mehrdeutigkeit mit validierten Optionen. Fehlt lokaler Referenzkontext, behandle die aktuelle Frage normal statt eine Referenz zu unterstellen.
                Nutze queryDetailValues.conversationReferenceAlias für Operationen über eine validierte frühere Ergebnismenge.
                noResults ist nur nach einem entsprechenden gültigen Tool-Ergebnis erlaubt. unsupported gilt für Graph-Mutationen, Attachment-Inhalte, Multi-Hop-Pfade und Query-Plan-v2-Funktionen.
                Antworte normalerweise in zwei bis vier klaren Sätzen: zuerst direkt, danach kurze Begründung oder Einschränkung. Setze hasInsufficientEvidence bei fehlender verlässlicher Tool-Evidence.
                Nenne bei Begriffen wie wichtig, dringend, relevant oder offen die konkret verwendeten Filter. Folgefragen bleiben optional, read-only und im selben Scope.
                Aktiver Scope: \(scopeDescription(scope.target, language: language)).
                """
        case .english:
            return """
                \(GraphChatResponseLocalizer(language: language).providerInstruction())
                Answer only questions about the active BrainMesh graph and scope with the registered read-only tools.
                Graph facts must come only from tool results in this request. State missing or ambiguous data and never guess.
                Evidence and Artifact UUIDs may only be copied unchanged from tool results. Never invent IDs or structured values.
                Tables, rankings, groups, metrics, and result rows belong in Artifacts; explain them briefly without repeating every row.
                Never offer a write, edit, delete, import, upload, or other mutation action.
                Attachments expose metadata only. Never claim to have read file, image, PDF, or binary contents.
                Use only aliases from the schema, trusted conversation snapshot, or tool results. Aliases are opaque and revalidated by the app.
                A tool result with status repairRequired permits exactly one complete corrected tool call using only its validated options. Never quote repair metadata in the visible answer. After repairFailed or repairBudgetExhausted, do not attempt another repair; ask a domain clarification instead.
                Conversation references are proposals. Use clarification only for genuine ambiguity with validated options. When local reference context is absent, handle the current question normally instead of assuming a reference.
                Use queryDetailValues.conversationReferenceAlias for operations over a validated previous result set.
                noResults is allowed only after a matching valid tool result. unsupported applies to graph mutations, attachment contents, multi-hop paths, and Query Plan v2 features.
                Normally answer in two to four clear sentences: answer directly first, then add a brief reason or limitation. Mark hasInsufficientEvidence when reliable tool evidence is missing.
                For terms such as important, urgent, relevant, or open, state the concrete applied filters. Follow-ups remain optional, read-only, and in the same scope.
                Active scope: \(scopeDescription(scope.target, language: language)).
                """
        }
    }

    func prewarmPromptPrefix(
        language: GraphChatResponseLanguage
    ) -> String {
        language == .german
            ? "Es folgt eine read-only Frage zum aktiven Graphen."
            : "A read-only question about the active graph will follow."
    }

    private func compactAlias(
        _ alias: GraphChatConversationContextAlias,
        itemLimit: Int,
        comparisonLimit: Int
    ) -> GraphChatConversationContextAlias {
        let target: GraphChatConversationContextAliasTarget
        switch alias.target {
        case .resultSet(let id, let nodes, let entityID):
            target = .resultSet(
                id,
                nodes: Array(nodes.prefix(itemLimit)),
                entityID: entityID
            )
        case .group(let id, let nodes, let fieldID, let count):
            target = .group(
                id,
                nodes: Array(nodes.prefix(itemLimit)),
                fieldID: fieldID,
                count: count
            )
        case .comparison(let references):
            target = .comparison(Array(references.prefix(comparisonLimit)))
        case .node, .entity, .field:
            target = alias.target
        }
        return GraphChatConversationContextAlias(
            alias: alias.alias,
            label: bounded(alias.label, limit: 120),
            target: target,
            ordinal: alias.ordinal
        )
    }

    private func retainedAlias(
        _ alias: String?,
        in availableAliases: Set<String>
    ) -> String? {
        guard let alias, availableAliases.contains(alias) else {
            return nil
        }
        return alias
    }

    private func scopeDescription(
        _ target: GraphChatScopeTarget,
        language: GraphChatResponseLanguage
    ) -> String {
        switch (language, target) {
        case (.german, .graph):
            return "gesamter Graph"
        case (.english, .graph):
            return "entire graph"
        case (.german, .entity):
            return "einzelne Entity"
        case (.english, .entity):
            return "single entity"
        case (.german, .node):
            return "einzelner Node"
        case (.english, .node):
            return "single node"
        case (.german, .selection(let nodes)):
            return "Auswahl aus \(nodes.count) Nodes"
        case (.english, .selection(let nodes)):
            return "selection of \(nodes.count) nodes"
        }
    }

    private func boundedQuestion(
        _ value: String,
        maximumLength: Int,
        language: GraphChatResponseLanguage
    ) -> String {
        guard value.count > maximumLength else {
            return value
        }
        let marker: String
        switch language {
        case .german:
            marker = "\n[Frage appseitig gekürzt]\n"
        case .english:
            marker = "\n[Question shortened by the app]\n"
        }
        let availableLength = max(2, maximumLength - marker.count)
        let prefixLength = max(1, availableLength * 2 / 3)
        let suffixLength = max(1, availableLength - prefixLength)
        return String(value.prefix(prefixLength))
            + marker
            + String(value.suffix(suffixLength))
    }

    private func bounded(_ value: String, limit: Int) -> String {
        guard value.count > limit else {
            return value
        }
        return String(value.prefix(limit))
    }
}
