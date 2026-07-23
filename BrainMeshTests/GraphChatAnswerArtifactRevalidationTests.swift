import Foundation
import Testing

@testable import BrainMesh

struct GraphChatAnswerArtifactRevalidationTests {
    @Test
    func deletedNodeInvalidatesCommittedArtifactAndItsEvidence() async throws {
        let graphScope = GraphScope(graphID: UUID(uuidString: "E0000000-0000-0000-0000-000000000001")!)
        let entityID = UUID(uuidString: "E0000000-0000-0000-0000-000000000002")!
        let attributeID = UUID(uuidString: "E0000000-0000-0000-0000-000000000003")!
        let repository = MutableArtifactEvidenceSourceRepository(
            graph: GraphMetadataDTO(
                id: graphScope.graphID,
                scope: graphScope,
                name: "Graph",
                createdAt: Date(timeIntervalSince1970: 1_735_732_800)
            ),
            entities: [
                GraphEntityDTO(
                    id: entityID,
                    scope: graphScope,
                    name: "Projects",
                    notes: "",
                    iconSymbolName: nil,
                    createdAt: Date(timeIntervalSince1970: 1_735_732_800)
                )
            ],
            attributes: [
                GraphAttributeDTO(
                    id: attributeID,
                    scope: graphScope,
                    ownerEntityID: entityID,
                    ownerLabel: "Projects",
                    name: "Alpha",
                    displayLabel: "Alpha",
                    notes: "",
                    iconSymbolName: nil
                )
            ]
        )
        let revalidator = GraphChatLiveAnswerArtifactRevalidator(
            evidenceValidator: GraphEvidenceSourceValidator(repository: repository),
            sourceRepository: repository
        )
        let sessionID = GraphChatAnswerArtifactSessionID()
        let registry = GraphChatAnswerArtifactRegistry(
            graphScope: graphScope,
            scope: .entireGraph(graphScope),
            sessionID: sessionID,
            revalidator: revalidator
        )
        let evidence = GraphEvidence(
            sourceReference: GraphSourceReference(
                graphID: graphScope.graphID,
                sourceKind: .attribute,
                sourceID: attributeID,
                node: GraphSourceNodeReference(kind: .attribute, id: attributeID),
                owner: GraphSourceNodeReference(kind: .entity, id: entityID)
            ),
            summary: "Alpha",
            identitySuffix: "artifact-node"
        )
        let evidenceRegistry = GraphChatEvidenceRegistry(scope: .entireGraph(graphScope))
        try await evidenceRegistry.register([evidence])
        let transactionID = GraphChatAnswerArtifactTransactionID()
        let binding = GraphChatAnswerArtifactEvidenceBinding(evidenceIDs: [evidence.id])
        let artifactID = try await registry.stage(
            GraphChatAnswerArtifactDraft(
                graphScope: graphScope,
                title: "Alpha",
                payload: .resultList(
                    GraphChatAnswerArtifactResultListPayload(
                        title: "Alpha",
                        rows: [
                            GraphChatAnswerArtifactListRow(
                                id: GraphChatAnswerArtifactItemID(rawValue: attributeID),
                                primaryText: "Alpha",
                                secondaryText: nil,
                                navigationTargets: [
                                    .openNode(
                                        graphScope: graphScope,
                                        node: NodeRefKey(kind: .attribute, id: attributeID)
                                    )
                                ],
                                evidence: binding
                            )
                        ],
                        resultMetadata: GraphChatAnswerArtifactResultMetadata(
                            resultCount: 1,
                            returnedCount: 1
                        ),
                        evidence: binding
                    )
                ),
                evidence: binding
            ),
            transactionID: transactionID,
            evidenceRegistry: evidenceRegistry
        )
        _ = try await registry.commit(
            transactionID: transactionID,
            retaining: [artifactID]
        )
        #expect(
            try await registry.artifact(
                for: artifactID,
                graphScope: graphScope,
                sessionID: sessionID
            ) != nil)

        await repository.removeAttribute(attributeID)

