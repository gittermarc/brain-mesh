import Foundation
import Testing

@testable import BrainMesh

struct GraphReadRepositoryTests {

    @Test
    func everySourceDTOIsHardScopedToTheRequestedGraph() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let primaryGraph = fixtures.makeGraph(name: "Primary")
        let secondaryGraph = fixtures.makeGraph(name: "Secondary")

        let sharedEntityID = UUID()
        let sharedAttributeID = UUID()
        let sharedFieldID = UUID()
        let sharedValueID = UUID()
        let sharedLinkID = UUID()
        let sharedAttachmentID = UUID()

        let primaryEntity = fixtures.makeEntity(
            name: "Primary Entity",
            in: primaryGraph,
            notes: "Primary Notes",
            id: sharedEntityID
        )
        let primaryAttribute = fixtures.makeAttribute(
            name: "Primary Attribute",
            owner: primaryEntity,
            notes: "Primary Attribute Notes",
            id: sharedAttributeID
        )
        let primaryField = fixtures.makeDetailField(
            owner: primaryEntity,
            name: "Primary Field",
            type: .singleLineText,
            sortIndex: 0,
            id: sharedFieldID
        )
        _ = fixtures.makeDetailValue(
            attribute: primaryAttribute,
            field: primaryField,
            stringValue: "Primary Value",
            id: sharedValueID
        )
        _ = fixtures.makeLink(
            source: .entity(primaryEntity),
            target: .attribute(primaryAttribute),
            note: "Primary Link",
            graphID: primaryGraph.id,
            id: sharedLinkID
        )
        _ = fixtures.makeAttachment(
            owner: .attribute(primaryAttribute),
            title: "Primary Attachment",
            originalFilename: "primary.pdf",
            contentTypeIdentifier: "com.adobe.pdf",
            fileExtension: "pdf",
            byteCount: 7,
            fileData: Data(repeating: 1, count: 7),
            id: sharedAttachmentID
        )

        let secondaryEntity = fixtures.makeEntity(
            name: "Secondary Entity",
            in: secondaryGraph,
            notes: "Secondary Notes",
            id: sharedEntityID
        )
        let secondaryAttribute = fixtures.makeAttribute(
            name: "Secondary Attribute",
            owner: secondaryEntity,
            notes: "Secondary Attribute Notes",
            id: sharedAttributeID
        )
        let secondaryField = fixtures.makeDetailField(
            owner: secondaryEntity,
            name: "Secondary Field",
            type: .singleLineText,
            sortIndex: 0,
            id: sharedFieldID
        )
        _ = fixtures.makeDetailValue(
            attribute: secondaryAttribute,
            field: secondaryField,
            stringValue: "Secondary Value",
            id: sharedValueID
        )
        _ = fixtures.makeLink(
            source: .entity(secondaryEntity),
            target: .attribute(secondaryAttribute),
            note: "Secondary Link",
            graphID: secondaryGraph.id,
            id: sharedLinkID
        )
        _ = fixtures.makeAttachment(
            owner: .attribute(secondaryAttribute),
            title: "Secondary Attachment",
            originalFilename: "secondary.pdf",
            contentTypeIdentifier: "com.adobe.pdf",
            fileExtension: "pdf",
            byteCount: 9,
            fileData: Data(repeating: 2, count: 9),
            id: sharedAttachmentID
        )
        try fixtures.save()

        let scope = GraphScope(graphID: primaryGraph.id)
        let repository = GraphReadRepository(container: AnyModelContainer(store.container))

