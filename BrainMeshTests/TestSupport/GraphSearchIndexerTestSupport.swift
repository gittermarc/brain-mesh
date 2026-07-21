import Foundation
import Testing
@testable import BrainMesh

nonisolated enum GraphSearchIndexerTestFailure: LocalizedError, Sendable {
    case injected
    case missingSnapshot(UUID)

    var errorDescription: String? {
        switch self {
        case .injected:
            return "Injected graph search indexer test failure."
        case .missingSnapshot:
            return "Missing graph search indexer test snapshot."
        }
    }
}

nonisolated enum GraphSearchIndexerTestRead: Hashable, Sendable {
    case snapshot(UUID)
    case entity(UUID, UUID)
    case attribute(UUID, UUID)
    case attributes(UUID, UUID)
    case link(UUID, UUID)
    case connectedLinks(UUID, NodeRefKey)
    case detailField(UUID, UUID)
    case detailFields(UUID, UUID)
    case detailValue(UUID, UUID)
    case detailValuesForAttribute(UUID, UUID)
    case detailValuesForField(UUID, UUID)
    case attachment(UUID, UUID)
}

actor GraphSearchIndexerTestSource {
    private var snapshots: [UUID: GraphSourceSnapshotDTO]
    private var reads: [GraphSearchIndexerTestRead: Int] = [:]
    private var failingGraphIDs: Set<UUID> = []
    private var snapshotDelayNanoseconds: UInt64 = 0

    init(snapshots: [GraphSourceSnapshotDTO]) {
        self.snapshots = Dictionary(
            uniqueKeysWithValues: snapshots.map { ($0.scope.graphID, $0) }
        )
    }

    func setSnapshot(_ snapshot: GraphSourceSnapshotDTO) {
        snapshots[snapshot.scope.graphID] = snapshot
    }

    func removeSnapshot(graphID: UUID) {
        snapshots.removeValue(forKey: graphID)
    }

    func setFailure(_ enabled: Bool, graphID: UUID) {
        if enabled {
            failingGraphIDs.insert(graphID)
        } else {
            failingGraphIDs.remove(graphID)
        }
    }

    func setSnapshotDelay(nanoseconds: UInt64) {
        snapshotDelayNanoseconds = nanoseconds
    }

    func clearReads() {
        reads.removeAll(keepingCapacity: true)
    }

    func readCount(for read: GraphSearchIndexerTestRead) -> Int {
        reads[read, default: 0]
    }

    func totalReadCount() -> Int {
        reads.values.reduce(0, +)
    }

    func sourceSnapshot(in scope: GraphScope) async throws -> GraphSourceSnapshotDTO {
        record(.snapshot(scope.graphID))
        if failingGraphIDs.contains(scope.graphID) {
            throw GraphSearchIndexerTestFailure.injected
        }
        if snapshotDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: snapshotDelayNanoseconds)
        }
        guard let snapshot = snapshots[scope.graphID] else {
            throw GraphSearchIndexerTestFailure.missingSnapshot(scope.graphID)
        }
        return snapshot
    }

    func entity(id: UUID, in scope: GraphScope) async throws -> GraphEntityDTO? {
        record(.entity(scope.graphID, id))
        return try snapshot(in: scope).entities.first { $0.id == id }
    }

    func attribute(id: UUID, in scope: GraphScope) async throws -> GraphAttributeDTO? {
        record(.attribute(scope.graphID, id))
        return try snapshot(in: scope).attributes.first { $0.id == id }
    }

    func attributes(
        ownerEntityID: UUID,
        in scope: GraphScope
    ) async throws -> [GraphAttributeDTO] {
        record(.attributes(scope.graphID, ownerEntityID))
        return try snapshot(in: scope).attributes.filter {
            $0.ownerEntityID == ownerEntityID
        }
    }

    func link(id: UUID, in scope: GraphScope) async throws -> GraphLinkDTO? {
        record(.link(scope.graphID, id))
        return try snapshot(in: scope).links.first { $0.id == id }
    }

    func links(
        connectedTo node: NodeRefKey,
        in scope: GraphScope
    ) async throws -> [GraphLinkDTO] {
        record(.connectedLinks(scope.graphID, node))
        return try snapshot(in: scope).links.filter { link in
            link.sourceNodeKey == node || link.targetNodeKey == node
        }
    }

    func detailFieldDefinition(
        id: UUID,
        in scope: GraphScope
    ) async throws -> GraphDetailFieldDefinitionDTO? {
        record(.detailField(scope.graphID, id))
        return try snapshot(in: scope).detailFieldDefinitions.first {
            $0.id == id
        }
    }

    func detailFieldDefinitions(
        ownerEntityID: UUID,
        in scope: GraphScope
    ) async throws -> [GraphDetailFieldDefinitionDTO] {
        record(.detailFields(scope.graphID, ownerEntityID))
        return try snapshot(in: scope).detailFieldDefinitions.filter {
            $0.entityID == ownerEntityID
        }
    }

    func detailValue(
        id: UUID,
        in scope: GraphScope
    ) async throws -> GraphDetailValueDTO? {
        record(.detailValue(scope.graphID, id))
        return try snapshot(in: scope).detailValues.first { $0.id == id }
    }

    func detailValues(
        attributeID: UUID,
        in scope: GraphScope
    ) async throws -> [GraphDetailValueDTO] {
        record(.detailValuesForAttribute(scope.graphID, attributeID))
        return try snapshot(in: scope).detailValues.filter {
            $0.attributeID == attributeID
        }
    }

    func detailValues(
        fieldID: UUID,
        in scope: GraphScope
    ) async throws -> [GraphDetailValueDTO] {
        record(.detailValuesForField(scope.graphID, fieldID))
        return try snapshot(in: scope).detailValues.filter {
            $0.fieldID == fieldID
        }
    }

    func attachmentMetadata(
        id: UUID,
        in scope: GraphScope
    ) async throws -> GraphAttachmentMetadataDTO? {
        record(.attachment(scope.graphID, id))
        return try snapshot(in: scope).attachments.first { $0.id == id }
    }

    private func snapshot(in scope: GraphScope) throws -> GraphSourceSnapshotDTO {
        guard let snapshot = snapshots[scope.graphID] else {
            throw GraphSearchIndexerTestFailure.missingSnapshot(scope.graphID)
        }
        return snapshot
    }

    private func record(_ read: GraphSearchIndexerTestRead) {
        reads[read, default: 0] += 1
    }
}

