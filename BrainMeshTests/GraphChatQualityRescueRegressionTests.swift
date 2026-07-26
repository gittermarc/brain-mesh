import Foundation
import Testing
@testable import BrainMesh

@Suite("Graph chat quality rescue regression")
struct GraphChatQualityRescueRegressionTests {
    @Test
    func aliasesAndUUIDsAreRejectedAcrossAllVisibleAnswerSurfaces() {
        let technicalID =
            "77777777-7777-4777-8777-777777777777"
        let candidates = [
            GraphChatAnswer(
                directAnswer: "E1 is open.",
                hasInsufficientEvidence: true
            ),
            GraphChatAnswer(
                directAnswer: "Safe answer.",
                sections: [
                    GraphChatAnswerSection(
                        title: "Details",
                        text: "F2 is available."
                    )
                ],
                hasInsufficientEvidence: true
            ),
            GraphChatAnswer(
                directAnswer: "Safe answer.",
                appliedFilters: [
                    GraphChatAppliedFilter(
                        fieldName: "Status",
                        operationDescription: "equals",
                        valueDescription: "CR_RESULTS"
                    )
                ],
                hasInsufficientEvidence: true
            ),
            GraphChatAnswer(
                directAnswer: "Safe answer.",
                followUpSuggestions: [
                    GraphChatFollowUpSuggestion(
                        title: "Open it",
                        prompt: "Open \(technicalID)"
                    )
                ],
                hasInsufficientEvidence: true
            ),
        ]
        let firewall = GraphChatPresentationFirewall()
        let context = GraphChatPresentationContext(
            registry: .empty,
            language: .english
        )

        for candidate in candidates {
            guard case .unsafe = firewall.present(
                candidate,
                context: context
            ) else {
                Issue.record(
                    "Expected every technical visible surface to be rejected."
                )
                continue
            }
        }
    }

    @Test
    func splitAliasIsBufferedUntilItsSafeDisplayNameCanBePublished() async {
        let graphScope = GraphScope(graphID: GraphChatTestSupport.graphID)
        let state = GraphChatConversationState.initial(
            graphScope: graphScope,
            chatScope: .entireGraph(graphScope)
        )
        let registry = GraphChatPresentationRegistry(
            schemaContext: GraphChatTestSupport.makeSchemaContext(),
            conversationContext: GraphChatConversationContextBuilder()
                .makeSnapshot(from: state.snapshot),
            language: .english
        )
        let stream = GraphChatPresentationStreamFirewall(
            registry: registry,
            language: .english
        )

        let incomplete = await stream.presentCumulativeText("E")
        let complete = await stream.presentCumulativeText("E1")
        let sentence = await stream.presentCumulativeText(
            "E1 contains twelve projects."
        )

        #expect(incomplete == nil)
        #expect(complete == "Projekte")
        #expect(sentence == "Projekte contains twelve projects.")
        #expect([complete, sentence].compactMap { $0 }.contains("E1") == false)
    }

