//
//  GraphBackupAttachmentImport.swift
//  BrainMesh
//
//  Value-only helpers for importing attachment assets from .bmbackup packages.
//

import Foundation

nonisolated struct GraphBackupAttachmentImportSummary: Sendable {
    var importedAttachments: Int
    var skippedAttachments: Int
    var warnings: [String]

    init(importedAttachments: Int = 0, skippedAttachments: Int = 0, warnings: [String] = []) {
        self.importedAttachments = importedAttachments
        self.skippedAttachments = skippedAttachments
        self.warnings = warnings
    }
}

nonisolated enum GraphBackupAttachmentImportWarningCode {
    static let manifestWarning = "backup-manifest-warning"
    static let unmappedOwner = "attachment-owner-unmapped"
    static let unsafeAssetPath = "attachment-unsafe-asset-path"
    static let missingAsset = "attachment-asset-missing"
    static let assetReadFailed = "attachment-asset-read-failed"
    static let byteCountMismatch = "attachment-byte-count-mismatch"
    static let checksumMismatch = "attachment-checksum-mismatch"
    static let cacheWriteFailed = "attachment-cache-write-failed"
}

nonisolated struct GraphBackupAttachmentImportPlan: Equatable, Sendable {
    var entryID: UUID
    var importedAttachmentID: UUID
    var ownerKindRaw: Int
    var remappedOwnerID: UUID
    var contentKindRaw: Int
    var title: String
    var originalFilename: String
    var contentTypeIdentifier: String
    var fileExtension: String
    var byteCount: Int
    var assetRelativePath: String
    var sha256Hex: String?

    init(
        entry: GraphBackupAttachmentManifestEntry,
        importedAttachmentID: UUID,
        remappedOwnerID: UUID
    ) {
        self.entryID = entry.id
        self.importedAttachmentID = importedAttachmentID
        self.ownerKindRaw = entry.ownerKindRaw
        self.remappedOwnerID = remappedOwnerID
        self.contentKindRaw = entry.contentKindRaw
        self.title = entry.title
        self.originalFilename = entry.originalFilename
        self.contentTypeIdentifier = entry.contentTypeIdentifier
        self.fileExtension = entry.fileExtension
        self.byteCount = max(0, Int(clamping: entry.byteCount))
        self.assetRelativePath = entry.assetRelativePath
        self.sha256Hex = entry.sha256Hex
    }
}

nonisolated enum GraphBackupAttachmentImportPlanner {
    static func makePlan(
        entry: GraphBackupAttachmentManifestEntry,
        importedAttachmentID: UUID = UUID(),
        entityIDMap: [UUID: UUID],
        attributeIDMap: [UUID: UUID]
    ) -> GraphBackupAttachmentImportPlan? {
        guard let remappedOwnerID = GraphTransferImportNodeRemapper.remapNodeID(
            kindRaw: entry.ownerKindRaw,
            oldID: entry.ownerID,
            entityIDMap: entityIDMap,
            attributeIDMap: attributeIDMap
        ) else {
            return nil
        }

        return GraphBackupAttachmentImportPlan(
            entry: entry,
            importedAttachmentID: importedAttachmentID,
            remappedOwnerID: remappedOwnerID
        )
    }
}

nonisolated enum GraphBackupAttachmentAssetReader {
    static func readValidatedData(
        for entry: GraphBackupAttachmentManifestEntry,
        packageURL: URL,
        fileManager: FileManager = .default
    ) throws -> Data {
        let assetURL: URL
        do {
            assetURL = try GraphBackupPackageLayout.safeURL(in: packageURL, relativePath: entry.assetRelativePath)
        } catch {
            throw GraphTransferError.backupAttachmentReadFailed(
                attachmentID: entry.id,
                underlying: "Unsafe asset path: \(entry.assetRelativePath)"
            )
        }

        guard fileManager.fileExists(atPath: assetURL.path) else {
            throw GraphTransferError.backupAttachmentMissing(attachmentID: entry.id)
        }

        do {
            let data = try Data(contentsOf: assetURL)
            guard Int64(data.count) == entry.byteCount else {
                throw GraphTransferError.backupAttachmentReadFailed(
                    attachmentID: entry.id,
                    underlying: "Asset byte count mismatch. Expected \(entry.byteCount), found \(data.count)."
                )
            }

            if let expectedChecksum = entry.sha256Hex, expectedChecksum.isEmpty == false {
                let actualChecksum = GraphBackupPackageIO.sha256Hex(for: data)
                guard actualChecksum.caseInsensitiveCompare(expectedChecksum) == .orderedSame else {
                    throw GraphTransferError.backupAttachmentChecksumMismatch(attachmentID: entry.id)
                }
            }

            return data
        } catch let error as GraphTransferError {
            throw error
        } catch {
            throw GraphTransferError.backupAttachmentReadFailed(
                attachmentID: entry.id,
                underlying: String(describing: error)
            )
        }
    }
}

