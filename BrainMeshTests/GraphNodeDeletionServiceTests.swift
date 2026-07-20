import Foundation
import SwiftData
import Testing

@testable import BrainMesh

@MainActor
struct GraphNodeDeletionServiceTests {

    @Test
    func deleteAttribute_removesDetailValuesLinksAndAttachments() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Primary")
        let owner = fixtures.makeEntity(name: "Owner", in: graph)
        let survivor = fixtures.makeEntity(name: "Survivor", in: graph)
        let attribute = fixtures.makeAttribute(name: "Target", owner: owner)
        let field = fixtures.makeDetailField(
            owner: owner,
            name: "Value",
            type: .singleLineText,
            sortIndex: 0
        )
        _ = fixtures.makeDetailValue(
            attribute: attribute,
            field: field,
            stringValue: "Stored"
        )
        _ = fixtures.makeLink(
            source: .entity(survivor),
            target: .attribute(attribute),
            graphID: graph.id
        )
        _ = fixtures.makeLink(
            source: .attribute(attribute),
            target: .entity(survivor),
            graphID: graph.id
        )
        let unrelatedLink = fixtures.makeLink(
            source: .entity(owner),
            target: .entity(survivor),
            graphID: graph.id
        )
        _ = fixtures.makeAttachment(owner: .attribute(attribute))
        let unrelatedAttachment = fixtures.makeAttachment(owner: .entity(survivor))
        try fixtures.save()

        let graphID = graph.id
        let attributeID = attribute.id
        let fieldID = field.id
        let unrelatedLinkID = unrelatedLink.id
        let unrelatedAttachmentID = unrelatedAttachment.id

        let result = try await GraphNodeDeletionService.deleteAttribute(
            attribute,
            in: store.context
        )