    @Test
    func listFallbackUsesBoundedDisplayNamesInGermanAndEnglish() throws {
        let fixture = QualityRescueFallbackFixture()
        let germanSource = fixture.listSource(entityLabel: "Projekte")
        let englishSource = fixture.listSource(entityLabel: "projects")
        let renderer = GraphChatDeterministicAnswerFallbackRenderer()

        let german = renderer.render(
            source: germanSource,
            language: .german
        )
        let english = renderer.render(
            source: englishSource,
            language: .english
        )

        #expect(
            german
                == "Ich habe 12 Projekte gefunden. Die ersten Ergebnisse sind Website-Relaunch, Mobile App und Kundenportal."
        )
        #expect(
            english
                == "I found 12 projects. The first results are Website Relaunch, Mobile App and Customer Portal."
        )
        #expect(german.contains("E1") == false)
        #expect(english.contains("CURRENT") == false)
        #expect(
            fixture.containsTechnicalIdentifier(
                german + "\n" + english
            ) == false
        )
    }

    @Test
    func countGroupingHealthAndComparisonFallbacksUseOnlyFormattedValues() {
        let fixture = QualityRescueFallbackFixture()
        let renderer = GraphChatDeterministicAnswerFallbackRenderer()

        let count = renderer.render(
            source: fixture.metricSource(),
            language: .german
        )
        let grouping = renderer.render(
            source: fixture.groupingSource(),
            language: .german
        )
        let health = renderer.render(
            source: fixture.healthSource(),
            language: .english
        )
        let comparison = renderer.render(
            source: fixture.comparisonSource(),
            language: .english
        )

        #expect(count == "Anzahl Projekte: 12.")
        #expect(
            grouping
                == "Ich habe 12 Projekte in 2 Gruppen zusammengefasst. Die ersten Gruppen sind Offen: 4 und Erledigt: 8."
        )
        #expect(
            health
                == "2 isolated nodes across 3 health findings."
        )
        #expect(comparison.contains("Website Relaunch"))
        #expect(comparison.contains("Mobile App"))
        #expect(comparison.contains("Status"))
        #expect(
            fixture.containsTechnicalIdentifier(
                [count, grouping, health, comparison].joined(separator: "\n")
            ) == false
        )
    }

    @Test
    func fallbackPolicyPreservesSafeTextAndRejectsEmptyTechnicalAndContradictoryText() {
        let fixture = QualityRescueFallbackFixture()
        let source = fixture.listSource(entityLabel: "projects")
        let policy = GraphChatDeterministicAnswerFallbackPolicy()

        #expect(
            policy.fallbackReason(
                for: fixture.answer(
                    "I found 12 projects. The first results include Website Relaunch."
                ),
                source: source
            ) == nil
        )
        #expect(
            policy.fallbackReason(
                for: fixture.answer(" \n "),
                source: source
            ) == .emptyAnswer
        )
        #expect(
            policy.fallbackReason(
                for: fixture.answer(
                    "RepositoryError: QueryDetailValuesTool failed."
                ),
                source: source
            ) == .technicalText
        )
        #expect(
            policy.fallbackReason(
                for: fixture.answer("No results were found."),
                source: source
            ) == .contradictoryNoResults
        )
        #expect(
            policy.fallbackReason(
                for: fixture.answer("I found 99 results."),
                source: source
            ) == .contradictoryCount
        )
        #expect(
            policy.fallbackReason(
                for: fixture.answer("This request is not supported."),
                source: source
            ) == .contradictoryState
        )
        #expect(
            policy.fallbackReason(
                for: fixture.answer(
                    "I found 12 projects.",
                    sections: [
                        GraphChatAnswerSection(
                            text: "ResolverError: CURRENT invalid."
                        )
                    ]
                ),
                source: source
            ) == .technicalText
        )
    }

    @Test
    func normalAnswerAndPublicFailureCannotReachTheUIEmptyOrTechnical() throws {
        var emptyAnswerState = GraphChatAssistantMessageState(
            question: "Welche Projekte sind offen?"
        )
        emptyAnswerState.apply(
            .completed(
                GraphChatAnswer(
                    directAnswer: "   ",
                    hasInsufficientEvidence: true,
                    presentationContext: GraphChatPresentationContext(
                        registry: .empty,
                        language: .german
                    )
                )
            )
        )

        #expect(emptyAnswerState.phase == .final)
        #expect(emptyAnswerState.text.isEmpty == false)
        #expect(
            emptyAnswerState.text
                == GraphChatResponseLocalizer(language: .german)
                    .answerUnavailable()
        )

        var failureState = GraphChatAssistantMessageState(
            question: "Which projects are open?"
        )
        failureState.apply(
            .failure(
                GraphChatError(
                    code: .toolFailure,
                    message:
                        "GraphChatSyntheticRepositoryError for E1 and 33333333-3333-3333-3333-333333333333"
                )
            )
        )
        let error = try #require(failureState.error)
        #expect(
            error.message
                == GraphChatResponseLocalizer(language: .english)
                    .userFacingFailure(.toolFailure)
        )
        #expect(error.message.contains("Repository") == false)
        #expect(error.message.contains("E1") == false)
        #expect(error.message.contains("33333333") == false)
    }

    @Test
    func everyPublicFailureCodeDiscardsRawProviderToolResolverAndRepositoryMessages() {
        let mapper = GraphChatProviderErrorMapper()
        let rawMessages = [
            "ToolError: E1 failed",
            "ResolverError: CURRENT invalid",
            "ProviderError: CR_CURRENT invalid",
            "RepositoryError: 44444444-4444-4444-4444-444444444444",
        ]

        for (index, code) in GraphChatErrorCode.allCases.enumerated() {
            let mapped = mapper.mapForPresentation(
                GraphChatError(
                    code: code,
                    message: rawMessages[index % rawMessages.count]
                ),
                language: index.isMultiple(of: 2) ? .german : .english
            )
            #expect(mapped.code == code)
            #expect(rawMessages.contains(mapped.message) == false)
            #expect(mapped.message.contains("E1") == false)
            #expect(mapped.message.contains("CURRENT") == false)
            #expect(mapped.message.contains("CR_") == false)
            #expect(mapped.message.contains("44444444") == false)
        }
    }

    @Test
    func copyUsesExactlyTheSafeFinalFallbackContent() throws {
        let fixture = QualityRescueFallbackFixture()
        let source = fixture.listSource(entityLabel: "Projekte")
        let text = GraphChatDeterministicAnswerFallbackRenderer().render(
            source: source,
            language: .german
        )
        var state = GraphChatAssistantMessageState(
            question: "Welche Projekte sind offen?"
        )
        state.apply(
            .completed(
                GraphChatAnswer(
                    directAnswer: text,
                    evidence: source.evidence,
                    artifactIDs: source.artifacts.map(\.id),
                    hasInsufficientEvidence: false,
                    presentationContext: GraphChatPresentationContext(
                        registry: .empty,
                        language: .german
                    )
                )
            )
        )

        let copy = try #require(
            GraphChatCopyContentBuilder.payload(
                for: state,
                sourcePolicy: .none
            )
        )
        #expect(copy.text == state.text)
        #expect(copy.text == text)
        #expect(fixture.containsTechnicalIdentifier(copy.text) == false)
    }
}

