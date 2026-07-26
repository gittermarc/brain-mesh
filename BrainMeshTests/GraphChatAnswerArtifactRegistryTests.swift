import Foundation
import Testing
@testable import BrainMesh

struct GraphChatAnswerArtifactRegistryTests {
    @Test
    func registrationAndLookupRequireMatchingGraphAndSession() async throws {
        let fixture = ArtifactRegistryFixture()
        let context = try await fixture.makeContext()
        let transactionID = GraphChatAnswerArtifactTransactionID()
        let artifactID = try await context.registry.stage(
            fixture.draft(evidenceID: context.evidence.id),
            transactionID: transactionID,
            evidenceRegistry: context.evidenceRegistry
        )
        try await context.registry.commit(
            transactionID: transactionID,
            retaining: [artifactID]
        )

        let artifact = try await context.registry.artifact(
            for: artifactID,
            graphScope: fixture.graphScope,
            sessionID: fixture.sessionID
        )
        #expect(artifact?.id == artifactID)
        #expect(artifact?.graphScope == fixture.graphScope)
        #expect(artifact?.sessionID == fixture.sessionID)
    }

    @Test
    func resolvedArtifactReturnsTheRevalidatedEvidenceUsedByTheRenderer() async throws {
        let fixture = ArtifactRegistryFixture()
        let context = try await fixture.makeContext()
        let transactionID = GraphChatAnswerArtifactTransactionID()
        let artifactID = try await context.registry.stage(
            fixture.draft(evidenceID: context.evidence.id),
            transactionID: transactionID,
            evidenceRegistry: context.evidenceRegistry
        )
        try await context.registry.commit(
            transactionID: transactionID,
            retaining: [artifactID]
        )

        let resolution = try await context.registry.resolvedArtifact(
            for: artifactID,
            graphScope: fixture.graphScope,
            sessionID: fixture.sessionID
        )

        #expect(resolution?.artifact.id == artifactID)
        #expect(resolution?.evidence.map(\.id) == [context.evidence.id])
    }

    @Test
    func unknownArtifactIDReturnsNil() async throws {
        let fixture = ArtifactRegistryFixture()
        let context = try await fixture.makeContext()

        let artifact = try await context.registry.artifact(
            for: GraphChatAnswerArtifactID(),
            graphScope: fixture.graphScope,
            sessionID: fixture.sessionID
        )

        #expect(artifact == nil)
    }

