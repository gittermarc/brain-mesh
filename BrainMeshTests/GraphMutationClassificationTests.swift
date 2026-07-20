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