extension GraphSearchIndexerTestSource: GraphSearchSourceReading {}

struct GraphSearchIndexerFixture {
    let graphID: UUID
    let scope: GraphScope
    let graph: GraphMetadataDTO

    let primaryEntityID: UUID
    let secondaryEntityID: UUID
    let attributeID: UUID
    let attributeLinkID: UUID
    let entityLinkID: UUID
    let attachmentID: UUID

    var primaryEntity: GraphEntityDTO
    var secondaryEntity: GraphEntityDTO
    var attribute: GraphAttributeDTO
    var links: [GraphLinkDTO]
    var definitions: [GraphDetailFieldDefinitionDTO]
    var values: [GraphDetailValueDTO]
    var attachment: GraphAttachmentMetadataDTO

    init(graphID: UUID = UUID()) {
        let fixtureScope = GraphScope(graphID: graphID)
        let primaryEntityID = graphSearchIndexerTestUUID(
            graphID: graphID,
            value: 1
        )
        let secondaryEntityID = graphSearchIndexerTestUUID(
            graphID: graphID,
            value: 2
        )
        let attributeID = graphSearchIndexerTestUUID(
            graphID: graphID,
            value: 3
        )
        let attributeLinkID = graphSearchIndexerTestUUID(
            graphID: graphID,
            value: 4
        )
        let entityLinkID = graphSearchIndexerTestUUID(
            graphID: graphID,
            value: 5
        )
        let attachmentID = graphSearchIndexerTestUUID(
            graphID: graphID,
            value: 6
        )
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let graph = GraphMetadataDTO(
            id: graphID,
            scope: fixtureScope,
            name: "Fixture Graph",
            createdAt: createdAt
        )
        let primaryEntity = GraphEntityDTO(
            id: primaryEntityID,
            scope: fixtureScope,
            name: "Person",
            notes: "Primary entity notes",
            iconSymbolName: "person",
            createdAt: createdAt
        )
        let secondaryEntity = GraphEntityDTO(
            id: secondaryEntityID,
            scope: fixtureScope,
            name: "Company",
            notes: "",
            iconSymbolName: "building.2",
            createdAt: createdAt.addingTimeInterval(1)
        )
        let attribute = GraphAttributeDTO(
            id: attributeID,
            scope: fixtureScope,
            ownerEntityID: primaryEntityID,
            ownerLabel: "Person",
            name: "Email",
            displayLabel: "Person · Email",
            notes: "Attribute notes",
            iconSymbolName: "envelope"
        )
        let links = [
            GraphLinkDTO(
                id: attributeLinkID,
                scope: fixtureScope,
                createdAt: createdAt.addingTimeInterval(2),
                sourceKindRaw: NodeKind.attribute.rawValue,
                sourceID: attributeID,
                sourceLabel: "Person · Email",
                targetKindRaw: NodeKind.entity.rawValue,
                targetID: secondaryEntityID,
                targetLabel: "Company",
                note: "Attribute link notes"
            ),
            GraphLinkDTO(
                id: entityLinkID,
                scope: fixtureScope,
                createdAt: createdAt.addingTimeInterval(3),
                sourceKindRaw: NodeKind.entity.rawValue,
                sourceID: primaryEntityID,
                sourceLabel: "Person",
                targetKindRaw: NodeKind.entity.rawValue,
                targetID: secondaryEntityID,
                targetLabel: "Company",
                note: "Entity link notes"
            )
        ]
        let fieldTypes: [DetailFieldType] = [
            .singleLineText,
            .numberInt,
            .numberDouble,
            .date,
            .toggle,
            .singleChoice
        ]
        let fieldNames = [
            "Alias",
            "Count",
            "Ratio",
            "Birthday",
            "Active",
            "Color"
        ]
        let definitions = zip(fieldTypes.indices, fieldTypes).map { index, type in
            GraphDetailFieldDefinitionDTO(
                id: graphSearchIndexerTestUUID(
                    graphID: graphID,
                    value: 20 + index
                ),
                scope: fixtureScope,
                entityID: primaryEntityID,
                entityLabel: "Person",
                name: fieldNames[index],
                typeRaw: type.rawValue,
                sortIndex: index,
                isPinned: index < 2,
                unit: type.supportsUnit ? "kg" : nil,
                options: type == .singleChoice ? ["Red", "Blue"] : []
            )
        }
        let dateValue = Date(timeIntervalSince1970: 946_684_800)
        let payloads: [GraphDetailValuePayload] = [
            .text("Ada"),
            .integer(42),
            .decimal(12.5),
            .date(dateValue),
            .boolean(true),
            .choice("Red")
        ]
        let values = definitions.indices.map { index in
            GraphDetailValueDTO(
                id: graphSearchIndexerTestUUID(
                    graphID: graphID,
                    value: 40 + index
                ),
                scope: fixtureScope,
                attributeID: attributeID,
                attributeLabel: "Person · Email",
                fieldID: definitions[index].id,
                fieldName: definitions[index].name,
                fieldTypeRaw: definitions[index].typeRaw,
                value: payloads[index]
            )
        }
        let attachment = GraphAttachmentMetadataDTO(
            id: attachmentID,
            scope: fixtureScope,
            createdAt: createdAt.addingTimeInterval(4),
            ownerKindRaw: NodeKind.attribute.rawValue,
            ownerID: attributeID,
            ownerLabel: "Person · Email",
            contentKindRaw: AttachmentContentKind.file.rawValue,
            title: "Profile PDF",
            originalFilename: "profile.pdf",
            contentTypeIdentifier: "com.adobe.pdf",
            fileExtension: "pdf",
            byteCount: 2_048
        )

        self.graphID = graphID
        self.scope = fixtureScope
        self.graph = graph
        self.primaryEntityID = primaryEntityID
        self.secondaryEntityID = secondaryEntityID
        self.attributeID = attributeID
        self.attributeLinkID = attributeLinkID
        self.entityLinkID = entityLinkID
        self.attachmentID = attachmentID
        self.primaryEntity = primaryEntity
        self.secondaryEntity = secondaryEntity
        self.attribute = attribute
        self.links = links
        self.definitions = definitions
        self.values = values
        self.attachment = attachment
    }