    @Test
    func wrongSessionIsRejected() async throws {
        let fixture = ArtifactRegistryFixture()
        let context = try await fixture.makeContext()

        await #expect(throws: GraphChatAnswerArtifactRegistryError.sessionMismatch) {
            _ = try await context.registry.artifact(
                for: GraphChatAnswerArtifactID(),
                graphScope: fixture.graphScope,
                sessionID: GraphChatAnswerArtifactSessionID()
            )
        }
    }

    @Test
    func wrongGraphIsRejectedForLookupAndRegistration() async throws {
        let fixture = ArtifactRegistryFixture()
        let context = try await fixture.makeContext()
        let otherScope = GraphScope(graphID: UUID())

        await #expect(throws: GraphChatAnswerArtifactRegistryError.graphScopeMismatch) {
            _ = try await context.registry.artifact(
                for: GraphChatAnswerArtifactID(),
                graphScope: otherScope,
                sessionID: fixture.sessionID
            )
        }
        await #expect(throws: GraphChatAnswerArtifactRegistryError.graphScopeMismatch) {
            _ = try await context.registry.stage(
                fixture.draft(
                    graphScope: otherScope,
                    evidenceID: context.evidence.id
                ),
                transactionID: GraphChatAnswerArtifactTransactionID(),
                evidenceRegistry: context.evidenceRegistry
            )
        }
    }

    @Test
    func artifactEvidenceMustAlreadyBeRevalidated() async throws {
        let fixture = ArtifactRegistryFixture()
        let evidenceRegistry = GraphChatEvidenceRegistry(scope: fixture.chatScope)
        let registry = GraphChatAnswerArtifactRegistry(
            graphScope: fixture.graphScope,
            sessionID: fixture.sessionID
        )
        let unregisteredEvidence = fixture.makeEvidence(sourceID: UUID())

        await #expect(throws: GraphChatAnswerArtifactRegistryError.evidenceUnavailable) {
            _ = try await registry.stage(
                fixture.draft(evidenceID: unregisteredEvidence.id),
                transactionID: GraphChatAnswerArtifactTransactionID(),
                evidenceRegistry: evidenceRegistry
            )
        }
    }

    @Test
    func oversizedArtifactIsRejectedBeforeItCanBeStaged() async throws {
        let fixture = ArtifactRegistryFixture()
        let evidenceRegistry = GraphChatEvidenceRegistry(scope: fixture.chatScope)
        let evidence = fixture.makeEvidence(sourceID: fixture.uuid(4))
        try await evidenceRegistry.register([evidence])
        let registry = GraphChatAnswerArtifactRegistry(
            graphScope: fixture.graphScope,
            sessionID: fixture.sessionID,
            budget: GraphChatAnswerArtifactRegistryBudget(
                maximumArtifactCount: 2,
                maximumTotalByteCount: 1_024,
                maximumArtifactByteCount: 64
            )
        )
        let transactionID = GraphChatAnswerArtifactTransactionID()

        await #expect(
            throws: GraphChatAnswerArtifactRegistryError.artifactTooLarge(
                maximumByteCount: 64
            )
        ) {
            _ = try await registry.stage(
                fixture.draft(evidenceID: evidence.id),
                transactionID: transactionID,
                evidenceRegistry: evidenceRegistry
            )
        }
        #expect(
            await registry.stagedSnapshotForTesting(
                transactionID: transactionID
            ).isEmpty
        )
    }

    @Test
    func nestedNavigationTargetFromAnotherGraphIsRejected() async throws {
        let fixture = ArtifactRegistryFixture()
        let context = try await fixture.makeContext()
        let otherScope = GraphScope(graphID: fixture.uuid(90))
        let binding = GraphChatAnswerArtifactEvidenceBinding(
            evidenceIDs: [context.evidence.id]
        )
        let row = GraphChatAnswerArtifactListRow(
            id: GraphChatAnswerArtifactItemID(rawValue: fixture.uuid(91)),
            primaryText: "Foreign target",
            secondaryText: nil,
            navigationTargets: [
                .openNode(
                    graphScope: otherScope,
                    node: NodeRefKey(kind: .entity, id: fixture.uuid(92))
                )
            ],
            evidence: binding
        )
        let draft = GraphChatAnswerArtifactDraft(
            graphScope: fixture.graphScope,
            title: "Result list",
            payload: .resultList(
                GraphChatAnswerArtifactResultListPayload(
                    title: "Result list",
                    rows: [row],
                    resultMetadata: GraphChatAnswerArtifactResultMetadata(
                        resultCount: 1,
                        returnedCount: 1
                    ),
                    evidence: binding
                )
            ),
            evidence: binding
        )

        await #expect(
            throws: GraphChatAnswerArtifactRegistryError.invalidNavigationTarget
        ) {
            _ = try await context.registry.stage(
                draft,
                transactionID: GraphChatAnswerArtifactTransactionID(),
                evidenceRegistry: context.evidenceRegistry
            )
        }
    }

    @Test
    func oldestCommittedArtifactsAreEvictedDeterministicallyByCountBudget() async throws {
        let fixture = ArtifactRegistryFixture()
        let evidenceRegistry = GraphChatEvidenceRegistry(scope: fixture.chatScope)
        let evidence = fixture.makeEvidence(sourceID: fixture.uuid(1))
        try await evidenceRegistry.register([evidence])
        let registry = GraphChatAnswerArtifactRegistry(
            graphScope: fixture.graphScope,
            sessionID: fixture.sessionID,
            budget: GraphChatAnswerArtifactRegistryBudget(
                maximumArtifactCount: 2,
                maximumTotalByteCount: 256 * 1_024,
                maximumArtifactByteCount: 64 * 1_024
            )
        )
        var ids: [GraphChatAnswerArtifactID] = []

        for index in 0..<3 {
            let transactionID = GraphChatAnswerArtifactTransactionID(
                rawValue: fixture.uuid(index + 10)
            )
            let id = try await registry.stage(
                fixture.draft(
                    title: "Artifact \(index)",
                    evidenceID: evidence.id
                ),
                transactionID: transactionID,
                evidenceRegistry: evidenceRegistry
            )
            try await registry.commit(
                transactionID: transactionID,
                retaining: [id]
            )
            ids.append(id)
        }

        let snapshot = await registry.snapshotForTesting()
        #expect(snapshot.map(\.id) == Array(ids.suffix(2)))
        #expect(
            try await registry.artifact(
                for: ids[0],
                graphScope: fixture.graphScope,
                sessionID: fixture.sessionID
            ) == nil
        )
    }

    @Test
    func everySecurityLifecycleClearReasonRemovesCommittedArtifacts() async throws {
        let fixture = ArtifactRegistryFixture()
        let reasons: [GraphChatAnswerArtifactRegistryClearReason] = [
            .newConversation,
            .graphChanged,
            .graphLocked,
            .graphDeleted
        ]

        for reason in reasons {
            let context = try await fixture.makeContext()
            let transactionID = GraphChatAnswerArtifactTransactionID()
            let id = try await context.registry.stage(
                fixture.draft(evidenceID: context.evidence.id),
                transactionID: transactionID,
                evidenceRegistry: context.evidenceRegistry
            )
            try await context.registry.commit(
                transactionID: transactionID,
                retaining: [id]
            )

            await context.registry.removeAll(reason: reason)

            #expect(await context.registry.snapshotForTesting().isEmpty)
            #expect(await context.registry.lastClearReasonForTesting() == reason)
        }
    }

    @Test
    func cancellationNeverCommitsOrLeavesAStagedArtifact() async throws {
        let fixture = ArtifactRegistryFixture()
        let context = try await fixture.makeContext()
        let transactionID = GraphChatAnswerArtifactTransactionID()
        let task = Task {
            withUnsafeCurrentTask { currentTask in
                currentTask?.cancel()
            }
            _ = try await context.registry.stage(
                fixture.draft(evidenceID: context.evidence.id),
                transactionID: transactionID,
                evidenceRegistry: context.evidenceRegistry
            )
        }

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
        #expect(
            await context.registry.stagedSnapshotForTesting(
                transactionID: transactionID
            ).isEmpty
        )
        #expect(await context.registry.snapshotForTesting().isEmpty)
    }

    @Test
    func rollbackDiscardsOnlyTheUnfinishedTransaction() async throws {
        let fixture = ArtifactRegistryFixture()
        let context = try await fixture.makeContext()
        let committedTransaction = GraphChatAnswerArtifactTransactionID()
        let committedID = try await context.registry.stage(
            fixture.draft(title: "Committed", evidenceID: context.evidence.id),
            transactionID: committedTransaction,
            evidenceRegistry: context.evidenceRegistry
        )
        try await context.registry.commit(
            transactionID: committedTransaction,
            retaining: [committedID]
        )
        let unfinishedTransaction = GraphChatAnswerArtifactTransactionID()
        _ = try await context.registry.stage(
            fixture.draft(title: "Unfinished", evidenceID: context.evidence.id),
            transactionID: unfinishedTransaction,
            evidenceRegistry: context.evidenceRegistry
        )

        await context.registry.rollback(transactionID: unfinishedTransaction)

        #expect(await context.registry.snapshotForTesting().map(\.id) == [committedID])
        #expect(
            await context.registry.stagedSnapshotForTesting(
                transactionID: unfinishedTransaction
            ).isEmpty
        )
    }
}

