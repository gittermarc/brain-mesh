import Foundation
import SwiftData
import Testing
@testable import BrainMesh

private nonisolated struct GraphChatReadinessStub: BrainMeshSearchIndexReadinessProviding {
    let result: GraphSearchIndexReadinessResult

    func ensureReady(
        scope: GraphScope,
        reason: GraphSearchIndexReconciliationReason
    ) async -> GraphSearchIndexReadinessResult {
        result.replacingReason(with: reason)
    }

    func invalidate(
        scope: GraphScope,
        reason: GraphSearchIndexReconciliationReason
    ) async {}
}

private nonisolated struct GraphChatIndexedProviderStub: BrainMeshIndexedSearchCandidateProviding {
    let candidatesToReturn: [BrainMeshSearchCandidate]

    func candidates(
        graphIDs: [UUID],
        foldedQuery: String,
        resultLimit: Int
    ) async throws -> BrainMeshIndexedSearchCandidateResponse {
        BrainMeshIndexedSearchCandidateResponse(
            candidates: Array(candidatesToReturn.prefix(resultLimit)),
            indexDocumentCount: candidatesToReturn.count
        )
    }
}

private actor GraphChatStatsReaderSpy: GraphChatStatsReading {
    let value: GraphChatStatsSnapshot
    private(set) var requestedScopes: [GraphScope] = []

    init(value: GraphChatStatsSnapshot) {
        self.value = value
    }

    func snapshot(in scope: GraphScope) async throws -> GraphChatStatsSnapshot {
        requestedScopes.append(scope)
        return value
    }

    func callCount() -> Int {
        requestedScopes.count
    }
}

struct GraphChatToolsTests {
    @Test
    func searchRevalidatesIndexHitsAndDropsStaleDocuments() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Search")
        let entity = fixtures.makeEntity(name: "Active Source", in: graph)
        try fixtures.save()

        let staleID = UUID()
        let existing = BrainMeshSearchCandidate(
            result: BrainMeshSearchResult(
                kind: .entity,
                id: entity.id,
                graphID: graph.id,
                title: "Outdated Indexed Name",
                subtitle: "Outdated Entity",
                iconSymbolName: "circle.hexagongrid",
                matchReason: "Name",
                nodeKindRaw: NodeKind.entity.rawValue,
                nodeID: entity.id,
                ownerKindRaw: nil,
                ownerID: nil
            ),
            score: 1
        )
        let stale = BrainMeshSearchCandidate(
            result: BrainMeshSearchResult(
                kind: .entity,
                id: staleID,
                graphID: graph.id,
                title: "Deleted Source",
                subtitle: "Stale",
                iconSymbolName: "circle.hexagongrid",
                matchReason: "Name",
                nodeKindRaw: NodeKind.entity.rawValue,
                nodeID: staleID,
                ownerKindRaw: nil,
                ownerID: nil
            ),
            score: 0
        )
        let repository = GraphReadRepository(container: AnyModelContainer(store.container))
        let readiness = GraphSearchIndexReadinessResult(
            graphID: graph.id,
            reason: .chatSession,
            outcome: .ready,
            isIndexUsable: true,
            documentCount: 2,
            metrics: nil,
            failure: nil
        )
        let tool = SearchGraphTool(
            readinessProvider: GraphChatReadinessStub(result: readiness),
            indexedProvider: GraphChatIndexedProviderStub(candidatesToReturn: [existing, stale]),
            sourceRepository: repository,
            evidenceValidator: GraphEvidenceSourceValidator(repository: repository),
            logger: NoOpGraphChatToolLogger()
        )
        let result = try await tool.execute(
            SearchGraphInput(query: "source", limit: 1),
            context: context(graphID: graph.id)
        )