    var snapshot: GraphSourceSnapshotDTO {
        GraphSourceSnapshotDTO(
            scope: scope,
            graph: graph,
            entities: [primaryEntity, secondaryEntity],
            attributes: [attribute],
            links: links,
            detailFieldDefinitions: definitions,
            detailValues: values,
            attachments: [attachment]
        )
    }

    mutating func updatePrimaryEntityNotes(_ notes: String) {
        primaryEntity = GraphEntityDTO(
            id: primaryEntity.id,
            scope: primaryEntity.scope,
            name: primaryEntity.name,
            notes: notes,
            iconSymbolName: primaryEntity.iconSymbolName,
            createdAt: primaryEntity.createdAt
        )
    }

    mutating func renamePrimaryEntity(to name: String) {
        primaryEntity = GraphEntityDTO(
            id: primaryEntity.id,
            scope: primaryEntity.scope,
            name: name,
            notes: primaryEntity.notes,
            iconSymbolName: primaryEntity.iconSymbolName,
            createdAt: primaryEntity.createdAt
        )
        let displayLabel = "\(name) · \(attribute.name)"
        attribute = GraphAttributeDTO(
            id: attribute.id,
            scope: attribute.scope,
            ownerEntityID: attribute.ownerEntityID,
            ownerLabel: name,
            name: attribute.name,
            displayLabel: displayLabel,
            notes: attribute.notes,
            iconSymbolName: attribute.iconSymbolName
        )
        definitions = definitions.map { definition in
            GraphDetailFieldDefinitionDTO(
                id: definition.id,
                scope: definition.scope,
                entityID: definition.entityID,
                entityLabel: name,
                name: definition.name,
                typeRaw: definition.typeRaw,
                sortIndex: definition.sortIndex,
                isPinned: definition.isPinned,
                unit: definition.unit,
                options: definition.options
            )
        }
        values = values.map { value in
            GraphDetailValueDTO(
                id: value.id,
                scope: value.scope,
                attributeID: value.attributeID,
                attributeLabel: displayLabel,
                fieldID: value.fieldID,
                fieldName: value.fieldName,
                fieldTypeRaw: value.fieldTypeRaw,
                value: value.value
            )
        }
        links = links.map { link in
            GraphLinkDTO(
                id: link.id,
                scope: link.scope,
                createdAt: link.createdAt,
                sourceKindRaw: link.sourceKindRaw,
                sourceID: link.sourceID,
                sourceLabel: link.sourceID == primaryEntityID
                    ? name
                    : (link.sourceID == attributeID ? displayLabel : link.sourceLabel),
                targetKindRaw: link.targetKindRaw,
                targetID: link.targetID,
                targetLabel: link.targetID == primaryEntityID ? name : link.targetLabel,
                note: link.note
            )
        }
        attachment = GraphAttachmentMetadataDTO(
            id: attachment.id,
            scope: attachment.scope,
            createdAt: attachment.createdAt,
            ownerKindRaw: attachment.ownerKindRaw,
            ownerID: attachment.ownerID,
            ownerLabel: displayLabel,
            contentKindRaw: attachment.contentKindRaw,
            title: attachment.title,
            originalFilename: attachment.originalFilename,
            contentTypeIdentifier: attachment.contentTypeIdentifier,
            fileExtension: attachment.fileExtension,
            byteCount: attachment.byteCount
        )
    }