        #expect(
            result
                == GraphNodeDeletionService.Result(
                    requestedEntityCount: 0,
                    requestedAttributeCount: 1,
                    deletedEntityCount: 0,
                    deletedAttributeCount: 1,
                    deletedDetailFieldCount: 0,
                    deletedDetailValueCount: 1,
                    deletedLinkCount: 2,
                    deletedAttachmentCount: 1
                ))

        let snapshot = try makeSnapshot(for: store.container)
        #expect(snapshot.attributes.contains { $0.graphID == graphID && $0.id == attributeID } == false)
        #expect(snapshot.detailValues.contains { $0.graphID == graphID && $0.attributeID == attributeID } == false)
        #expect(snapshot.links.contains { linkReferences($0, kind: .attribute, id: attributeID) } == false)
        #expect(snapshot.attachments.contains { attachmentReferences($0, kind: .attribute, id: attributeID) } == false)
        #expect(snapshot.detailFields.contains { $0.graphID == graphID && $0.id == fieldID })
        #expect(snapshot.links.contains { $0.id == unrelatedLinkID })
        #expect(snapshot.attachments.contains { $0.id == unrelatedAttachmentID })
    }

    @Test
    func deleteAttribute_doesNotChangeMatchingScalarReferencesInAnotherGraph() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let primaryGraph = fixtures.makeGraph(name: "Primary")
        let otherGraph = fixtures.makeGraph(name: "Other")
        let sharedOwnerID = UUID()
        let sharedAttributeID = UUID()

        let primaryOwner = fixtures.makeEntity(
            name: "Same Owner",
            in: primaryGraph,
            id: sharedOwnerID
        )
        let primaryTarget = fixtures.makeAttribute(
            name: "Same Attribute",
            owner: primaryOwner,
            id: sharedAttributeID
        )
        let primarySurvivor = fixtures.makeEntity(name: "Primary Survivor", in: primaryGraph)
        let primaryField = fixtures.makeDetailField(
            owner: primaryOwner,
            name: "Primary Value",
            type: .singleLineText,
            sortIndex: 0
        )
        _ = fixtures.makeDetailValue(
            attribute: primaryTarget,
            field: primaryField,
            stringValue: "Primary"
        )
        _ = fixtures.makeLink(
            source: .attribute(primaryTarget),
            target: .entity(primarySurvivor),
            graphID: primaryGraph.id
        )
        _ = fixtures.makeAttachment(owner: .attribute(primaryTarget))

        let otherOwner = fixtures.makeEntity(
            name: "Same Owner",
            in: otherGraph,
            id: sharedOwnerID
        )
        let otherTarget = fixtures.makeAttribute(
            name: "Same Attribute",
            owner: otherOwner,
            id: sharedAttributeID
        )
        let otherSurvivor = fixtures.makeEntity(name: "Other Survivor", in: otherGraph)
        let otherField = fixtures.makeDetailField(
            owner: otherOwner,
            name: "Other Value",
            type: .singleLineText,
            sortIndex: 0
        )
        let otherValue = fixtures.makeDetailValue(
            attribute: otherTarget,
            field: otherField,
            stringValue: "Other"
        )
        let otherLink = fixtures.makeLink(
            source: .attribute(otherTarget),
            target: .entity(otherSurvivor),
            graphID: otherGraph.id
        )
        let otherAttachment = fixtures.makeAttachment(owner: .attribute(otherTarget))
        try fixtures.save()

        let otherGraphID = otherGraph.id
        let otherValueID = otherValue.id
        let otherLinkID = otherLink.id
        let otherAttachmentID = otherAttachment.id

        let result = try await GraphNodeDeletionService.deleteAttribute(
            primaryTarget,
            in: store.context
        )

        #expect(result.deletedAttributeCount == 1)
        #expect(result.deletedDetailValueCount == 1)
        #expect(result.deletedLinkCount == 1)
        #expect(result.deletedAttachmentCount == 1)

        let snapshot = try makeSnapshot(for: store.container)
        #expect(snapshot.attributes.contains { $0.graphID == otherGraphID && $0.id == sharedAttributeID })
        #expect(snapshot.detailValues.contains { $0.graphID == otherGraphID && $0.id == otherValueID })
        #expect(snapshot.links.contains { $0.graphID == otherGraphID && $0.id == otherLinkID })
        #expect(snapshot.attachments.contains { $0.graphID == otherGraphID && $0.id == otherAttachmentID })
    }

    @Test
    func deleteEntity_removesChildrenDetailsLinksAndAttachments() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Primary")
        let target = fixtures.makeEntity(name: "Target", in: graph)
        let firstAttribute = fixtures.makeAttribute(name: "First", owner: target)
        let secondAttribute = fixtures.makeAttribute(name: "Second", owner: target)
        let firstField = fixtures.makeDetailField(
            owner: target,
            name: "First Field",
            type: .singleLineText,
            sortIndex: 0
        )
        let secondField = fixtures.makeDetailField(
            owner: target,
            name: "Second Field",
            type: .toggle,
            sortIndex: 1
        )
        _ = fixtures.makeDetailValue(
            attribute: firstAttribute,
            field: firstField,
            stringValue: "First"
        )
        _ = fixtures.makeDetailValue(
            attribute: secondAttribute,
            field: secondField,
            boolValue: true
        )

        let survivor = fixtures.makeEntity(name: "Survivor", in: graph)
        let survivorAttribute = fixtures.makeAttribute(name: "Survivor Attribute", owner: survivor)
        _ = fixtures.makeLink(
            source: .entity(target),
            target: .entity(survivor),
            graphID: graph.id
        )
        _ = fixtures.makeLink(
            source: .entity(survivor),
            target: .attribute(firstAttribute),
            graphID: graph.id
        )
        _ = fixtures.makeLink(
            source: .attribute(firstAttribute),
            target: .attribute(secondAttribute),
            graphID: graph.id
        )
        let unrelatedLink = fixtures.makeLink(
            source: .entity(survivor),
            target: .attribute(survivorAttribute),
            graphID: graph.id
        )

        _ = fixtures.makeAttachment(owner: .entity(target))
        _ = fixtures.makeAttachment(owner: .attribute(firstAttribute))
        _ = fixtures.makeAttachment(owner: .attribute(secondAttribute))
        let unrelatedAttachment = fixtures.makeAttachment(owner: .entity(survivor))
        try fixtures.save()

        let graphID = graph.id
        let targetID = target.id
        let childAttributeIDs = Set([firstAttribute.id, secondAttribute.id])
        let fieldIDs = Set([firstField.id, secondField.id])
        let unrelatedLinkID = unrelatedLink.id
        let unrelatedAttachmentID = unrelatedAttachment.id

        let result = try await GraphNodeDeletionService.deleteEntity(
            target,
            in: store.context
        )

        #expect(
            result
                == GraphNodeDeletionService.Result(
                    requestedEntityCount: 1,
                    requestedAttributeCount: 0,
                    deletedEntityCount: 1,
                    deletedAttributeCount: 2,
                    deletedDetailFieldCount: 2,
                    deletedDetailValueCount: 2,
                    deletedLinkCount: 3,
                    deletedAttachmentCount: 3
                ))

        let snapshot = try makeSnapshot(for: store.container)
        #expect(snapshot.entities.contains { $0.graphID == graphID && $0.id == targetID } == false)
        #expect(snapshot.attributes.contains { $0.graphID == graphID && childAttributeIDs.contains($0.id) } == false)
        #expect(snapshot.detailFields.contains { $0.graphID == graphID && fieldIDs.contains($0.id) } == false)
        #expect(snapshot.detailValues.contains { $0.graphID == graphID && childAttributeIDs.contains($0.attributeID) } == false)
        #expect(
            snapshot.links.contains { link in
                linkReferences(link, kind: .entity, id: targetID)
                    || childAttributeIDs.contains(where: { linkReferences(link, kind: .attribute, id: $0) })
            } == false)
        #expect(
            snapshot.attachments.contains { attachment in
                attachmentReferences(attachment, kind: .entity, id: targetID)
                    || childAttributeIDs.contains(where: { attachmentReferences(attachment, kind: .attribute, id: $0) })
            } == false)
        #expect(snapshot.links.contains { $0.id == unrelatedLinkID })
        #expect(snapshot.attachments.contains { $0.id == unrelatedAttachmentID })
    }

    @Test
    func deleteEntity_doesNotChangeMatchingNodesInAnotherGraph() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let primaryGraph = fixtures.makeGraph(name: "Primary")
        let otherGraph = fixtures.makeGraph(name: "Other")
        let sharedEntityID = UUID()
        let sharedAttributeID = UUID()

        let primaryEntity = fixtures.makeEntity(
            name: "Same Entity",
            in: primaryGraph,
            id: sharedEntityID
        )
        let primaryAttribute = fixtures.makeAttribute(
            name: "Same Attribute",
            owner: primaryEntity,
            id: sharedAttributeID
        )
        let primaryField = fixtures.makeDetailField(
            owner: primaryEntity,
            name: "Primary Field",
            type: .singleLineText,
            sortIndex: 0
        )
        _ = fixtures.makeDetailValue(
            attribute: primaryAttribute,
            field: primaryField,
            stringValue: "Primary"
        )
        _ = fixtures.makeLink(
            source: .entity(primaryEntity),
            target: .attribute(primaryAttribute),
            graphID: primaryGraph.id
        )
        _ = fixtures.makeAttachment(owner: .entity(primaryEntity))
        _ = fixtures.makeAttachment(owner: .attribute(primaryAttribute))

        let otherEntity = fixtures.makeEntity(
            name: "Same Entity",
            in: otherGraph,
            id: sharedEntityID
        )
        let otherAttribute = fixtures.makeAttribute(
            name: "Same Attribute",
            owner: otherEntity,
            id: sharedAttributeID
        )
        let otherField = fixtures.makeDetailField(
            owner: otherEntity,
            name: "Other Field",
            type: .singleLineText,
            sortIndex: 0
        )
        let otherValue = fixtures.makeDetailValue(
            attribute: otherAttribute,
            field: otherField,
            stringValue: "Other"
        )
        let otherLink = fixtures.makeLink(
            source: .entity(otherEntity),
            target: .attribute(otherAttribute),
            graphID: otherGraph.id
        )
        let otherEntityAttachment = fixtures.makeAttachment(owner: .entity(otherEntity))
        let otherAttributeAttachment = fixtures.makeAttachment(owner: .attribute(otherAttribute))
        try fixtures.save()

        let otherGraphID = otherGraph.id
        let otherFieldID = otherField.id
        let otherValueID = otherValue.id
        let otherLinkID = otherLink.id
        let otherAttachmentIDs = Set([otherEntityAttachment.id, otherAttributeAttachment.id])

        let result = try await GraphNodeDeletionService.deleteEntity(
            primaryEntity,
            in: store.context
        )

        #expect(result.deletedEntityCount == 1)
        #expect(result.deletedAttributeCount == 1)
        #expect(result.deletedDetailFieldCount == 1)
        #expect(result.deletedDetailValueCount == 1)
        #expect(result.deletedLinkCount == 1)
        #expect(result.deletedAttachmentCount == 2)

        let snapshot = try makeSnapshot(for: store.container)
        #expect(snapshot.entities.contains { $0.graphID == otherGraphID && $0.id == sharedEntityID })
        #expect(snapshot.attributes.contains { $0.graphID == otherGraphID && $0.id == sharedAttributeID })
        #expect(snapshot.detailFields.contains { $0.graphID == otherGraphID && $0.id == otherFieldID })
        #expect(snapshot.detailValues.contains { $0.graphID == otherGraphID && $0.id == otherValueID })
        #expect(snapshot.links.contains { $0.graphID == otherGraphID && $0.id == otherLinkID })
        #expect(snapshot.attachments.filter { $0.graphID == otherGraphID && otherAttachmentIDs.contains($0.id) }.count == 2)
    }

    @Test
    func deleteAttributesBatch_commitsAndLeavesNoScalarOrphans() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Primary")
        let owner = fixtures.makeEntity(name: "Owner", in: graph)
        let first = fixtures.makeAttribute(name: "First", owner: owner)
        let second = fixtures.makeAttribute(name: "Second", owner: owner)
        let survivor = fixtures.makeEntity(name: "Survivor", in: graph)
        let field = fixtures.makeDetailField(
            owner: owner,
            name: "Value",
            type: .singleLineText,
            sortIndex: 0
        )
        _ = fixtures.makeDetailValue(attribute: first, field: field, stringValue: "First")
        _ = fixtures.makeDetailValue(attribute: second, field: field, stringValue: "Second")

        _ = fixtures.makeLink(
            source: .attribute(first),
            target: .attribute(second),
            graphID: graph.id
        )
        _ = fixtures.makeLink(
            source: .attribute(second),
            target: .entity(survivor),
            graphID: graph.id
        )
        _ = fixtures.makeLink(
            source: .entity(survivor),
            target: .attribute(first),
            graphID: graph.id
        )
        let unrelatedLink = fixtures.makeLink(
            source: .entity(owner),
            target: .entity(survivor),
            graphID: graph.id
        )
        _ = fixtures.makeAttachment(owner: .attribute(first))
        _ = fixtures.makeAttachment(owner: .attribute(second))
        try fixtures.save()

        let graphID = graph.id
        let deletedAttributeIDs = Set([first.id, second.id])
        let unrelatedLinkID = unrelatedLink.id

        let result = try await GraphNodeDeletionService.deleteAttributes(
            [first, second, first],
            in: store.context
        )

        #expect(
            result
                == GraphNodeDeletionService.Result(
                    requestedEntityCount: 0,
                    requestedAttributeCount: 2,
                    deletedEntityCount: 0,
                    deletedAttributeCount: 2,
                    deletedDetailFieldCount: 0,
                    deletedDetailValueCount: 2,
                    deletedLinkCount: 3,
                    deletedAttachmentCount: 2
                ))

        let snapshot = try makeSnapshot(for: store.container)
        #expect(snapshot.attributes.contains { $0.graphID == graphID && deletedAttributeIDs.contains($0.id) } == false)
        #expect(snapshot.detailValues.contains { $0.graphID == graphID && deletedAttributeIDs.contains($0.attributeID) } == false)
        #expect(
            snapshot.links.contains { link in
                deletedAttributeIDs.contains(where: { linkReferences(link, kind: .attribute, id: $0) })
            } == false)
        #expect(
            snapshot.attachments.contains { attachment in
                deletedAttributeIDs.contains(where: { attachmentReferences(attachment, kind: .attribute, id: $0) })
            } == false)
        #expect(snapshot.links.contains { $0.id == unrelatedLinkID })
    }

    @Test
    func deleteAttribute_missingTargetCleansDanglingDependencies() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Primary")
        let survivor = fixtures.makeEntity(name: "Survivor", in: graph)
        let missingAttribute = MetaAttribute(
            name: "Missing",
            owner: nil,
            graphID: graph.id
        )
        let danglingLink = fixtures.makeLink(
            source: .entity(survivor),
            target: .attribute(missingAttribute),
            graphID: graph.id
        )
        let danglingAttachment = fixtures.makeAttachment(owner: .attribute(missingAttribute))
        let danglingDetailValue = MetaDetailFieldValue(
            attribute: missingAttribute,
            fieldID: UUID()
        )
        danglingDetailValue.attribute = nil
        danglingDetailValue.attributeID = missingAttribute.id
        danglingDetailValue.graphID = graph.id
        store.context.insert(danglingDetailValue)
        try fixtures.save()

        let missingAttributeID = missingAttribute.id
        let danglingLinkID = danglingLink.id
        let danglingAttachmentID = danglingAttachment.id
        let danglingDetailValueID = danglingDetailValue.id

        let before = try makeSnapshot(for: store.container)
        #expect(before.attributes.contains { $0.id == missingAttributeID } == false)
        #expect(before.links.contains { $0.id == danglingLinkID })
        #expect(before.attachments.contains { $0.id == danglingAttachmentID })
        #expect(before.detailValues.contains { $0.id == danglingDetailValueID })

        let result = try await GraphNodeDeletionService.deleteAttribute(
            missingAttribute,
            in: store.context
        )

        #expect(result.requestedAttributeCount == 1)
        #expect(result.deletedAttributeCount == 0)
        #expect(result.deletedDetailValueCount == 1)
        #expect(result.deletedLinkCount == 1)
        #expect(result.deletedAttachmentCount == 1)

        let snapshot = try makeSnapshot(for: store.container)
        #expect(snapshot.links.contains { $0.id == danglingLinkID } == false)
        #expect(snapshot.attachments.contains { $0.id == danglingAttachmentID } == false)
        #expect(snapshot.detailValues.contains { $0.id == danglingDetailValueID } == false)
    }

    @Test
    func deleteAttribute_alreadyDeletedDependenciesRemainConsistent() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Primary")
        let owner = fixtures.makeEntity(name: "Owner", in: graph)
        let survivor = fixtures.makeEntity(name: "Survivor", in: graph)
        let attribute = fixtures.makeAttribute(name: "Target", owner: owner)
        let field = fixtures.makeDetailField(
            owner: owner,
            name: "Value",
            type: .singleLineText,
            sortIndex: 0
        )
        _ = fixtures.makeDetailValue(attribute: attribute, field: field, stringValue: "Stored")
        let link = fixtures.makeLink(
            source: .attribute(attribute),
            target: .entity(survivor),
            graphID: graph.id
        )
        let attachment = fixtures.makeAttachment(owner: .attribute(attribute))
        try fixtures.save()

        store.context.delete(link)
        store.context.delete(attachment)
        try store.context.save()

        let attributeID = attribute.id
        let result = try await GraphNodeDeletionService.deleteAttribute(
            attribute,
            in: store.context
        )

        #expect(result.deletedAttributeCount == 1)
        #expect(result.deletedDetailValueCount == 1)
        #expect(result.deletedLinkCount == 0)
        #expect(result.deletedAttachmentCount == 0)

        let snapshot = try makeSnapshot(for: store.container)
        #expect(snapshot.attributes.contains { $0.id == attributeID } == false)
        #expect(snapshot.detailValues.contains { $0.attributeID == attributeID } == false)
        #expect(snapshot.links.contains { linkReferences($0, kind: .attribute, id: attributeID) } == false)
        #expect(snapshot.attachments.contains { attachmentReferences($0, kind: .attribute, id: attributeID) } == false)
    }

    @Test
    func cancelledDeleteDoesNotMutateData() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Primary")
        let owner = fixtures.makeEntity(name: "Owner", in: graph)
        let survivor = fixtures.makeEntity(name: "Survivor", in: graph)
        let attribute = fixtures.makeAttribute(name: "Target", owner: owner)
        let link = fixtures.makeLink(
            source: .attribute(attribute),
            target: .entity(survivor),
            graphID: graph.id
        )
        let attachment = fixtures.makeAttachment(owner: .attribute(attribute))
        try fixtures.save()

        let attributeID = attribute.id
        let linkID = link.id
        let attachmentID = attachment.id

        let deletionTask = Task { @MainActor in
            try await GraphNodeDeletionService.deleteAttribute(
                attribute,
                in: store.context
            )
        }
        deletionTask.cancel()

        do {
            _ = try await deletionTask.value
            Issue.record("Expected cancelled deletion")
        } catch let error as GraphNodeDeletionService.DeletionError {
            #expect(error == .cancelled)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        let snapshot = try makeSnapshot(for: store.container)
        #expect(snapshot.attributes.contains { $0.id == attributeID })
        #expect(snapshot.links.contains { $0.id == linkID })
        #expect(snapshot.attachments.contains { $0.id == attachmentID })
    }

    @Test
    func deleteAttribute_withoutGraphScopeFailsWithoutMutatingData() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let owner = fixtures.makeEntity(name: "Legacy Owner")
        let attribute = fixtures.makeAttribute(name: "Legacy Attribute", owner: owner)
        let link = fixtures.makeLink(
            source: .entity(owner),
            target: .attribute(attribute),
            graphID: nil
        )
        let attachment = fixtures.makeAttachment(owner: .attribute(attribute))
        try fixtures.save()

        let attributeID = attribute.id
        let linkID = link.id
        let attachmentID = attachment.id

        do {
            _ = try await GraphNodeDeletionService.deleteAttribute(
                attribute,
                in: store.context
            )
            Issue.record("Expected missing graph scope failure")
        } catch let error as GraphNodeDeletionService.DeletionError {
            #expect(error == .missingGraphScope)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        let snapshot = try makeSnapshot(for: store.container)
        #expect(snapshot.attributes.contains { $0.id == attributeID })
        #expect(snapshot.links.contains { $0.id == linkID })
        #expect(snapshot.attachments.contains { $0.id == attachmentID })
    }

    private struct NodeRecord {
        let id: UUID
        let graphID: UUID?
    }

    private struct LinkRecord {
        let id: UUID
        let graphID: UUID?
        let sourceKindRaw: Int
        let sourceID: UUID
        let targetKindRaw: Int
        let targetID: UUID
    }

    private struct AttachmentRecord {
        let id: UUID
        let graphID: UUID?
        let ownerKindRaw: Int
        let ownerID: UUID
    }

    private struct DetailValueRecord {
        let id: UUID
        let graphID: UUID?
        let attributeID: UUID
    }

    private struct Snapshot {
        let entities: [NodeRecord]
        let attributes: [NodeRecord]
        let links: [LinkRecord]
        let attachments: [AttachmentRecord]
        let detailFields: [NodeRecord]
        let detailValues: [DetailValueRecord]
    }

    private func makeSnapshot(for container: ModelContainer) throws -> Snapshot {
        let context = BrainMeshTestContainer.makeContext(for: container)
        let entities = try context.fetch(FetchDescriptor<MetaEntity>())
        let attributes = try context.fetch(FetchDescriptor<MetaAttribute>())
        let links = try context.fetch(FetchDescriptor<MetaLink>())
        let attachments = try context.fetch(FetchDescriptor<MetaAttachment>())
        let detailFields = try context.fetch(FetchDescriptor<MetaDetailFieldDefinition>())
        let detailValues = try context.fetch(FetchDescriptor<MetaDetailFieldValue>())

        return Snapshot(
            entities: entities.map { NodeRecord(id: $0.id, graphID: $0.graphID) },
            attributes: attributes.map { NodeRecord(id: $0.id, graphID: $0.graphID) },
            links: links.map {
                LinkRecord(
                    id: $0.id,
                    graphID: $0.graphID,
                    sourceKindRaw: $0.sourceKindRaw,
                    sourceID: $0.sourceID,
                    targetKindRaw: $0.targetKindRaw,
                    targetID: $0.targetID
                )
            },
            attachments: attachments.map {
                AttachmentRecord(
                    id: $0.id,
                    graphID: $0.graphID,
                    ownerKindRaw: $0.ownerKindRaw,
                    ownerID: $0.ownerID
                )
            },
            detailFields: detailFields.map { NodeRecord(id: $0.id, graphID: $0.graphID) },
            detailValues: detailValues.map {
                DetailValueRecord(
                    id: $0.id,
                    graphID: $0.graphID,
                    attributeID: $0.attributeID
                )
            }
        )
    }

    private func linkReferences(
        _ link: LinkRecord,
        kind: NodeKind,
        id: UUID
    ) -> Bool {
        let rawKind = kind.rawValue
        return (link.sourceKindRaw == rawKind && link.sourceID == id)
            || (link.targetKindRaw == rawKind && link.targetID == id)
    }

    private func attachmentReferences(
        _ attachment: AttachmentRecord,
        kind: NodeKind,
        id: UUID
    ) -> Bool {
        attachment.ownerKindRaw == kind.rawValue && attachment.ownerID == id
    }
}