        let graph = try await repository.graphMetadata(in: scope)
        let entities = try await repository.entities(in: scope)
        let attributes = try await repository.attributes(in: scope)
        let links = try await repository.links(in: scope)
        let fields = try await repository.detailFieldDefinitions(in: scope)
        let values = try await repository.detailValues(in: scope)
        let attachments = try await repository.attachmentMetadata(in: scope)
        let preciseEntity = try await repository.entity(
            id: sharedEntityID,
            in: scope
        )
        let preciseAttribute = try await repository.attribute(
            id: sharedAttributeID,
            in: scope
        )
        let ownedAttributes = try await repository.attributes(
            ownerEntityID: sharedEntityID,
            in: scope
        )
        let preciseLink = try await repository.link(
            id: sharedLinkID,
            in: scope
        )
        let connectedLinks = try await repository.links(
            connectedTo: NodeRefKey(
                kind: .attribute,
                id: sharedAttributeID
            ),
            in: scope
        )
        let preciseField = try await repository.detailFieldDefinition(
            id: sharedFieldID,
            in: scope
        )
        let preciseValue = try await repository.detailValue(
            id: sharedValueID,
            in: scope
        )
        let preciseAttachment = try await repository.attachmentMetadata(
            id: sharedAttachmentID,
            in: scope
        )

        #expect(graph?.name == "Primary")
        #expect(entities.map(\.name) == ["Primary Entity"])
        #expect(attributes.map(\.name) == ["Primary Attribute"])
        #expect(attributes.first?.ownerLabel == "Primary Entity")
        #expect(links.map(\.note) == ["Primary Link"])
        #expect(fields.map(\.name) == ["Primary Field"])
        #expect(values.map(\.value) == [.text("Primary Value")])
        #expect(attachments.map(\.title) == ["Primary Attachment"])
        #expect(preciseEntity?.name == "Primary Entity")
        #expect(preciseAttribute?.name == "Primary Attribute")
        #expect(ownedAttributes.map(\.name) == ["Primary Attribute"])
        #expect(preciseLink?.note == "Primary Link")
        #expect(connectedLinks.map(\.note) == ["Primary Link"])
        #expect(preciseField?.name == "Primary Field")
        #expect(preciseValue?.value == .text("Primary Value"))
        #expect(preciseAttachment?.title == "Primary Attachment")

        #expect(entities.allSatisfy { $0.scope == scope })
        #expect(attributes.allSatisfy { $0.scope == scope })
        #expect(links.allSatisfy { $0.scope == scope })
        #expect(fields.allSatisfy { $0.scope == scope })
        #expect(values.allSatisfy { $0.scope == scope })
        #expect(attachments.allSatisfy { $0.scope == scope })