        #expect(result.state == .success)
        #expect(result.payload?.hits.map(\.sourceReference.sourceID) == [entity.id])
        #expect(result.payload?.hits.map(\.title) == ["Active Source"])
        #expect(result.payload?.hits.map(\.subtitle) == ["Entity"])
        #expect(result.evidence.map(\.sourceReference.sourceID) == [entity.id])
        #expect(result.evidence.contains { $0.sourceReference.sourceID == staleID } == false)
    }

    @Test
    func getNodeReturnsTypedValuesAndAttachmentMetadataWithoutBinaryData() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Node")
        let entity = fixtures.makeEntity(name: "Documents", in: graph)
        let attribute = fixtures.makeAttribute(
            name: "Policy",
            owner: entity,
            notes: "Current policy"
        )
        let field = fixtures.makeDetailField(
            owner: entity,
            name: "Version",
            type: .numberInt,
            sortIndex: 0,
            unit: "Revision"
        )
        fixtures.makeDetailValue(attribute: attribute, field: field, intValue: 4)
        fixtures.makeAttachment(
            owner: .attribute(attribute),
            title: "Policy PDF",
            originalFilename: "policy.pdf",
            contentTypeIdentifier: "com.adobe.pdf",
            fileExtension: "pdf",
            fileData: Data("BINARY-CONTENT-MUST-STAY-UNREAD".utf8)
        )
        try fixtures.save()

        let repository = GraphReadRepository(container: AnyModelContainer(store.container))
        let result = try await GetNodeTool(
            repository: repository,
            evidenceValidator: GraphEvidenceSourceValidator(repository: repository),
            logger: NoOpGraphChatToolLogger()
        ).execute(
            GetNodeInput(
                node: NodeRefKey(kind: .attribute, id: attribute.id),
                relatedLimit: 10
            ),
            context: context(graphID: graph.id)
        )

        let output = try #require(result.payload)
        #expect(result.state == .success)
        #expect(output.label == "Documents · Policy")
        #expect(output.detailValues.map(\.value) == [.integer(4)])
        #expect(output.attachments.count == 1)
        #expect(output.attachments[0].originalFilename == "policy.pdf")
        #expect(output.attachments[0].byteCount > 0)
        #expect(String(describing: output).contains("BINARY-CONTENT-MUST-STAY-UNREAD") == false)
        #expect(result.evidence.flatMap(\.fieldValues).contains { field in
            if case .text("BINARY-CONTENT-MUST-STAY-UNREAD") = field.value {
                return true
            }
            return false
        } == false)
    }

    @Test
    func getNeighborsReturnsOnlyDirectIncomingAndOutgoingConnections() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Network")
        let center = fixtures.makeEntity(name: "Center", in: graph)
        let direct = fixtures.makeEntity(name: "Direct", in: graph)
        let secondHop = fixtures.makeEntity(name: "Second Hop", in: graph)
        fixtures.makeLink(source: .entity(center), target: .entity(direct))
        fixtures.makeLink(source: .entity(direct), target: .entity(secondHop))
        try fixtures.save()

        let readRepository = GraphReadRepository(container: AnyModelContainer(store.container))
        let result = try await GetNeighborsTool(
            repository: NodeRepository(container: AnyModelContainer(store.container)),
            evidenceValidator: GraphEvidenceSourceValidator(repository: readRepository),
            logger: NoOpGraphChatToolLogger()
        ).execute(
            GetNeighborsInput(
                node: NodeRefKey(kind: .entity, id: center.id),
                limit: 10
            ),
            context: context(graphID: graph.id)
        )

        let output = try #require(result.payload)
        #expect(output.connections.count == 1)
        #expect(output.connections[0].neighbor == NodeRefKey(kind: .entity, id: direct.id))
        #expect(output.connections.contains {
            $0.neighbor == NodeRefKey(kind: .entity, id: secondHop.id)
        } == false)
    }

    @Test
    func centralBudgetEnforcesCallsResultCountsAndEvidence() async throws {
        let budget = GraphChatToolBudget(
            policy: GraphChatToolBudgetPolicy(
                maximumCalls: 1,
                maximumResultCountPerTool: 3,
                maximumEvidenceCount: 2
            )
        )
        let accepted = try await budget.beginCall(
            tool: .getNode,
            requestedResultCount: 3,
            toolMaximumResultCount: 10
        )
        #expect(accepted == 3)
        try await budget.consumeEvidence(2)

        do {
            _ = try await budget.beginCall(
                tool: .searchGraph,
                requestedResultCount: 1,
                toolMaximumResultCount: 10
            )
            Issue.record("Expected the call budget to reject a second tool call")
        } catch let error as GraphChatToolError {
            #expect(error.code == .budgetExceeded)
        }

        do {
            try await budget.consumeEvidence(1)
            Issue.record("Expected the evidence budget to reject additional evidence")
        } catch let error as GraphChatToolError {
            #expect(error.code == .budgetExceeded)
        }
    }

    @Test
    func statsReaderReturnsTheExistingGraphStatsServiceSnapshots() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Stats")
        let first = fixtures.makeEntity(name: "First", in: graph)
        let second = fixtures.makeEntity(name: "Second", in: graph)
        fixtures.makeLink(source: .entity(first), target: .entity(second))
        try fixtures.save()

        let directService = GraphStatsService(context: store.context)
        let expectedCounts = try directService.counts(for: graph.id)
        let expectedStructure = try directService.structureSnapshot(for: graph.id)
        let expectedMedia = try directService.mediaSnapshot(for: graph.id)
        let expectedHealth = try directService.healthSnapshot(
            for: graph.id,
            counts: expectedCounts,
            structure: expectedStructure,
            media: expectedMedia
        )
        let actual = try await GraphStatsServiceReader(
            container: AnyModelContainer(store.container)
        ).snapshot(in: GraphScope(graphID: graph.id))

        #expect(actual.counts == expectedCounts)
        #expect(actual.structure == expectedStructure)
        #expect(actual.health == expectedHealth)
    }

    @Test
    func statsToolProjectsInjectedExistingServiceResultsWithoutRecalculation() async throws {
        let graphID = UUID()
        let counts = GraphCounts(
            entities: 3,
            attributes: 7,
            links: 5,
            notes: 4,
            images: 2,
            attachments: 6,
            attachmentBytes: 12_345
        )
        let hubID = UUID()
        let structure = GraphStructureSnapshot(
            nodeCount: 10,
            linkCount: 5,
            isolatedNodeCount: 2,
            topHubs: [
                GraphHubItem(id: hubID, label: "Hub", kind: .entity, degree: 4)
            ]
        )
        let health = GraphHealthSnapshot(
            graphID: graphID,
            counts: counts,
            score: GraphHealthScore.make(counts: counts, issues: []),
            issues: []
        )
        let spy = GraphChatStatsReaderSpy(
            value: GraphChatStatsSnapshot(
                counts: counts,
                structure: structure,
                health: health
            )
        )
        let result = try await GraphStatsTool(
            reader: spy,
            evidenceValidator: PassthroughGraphEvidenceValidator(),
            logger: NoOpGraphChatToolLogger()
        ).execute(
            GraphStatsInput(hubLimit: 1),
            context: context(graphID: graphID)
        )

        let output = try #require(result.payload)
        #expect(await spy.callCount() == 1)
        #expect(output.counts.entities == counts.entities)
        #expect(output.counts.images == counts.images)
        #expect(output.nodeCount == structure.nodeCount)
        #expect(output.isolatedNodeCount == structure.isolatedNodeCount)
        #expect(output.hubs.map(\.node.id) == [hubID])
        #expect(output.healthScore == health.score.value)
    }

    private func context(graphID: UUID) -> GraphChatToolContext {
        GraphChatToolContext(
            scope: .entireGraph(GraphScope(graphID: graphID)),
            budget: GraphChatToolBudget()
        )
    }
}