        #expect(
            try await registry.artifact(
                for: artifactID,
                graphScope: graphScope,
                sessionID: sessionID
            ) == nil)
        #expect(await registry.snapshotForTesting().isEmpty)
    }

    @Test
    func deletedEvidenceSourceInvalidatesArtifactWithoutNavigationTarget() async throws {
        let graphScope = GraphScope(graphID: UUID(uuidString: "E0000000-0000-0000-0000-000000000010")!)
        let entityID = UUID(uuidString: "E0000000-0000-0000-0000-000000000011")!
        let repository = MutableArtifactEvidenceSourceRepository(
            graph: GraphMetadataDTO(
                id: graphScope.graphID,
                scope: graphScope,
                name: "Graph",
                createdAt: Date(timeIntervalSince1970: 1_735_732_800)
            ),
            entities: [
                GraphEntityDTO(
                    id: entityID,
                    scope: graphScope,
                    name: "Projects",
                    notes: "",
                    iconSymbolName: nil,
                    createdAt: Date(timeIntervalSince1970: 1_735_732_800)
                )
            ],
            attributes: []
        )
        let sessionID = GraphChatAnswerArtifactSessionID()
        let registry = GraphChatAnswerArtifactRegistry(
            graphScope: graphScope,
            scope: .entireGraph(graphScope),
            sessionID: sessionID,
            revalidator: GraphChatLiveAnswerArtifactRevalidator(
                evidenceValidator: GraphEvidenceSourceValidator(repository: repository),
                sourceRepository: repository
            )
        )
        let evidence = GraphEvidence(
            sourceReference: GraphSourceReference(
                graphID: graphScope.graphID,
                sourceKind: .entity,
                sourceID: entityID,
                node: GraphSourceNodeReference(kind: .entity, id: entityID)
            ),
            summary: "Projects",
            identitySuffix: "artifact-evidence"
        )
        let evidenceRegistry = GraphChatEvidenceRegistry(scope: .entireGraph(graphScope))
        try await evidenceRegistry.register([evidence])
        let binding = GraphChatAnswerArtifactEvidenceBinding(evidenceIDs: [evidence.id])
        let transactionID = GraphChatAnswerArtifactTransactionID()
        let artifactID = try await registry.stage(
            GraphChatAnswerArtifactDraft(
                graphScope: graphScope,
                title: "Count",
                payload: .metric(
                    GraphChatAnswerArtifactMetricPayload(
                        title: "Count",
                        value: .integer(1),
                        unit: nil,
                        contextDescription: nil,
                        evidence: binding
                    )
                ),
                evidence: binding
            ),
            transactionID: transactionID,
            evidenceRegistry: evidenceRegistry
        )
        _ = try await registry.commit(
            transactionID: transactionID,
            retaining: [artifactID]
        )

        await repository.removeEntity(entityID)

        #expect(
            try await registry.artifact(
                for: artifactID,
                graphScope: graphScope,
                sessionID: sessionID
            ) == nil)
    }

    @Test
    func graphChangeClearsArtifactsAndPreventsCrossGraphAccess() async throws {
        let graphScope = GraphScope(graphID: UUID(uuidString: "E0000000-0000-0000-0000-000000000020")!)
        let otherGraphScope = GraphScope(
            graphID: UUID(uuidString: "E0000000-0000-0000-0000-000000000021")!)
        let sessionID = GraphChatAnswerArtifactSessionID()
        let registry = GraphChatAnswerArtifactRegistry(
            graphScope: graphScope,
            sessionID: sessionID
        )

        do {
            _ = try await registry.artifact(
                for: GraphChatAnswerArtifactID(),
                graphScope: otherGraphScope,
                sessionID: sessionID
            )
            Issue.record("Expected graph scope mismatch")
        } catch let error as GraphChatAnswerArtifactRegistryError {
            #expect(error == .graphScopeMismatch)
        }

        await registry.removeAll(reason: .graphChanged)
        #expect(await registry.snapshotForTesting().isEmpty)
        #expect(await registry.lastClearReasonForTesting() == .graphChanged)
    }

    @Test
    func workspaceNavigationTargetsDropDeletedNodesImmediatelyBeforeExecution() async throws {
        let graphScope = GraphScope(
            graphID: UUID(uuidString: "E0000000-0000-0000-0000-000000000040")!
        )
        let entityID = UUID(uuidString: "E0000000-0000-0000-0000-000000000041")!
        let attributeID = UUID(uuidString: "E0000000-0000-0000-0000-000000000042")!
        let deletedAttributeID = UUID(uuidString: "E0000000-0000-0000-0000-000000000043")!
        let repository = MutableArtifactEvidenceSourceRepository(
            graph: GraphMetadataDTO(
                id: graphScope.graphID,
                scope: graphScope,
                name: "Graph",
                createdAt: Date(timeIntervalSince1970: 1_735_732_800)
            ),
            entities: [
                GraphEntityDTO(
                    id: entityID,
                    scope: graphScope,
                    name: "Projects",
                    notes: "",
                    iconSymbolName: nil,
                    createdAt: Date(timeIntervalSince1970: 1_735_732_800)
                )
            ],
            attributes: [
                GraphAttributeDTO(
                    id: attributeID,
                    scope: graphScope,
                    ownerEntityID: entityID,
                    ownerLabel: "Projects",
                    name: "Alpha",
                    displayLabel: "Alpha",
                    notes: "",
                    iconSymbolName: nil
                )
            ]
        )
        let revalidator = GraphChatAnswerArtifactNavigationTargetRevalidator(
            sourceRepository: repository
        )
        let entity = NodeRefKey(kind: .entity, id: entityID)
        let attribute = NodeRefKey(kind: .attribute, id: attributeID)
        let deleted = NodeRefKey(kind: .attribute, id: deletedAttributeID)

        let revalidated = try await revalidator.revalidatedTarget(
            .highlightNodesInCanvas(
                graphScope: graphScope,
                nodes: [attribute, deleted, entity, attribute]
            ),
            in: graphScope
        )

        #expect(
            revalidated
                == .highlightNodesInCanvas(
                    graphScope: graphScope,
                    nodes: [attribute, entity]
                ))
        #expect(
            try await revalidator.revalidatedTarget(
                .replaceCanvasSelection(
                    graphScope: graphScope,
                    nodes: [deleted]
                ),
                in: graphScope
            ) == nil)
        #expect(
            try await revalidator.revalidatedTarget(
                .compareNodes(
                    graphScope: graphScope,
                    nodes: [attribute, deleted]
                ),
                in: graphScope
            ) == nil)
    }

    @Test
    func workspaceNavigationTargetsRejectForeignGraphsAndDeletedFilterEntities() async throws {
        let graphScope = GraphScope(
            graphID: UUID(uuidString: "E0000000-0000-0000-0000-000000000050")!
        )
        let foreignScope = GraphScope(
            graphID: UUID(uuidString: "E0000000-0000-0000-0000-000000000051")!
        )
        let entityID = UUID(uuidString: "E0000000-0000-0000-0000-000000000052")!
        let repository = MutableArtifactEvidenceSourceRepository(
            graph: GraphMetadataDTO(
                id: graphScope.graphID,
                scope: graphScope,
                name: "Graph",
                createdAt: Date(timeIntervalSince1970: 1_735_732_800)
            ),
            entities: [],
            attributes: []
        )
        let revalidator = GraphChatAnswerArtifactNavigationTargetRevalidator(
            sourceRepository: repository
        )
        let node = NodeRefKey(kind: .entity, id: entityID)

        #expect(
            try await revalidator.revalidatedTarget(
                .showResultNodes(
                    graphScope: foreignScope,
                    title: "Foreign",
                    nodes: [node]
                ),
                in: graphScope
            ) == nil)
        #expect(
            try await revalidator.revalidatedTarget(
                .openResultFilter(
                    graphScope: graphScope,
                    entityID: entityID,
                    filters: [],
                    resultNodes: [node]
                ),
                in: graphScope
            ) == nil)
        #expect(
            try await revalidator.revalidatedTarget(
                .clearCanvasHighlight(graphScope: foreignScope),
                in: graphScope
            ) == nil)
    }

    @Test
    func cancellationDuringCommitLeavesNoCommittedArtifactReference() async throws {
        let graphScope = GraphScope(graphID: UUID(uuidString: "E0000000-0000-0000-0000-000000000030")!)
        let sessionID = GraphChatAnswerArtifactSessionID()
        let revalidator = CommitBlockingArtifactRevalidator()
        let registry = GraphChatAnswerArtifactRegistry(
            graphScope: graphScope,
            sessionID: sessionID,
            revalidator: revalidator
        )
        let evidence = GraphEvidence(
            sourceReference: GraphSourceReference(
                graphID: graphScope.graphID,
                sourceKind: .graph,
                sourceID: graphScope.graphID
            ),
            summary: "Graph",
            identitySuffix: "commit-cancellation"
        )
        let evidenceRegistry = GraphChatEvidenceRegistry(scope: .entireGraph(graphScope))
        try await evidenceRegistry.register([evidence])
        let binding = GraphChatAnswerArtifactEvidenceBinding(evidenceIDs: [evidence.id])
        let transactionID = GraphChatAnswerArtifactTransactionID()
        let artifactID = try await registry.stage(
            GraphChatAnswerArtifactDraft(
                graphScope: graphScope,
                title: "Count",
                payload: .metric(
                    GraphChatAnswerArtifactMetricPayload(
                        title: "Count",
                        value: .integer(1),
                        unit: nil,
                        contextDescription: nil,
                        evidence: binding
                    )
                ),
                evidence: binding
            ),
            transactionID: transactionID,
            evidenceRegistry: evidenceRegistry
        )

        let commitTask = Task {
            try await registry.commit(
                transactionID: transactionID,
                retaining: [artifactID]
            )
        }
        for _ in 0..<1_000 {
            if await revalidator.callCount() >= 2 {
                break
            }
            await Task.yield()
        }
        commitTask.cancel()
        do {
            _ = try await commitTask.value
            Issue.record("Expected cancellation")
        } catch is CancellationError {
        }

        #expect(await registry.snapshotForTesting().isEmpty)
        #expect(
            await registry.stagedSnapshotForTesting(transactionID: transactionID).map(\.id) == [
                artifactID
            ])
    }
}