private struct QualityRescueFallbackFixture {
    private let graphScope = GraphScope(
        graphID: UUID(
            uuidString: "10000000-0000-0000-0000-000000000001"
        )!
    )
    private let sessionID = GraphChatAnswerArtifactSessionID(
        rawValue: UUID(
            uuidString: "20000000-0000-0000-0000-000000000001"
        )!
    )

    func answer(
        _ text: String,
        sections: [GraphChatAnswerSection] = []
    ) -> GraphChatAnswer {
        GraphChatAnswer(
            directAnswer: text,
            sections: sections,
            evidence: [evidence()],
            artifactIDs: [artifactID(1)],
            hasInsufficientEvidence: false
        )
    }

    func listSource(
        entityLabel: String
    ) -> GraphChatDeterministicAnswerFallbackSource {
        let names: [String]
        if entityLabel == "Projekte" {
            names = [
                "Website-Relaunch",
                "Mobile App",
                "Kundenportal",
                "Datenplattform",
            ]
        } else {
            names = [
                "Website Relaunch",
                "Mobile App",
                "Customer Portal",
                "Data Platform",
            ]
        }
        let binding = evidenceBinding()
        let rows = names.enumerated().map { index, name in
            GraphChatAnswerArtifactListRow(
                id: itemID(index + 1),
                primaryText: name,
                secondaryText: nil,
                navigationTargets: [],
                evidence: binding
            )
        }
        let artifact = makeArtifact(
            id: artifactID(1),
            title: entityLabel,
            payload: .resultList(
                GraphChatAnswerArtifactResultListPayload(
                    title: entityLabel,
                    rows: rows,
                    resultMetadata: GraphChatAnswerArtifactResultMetadata(
                        resultCount: 12,
                        returnedCount: rows.count,
                        truncation: GraphChatAnswerArtifactTruncation(
                            isTruncated: true,
                            omittedCount: 8,
                            reason: .queryLimit
                        )
                    ),
                    evidence: binding
                )
            ),
            querySummary: querySummary(entityLabel: entityLabel)
        )
        return source(artifacts: [artifact])
    }