    mutating func renameAttribute(to name: String) {
        let ownerLabel = attribute.ownerLabel ?? primaryEntity.name
        let displayLabel = "\(ownerLabel) · \(name)"
        attribute = GraphAttributeDTO(
            id: attribute.id,
            scope: attribute.scope,
            ownerEntityID: attribute.ownerEntityID,
            ownerLabel: ownerLabel,
            name: name,
            displayLabel: displayLabel,
            notes: attribute.notes,
            iconSymbolName: attribute.iconSymbolName
        )
        values = values.map { value in
            GraphDetailValueDTO(
                id: value.id,
                scope: value.scope,
                attributeID: value.attributeID,
                attributeLabel: displayLabel,
                fieldID: value.fieldID,
                fieldName: value.fieldName,
                fieldTypeRaw: value.fieldTypeRaw,
                value: value.value
            )
        }
        links = links.map { link in
            GraphLinkDTO(
                id: link.id,
                scope: link.scope,
                createdAt: link.createdAt,
                sourceKindRaw: link.sourceKindRaw,
                sourceID: link.sourceID,
                sourceLabel: link.sourceID == attributeID ? displayLabel : link.sourceLabel,
                targetKindRaw: link.targetKindRaw,
                targetID: link.targetID,
                targetLabel: link.targetID == attributeID ? displayLabel : link.targetLabel,
                note: link.note
            )
        }
        attachment = GraphAttachmentMetadataDTO(
            id: attachment.id,
            scope: attachment.scope,
            createdAt: attachment.createdAt,
            ownerKindRaw: attachment.ownerKindRaw,
            ownerID: attachment.ownerID,
            ownerLabel: displayLabel,
            contentKindRaw: attachment.contentKindRaw,
            title: attachment.title,
            originalFilename: attachment.originalFilename,
            contentTypeIdentifier: attachment.contentTypeIdentifier,
            fileExtension: attachment.fileExtension,
            byteCount: attachment.byteCount
        )
    }