        let preciseAttachmentProperties = try #require(preciseAttachment)
        let preciseAttachmentChildren = Mirror(
            reflecting: preciseAttachmentProperties
        ).children
        #expect(
            preciseAttachmentChildren.contains { $0.label == "fileData" }
                == false
        )
        #expect(
            preciseAttachmentChildren.contains { $0.value is Data }
                == false
        )
    }

    @Test
    func detailDefinitionsAndValuesPreserveEveryTypedVariant() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Typed Values")
        let entity = fixtures.makeEntity(name: "Entity", in: graph)
        let attribute = fixtures.makeAttribute(name: "Attribute", owner: entity)
        let date = Date(timeIntervalSince1970: 1_735_689_600)

        let textField = fixtures.makeDetailField(
            owner: entity,
            name: "Text",
            type: .singleLineText,
            sortIndex: 0
        )
        let intField = fixtures.makeDetailField(
            owner: entity,
            name: "Integer",
            type: .numberInt,
            sortIndex: 1
        )
        let doubleField = fixtures.makeDetailField(
            owner: entity,
            name: "Double",
            type: .numberDouble,
            sortIndex: 2,
            unit: "kg"
        )
        let dateField = fixtures.makeDetailField(
            owner: entity,
            name: "Date",
            type: .date,
            sortIndex: 3
        )
        let boolField = fixtures.makeDetailField(
            owner: entity,
            name: "Boolean",
            type: .toggle,
            sortIndex: 4
        )
        let choiceField = fixtures.makeDetailField(
            owner: entity,
            name: "Choice",
            type: .singleChoice,
            sortIndex: 5,
            options: ["Alpha", "Beta"]
        )

        _ = fixtures.makeDetailValue(
            attribute: attribute,
            field: textField,
            stringValue: "Text Value"
        )
        _ = fixtures.makeDetailValue(
            attribute: attribute,
            field: intField,
            intValue: 42
        )
        _ = fixtures.makeDetailValue(
            attribute: attribute,
            field: doubleField,
            doubleValue: 3.5
        )
        _ = fixtures.makeDetailValue(
            attribute: attribute,
            field: dateField,
            dateValue: date
        )
        _ = fixtures.makeDetailValue(
            attribute: attribute,
            field: boolField,
            boolValue: true
        )
        _ = fixtures.makeDetailValue(
            attribute: attribute,
            field: choiceField,
            stringValue: "Beta"
        )
        try fixtures.save()

        let scope = GraphScope(graphID: graph.id)
        let repository = GraphReadRepository(container: AnyModelContainer(store.container))
        let fields = try await repository.detailFieldDefinitions(
            ownerEntityID: entity.id,
            in: scope
        )
        let values = try await repository.detailValues(
            attributeID: attribute.id,
            in: scope
        )
        let valuesByFieldID = Dictionary(uniqueKeysWithValues: values.map { ($0.fieldID, $0) })

        #expect(fields.count == 6)
        #expect(fields.first { $0.id == doubleField.id }?.unit == "kg")
        #expect(fields.first { $0.id == choiceField.id }?.options == ["Alpha", "Beta"])
        #expect(valuesByFieldID[textField.id]?.value == .text("Text Value"))
        #expect(valuesByFieldID[intField.id]?.value == .integer(42))
        #expect(valuesByFieldID[doubleField.id]?.value == .decimal(3.5))
        #expect(valuesByFieldID[dateField.id]?.value == .date(date))
        #expect(valuesByFieldID[boolField.id]?.value == .boolean(true))
        #expect(valuesByFieldID[choiceField.id]?.value == .choice("Beta"))
        #expect(valuesByFieldID[choiceField.id]?.fieldType == .singleChoice)
    }

    @Test
    func attachmentReadsReturnMetadataWithoutBinaryOrLocalFileState() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Attachments")
        let entity = fixtures.makeEntity(name: "Entity", in: graph)
        let attachment = fixtures.makeAttachment(
            owner: .entity(entity),
            contentKind: .video,
            title: "Launch Video",
            originalFilename: "launch.mov",
            contentTypeIdentifier: "public.movie",
            fileExtension: "mov",
            byteCount: 32_768,
            fileData: Data(repeating: 7, count: 32_768),
            localPath: "private-cache-path.mov"
        )
        try fixtures.save()

        let scope = GraphScope(graphID: graph.id)
        let repository = GraphReadRepository(container: AnyModelContainer(store.container))
        let metadata = try await repository.attachmentMetadata(
            owner: NodeRefKey(kind: .entity, id: entity.id),
            in: scope
        )

        #expect(metadata.count == 1)
        #expect(metadata.first?.id == attachment.id)
        #expect(metadata.first?.contentKind == .video)
        #expect(metadata.first?.byteCount == 32_768)

        let storedProperties = Mirror(reflecting: metadata[0]).children
        #expect(storedProperties.contains { $0.label == "fileData" } == false)
        #expect(storedProperties.contains { $0.label == "localPath" } == false)
        #expect(storedProperties.contains { $0.value is Data } == false)
    }

    @Test
    func sourceSnapshotContainsEverySourceRecordExactlyOnce() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Snapshot")
        let firstEntity = fixtures.makeEntity(name: "First", in: graph)
        let secondEntity = fixtures.makeEntity(name: "Second", in: graph)
        let firstAttribute = fixtures.makeAttribute(name: "A", owner: firstEntity)
        let secondAttribute = fixtures.makeAttribute(name: "B", owner: secondEntity)
        let firstField = fixtures.makeDetailField(
            owner: firstEntity,
            name: "Field A",
            type: .singleLineText,
            sortIndex: 0
        )
        let secondField = fixtures.makeDetailField(
            owner: secondEntity,
            name: "Field B",
            type: .toggle,
            sortIndex: 0
        )
        _ = fixtures.makeDetailValue(
            attribute: firstAttribute,
            field: firstField,
            stringValue: "A"
        )
        _ = fixtures.makeDetailValue(
            attribute: secondAttribute,
            field: secondField,
            boolValue: false
        )
        _ = fixtures.makeLink(
            source: .entity(firstEntity),
            target: .attribute(secondAttribute),
            graphID: graph.id
        )
        _ = fixtures.makeLink(
            source: .attribute(firstAttribute),
            target: .entity(secondEntity),
            graphID: graph.id
        )
        _ = fixtures.makeAttachment(owner: .entity(firstEntity))
        _ = fixtures.makeAttachment(owner: .attribute(secondAttribute))
        try fixtures.save()

        let scope = GraphScope(graphID: graph.id)
        let repository = GraphReadRepository(container: AnyModelContainer(store.container))
        let snapshot = try await repository.sourceSnapshot(in: scope)

        #expect(snapshot.scope == scope)
        #expect(snapshot.graph.id == graph.id)
        #expect(snapshot.entities.count == 2)
        #expect(snapshot.attributes.count == 2)
        #expect(snapshot.links.count == 2)
        #expect(snapshot.detailFieldDefinitions.count == 2)
        #expect(snapshot.detailValues.count == 2)
        #expect(snapshot.attachments.count == 2)

        #expect(Set(snapshot.entities.map(\.id)).count == snapshot.entities.count)
        #expect(Set(snapshot.attributes.map(\.id)).count == snapshot.attributes.count)
        #expect(Set(snapshot.links.map(\.id)).count == snapshot.links.count)
        #expect(
            Set(snapshot.detailFieldDefinitions.map(\.id)).count
                == snapshot.detailFieldDefinitions.count
        )
        #expect(Set(snapshot.detailValues.map(\.id)).count == snapshot.detailValues.count)
        #expect(Set(snapshot.attachments.map(\.id)).count == snapshot.attachments.count)
    }

    @Test
    func cancelledLargeSnapshotDoesNotReturnPartialData() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Large")

        for index in 0..<512 {
            let entity = fixtures.makeEntity(name: "Entity \(index)", in: graph)
            _ = fixtures.makeAttribute(name: "Attribute \(index)", owner: entity)
        }
        try fixtures.save()

        let cancellationTrigger = GraphReadCancellationTrigger(triggerAtCheck: 10)
        let repository = GraphReadRepository(
            container: AnyModelContainer(store.container),
            cancellationCheck: {
                cancellationTrigger.cancelRegisteredTaskIfNeeded()
            }
        )
        let scope = GraphScope(graphID: graph.id)
        let startGate = GraphReadTestStartGate()
        let snapshotTask = Task {
            await startGate.wait()
            return try await repository.sourceSnapshot(in: scope)
        }
        cancellationTrigger.setCancellationAction {
            snapshotTask.cancel()
        }
        await startGate.release()

        var receivedCancellation = false
        do {
            _ = try await snapshotTask.value
        } catch is CancellationError {
            receivedCancellation = true
        }

        #expect(receivedCancellation)
        #expect(cancellationTrigger.checkCount >= 10)
    }
}

private nonisolated final class GraphReadCancellationTrigger: @unchecked Sendable {
    private let lock = NSLock()
    private let triggerAtCheck: Int
    private var storedCheckCount: Int = 0
    private var cancellationAction: (@Sendable () -> Void)?

    init(triggerAtCheck: Int) {
        self.triggerAtCheck = triggerAtCheck
    }

    var checkCount: Int {
        lock.withLock {
            storedCheckCount
        }
    }

    func setCancellationAction(_ action: @escaping @Sendable () -> Void) {
        lock.withLock {
            cancellationAction = action
        }
    }

    func cancelRegisteredTaskIfNeeded() {
        let action: (@Sendable () -> Void)? = lock.withLock {
            storedCheckCount += 1
            guard storedCheckCount == triggerAtCheck else {
                return nil
            }
            return cancellationAction
        }
        action?()
    }
}

private actor GraphReadTestStartGate {
    private var isReleased = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isReleased {
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        guard isReleased == false else { return }
        isReleased = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume()
        }
    }
}