    func metricSource() -> GraphChatDeterministicAnswerFallbackSource {
        let binding = evidenceBinding()
        let artifact = makeArtifact(
            id: artifactID(2),
            title: "Anzahl Projekte",
            payload: .metric(
                GraphChatAnswerArtifactMetricPayload(
                    title: "Anzahl Projekte",
                    value: .integer(12),
                    unit: nil,
                    contextDescription: nil,
                    evidence: binding
                )
            ),
            querySummary: GraphChatAnswerArtifactQuerySummary(
                language: .german,
                entityID: uuid(300),
                entityLabel: "Projekte",
                filters: [],
                grouping: nil,
                sorting: [],
                projection: [],
                includesNodeIdentity: false,
                limit: 20,
                aggregation: .count(label: "Anzahl"),
                displayText: "Anzahl Projekte"
            )
        )
        return source(artifacts: [artifact])
    }

    func groupingSource() -> GraphChatDeterministicAnswerFallbackSource {
        let binding = evidenceBinding()
        let groups = [
            GraphChatAnswerArtifactGroupingEntry(
                id: itemID(20),
                groupKey: .choice(
                    GraphChatAnswerArtifactChoiceValue(
                        value: "open",
                        label: "Offen"
                    )
                ),
                label: "Offen",
                count: 4,
                share: .percentage(Decimal(string: "0.333")!),
                includedResultReferences: [],
                navigationTarget: nil,
                evidence: binding
            ),
            GraphChatAnswerArtifactGroupingEntry(
                id: itemID(21),
                groupKey: .choice(
                    GraphChatAnswerArtifactChoiceValue(
                        value: "done",
                        label: "Erledigt"
                    )
                ),
                label: "Erledigt",
                count: 8,
                share: .percentage(Decimal(string: "0.667")!),
                includedResultReferences: [],
                navigationTarget: nil,
                evidence: binding
            ),
        ]
        let artifact = makeArtifact(
            id: artifactID(3),
            title: "Nach Status gruppiert",
            payload: .grouping(
                GraphChatAnswerArtifactGroupingPayload(
                    title: "Nach Status gruppiert",
                    groups: groups,
                    resultMetadata: GraphChatAnswerArtifactResultMetadata(
                        resultCount: groups.count,
                        returnedCount: groups.count
                    ),
                    evidence: binding
                )
            ),
            querySummary: querySummary(entityLabel: "Projekte")
        )
        return source(artifacts: [artifact])
    }

    func healthSource() -> GraphChatDeterministicAnswerFallbackSource {
        let binding = evidenceBinding()
        let artifact = makeArtifact(
            id: artifactID(4),
            title: "Graph health finding",
            payload: .healthFinding(
                GraphChatAnswerArtifactHealthFindingPayload(
                    findingType: .isolatedNodes,
                    severity: .warning,
                    summary:
                        "2 isolated nodes across 3 health findings.",
                    affectedElementCount: 2,
                    affectedNodes: [],
                    evidence: binding,
                    navigationTargets: []
                )
            )
        )
        return source(
            kind: .statistics,
            artifacts: [artifact]
        )
    }

