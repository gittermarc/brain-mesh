import Foundation
import Testing
@testable import BrainMesh

private actor RecordingGraphChatObservability: GraphChatObservabilityRecording {
    private var events: [GraphChatObservabilityEvent] = []

    func record(_ event: GraphChatObservabilityEvent) {
        events.append(event)
    }

    func snapshot() -> [GraphChatObservabilityEvent] {
        events
    }
}

struct GraphChatPrivacyTests {
    @MainActor
    @Test
    func observableRequestPayloadContainsOnlyTechnicalMetrics() async throws {
        let promptSentinel = "PRIVATE-PROMPT-9F3B"
        let answerSentinel = "PRIVATE-ANSWER-A71C"
        let notesSentinel = "PRIVATE-NOTES-442D"
        let detailSentinel = "PRIVATE-DETAIL-58EE"
        let filenameSentinel = "private-file-6c21.pdf"
        let recorder = RecordingGraphChatObservability()
        let activityID = UUID()
        let setup = GraphChatUITestSupport.makeViewModel(
            scripts: [
                GraphChatUIFakeScript(
                    events: [
                        .started(requestID: UUID()),
                        .toolActivity(
                            GraphChatToolActivity(
                                id: activityID,
                                tool: .getNode,
                                state: .started
                            )
                        ),
                        .toolActivity(
                            GraphChatToolActivity(
                                id: activityID,
                                tool: .getNode,
                                state: .finished
                            )
                        ),
                        .completed(
                            GraphChatUITestSupport.finalAnswer(
                                directAnswer: answerSentinel,
                                evidence: [],
                                insufficient: true
                            )
                        )
                    ]
                )
            ]
        )
        let viewModel = GraphChatViewModel(
            graphScope: setup.viewModel.graphScope,
            chatScope: setup.viewModel.chatScope,
            graphName: setup.viewModel.configuredGraphName,
            orchestrator: setup.orchestrator,
            schemaProvider: GraphChatUIFakeSchemaProvider(
                contexts: [GraphChatTestSupport.makeSchemaContext()]
            ),
            availabilityProvider: GraphChatUIFakeAvailabilityProvider(
                value: .available
            ),
            indexStatusProvider: GraphChatUIFakeIndexProvider(
                value: .ready(documentCount: 12)
            ),
            historyStore: InMemoryGraphChatHistoryStore(),
            navigationActions: .disabled,
            observability: recorder
        )

        await viewModel.load()
        viewModel.setComposerText(promptSentinel)
        viewModel.send()
        await GraphChatUITestSupport.waitUntil {
            viewModel.isGenerating == false
                && viewModel.messages.count == 2
        }

        let events = await recorder.snapshot()
        let serialized = String(reflecting: events)
        #expect(events.count == 1)
        #expect(serialized.contains(promptSentinel) == false)
        #expect(serialized.contains(answerSentinel) == false)
        #expect(serialized.contains(notesSentinel) == false)
        #expect(serialized.contains(detailSentinel) == false)
        #expect(serialized.contains(filenameSentinel) == false)
        guard case .request(let metric) = try #require(events.first) else {
            Issue.record("Expected one request metric.")
            return
        }
        #expect(metric.durationMilliseconds >= 0)
        #expect(metric.toolCount == 1)
        #expect(metric.toolKinds == [.getNode])
        #expect(metric.evidenceCount == 0)
        #expect(metric.outcome == .noResults)
    }

    @MainActor
    @Test
    func attachmentPathExposesMetadataOnlyAndNeverBinaryContent() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let fixture = fixtures.makeGraphChatMixedKnowledgeFixture()
        try fixtures.save()

        let repository = GraphReadRepository(
            container: AnyModelContainer(store.container)
        )
        let schemaService = GraphSchemaService(repository: repository)
        let graphScope = GraphScope(graphID: fixture.graph.id)
        let schema = try await schemaService.makeSnapshot(in: graphScope)
        let entityAlias = try #require(schema.entityAlias(named: "Themen"))
        let classificationAlias = try #require(
            schema.fieldAlias(named: "Klassifikation", in: entityAlias)
        )
        let provider = FakeGraphChatModelProvider(
            scripts: [
                FakeGraphChatProviderScript(
                    steps: [
                        .toolRequest(
                            .queryDetailValues(
                                GraphChatModelQueryRequest(
                                    entityAlias: entityAlias.rawValue,
                                    filters: [],
                                    sortFieldAlias: "nodeName",
                                    sortDirection: GraphQuerySortDirection.ascending.rawValue,
                                    projectionFieldAliases: [classificationAlias.rawValue],
                                    aggregation: nil,
                                    aggregationFieldAlias: nil,
                                    limit: 1
                                )
                            )
                        ),
                        .toolRequest(.getNode(nodeAlias: "N1", relatedLimit: 10)),
                        .event(
                            .completed(
                                GraphChatProviderTestSupport.makeFinalAnswer(
                                    directAnswer: "Es wurden ausschließlich dokumentierte Metadaten berücksichtigt.",
                                    hasInsufficientEvidence: true
                                )
                            )
                        )
                    ]
                )
            ]
        )
        let orchestrator = GraphChatOrchestrator(
            provider: provider,
            schemaProvider: schemaService,
            toolRunnerFactory: GraphChatProviderTestSupport.makeRealRuntimeFactory(
                store: store,
                schemaService: schemaService,
                repository: repository
            )
        )
        _ = await GraphChatProviderTestSupport.collect(
            await orchestrator.streamAnswer(
                question: "Welche dokumentierten Metadaten gibt es?",
                graphScope: graphScope,
                chatScope: .entireGraph(graphScope)
            )
        )

        let snapshot = await provider.snapshot()
        #expect(snapshot.toolResponses.count == 2)
        let nodeResponse = snapshot.toolResponses[1]
        #expect(nodeResponse.tool == .getNode)
        #expect(nodeResponse.content.contains("attachmentMetadata"))
        #expect(nodeResponse.content.contains("governance-private.bin"))
        #expect(nodeResponse.content.contains("contentNotRead=true"))
        #expect(nodeResponse.content.contains(fixture.attachmentPayload.base64EncodedString()) == false)
        #expect(nodeResponse.content.contains("BM\\0") == false)

        let request = try #require(snapshot.streamedRequests.first)
        #expect(request.schemaPrompt.contains(fixture.person.notes) == false)
        #expect(request.schemaPrompt.contains(fixture.topic.notes) == false)
        #expect(request.schemaPrompt.contains(fixture.attachment.originalFilename) == false)

        let loadedMetadata = try await repository.attachmentMetadata(
            id: fixture.attachment.id,
            in: graphScope
        )
        let metadata = try #require(loadedMetadata)
        let labels = Set(Mirror(reflecting: metadata).children.compactMap(\.label))
        #expect(labels.contains("fileData") == false)
        #expect(labels.contains("localPath") == false)
        #expect(metadata.byteCount == fixture.attachmentPayload.count)
    }
}
