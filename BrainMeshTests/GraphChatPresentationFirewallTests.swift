import Foundation
import Testing

@testable import BrainMesh

@Suite("Graph chat presentation firewall")
struct GraphChatPresentationFirewallTests {
    @Test
    func knownSchemaAndNodeAliasesAreReplacedWithoutDamagingMarkdown() async {
        let resources = makeRegistryResources(language: .german)
        await resources.registry.registerValidatedNode(
            alias: "N3",
            node: NodeRefKey(
                kind: .attribute,
                id: GraphChatTestSupport.projectAttributeID
            ),
            displayName: "Website-Relaunch"
        )
        let snapshot = await resources.registry.snapshot()
        let firewall = GraphChatPresentationFirewall()

        let result = firewall.present(
            """
            **E1**
            - F2: `N3`.
            """,
            using: snapshot
        )

        #expect(
            result
                == .safe(
                    """
                    **Projekte**
                    - Beschreibung: `Website-Relaunch`.
                    """
                )
        )
    }

    @Test
    func currentAndConversationReferencesRequireValidatedPresentation() async {
        let resources = makeRegistryResources(language: .english)
        let snapshot = await resources.registry.snapshot()
        let firewall = GraphChatPresentationFirewall()

        #expect(
            firewall.present(
                "Open CURRENT from CR_RESULTS.",
                using: snapshot
            )
                == .safe(
                    "Open Website Relaunch from the previous results."
                )
        )

        let unknownCurrent = firewall.present(
            "Open CURRENT.",
            using: .empty
        )
        guard case .unsafe(let currentContent) = unknownCurrent else {
            Issue.record("Expected CURRENT without a validated label to be unsafe.")
            return
        }
        #expect(currentContent.kind == .conversationReference)
        #expect(currentContent.identifier == "CURRENT")

        let unknownReference = firewall.present(
            "Use CR_UNKNOWN.",
            using: snapshot
        )
        guard case .unsafe(let referenceContent) = unknownReference else {
            Issue.record("Expected an unknown CR reference to be unsafe.")
            return
        }
        #expect(referenceContent.kind == .conversationReference)
    }

    @Test
    func unknownAliasAndUUIDReturnTypedUnsafeResults() {
        let firewall = GraphChatPresentationFirewall()
        let uuid = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"

        guard case .unsafe(let aliasContent) = firewall.present(
            "Unknown E99",
            using: .empty
        ) else {
            Issue.record("Expected an unknown alias to be unsafe.")
            return
        }
        #expect(aliasContent.kind == .alias)
        #expect(aliasContent.identifier == "E99")

        guard case .unsafe(let identifierContent) = firewall.present(
            "Reference \(uuid)",
            using: .empty
        ) else {
            Issue.record("Expected an unknown UUID to be unsafe.")
            return
        }
        #expect(identifierContent.kind == .technicalIdentifier)
        #expect(identifierContent.identifier == uuid)
    }

    @Test
    func validatedDisplayNamesCannotReintroduceTechnicalTokens() async {
        let resources = makeRegistryResources(language: .english)
        await resources.registry.registerValidatedNode(
            alias: "N99",
            node: NodeRefKey(
                kind: .attribute,
                id: UUID()
            ),
            displayName: "Project E99"
        )
        let snapshot = await resources.registry.snapshot()

        guard case .unsafe(let content) =
            GraphChatPresentationFirewall().present(
                "Open N99.",
                using: snapshot
            )
        else {
            Issue.record(
                "Expected a display name containing an unresolved alias to be unsafe."
            )
            return
        }
        #expect(content.kind == .alias)
        #expect(content.identifier == "E99")
    }

    @Test
    func ordinaryWordsAndSafeAnswersRemainUnchanged() {
        let text =
            "The current project is currently active; CURRENTLY and preE1post are ordinary words."
        #expect(
            GraphChatPresentationFirewall().present(
                text,
                using: .empty
            ) == .safe(text)
        )
    }

    @Test
    func cumulativeStreamingNeverPublishesACompleteInternalAlias() async {
        let resources = makeRegistryResources(language: .english)
        let streamFirewall = GraphChatPresentationStreamFirewall(
            registry: resources.registry,
            language: .english
        )

        let first = await streamFirewall.presentCumulativeText("E")
        let second = await streamFirewall.presentCumulativeText("E1")
        let third = await streamFirewall.presentCumulativeText(
            "E1 is active."
        )

        #expect(first == nil)
        #expect(second == "Projekte")
        #expect(third == "Projekte is active.")
        #expect([first, second, third].compactMap { $0 }.contains("E1") == false)
    }

    @Test
    func answerSectionsFiltersFollowUpsAndClarificationAreProtected() async throws {
        let resources = makeRegistryResources(language: .english)
        let snapshot = await resources.registry.snapshot()
        let context = GraphChatPresentationContext(
            registry: snapshot,
            language: .english
        )
        let answer = GraphChatAnswer(
            state: .clarification(
                GraphChatClarification(
                    id: UUID(),
                    question: "Which CURRENT?",
                    options: [
                        GraphChatClarificationOption(
                            id: "one",
                            title: "Use E1"
                        )
                    ]
                )
            ),
            directAnswer: "Which CURRENT?",
            sections: [
                GraphChatAnswerSection(
                    title: "About E1",
                    text: "F2 belongs to CURRENT."
                )
            ],
            appliedFilters: [
                GraphChatAppliedFilter(
                    fieldName: "F2",
                    operationDescription: "matches E1",
                    valueDescription: "CURRENT"
                )
            ],
            followUpSuggestions: [
                GraphChatFollowUpSuggestion(
                    title: "Open E1",
                    prompt: "Show CURRENT"
                )
            ],
            hasInsufficientEvidence: true
        )

        let result = GraphChatPresentationFirewall().present(
            answer,
            context: context
        )
        guard case .safe(let safeAnswer) = result else {
            Issue.record("Expected all registered aliases to be presentable.")
            return
        }

        #expect(safeAnswer.directAnswer == "Which Website Relaunch?")
        #expect(safeAnswer.sections.first?.title == "About Projekte")
        #expect(
            safeAnswer.sections.first?.text
                == "Beschreibung belongs to Website Relaunch."
        )
        #expect(safeAnswer.appliedFilters.first?.fieldName == "Beschreibung")
        #expect(
            safeAnswer.followUpSuggestions.first?.prompt
                == "Show Website Relaunch"
        )
        guard case .clarification(let clarification) = safeAnswer.state else {
            Issue.record("Expected the clarification state to be retained.")
            return
        }
        #expect(clarification.question == "Which Website Relaunch?")
        #expect(clarification.options.first?.title == "Use Projekte")
    }

    @Test
    func unsafeFallbackIsLocalizedInGermanAndEnglish() {
        let firewall = GraphChatPresentationFirewall()
        let german = firewall.replacementAnswer(
            language: .german,
            registry: .empty
        )
        let english = firewall.replacementAnswer(
            language: .english,
            registry: .empty
        )

        #expect(
            german.directAnswer
                == GraphChatResponseLocalizer(
                    language: .german
                ).unsafePresentation()
        )
        #expect(
            english.directAnswer
                == GraphChatResponseLocalizer(
                    language: .english
                ).unsafePresentation()
        )
    }

    @Test
    func fullProviderTurnProtectsStreamingFinalStateAndCopy() async throws {
        let provider = FakeGraphChatModelProvider(
            scripts: [
                FakeGraphChatProviderScript(
                    steps: [
                        .event(
                            .partialAnswer(
                                GraphChatProviderPartialAnswer(
                                    directAnswer: "E",
                                    hasInsufficientEvidence: nil
                                )
                            )
                        ),
                        .event(
                            .partialAnswer(
                                GraphChatProviderPartialAnswer(
                                    directAnswer: "E1 is active.",
                                    hasInsufficientEvidence: nil
                                )
                            )
                        ),
                        .event(
                            .completed(
                                GraphChatProviderTestSupport.makeFinalAnswer(
                                    directAnswer: "E1 is active.",
                                    sections: [
                                        GraphChatProviderAnswerSection(
                                            title: "About E1",
                                            text: "F2 is available.",
                                            evidenceIDValues: []
                                        )
                                    ],
                                    followUpSuggestions: [
                                        GraphChatProviderFollowUpSuggestion(
                                            title: "Open E1",
                                            prompt: "Show F2 for E1"
                                        )
                                    ],
                                    hasInsufficientEvidence: true
                                )
                            )
                        )
                    ]
                )
            ]
        )
        let orchestrator = GraphChatProviderTestSupport.makeOrchestrator(
            provider: provider,
            factory: EvidenceRegisteringFakeToolRunnerFactory(),
            responseLanguageSelector: GraphChatResponseLanguageSelector(
                fallback: .english
            )
        )
        let graphScope = GraphScope(
            graphID: GraphChatTestSupport.graphID
        )
        let events = await GraphChatProviderTestSupport.collect(
            await orchestrator.streamAnswer(
                question: "What is the current project status?",
                graphScope: graphScope,
                chatScope: .entireGraph(graphScope)
            )
        )

        let partials = events.compactMap { event -> String? in
            guard case .partialAnswer(let text) = event else {
                return nil
            }
            return text
        }
        #expect(partials == ["Projekte is active."])
        #expect(partials.contains(where: { $0.contains("E1") }) == false)

        var messageState = GraphChatAssistantMessageState(
            question: "What is the current project status?"
        )
        for event in events {
            messageState.apply(event)
        }
        #expect(messageState.text == "Projekte is active.")
        #expect(
            messageState.answer?.sections.first?.text
                == "Beschreibung is available."
        )
        #expect(
            messageState.answer?.followUpSuggestions.first?.prompt
                == "Show Beschreibung for Projekte"
        )

        let copyPayload = try #require(
            GraphChatCopyContentBuilder.payload(
                for: messageState,
                sourcePolicy: .none
            )
        )
        #expect(copyPayload.text.contains("Projekte is active."))
        #expect(copyPayload.text.contains("Beschreibung is available."))
        #expect(copyPayload.text.contains("E1") == false)
        #expect(copyPayload.text.contains("F2") == false)
    }

    @Test
    func fullProviderTurnUsesLocalizedFallbackForUnknownAlias() async throws {
        let provider = FakeGraphChatModelProvider(
            scripts: [
                FakeGraphChatProviderScript(
                    steps: [
                        .event(
                            .completed(
                                GraphChatProviderTestSupport.makeFinalAnswer(
                                    directAnswer: "E99 ist aktiv.",
                                    hasInsufficientEvidence: true
                                )
                            )
                        )
                    ]
                )
            ]
        )
        let orchestrator = GraphChatProviderTestSupport.makeOrchestrator(
            provider: provider,
            factory: EvidenceRegisteringFakeToolRunnerFactory(),
            responseLanguageSelector: GraphChatResponseLanguageSelector(
                fallback: .german
            )
        )
        let graphScope = GraphScope(
            graphID: GraphChatTestSupport.graphID
        )
        let events = await GraphChatProviderTestSupport.collect(
            await orchestrator.streamAnswer(
                question: "Welches Projekt ist aktiv?",
                graphScope: graphScope,
                chatScope: .entireGraph(graphScope)
            )
        )
        let answer = try #require(
            events.compactMap { event -> GraphChatAnswer? in
                guard case .completed(let answer) = event else {
                    return nil
                }
                return answer
            }.last
        )

        #expect(
            answer.directAnswer
                == GraphChatResponseLocalizer(
                    language: .german
                ).unsafePresentation()
        )
        #expect(answer.directAnswer.contains("E99") == false)
        #expect(answer.sections.isEmpty)
        #expect(answer.followUpSuggestions.isEmpty)
    }

    @Test
    func providerFailureCannotExposeUnknownTechnicalContent() async throws {
        let technicalID = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        let provider = FakeGraphChatModelProvider(
            scripts: [
                FakeGraphChatProviderScript(
                    steps: [
                        .failure(
                            GraphChatProviderError(
                                code: .toolFailure,
                                message:
                                    "Unknown E99 referenced \(technicalID)."
                            )
                        )
                    ]
                )
            ]
        )
        let orchestrator = GraphChatProviderTestSupport.makeOrchestrator(
            provider: provider,
            factory: EvidenceRegisteringFakeToolRunnerFactory(),
            responseLanguageSelector: GraphChatResponseLanguageSelector(
                fallback: .english
            )
        )
        let graphScope = GraphScope(
            graphID: GraphChatTestSupport.graphID
        )
        let events = await GraphChatProviderTestSupport.collect(
            await orchestrator.streamAnswer(
                question: "What happened?",
                graphScope: graphScope,
                chatScope: .entireGraph(graphScope)
            )
        )
        let error = try #require(
            events.compactMap { event -> GraphChatError? in
                guard case .failure(let error) = event else {
                    return nil
                }
                return error
            }.last
        )

        #expect(error.code == .toolFailure)
        #expect(
            error.message
                == GraphChatResponseLocalizer(
                    language: .english
                ).userFacingFailure(.toolFailure)
        )
        #expect(error.message.contains("E99") == false)
        #expect(error.message.contains(technicalID) == false)
    }

    private func makeRegistryResources(
        language: GraphChatResponseLanguage
    ) -> (
        registry: GraphChatPresentationRegistry,
        context: GraphChatConversationContextSnapshot
    ) {
        let graphScope = GraphScope(
            graphID: GraphChatTestSupport.graphID
        )
        let chatScope = GraphChatScope.entireGraph(graphScope)
        let context = GraphChatConversationContextSnapshot(
            conversationID: UUID(),
            graphScope: graphScope,
            chatScope: chatScope,
            aliases: [
                GraphChatConversationContextAlias(
                    alias: "CURRENT",
                    label: "Website Relaunch",
                    target: .node(
                        NodeRefKey(
                            kind: .attribute,
                            id: GraphChatTestSupport.projectAttributeID
                        ),
                        ownerEntityID: GraphChatTestSupport.projectEntityID
                    ),
                    ordinal: nil
                ),
                GraphChatConversationContextAlias(
                    alias: "CR_RESULTS",
                    label: "Three projects",
                    target: .resultSet(
                        UUID(),
                        nodes: [
                            NodeRefKey(
                                kind: .attribute,
                                id: GraphChatTestSupport.projectAttributeID
                            )
                        ],
                        entityID: GraphChatTestSupport.projectEntityID
                    ),
                    ordinal: nil
                ),
            ],
            results: [],
            turns: [],
            latestResultAlias: "CR_RESULTS",
            lastEntityAlias: "E1",
            lastFieldAlias: "F2",
            lastGroupAlias: nil,
            lastNodeAlias: nil,
            lastComparisonAlias: nil,
            currentReferenceAlias: "CURRENT",
            lastValidatedQuery: nil,
            resultRevalidations: [],
            pendingClarificationID: nil
        )
        return (
            GraphChatPresentationRegistry(
                schemaContext: GraphChatTestSupport.makeSchemaContext(),
                conversationContext: context,
                language: language
            ),
            context
        )
    }
}
