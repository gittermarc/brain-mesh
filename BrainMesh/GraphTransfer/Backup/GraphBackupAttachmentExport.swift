//
//  GraphBackupAttachmentExport.swift
//  BrainMesh
//
//  Value-only attachment asset writer for full-backup packages.
//

import Foundation

nonisolated struct GraphBackupAttachmentExportCandidate: Sendable {
    var id: UUID
    var ownerKindRaw: Int
    var ownerID: UUID
    var contentKindRaw: Int
    var title: String
    var originalFilename: String
    var contentTypeIdentifier: String
    var fileExtension: String
    var declaredByteCount: Int64
    var fileData: Data?

    init(
        id: UUID,
        ownerKindRaw: Int,
        ownerID: UUID,
        contentKindRaw: Int,
        title: String,
        originalFilename: String,
        contentTypeIdentifier: String,
        fileExtension: String,
        declaredByteCount: Int64,
        fileData: Data?
    ) {
        self.id = id
        self.ownerKindRaw = ownerKindRaw
        self.ownerID = ownerID
        self.contentKindRaw = contentKindRaw
        self.title = title
        self.originalFilename = originalFilename
        self.contentTypeIdentifier = contentTypeIdentifier
        self.fileExtension = fileExtension
        self.declaredByteCount = declaredByteCount
        self.fileData = fileData
    }
}

nonisolated struct GraphBackupAttachmentExportResult: Sendable {
    var entry: GraphBackupAttachmentManifestEntry?
    var warnings: [GraphBackupManifestWarning]

    static func skipped(_ warning: GraphBackupManifestWarning) -> GraphBackupAttachmentExportResult {
        GraphBackupAttachmentExportResult(entry: nil, warnings: [warning])
    }
}

nonisolated enum GraphBackupAttachmentExportWarningCode {
    static let missingFileData = "attachment-file-data-missing"
    static let byteCountMismatch = "attachment-byte-count-mismatch"
}

nonisolated enum GraphBackupAttachmentAssetExporter {

    static func export(
        candidate: GraphBackupAttachmentExportCandidate,
        to packageURL: URL,
        fileManager: FileManager = .default
    ) throws -> GraphBackupAttachmentExportResult {
        guard let data = candidate.fileData else {
            return .skipped(
                GraphBackupManifestWarning(
                    code: GraphBackupAttachmentExportWarningCode.missingFileData,
                    message: missingDataWarningMessage(for: candidate)
                )
            )
        }

        let assetURL = try GraphBackupPackageLayout.attachmentURL(
            in: packageURL,
            attachmentID: candidate.id,
            fileExtension: candidate.fileExtension
        )
        try fileManager.createDirectory(at: assetURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        do {
            try data.write(to: assetURL, options: [.atomic])
        } catch {
            throw GraphTransferError.backupAttachmentWriteFailed(
                attachmentID: candidate.id,
                underlying: String(describing: error)
            )
        }

        let writtenByteCount = try writtenSize(of: assetURL, attachmentID: candidate.id, fileManager: fileManager)
        guard writtenByteCount == Int64(data.count) else {
            throw GraphTransferError.backupAttachmentWriteFailed(
                attachmentID: candidate.id,
                underlying: "Written asset size does not match source data size."
            )
        }

        var warnings: [GraphBackupManifestWarning] = []
        if candidate.declaredByteCount != writtenByteCount {
            warnings.append(
                GraphBackupManifestWarning(
                    code: GraphBackupAttachmentExportWarningCode.byteCountMismatch,
                    message: byteCountMismatchWarningMessage(
                        declaredByteCount: candidate.declaredByteCount,
                        writtenByteCount: writtenByteCount,
                        candidate: candidate
                    )
                )
            )
        }

        let entry = GraphBackupAttachmentManifestEntry(
            id: candidate.id,
            ownerKindRaw: candidate.ownerKindRaw,
            ownerID: candidate.ownerID,
            contentKindRaw: candidate.contentKindRaw,
            title: candidate.title,
            originalFilename: candidate.originalFilename,
            contentTypeIdentifier: candidate.contentTypeIdentifier,
            fileExtension: candidate.fileExtension,
            byteCount: writtenByteCount,
            sha256Hex: GraphBackupPackageIO.sha256Hex(for: data)
        )

        return GraphBackupAttachmentExportResult(entry: entry, warnings: warnings)
    }
}

private nonisolated extension GraphBackupAttachmentAssetExporter {

    static func writtenSize(of url: URL, attachmentID: UUID, fileManager: FileManager) throws -> Int64 {
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            if let size = attributes[.size] as? NSNumber {
                return size.int64Value
            }
            return 0
        } catch {
            throw GraphTransferError.backupAttachmentWriteFailed(
                attachmentID: attachmentID,
                underlying: String(describing: error)
            )
        }
    }

    static func missingDataWarningMessage(for candidate: GraphBackupAttachmentExportCandidate) -> String {
        let label = candidate.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? candidate.originalFilename
            : candidate.title
        return "Anhang \"\(label)\" wurde übersprungen, weil keine synchronisierten Dateidaten vorhanden sind."
    }

    static func byteCountMismatchWarningMessage(
        declaredByteCount: Int64,
        writtenByteCount: Int64,
        candidate: GraphBackupAttachmentExportCandidate
    ) -> String {
        let label = candidate.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? candidate.originalFilename
            : candidate.title
        return "Anhang \"\(label)\" wurde mit \(writtenByteCount) Bytes exportiert. Gespeichert waren \(declaredByteCount) Bytes."
    }
}
