import Foundation
import Testing
@testable import BrainMesh

struct GraphMutationWritePathInventoryTests {

    @Test
    func inventoryHasUniqueStableIdentifiersAndNoOpenClassification() {
        let entries = GraphMutationWritePathInventory.entries
        let identifiers = entries.map(\.id)

        #expect(Set(identifiers).count == identifiers.count)
        #expect(entries.isEmpty == false)
        #expect(
            entries.allSatisfy { entry in
                let searchable = [
                    entry.id,
                    entry.productionLocation,
                    entry.domainOperation,
                    entry.exclusionReason ?? ""
                ]
                .joined(separator: " ")
                .lowercased()
                return searchable.contains("deferred") == false
                    && searchable.contains("unknown") == false
                    && searchable.contains("unclassified") == false
            }
        )
    }

    @Test
    func eventClassificationsDeclareTechnicalExpectedKinds() {
        for entry in GraphMutationWritePathInventory.entries {
            switch entry.classification {
            case .preciseMutationBatch, .fullRebuildBatch:
                #expect(entry.expectedKinds.isEmpty == false, Comment(rawValue: entry.id))
                #expect(entry.exclusionReason == nil, Comment(rawValue: entry.id))
            case .migrationOrBootstrap:
                #expect(
                    entry.expectedKinds.isEmpty == false || entry.exclusionReason != nil,
                    Comment(rawValue: entry.id)
                )
            case .reconstructibleLocalCacheMetadata,
                 .securityOrUIMetadata,
                 .unreferencedLegacyFile:
                #expect(entry.expectedKinds.isEmpty, Comment(rawValue: entry.id))
                #expect(entry.exclusionReason != nil, Comment(rawValue: entry.id))
            }
        }
    }

    @Test
    func inventoryCoversEveryPartPRAndEveryRequiredClassification() {
        let entries = GraphMutationWritePathInventory.entries
        #expect(Set(entries.map(\.responsiblePR)) == Set(GraphMutationInventoryPR.allCases))
        #expect(Set(entries.map(\.classification)) == Set(GraphMutationWritePathClassification.allCases))
    }

    @Test
    func declaredEventKindsRemainDataMinimal() throws {
        let graphID = inventoryTestUUID(1)
        let batches = [
            try GraphMutationBatchFactory.entityCreated(
                graphID: graphID,
                entityID: inventoryTestUUID(2)
            ),
            try GraphMutationBatchFactory.attributeCreated(
                graphID: graphID,
                attributeID: inventoryTestUUID(3),
                ownerEntityID: inventoryTestUUID(2)
            ),
            try GraphMutationBatchFactory.graphImported(graphID: graphID),
            try GraphMutationBatchFactory.graphReplaced(graphID: graphID),
            try GraphMutationBatchFactory.graphIntegrityRepair(graphID: graphID),
            try GraphMutationBatchFactory.detailTemplateCreated(
                graphID: graphID,
                templateID: inventoryTestUUID(4)
            )
        ]

        for batch in batches {
            #expect(inventoryContainsUserPayload(batch) == false)
        }
    }
}

private enum GraphMutationWritePathClassification: String, CaseIterable, Hashable {
    case preciseMutationBatch
    case fullRebuildBatch
    case reconstructibleLocalCacheMetadata
    case migrationOrBootstrap
    case securityOrUIMetadata
    case unreferencedLegacyFile
}

private enum GraphMutationInventoryPR: String, CaseIterable, Hashable {
    case pr05A
    case pr05B
    case pr05C
}

private struct GraphMutationWritePathInventoryEntry {
    let id: String
    let productionLocation: String
    let domainOperation: String
    let classification: GraphMutationWritePathClassification
    let expectedKinds: [GraphMutationKind]
    let exclusionReason: String?
    let responsiblePR: GraphMutationInventoryPR
}