    mutating func updateLinkNote(id: UUID, note: String?) {
        links = links.map { link in
            guard link.id == id else { return link }
            return GraphLinkDTO(
                id: link.id,
                scope: link.scope,
                createdAt: link.createdAt,
                sourceKindRaw: link.sourceKindRaw,
                sourceID: link.sourceID,
                sourceLabel: link.sourceLabel,
                targetKindRaw: link.targetKindRaw,
                targetID: link.targetID,
                targetLabel: link.targetLabel,
                note: note
            )
        }
    }

    mutating func renameDetailField(id: UUID, to name: String) {
        definitions = definitions.map { definition in
            guard definition.id == id else { return definition }
            return GraphDetailFieldDefinitionDTO(
                id: definition.id,
                scope: definition.scope,
                entityID: definition.entityID,
                entityLabel: definition.entityLabel,
                name: name,
                typeRaw: definition.typeRaw,
                sortIndex: definition.sortIndex,
                isPinned: definition.isPinned,
                unit: definition.unit,
                options: definition.options
            )
        }
        values = values.map { value in
            guard value.fieldID == id else { return value }
            return GraphDetailValueDTO(
                id: value.id,
                scope: value.scope,
                attributeID: value.attributeID,
                attributeLabel: value.attributeLabel,
                fieldID: value.fieldID,
                fieldName: name,
                fieldTypeRaw: value.fieldTypeRaw,
                value: value.value
            )
        }
    }

    mutating func updateDetailValue(id: UUID, payload: GraphDetailValuePayload) {
        values = values.map { value in
            guard value.id == id else { return value }
            return GraphDetailValueDTO(
                id: value.id,
                scope: value.scope,
                attributeID: value.attributeID,
                attributeLabel: value.attributeLabel,
                fieldID: value.fieldID,
                fieldName: value.fieldName,
                fieldTypeRaw: value.fieldTypeRaw,
                value: payload
            )
        }
    }

    mutating func updateAttachmentTitle(_ title: String) {
        attachment = GraphAttachmentMetadataDTO(
            id: attachment.id,
            scope: attachment.scope,
            createdAt: attachment.createdAt,
            ownerKindRaw: attachment.ownerKindRaw,
            ownerID: attachment.ownerID,
            ownerLabel: attachment.ownerLabel,
            contentKindRaw: attachment.contentKindRaw,
            title: title,
            originalFilename: attachment.originalFilename,
            contentTypeIdentifier: attachment.contentTypeIdentifier,
            fileExtension: attachment.fileExtension,
            byteCount: attachment.byteCount
        )
    }
}

func withGraphSearchIndexerTestEnvironment<T>(
    snapshots: [GraphSourceSnapshotDTO],
    sourceBatchSize: Int = GraphSearchIndexer.defaultSourceBatchSize,
    operation: (
        GraphSearchIndexer,
        GraphSearchIndexerTestSource,
        GraphSearchIndexStore
    ) async throws -> T
) async throws -> T {
    let location = try GraphSearchIndexTestSupport.makeLocation()
    let store = GraphSearchIndexStore(
        databaseURL: location.databaseURL,
        backendPreference: .indexedFallback
    )
    let source = GraphSearchIndexerTestSource(snapshots: snapshots)
    let bus = GraphMutationEventBus()
    let indexer = GraphSearchIndexer(
        sourceReader: source,
        store: store,
        subscriber: bus,
        sourceBatchSize: sourceBatchSize
    )

    do {
        let result = try await operation(indexer, source, store)
        await indexer.resetForTesting()
        try await store.close()
        location.remove()
        return result
    } catch {
        await indexer.resetForTesting()
        do {
            try await store.close()
        } catch let closeError {
            Issue.record("Failed to close graph search indexer test store: \(closeError)")
        }
        location.remove()
        throw error
    }
}

nonisolated func graphSearchIndexerTestUUID(
    graphID: UUID,
    value: Int
) -> UUID {
    var bytes = graphID.uuid
    let rawValue = UInt32(truncatingIfNeeded: value)
    bytes.12 = UInt8(truncatingIfNeeded: rawValue >> 24)
    bytes.13 = UInt8(truncatingIfNeeded: rawValue >> 16)
    bytes.14 = UInt8(truncatingIfNeeded: rawValue >> 8)
    bytes.15 = UInt8(truncatingIfNeeded: rawValue)
    return UUID(uuid: bytes)
}

func waitForGraphSearchIndexerCondition(
    maximumAttempts: Int = 200,
    operation: @escaping @Sendable () async -> Bool
) async throws {
    for _ in 0..<maximumAttempts {
        if await operation() {
            return
        }
        try await Task.sleep(nanoseconds: 5_000_000)
    }
    Issue.record("Timed out waiting for graph search indexer test condition.")
}
