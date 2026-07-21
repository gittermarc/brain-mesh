import Foundation
import Testing
@testable import BrainMesh

struct GraphSearchDocumentBuilderTests {
    @Test
    func completeSnapshotBuildsEveryDefinedSourceKind() throws {
        let fixture = GraphSearchIndexerFixture()
        let documents = try GraphSearchDocumentBuilder().documents(
            for: fixture.snapshot
        )

        #expect(documents.count == 22)
        #expect(Set(documents.map(\.sourceKind)) == Set(GraphSearchSourceKind.allCases))
        #expect(Set(documents.map(\.documentKind)) == Set(GraphSearchDocumentKind.allCases))
        #expect(documents.filter { $0.documentKind == .detailValue }.count == 6)
        #expect(documents.filter { $0.documentKind == .detailFieldDefinition }.count == 6)

        let attribute = try #require(documents.first {
            $0.documentKind == .attribute && $0.sourceID == fixture.attributeID
        })
        #expect(attribute.normalizedSearchText.contains(BMSearch.fold("Email")))
        #expect(attribute.normalizedSearchText.contains(BMSearch.fold("Person · Email")))
        #expect(attribute.normalizedSearchText.contains(BMSearch.fold("Person")))

        let link = try #require(documents.first {
            $0.documentKind == .link && $0.sourceID == fixture.attributeLinkID
        })
        #expect(link.normalizedSearchText.contains(BMSearch.fold("Person · Email")))
        #expect(link.normalizedSearchText.contains(BMSearch.fold("Company")))

        let definition = try #require(documents.first {
            $0.documentKind == .detailFieldDefinition
                && $0.sourceID == fixture.definitions.last?.id
        })
        #expect(definition.normalizedSearchText.contains(BMSearch.fold("Red")))
        #expect(definition.normalizedSearchText.contains(BMSearch.fold("Blue")))
    }

    @Test
    func documentIdentifiersAndContentHashesAreStableAcrossBuilds() throws {
        let fixture = GraphSearchIndexerFixture()
        let builder = GraphSearchDocumentBuilder()

        let first = try builder.documents(for: fixture.snapshot)
        let second = try builder.documents(for: fixture.snapshot)

        #expect(first == second)
        #expect(first.map(\.documentID) == second.map(\.documentID))
        #expect(first.map(\.contentHash) == second.map(\.contentHash))
        #expect(first.allSatisfy { document in
            document.contentHash.count == 64
                && document.contentHash.allSatisfy(\.isHexDigit)
        })
    }

    @Test
    func hashesIgnoreNonIndexedEntityAndSchemaPresentationValues() throws {
        let fixture = GraphSearchIndexerFixture()
        let builder = GraphSearchDocumentBuilder()
        let entity = fixture.primaryEntity
        let changedPresentationEntity = GraphEntityDTO(
            id: entity.id,
            scope: entity.scope,
            name: entity.name,
            notes: entity.notes,
            iconSymbolName: "star",
            createdAt: entity.createdAt.addingTimeInterval(10_000)
        )
        let definition = fixture.definitions[0]
        let changedPresentationDefinition = GraphDetailFieldDefinitionDTO(
            id: definition.id,
            scope: definition.scope,
            entityID: definition.entityID,
            entityLabel: definition.entityLabel,
            name: definition.name,
            typeRaw: definition.typeRaw,
            sortIndex: definition.sortIndex + 99,
            isPinned: definition.isPinned == false,
            unit: definition.unit,
            options: definition.options
        )

        #expect(
            try builder.documents(for: entity).map(\.contentHash)
                == builder.documents(for: changedPresentationEntity).map(\.contentHash)
        )
        #expect(
            try builder.document(for: definition).contentHash
                == builder.document(for: changedPresentationDefinition).contentHash
        )
    }

    @Test
    func everyTypedDetailPayloadProducesDeterministicSearchText() throws {
        let fixture = GraphSearchIndexerFixture()
        let builder = GraphSearchDocumentBuilder()
        let documents = try fixture.values.compactMap {
            try builder.document(for: $0)
        }

        #expect(documents.count == fixture.values.count)
        #expect(documents.contains { $0.normalizedSearchText.contains(BMSearch.fold("Ada")) })
        #expect(documents.contains { $0.normalizedSearchText.contains("42") })
        #expect(documents.contains { $0.normalizedSearchText.contains("12.5") })
        #expect(documents.contains { $0.normalizedSearchText.contains("2000-01-01") })
        #expect(documents.contains { $0.normalizedSearchText.contains(BMSearch.fold("Ja")) })
        #expect(documents.contains { $0.normalizedSearchText.contains(BMSearch.fold("Red")) })
    }

    @Test
    func emptyDetailPayloadRemovesTheDocumentContractually() throws {
        let fixture = GraphSearchIndexerFixture()
        let value = fixture.values[0]
        let emptyValue = GraphDetailValueDTO(
            id: value.id,
            scope: value.scope,
            attributeID: value.attributeID,
            attributeLabel: value.attributeLabel,
            fieldID: value.fieldID,
            fieldName: value.fieldName,
            fieldTypeRaw: value.fieldTypeRaw,
            value: .empty
        )

        #expect(try GraphSearchDocumentBuilder().document(for: emptyValue) == nil)
    }

    @Test
    func attachmentDocumentContainsMetadataOnly() throws {
        let fixture = GraphSearchIndexerFixture()
        let attachment = GraphAttachmentMetadataDTO(
            id: fixture.attachment.id,
            scope: fixture.attachment.scope,
            createdAt: fixture.attachment.createdAt.addingTimeInterval(5_000),
            ownerKindRaw: fixture.attachment.ownerKindRaw,
            ownerID: fixture.attachment.ownerID,
            ownerLabel: "BINARY_FILE_DATA_SENTINEL",
            contentKindRaw: fixture.attachment.contentKindRaw,
            title: fixture.attachment.title,
            originalFilename: fixture.attachment.originalFilename,
            contentTypeIdentifier: fixture.attachment.contentTypeIdentifier,
            fileExtension: fixture.attachment.fileExtension,
            byteCount: fixture.attachment.byteCount
        )
        let document = try GraphSearchDocumentBuilder().document(for: attachment)

        #expect(document.documentKind == .attachmentMetadata)
        #expect(document.navigation.ownerNode?.label == nil)
        #expect(document.normalizedSearchText.contains("binary_file_data_sentinel") == false)
        #expect(document.evidence.label == attachment.title)
        #expect(document.attachmentMetadata?.byteCount == Int64(attachment.byteCount))
        try document.validateForStorage()
    }
}