private struct ArtifactRegistryFixture {
    struct Context {
        let evidence: GraphEvidence
        let evidenceRegistry: GraphChatEvidenceRegistry
        let registry: GraphChatAnswerArtifactRegistry
    }

    let graphScope = GraphScope(
        graphID: UUID(uuidString: "B0000000-0000-0000-0000-000000000001")!
    )
    let sessionID = GraphChatAnswerArtifactSessionID(
        rawValue: UUID(uuidString: "B0000000-0000-0000-0000-000000000002")!
    )

    var chatScope: GraphChatScope {
        .entireGraph(graphScope)
    }

    func makeContext() async throws -> Context {
        let evidence = makeEvidence(sourceID: uuid(3))
        let evidenceRegistry = GraphChatEvidenceRegistry(scope: chatScope)
        try await evidenceRegistry.register([evidence])
        return Context(
            evidence: evidence,
            evidenceRegistry: evidenceRegistry,
            registry: GraphChatAnswerArtifactRegistry(
                graphScope: graphScope,
                sessionID: sessionID
            )
        )
    }

    func makeEvidence(sourceID: UUID) -> GraphEvidence {
        GraphEvidence(
            sourceReference: GraphSourceReference(
                graphID: graphScope.graphID,
                sourceKind: .entity,
                sourceID: sourceID
            ),
            summary: "Validated artifact evidence",
            identitySuffix: sourceID.uuidString
        )
    }

    func draft(
        graphScope: GraphScope? = nil,
        title: String = "Metric",
        evidenceID: GraphEvidenceID
    ) -> GraphChatAnswerArtifactDraft {
        let binding = GraphChatAnswerArtifactEvidenceBinding(
            evidenceIDs: [evidenceID]
        )
        return GraphChatAnswerArtifactDraft(
            graphScope: graphScope ?? self.graphScope,
            title: title,
            payload: .metric(
                GraphChatAnswerArtifactMetricPayload(
                    title: title,
                    value: .integer(1),
                    unit: nil,
                    contextDescription: nil,
                    evidence: binding
                )
            ),
            evidence: binding
        )
    }

    func uuid(_ suffix: Int) -> UUID {
        UUID(uuidString: String(format: "B0000000-0000-0000-0000-%012d", suffix))!
    }
}
