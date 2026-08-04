import Foundation
import Testing
@testable import BrainMesh

struct GraphMutationClassificationTests {
    @Test
    func classificationMatrixCoversAllPR05ABasisMutations() throws {
        let graphID = testUUID(100)
        let entityID = testUUID(101)
        let ownerEntityID = testUUID(102)
        let attributeID = testUUID(103)
        let source = NodeRefKey(kind: .entity, id: testUUID(104))
        let target = NodeRefKey(kind: .attribute, id: testUUID(105))
        let link = GraphMutationLinkReference(
            id: testUUID(106),
            source: source,
            target: target
        )
        let fieldID = testUUID(107)
        let value = GraphMutationDetailValueReference(
            id: testUUID(108),
            ownerAttributeID: attributeID,
            fieldID: fieldID
        )

        let matrix: [GraphMutationClassificationCase] = [
            GraphMutationClassificationCase(
                name: "entity-create",
                batch: try GraphMutationBatchFactory.entityCreated(
                    graphID: graphID,
                    entityID: entityID
                ),
                expectedEvents: [
                    ExpectedMutationEvent(
                        kind: .entityCreated,
                        references: [
                            .node(NodeRefKey(kind: .entity, id: entityID))
                        ]
                    )
                ]
            ),
            GraphMutationClassificationCase(
                name: "attribute-create",
                batch: try GraphMutationBatchFactory.attributeCreated(
                    graphID: graphID,
                    attributeID: attributeID,
                    ownerEntityID: ownerEntityID
                ),
                expectedEvents: [
                    ExpectedMutationEvent(
                        kind: .attributeCreated,
                        references: [
                            .node(NodeRefKey(kind: .attribute, id: attributeID)),
                            .node(NodeRefKey(kind: .entity, id: ownerEntityID))
                        ]
                    )
                ]
            ),
            GraphMutationClassificationCase(
                name: "link-create",
                batch: try GraphMutationBatchFactory.linksCreated(
                    graphID: graphID,
                    links: [link]
                ),
                expectedEvents: [
                    ExpectedMutationEvent(
                        kind: .linkCreated,
                        references: [
                            .link(id: link.id, source: source, target: target)
                        ]
                    )
                ]
            ),
            GraphMutationClassificationCase(
                name: "link-update",
                batch: try GraphMutationBatchFactory.linkUpdated(
                    graphID: graphID,
                    link: link
                ),
                expectedEvents: [
                    ExpectedMutationEvent(
                        kind: .linkUpdated,
                        references: [
                            .link(id: link.id, source: source, target: target)
                        ]
                    )
                ]
            ),
            GraphMutationClassificationCase(
                name: "link-delete",
                batch: try GraphMutationBatchFactory.linksDeleted(
                    graphID: graphID,
                    links: [link]
                ),
                expectedEvents: [
                    ExpectedMutationEvent(
                        kind: .linkDeleted,
                        references: [
                            .link(id: link.id, source: source, target: target)
                        ]
                    )
                ]
            ),
            GraphMutationClassificationCase(
                name: "detail-schema-change",
                batch: try GraphMutationBatchFactory.detailSchemaChanged(
                    graphID: graphID,
                    ownerEntityID: ownerEntityID,
                    definitionIDs: [fieldID]
                ),
                expectedEvents: [
                    ExpectedMutationEvent(
                        kind: .detailSchemaChanged,
                        references: [
                            .detailFieldDefinition(
                                id: fieldID,
                                ownerEntityID: ownerEntityID
                            )
                        ]
                    )
                ]
            ),
            GraphMutationClassificationCase(
                name: "detail-value-change",
                batch: try GraphMutationBatchFactory.detailValueChanged(
                    graphID: graphID,
                    value: value
                ),
                expectedEvents: [
                    ExpectedMutationEvent(
                        kind: .detailValueChanged,
                        references: [
                            .detailValue(
                                id: value.id,
                                ownerAttributeID: attributeID,
                                fieldID: fieldID
                            )
                        ]
                    )
                ]
            ),
            GraphMutationClassificationCase(
                name: "detail-value-delete",
                batch: try GraphMutationBatchFactory.detailValueDeleted(
                    graphID: graphID,
                    value: value
                ),
                expectedEvents: [
                    ExpectedMutationEvent(
                        kind: .detailValueDeleted,
                        references: [
                            .detailValue(
                                id: value.id,
                                ownerAttributeID: attributeID,
                                fieldID: fieldID
                            )
                        ]
                    )
                ]
            )
        ]

        for entry in matrix {
            #expect(entry.batch.graphID == graphID, Comment(rawValue: entry.name))
            #expect(
                entry.batch.events.map(\.graphID) == Array(
                    repeating: graphID,
                    count: entry.expectedEvents.count
                ),
                Comment(rawValue: entry.name)
            )
            #expect(
                entry.batch.events.map { event in
                    ExpectedMutationEvent(
                        kind: event.kind,
                        references: event.references
                    )
                } == entry.expectedEvents,
                Comment(rawValue: entry.name)
            )
            #expect(
                containsForbiddenUserPayload(entry.batch) == false,
                Comment(rawValue: entry.name)
            )
        }
    }

    @Test
    func bidirectionalLinkOrderIsForwardThenReverse() throws {
        let graphID = testUUID(200)
        let firstNode = NodeRefKey(kind: .entity, id: testUUID(201))
        let secondNode = NodeRefKey(kind: .attribute, id: testUUID(202))
        let forward = GraphMutationLinkReference(
            id: testUUID(203),
            source: firstNode,
            target: secondNode
        )
        let reverse = GraphMutationLinkReference(
            id: testUUID(204),
            source: secondNode,
            target: firstNode
        )

        let batch = try GraphMutationBatchFactory.linksCreated(
            graphID: graphID,
            links: [forward, reverse]
        )

        #expect(batch.events.map(\.kind) == [.linkCreated, .linkCreated])
        #expect(
            batch.events.map(\.references) == [
                [.link(id: forward.id, source: firstNode, target: secondNode)],
                [.link(id: reverse.id, source: secondNode, target: firstNode)]
            ]
        )
    }

    @Test
    func multiLinkDeleteOrderIsIndependentOfSelectionOrder() throws {
        let graphID = testUUID(250)
        let source = NodeRefKey(kind: .entity, id: testUUID(251))
        let target = NodeRefKey(kind: .attribute, id: testUUID(252))
        let first = GraphMutationLinkReference(
            id: testUUID(253),
            source: source,
            target: target
        )
        let second = GraphMutationLinkReference(
            id: testUUID(254),
            source: target,
            target: source
        )

        let batch = try GraphMutationBatchFactory.linksDeleted(
            graphID: graphID,
            links: [second, first]
        )

        #expect(batch.events.map(\.kind) == [.linkDeleted, .linkDeleted])
        #expect(
            batch.events.map(\.references) == [
                [.link(id: first.id, source: source, target: target)],
                [.link(id: second.id, source: target, target: source)]
            ]
        )
    }

    @Test
    func multipleLinkDeletionOrderIsIndependentOfSelectionOrder() throws {
        let graphID = testUUID(250)
        let source = NodeRefKey(kind: .entity, id: testUUID(251))
        let target = NodeRefKey(kind: .attribute, id: testUUID(252))
        let first = GraphMutationLinkReference(
            id: testUUID(253),
            source: source,
            target: target
        )
        let second = GraphMutationLinkReference(
            id: testUUID(254),
            source: target,
            target: source
        )
        let third = GraphMutationLinkReference(
            id: testUUID(255),
            source: source,
            target: target
        )

        let batch = try GraphMutationBatchFactory.linksDeleted(
            graphID: graphID,
            links: [third, first, second]
        )

        #expect(batch.events.map(\.kind) == [.linkDeleted, .linkDeleted, .linkDeleted])
        #expect(
            batch.events.map(\.references) == [
                [.link(id: first.id, source: first.source, target: first.target)],
                [.link(id: second.id, source: second.source, target: second.target)],
                [.link(id: third.id, source: third.source, target: third.target)]
            ]
        )
    }

    @Test
    func detailFieldCleanupOrderIsIndependentOfFetchOrder() throws {
        let graphID = testUUID(300)
        let ownerEntityID = testUUID(301)
        let firstFieldID = testUUID(302)
        let secondFieldID = testUUID(303)
        let firstValue = GraphMutationDetailValueReference(
            id: testUUID(304),
            ownerAttributeID: testUUID(305),
            fieldID: firstFieldID
        )
        let secondValue = GraphMutationDetailValueReference(
            id: testUUID(306),
            ownerAttributeID: testUUID(307),
            fieldID: firstFieldID
        )
        let thirdValue = GraphMutationDetailValueReference(
            id: testUUID(308),
            ownerAttributeID: testUUID(309),
            fieldID: secondFieldID
        )

        let batch = try GraphMutationBatchFactory.detailFieldsDeleted(
            graphID: graphID,
            ownerEntityID: ownerEntityID,
            affectedDefinitionIDs: [secondFieldID, firstFieldID, secondFieldID],
            deletedValues: [thirdValue, secondValue, firstValue]
        )

        #expect(
            batch.events.map(\.kind) == [
                .detailValueDeleted,
                .detailValueDeleted,
                .detailValueDeleted,
                .detailSchemaChanged
            ]
        )
        #expect(
            batch.events.map(\.references) == [
                [
                    .detailValue(
                        id: firstValue.id,
                        ownerAttributeID: firstValue.ownerAttributeID,
                        fieldID: firstValue.fieldID
                    )
                ],
                [
                    .detailValue(
                        id: secondValue.id,
                        ownerAttributeID: secondValue.ownerAttributeID,
                        fieldID: secondValue.fieldID
                    )
                ],
                [
                    .detailValue(
                        id: thirdValue.id,
                        ownerAttributeID: thirdValue.ownerAttributeID,
                        fieldID: thirdValue.fieldID
                    )
                ],
                [
                    .detailFieldDefinition(
                        id: firstFieldID,
                        ownerEntityID: ownerEntityID
                    ),
                    .detailFieldDefinition(
                        id: secondFieldID,
                        ownerEntityID: ownerEntityID
                    )
                ]
            ]
        )
    }

    @Test
    func classificationMatrixCoversPR05BNodeAndAttachmentMutations() throws {
        let graphID = testUUID(400)
        let entity = NodeRefKey(kind: .entity, id: testUUID(401))
        let attribute = NodeRefKey(kind: .attribute, id: testUUID(402))
        let entityAttachment = GraphMutationAttachmentReference(
            id: testUUID(403),
            owner: entity
        )
        let attributeAttachment = GraphMutationAttachmentReference(
            id: testUUID(404),
            owner: attribute
        )

        let matrix: [GraphMutationClassificationCase] = [
            GraphMutationClassificationCase(
                name: "entity-notes-or-header-update",
                batch: try GraphMutationBatchFactory.nodeUpdated(
                    graphID: graphID,
                    node: entity
                ),
                expectedEvents: [
                    ExpectedMutationEvent(
                        kind: .entityUpdated,
                        references: [.node(entity)]
                    )
                ]
            ),
            GraphMutationClassificationCase(
                name: "attribute-notes-or-header-update",
                batch: try GraphMutationBatchFactory.nodeUpdated(
                    graphID: graphID,
                    node: attribute
                ),
                expectedEvents: [
                    ExpectedMutationEvent(
                        kind: .attributeUpdated,
                        references: [.node(attribute)]
                    )
                ]
            ),
            GraphMutationClassificationCase(
                name: "gallery-or-attachment-create",
                batch: try GraphMutationBatchFactory.attachmentsCreated(
                    graphID: graphID,
                    attachments: [entityAttachment]
                ),
                expectedEvents: [
                    ExpectedMutationEvent(
                        kind: .attachmentCreated,
                        references: [
                            .attachment(id: entityAttachment.id, owner: entity)
                        ]
                    )
                ]
            ),
            GraphMutationClassificationCase(
                name: "attachment-update",
                batch: try GraphMutationBatchFactory.attachmentsUpdated(
                    graphID: graphID,
                    attachments: [attributeAttachment]
                ),
                expectedEvents: [
                    ExpectedMutationEvent(
                        kind: .attachmentUpdated,
                        references: [
                            .attachment(id: attributeAttachment.id, owner: attribute)
                        ]
                    )
                ]
            ),
            GraphMutationClassificationCase(
                name: "attachment-delete",
                batch: try GraphMutationBatchFactory.attachmentsDeleted(
                    graphID: graphID,
                    attachments: [entityAttachment]
                ),
                expectedEvents: [
                    ExpectedMutationEvent(
                        kind: .attachmentDeleted,
                        references: [
                            .attachment(id: entityAttachment.id, owner: entity)
                        ]
                    )
                ]
            )
        ]

        for entry in matrix {
            #expect(entry.batch.graphID == graphID, Comment(rawValue: entry.name))
            #expect(
                entry.batch.events.map {
                    ExpectedMutationEvent(
                        kind: $0.kind,
                        references: $0.references
                    )
                } == entry.expectedEvents,
                Comment(rawValue: entry.name)
            )
            #expect(
                containsForbiddenUserPayload(entry.batch) == false,
                Comment(rawValue: entry.name)
            )
        }
    }

    @Test
    func renameBatchOrdersNodeBeforeRelabeledLinksSortedByTechnicalID() throws {
        let graphID = testUUID(450)
        let node = NodeRefKey(kind: .entity, id: testUUID(451))
        let target = NodeRefKey(kind: .attribute, id: testUUID(452))
        let laterLink = GraphMutationLinkReference(
            id: testUUID(454),
            source: node,
            target: target
        )
        let earlierLink = GraphMutationLinkReference(
            id: testUUID(453),
            source: target,
            target: node
        )

        let batch = try GraphMutationBatchFactory.nodeRenamed(
            graphID: graphID,
            node: node,
            relabeledLinks: [laterLink, earlierLink]
        )

        #expect(batch.events.map(\.kind) == [.entityUpdated, .linkUpdated, .linkUpdated])
        #expect(batch.events.first?.references == [.node(node)])
        #expect(
            batch.events.dropFirst().compactMap { event -> UUID? in
                guard case .link(let id, _, _) = event.references.first else { return nil }
                return id
            } == [earlierLink.id, laterLink.id]
        )
        #expect(containsForbiddenUserPayload(batch) == false)
    }

    @Test
    func nodeContentUpdatesAndRenamesHaveExplicitSchemaImpacts() throws {
        let graphID = testUUID(460)
        let nodes = [
            NodeRefKey(kind: .entity, id: testUUID(461)),
            NodeRefKey(kind: .attribute, id: testUUID(462))
        ]

        for node in nodes {
            let contentUpdate = try GraphMutationBatchFactory.nodeUpdated(
                graphID: graphID,
                node: node
            )
            let contentUpdateEvent = try #require(
                contentUpdate.events.first
            )
            #expect(contentUpdate.events.count == 1)
            #expect(
                contentUpdateEvent.schemaImpact
                    == GraphMutationSchemaImpact.none
            )

            let rename = try GraphMutationBatchFactory.nodeRenamed(
                graphID: graphID,
                node: node,
                relabeledLinks: []
            )
            let renameEvent = try #require(rename.events.first)
            #expect(rename.events.count == 1)
            #expect(
                renameEvent.schemaImpact
                    == GraphMutationSchemaImpact.structure
            )
        }
    }

    @Test
    func classificationMatrixCoversPR05CGraphwideMutations() throws {
        let graphID = testUUID(470)
        let templateID = testUUID(471)

        let cases: [(String, GraphMutationBatch, [GraphMutationKind], [GraphMutationReference])] = [
            (
                "graph-create",
                try GraphMutationBatchFactory.graphCreated(graphID: graphID),
                [.graphCreated],
                [.graph]
            ),
            (
                "graph-update",
                try GraphMutationBatchFactory.graphUpdated(graphID: graphID),
                [.graphUpdated],
                [.graph]
            ),
            (
                "graph-delete",
                try GraphMutationBatchFactory.graphDeleted(graphID: graphID),
                [.graphDeleted],
                [.graph]
            ),
            (
                "graph-import",
                try GraphMutationBatchFactory.graphImported(graphID: graphID),
                [.graphImported, .graphRequiresFullRebuild(.graphImport)],
                [.graph, .graph]
            ),
            (
                "graph-replace",
                try GraphMutationBatchFactory.graphReplaced(graphID: graphID),
                [.graphReplaced, .graphRequiresFullRebuild(.graphReplacement)],
                [.graph, .graph]
            ),
            (
                "integrity-repair",
                try GraphMutationBatchFactory.graphIntegrityRepair(graphID: graphID),
                [.graphRequiresFullRebuild(.integrityRepair)],
                [.graph]
            ),
            (
                "detail-template-create",
                try GraphMutationBatchFactory.detailTemplateCreated(
                    graphID: graphID,
                    templateID: templateID
                ),
                [.detailTemplateCreated],
                [.detailTemplate(id: templateID)]
            )
        ]

        for (name, batch, expectedKinds, expectedReferences) in cases {
            #expect(batch.graphID == graphID, Comment(rawValue: name))
            #expect(batch.events.map(\.kind) == expectedKinds, Comment(rawValue: name))
            #expect(
                batch.events.flatMap(\.references) == expectedReferences,
                Comment(rawValue: name)
            )
            #expect(containsForbiddenUserPayload(batch) == false, Comment(rawValue: name))
        }
    }

    @Test
    func nodeCleanupBatchUsesStableDependencyOrder() throws {
        let graphID = testUUID(500)
        let entityID = testUUID(501)
        let attributeID = testUUID(502)
        let fieldID = testUUID(503)
        let value = GraphMutationDetailValueReference(
            id: testUUID(504),
            ownerAttributeID: attributeID,
            fieldID: fieldID
        )
        let link = GraphMutationLinkReference(
            id: testUUID(505),
            source: NodeRefKey(kind: .entity, id: entityID),
            target: NodeRefKey(kind: .attribute, id: attributeID)
        )
        let attachment = GraphMutationAttachmentReference(
            id: testUUID(506),
            owner: NodeRefKey(kind: .attribute, id: attributeID)
        )

        let batch = try GraphMutationBatchFactory.nodeDeletion(
            graphID: graphID,
            links: [link],
            detailValues: [value],
            detailSchemas: [
                GraphMutationDetailSchemaCleanupReference(
                    ownerEntityID: entityID,
                    definitionIDs: [fieldID]
                )
            ],
            attachments: [attachment],
            attributeIDs: [attributeID],
            entityIDs: [entityID]
        )

        #expect(
            batch.events.map(\.kind) == [
                .linkDeleted,
                .detailValueDeleted,
                .detailSchemaChanged,
                .attachmentDeleted,
                .attributeDeleted,
                .entityDeleted
            ]
        )
        #expect(containsForbiddenUserPayload(batch) == false)
    }

}

private struct GraphMutationClassificationCase {
    let name: String
    let batch: GraphMutationBatch
    let expectedEvents: [ExpectedMutationEvent]
}

private struct ExpectedMutationEvent: Equatable {
    let kind: GraphMutationKind
    let references: [GraphMutationReference]
}

private func containsForbiddenUserPayload(_ value: Any) -> Bool {
    if value is String || value is Data {
        return true
    }

    let mirror = Mirror(reflecting: value)
    return mirror.children.contains { child in
        containsForbiddenUserPayload(child.value)
    }
}

private func testUUID(_ value: Int) -> UUID {
    let suffix = String(format: "%012X", value)
    return UUID(uuidString: "00000000-0000-0000-0000-\(suffix)")!
}