private enum GraphMutationWritePathInventory {
    static let entries: [GraphMutationWritePathInventoryEntry] = [
        precise("entity.create", "BrainMesh/Mainscreen/AddEntityView.swift", "Entity creation", [.entityCreated], .pr05A),
        precise("attribute.create", "BrainMesh/Mainscreen/AddAttributeView.swift", "Attribute creation", [.attributeCreated], .pr05A),
        precise("link.create", "BrainMesh/Mainscreen/AddLinkView.swift", "Single and bidirectional link creation", [.linkCreated], .pr05A),
        precise("link.update-delete", "BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections/NodeDetailShared+Connections.AllView.swift", "Link note update and single or multi-delete", [.linkUpdated, .linkDeleted], .pr05A),
        precise("details.schema.actions", "BrainMesh/Mainscreen/Details/DetailsSchema/DetailsSchemaActions.swift", "Detail schema apply, reorder and delete", [.detailSchemaChanged, .detailValueDeleted], .pr05A),
        precise("details.schema.add", "BrainMesh/Mainscreen/Details/DetailsSchema/DetailsSchemaAddFieldSheet.swift", "Detail definition creation", [.detailSchemaChanged], .pr05A),
        precise("details.schema.edit", "BrainMesh/Mainscreen/Details/DetailsSchema/DetailsSchemaEditFieldSheet.swift", "Detail definition update", [.detailSchemaChanged], .pr05A),
        precise("details.value.persistence", "BrainMesh/Mainscreen/Details/DetailsValueEditorSheet/DetailsValueEditorSheet+Persistence.swift", "Detail value upsert and delete", [.detailValueChanged, .detailValueDeleted], .pr05A),

        precise("node.rename.entity", "BrainMesh/Mainscreen/EntityDetail/EntityDetailView+Actions.swift", "Entity rename with denormalized link relabeling", [.entityUpdated, .linkUpdated], .pr05B),
        precise("node.rename.attribute", "BrainMesh/Mainscreen/AttributeDetail/AttributeDetailView+Sheets.swift", "Attribute rename with denormalized link relabeling", [.attributeUpdated, .linkUpdated], .pr05B),
        precise("node.notes", "BrainMesh/Mainscreen/NodeDetailShared/NodeNotesPersistence.swift", "Final entity or attribute notes commit", [.entityUpdated, .attributeUpdated], .pr05B),
        precise("node.delete.service", "BrainMesh/Mainscreen/Deletion/GraphNodeDeletionService.swift", "Central composite entity and attribute cleanup", [.linkDeleted, .detailValueDeleted, .detailSchemaChanged, .attachmentDeleted, .attributeDeleted, .entityDeleted], .pr05B),
        precise("node.delete.attribute-callers", "BrainMesh/Mainscreen/EntityDetail/EntityAttributes", "Single and multi-attribute delete callers routed to the central service", [.attributeDeleted], .pr05B),
        precise("bulk-link.execute", "BrainMesh/Mainscreen/BulkLink/BulkLinkExecutor.swift", "One planned bulk-link insertion", [.linkCreated], .pr05B),
        precise("media.entity-header", "BrainMesh/Mainscreen/EntityDetail/EntityDetailView+MediaSection.swift", "Entity header image mutation", [.entityUpdated], .pr05B),
        precise("media.attribute-header", "BrainMesh/Mainscreen/AttributeDetail/AttributeDetailView+MediaSection.swift", "Attribute header image mutation", [.attributeUpdated], .pr05B),
        precise("attachment.service", "BrainMesh/Attachments/AttachmentMutationService.swift", "Attachment create, update and delete", [.attachmentCreated, .attachmentUpdated, .attachmentDeleted], .pr05B),
        precise("attachment.import-callers", "BrainMesh/Attachments and BrainMesh/Mainscreen/NodeDetailShared", "Attachment import and management callers routed to the attachment service", [.attachmentCreated, .attachmentUpdated, .attachmentDeleted], .pr05B),
        precise("gallery.mutations", "BrainMesh/PhotoGallery", "Gallery import, metadata update, delete and set-as-header", [.attachmentCreated, .attachmentUpdated, .attachmentDeleted, .entityUpdated, .attributeUpdated], .pr05B),

        precise("graph.create.picker", "BrainMesh/GraphPicker/GraphPickerSheet.swift", "User-created graph", [.graphCreated], .pr05C),
        precise("graph.rename.picker", "BrainMesh/GraphPicker/GraphPickerSheet.swift", "Graph display-name update", [.graphUpdated], .pr05C),
        precise("graph.delete", "BrainMesh/GraphPicker/GraphDeletionService.swift", "Graph delete and optional replacement default graph", [.graphDeleted, .graphCreated], .pr05C),
        fullRebuild("graph.dedupe", "BrainMesh/GraphPicker/GraphDedupeService.swift", "Duplicate graph-record integrity repair", [.graphRequiresFullRebuild(.integrityRepair)], .pr05C),
        migration("bootstrap.default-graph", "BrainMesh/Bootstrap/GraphBootstrap+Repair.swift", "Create a missing default graph at startup", [.graphCreated], nil),
        migration("bootstrap.legacy-scope", "BrainMesh/Bootstrap/GraphBootstrap+Repair.swift", "Assign graph scope to legacy records", [.graphRequiresFullRebuild(.integrityRepair)], nil),
        migration("bootstrap.folded-notes", "BrainMesh/Bootstrap/GraphBootstrap+Backfill.swift", "Backfill stored folded note fields", [.graphRequiresFullRebuild(.integrityRepair)], nil),
        migration("attachment.graph-scope", "BrainMesh/Attachments/AttachmentGraphIDMigration.swift", "Owner-local legacy attachment graph-scope migration", [.graphRequiresFullRebuild(.integrityRepair)], nil),
        fullRebuild("transfer.structure-import", "BrainMesh/GraphTransfer/GraphTransferService", "Structure import including event-free checkpoint saves", [.graphImported, .graphRequiresFullRebuild(.graphImport)], .pr05C),
        fullRebuild("transfer.full-backup-import", "BrainMesh/GraphTransfer/Backup/GraphTransferService+FullBackupImport.swift", "Full-backup import including event-free checkpoint saves", [.graphImported, .graphRequiresFullRebuild(.graphImport)], .pr05C),
        fullRebuild("transfer.replace", "BrainMesh/GraphTransfer/GraphTransferView/GraphTransferViewModel/GraphTransferViewModel+Replace.swift", "Replace across the actual delete and import save boundaries", [.graphDeleted, .graphReplaced, .graphRequiresFullRebuild(.graphReplacement)], .pr05C),
        migration("transfer.failed-import-cleanup", "BrainMesh/GraphTransfer/GraphTransferService/GraphTransferImportCoordinator+Cleanup.swift", "Rollback and persistent cleanup of a never-finalized partial import", [], "Failure recovery has no success event and removes the incomplete graph before returning the original error."),
        precise("details.template.create", "BrainMesh/Mainscreen/Details/DetailsSchema/DetailsSchemaActions.swift", "Create a graph-scoped reusable details template", [.detailTemplateCreated], .pr05C),

        excluded("cache.graph-canvas-image-path", "BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen+Helpers.swift", "Rehydrate reconstructible node imagePath metadata", .reconstructibleLocalCacheMetadata, "imageData remains authoritative; imagePath only identifies a local cache file."),
        excluded("cache.image-hydrator-image-path", "BrainMesh/ImageHydrator.swift", "Rehydrate reconstructible imagePath metadata", .reconstructibleLocalCacheMetadata, "The write recreates local cache metadata without changing graph content."),
        excluded("security.graph-settings", "BrainMesh/Security/GraphSecuritySheet.swift", "Persist graph access-control configuration", .securityOrUIMetadata, "Security settings do not participate in graph-content Home or Stats caches."),
        excluded("security.graph-password", "BrainMesh/Security/GraphSetPasswordView.swift", "Persist password hash, salt and lock configuration", .securityOrUIMetadata, "Security metadata is intentionally excluded from graph-content mutation events."),

        excluded("ui.graph-canvas-view-presets", "BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen+ViewPresets.swift", "Persist graph canvas view presets in UserDefaults", .securityOrUIMetadata, "Local saved-view preferences are UI state; they do not mutate SwiftData graph content or graph-content caches."),

        excluded("legacy.notes-and-photo", "BrainMesh/NotesAndPhotoSection.swift", "Legacy notes and photo writes", .unreferencedLegacyFile, "Project-wide symbol search finds only the declaration; no productive caller exists."),
        excluded("legacy.node-links", "BrainMesh/Mainscreen/NodeLinksSectionView.swift", "Legacy link deletion view", .unreferencedLegacyFile, "Project-wide symbol search finds only the declaration; no productive caller exists."),
        excluded("legacy.graph-rename-sheet", "BrainMesh/GraphPicker/GraphPickerRenameSheet.swift", "Legacy graph rename modifier", .unreferencedLegacyFile, "Project-wide symbol search finds only the declaration; the active picker uses GraphPickerNameEditorSheet.")
    ]