private actor MutableArtifactEvidenceSourceRepository: GraphEvidenceSourceReading {
    private var graph: GraphMetadataDTO?
    private var entitiesByID: [UUID: GraphEntityDTO]
    private var attributesByID: [UUID: GraphAttributeDTO]

    init(
        graph: GraphMetadataDTO,
        entities: [GraphEntityDTO],
        attributes: [GraphAttributeDTO]
    ) {
        self.graph = graph
        self.entitiesByID = Dictionary(uniqueKeysWithValues: entities.map { ($0.id, $0) })
        self.attributesByID = Dictionary(uniqueKeysWithValues: attributes.map { ($0.id, $0) })
    }

    func removeEntity(_ id: UUID) {
        entitiesByID.removeValue(forKey: id)
    }

    func removeAttribute(_ id: UUID) {
        attributesByID.removeValue(forKey: id)
    }

    func graphMetadata(in scope: GraphScope) async throws -> GraphMetadataDTO? {
        graph?.scope == scope ? graph : nil
    }

    func entity(id: UUID, in scope: GraphScope) async throws -> GraphEntityDTO? {
        guard let entity = entitiesByID[id], entity.scope == scope else {
            return nil
        }
        return entity
    }

    func attribute(id: UUID, in scope: GraphScope) async throws -> GraphAttributeDTO? {
        guard let attribute = attributesByID[id], attribute.scope == scope else {
            return nil
        }
        return attribute
    }

    func detailFieldDefinition(id: UUID, in scope: GraphScope) async throws
        -> GraphDetailFieldDefinitionDTO?
    {
        nil
    }

    func detailValue(id: UUID, in scope: GraphScope) async throws -> GraphDetailValueDTO? {
        nil
    }

    func link(id: UUID, in scope: GraphScope) async throws -> GraphLinkDTO? {
        nil
    }

    func attachmentMetadata(id: UUID, in scope: GraphScope) async throws
        -> GraphAttachmentMetadataDTO?
    {
        nil
    }
}

private actor CommitBlockingArtifactRevalidator: GraphChatAnswerArtifactRevalidating {
    private var calls = 0

    func callCount() -> Int {
        calls
    }

    func revalidatedArtifact(
        _ artifact: GraphChatAnswerArtifact,
        evidence: [GraphEvidence],
        in scope: GraphChatScope
    ) async throws -> GraphChatAnswerArtifact? {
        calls += 1
        if calls >= 2 {
            try await Task.sleep(nanoseconds: UInt64.max)
        }
        return artifact.graphScope == scope.graphScope ? artifact : nil
    }
}