    func comparisonSource() -> GraphChatDeterministicAnswerFallbackSource {
        let binding = evidenceBinding()
        let subjects = [
            GraphChatAnswerArtifactComparisonSubject(
                id: itemID(30),
                label: "Website Relaunch",
                navigationTarget: nil,
                evidence: binding
            ),
            GraphChatAnswerArtifactComparisonSubject(
                id: itemID(31),
                label: "Mobile App",
                navigationTarget: nil,
                evidence: binding
            ),
        ]
        let features = [
            GraphChatAnswerArtifactComparisonFeature(
                id: itemID(32),
                key: "status",
                label: "Status",
                unit: nil,
                evidence: binding
            )
        ]
        let artifact = makeArtifact(
            id: artifactID(5),
            title: "Project comparison",
            payload: .comparison(
                GraphChatAnswerArtifactComparisonPayload(
                    title: "Project comparison",
                    subjects: subjects,
                    features: features,
                    values: [],
                    evidence: binding
                )
            )
        )
        return source(artifacts: [artifact])
    }

    func containsTechnicalIdentifier(_ text: String) -> Bool {
        let expression = try! NSRegularExpression(
            pattern:
                #"(?<![A-Za-z0-9_])(?:[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}|[EFN][0-9]+|CURRENT(?:_[0-9]+)?|CR_[A-Z0-9_]+)(?![A-Za-z0-9_])"#
        )
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.firstMatch(in: text, range: range) != nil
    }

    private func source(
        kind: GraphChatPrimaryResultKind = .query,
        artifacts: [GraphChatAnswerArtifact]
    ) -> GraphChatDeterministicAnswerFallbackSource {
        GraphChatDeterministicAnswerFallbackSource(
            kind: kind,
            completionStatus: .succeeded,
            evidence: [evidence()],
            artifacts: artifacts
        )
    }

    private func makeArtifact(
        id: GraphChatAnswerArtifactID,
        title: String,
        payload: GraphChatAnswerArtifactPayload,
        querySummary: GraphChatAnswerArtifactQuerySummary? = nil
    ) -> GraphChatAnswerArtifact {
        GraphChatAnswerArtifact(
            id: id,
            sessionID: sessionID,
            graphScope: graphScope,
            title: title,
            payload: payload,
            evidence: evidenceBinding(),
            navigationTargets: [],
            querySummary: querySummary
        )
    }

    private func querySummary(
        entityLabel: String
    ) -> GraphChatAnswerArtifactQuerySummary {
        GraphChatAnswerArtifactQuerySummary(
            language: entityLabel == "Projekte" ? .german : .english,
            entityID: uuid(300),
            entityLabel: entityLabel,
            filters: [],
            grouping: nil,
            sorting: [],
            projection: [],
            includesNodeIdentity: true,
            limit: 20,
            aggregation: nil,
            displayText: entityLabel
        )
    }

    private func evidence() -> GraphEvidence {
        GraphEvidence(
            sourceReference: GraphSourceReference(
                graphID: graphScope.graphID,
                sourceKind: .graph,
                sourceID: graphScope.graphID
            ),
            summary: "Validated result",
            navigationTitle: "Projects",
            identitySuffix: "quality-rescue"
        )
    }

    private func evidenceBinding() -> GraphChatAnswerArtifactEvidenceBinding {
        GraphChatAnswerArtifactEvidenceBinding(
            evidenceIDs: [evidence().id]
        )
    }

    private func artifactID(_ value: Int) -> GraphChatAnswerArtifactID {
        GraphChatAnswerArtifactID(rawValue: uuid(100 + value))
    }

    private func itemID(_ value: Int) -> GraphChatAnswerArtifactItemID {
        GraphChatAnswerArtifactItemID(rawValue: uuid(200 + value))
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(
            uuidString: String(
                format: "90000000-0000-0000-0000-%012d",
                value
            )
        )!
    }
}