    private static func precise(
        _ id: String,
        _ location: String,
        _ operation: String,
        _ kinds: [GraphMutationKind],
        _ pr: GraphMutationInventoryPR
    ) -> GraphMutationWritePathInventoryEntry {
        GraphMutationWritePathInventoryEntry(
            id: id,
            productionLocation: location,
            domainOperation: operation,
            classification: .preciseMutationBatch,
            expectedKinds: kinds,
            exclusionReason: nil,
            responsiblePR: pr
        )
    }

    private static func fullRebuild(
        _ id: String,
        _ location: String,
        _ operation: String,
        _ kinds: [GraphMutationKind],
        _ pr: GraphMutationInventoryPR
    ) -> GraphMutationWritePathInventoryEntry {
        GraphMutationWritePathInventoryEntry(
            id: id,
            productionLocation: location,
            domainOperation: operation,
            classification: .fullRebuildBatch,
            expectedKinds: kinds,
            exclusionReason: nil,
            responsiblePR: pr
        )
    }

    private static func migration(
        _ id: String,
        _ location: String,
        _ operation: String,
        _ kinds: [GraphMutationKind],
        _ reason: String?
    ) -> GraphMutationWritePathInventoryEntry {
        GraphMutationWritePathInventoryEntry(
            id: id,
            productionLocation: location,
            domainOperation: operation,
            classification: .migrationOrBootstrap,
            expectedKinds: kinds,
            exclusionReason: reason,
            responsiblePR: .pr05C
        )
    }

    private static func excluded(
        _ id: String,
        _ location: String,
        _ operation: String,
        _ classification: GraphMutationWritePathClassification,
        _ reason: String
    ) -> GraphMutationWritePathInventoryEntry {
        GraphMutationWritePathInventoryEntry(
            id: id,
            productionLocation: location,
            domainOperation: operation,
            classification: classification,
            expectedKinds: [],
            exclusionReason: reason,
            responsiblePR: .pr05C
        )
    }
}

private func inventoryContainsUserPayload(_ value: Any) -> Bool {
    if value is String || value is Data {
        return true
    }
    return Mirror(reflecting: value).children.contains { child in
        inventoryContainsUserPayload(child.value)
    }
}

private func inventoryTestUUID(_ value: Int) -> UUID {
    let suffix = String(format: "%012X", value)
    return UUID(uuidString: "00000000-0000-0000-0000-\(suffix)")!
}
