//
//  GraphBackupPreviewInspection.swift
//  BrainMesh
//
//  Full-backup package validation for import preview. Import itself is intentionally not implemented here.
//

import Foundation

nonisolated enum GraphBackupPreviewInspectionWarningCode {
    static let manifestWarning = "backup-manifest-warning"
    static let unsafeAssetPath = "backup-unsafe-asset-path"
    static let missingAttachmentsDirectory = "backup-missing-attachments-directory"
    static let missingAttachmentAsset = "backup-missing-attachment-asset"
    static let attachmentSizeMismatch = "backup-attachment-size-mismatch"
    static let checksumMismatch = "backup-checksum-mismatch"
    static let checksumReadFailed = "backup-checksum-read-failed"
    static let unexpectedAttachmentAsset = "backup-unexpected-attachment-asset"
    static let manifestCountMismatch = "backup-manifest-count-mismatch"
    static let manifestGraphMismatch = "backup-manifest-graph-mismatch"
}

nonisolated enum GraphBackupPreviewInspection {

    static func makePreview(
        packageURL: URL,
        fileManager: FileManager = .default
    ) throws -> ImportPreview {
        let didStart = packageURL.startAccessingSecurityScopedResource()
        defer {
            if didStart { packageURL.stopAccessingSecurityScopedResource() }
        }

        let manifest = try readSupportedManifest(from: packageURL, fileManager: fileManager)
        let coreGraph = try readAndValidateCoreGraph(
            packageURL: packageURL,
            filename: manifest.coreGraphFilename,
            fileManager: fileManager
        )

        var warnings = manifest.warnings.map { warning in
            GraphBackupPreviewWarning.warning(
                code: "\(GraphBackupPreviewInspectionWarningCode.manifestWarning)-\(warning.code)",
                message: warning.message
            )
        }
        var blockingProblems: [GraphBackupPreviewWarning] = []

        appendManifestConsistencyWarnings(
            manifest: manifest,
            coreGraph: coreGraph,
            warnings: &warnings
        )
        inspectAttachmentAssets(
            manifest: manifest,
            packageURL: packageURL,
            fileManager: fileManager,
            warnings: &warnings,
            blockingProblems: &blockingProblems
        )

        return ImportPreview(
            kind: .fullBackup,
            graphName: manifest.graphName,
            exportedAt: manifest.exportedAt,
            version: manifest.version,
            counts: manifest.counts,
            attachmentCount: manifest.attachmentCount,
            attachmentBytes: manifest.attachmentBytes,
            warnings: warnings,
            blockingProblems: blockingProblems
        )
    }
}

private nonisolated extension GraphBackupPreviewInspection {

    static func readSupportedManifest(
        from packageURL: URL,
        fileManager: FileManager
    ) throws -> GraphBackupManifestV2 {
        do {
            let manifest = try GraphBackupPackageIO.readManifest(from: packageURL, fileManager: fileManager)
            guard manifest.format == GraphBackupFormat.formatID else {
                throw GraphTransferError.invalidBackupFormat
            }
            guard manifest.version == GraphBackupFormat.version else {
                throw GraphTransferError.unsupportedBackupVersion(found: manifest.version)
            }
            return manifest
        } catch let error as GraphTransferError {
            throw error
        } catch {
            throw GraphTransferError.backupManifestReadFailed(underlying: String(describing: error))
        }
    }

    static func readAndValidateCoreGraph(
        packageURL: URL,
        filename: String,
        fileManager: FileManager
    ) throws -> GraphExportFileV1 {
        let coreURL: URL
        do {
            coreURL = try GraphBackupPackageLayout.safeURL(in: packageURL, relativePath: filename)
        } catch {
            throw GraphTransferError.backupCoreGraphInvalid(underlying: String(describing: error))
        }

        guard fileManager.fileExists(atPath: coreURL.path) else {
            throw GraphTransferError.backupCoreGraphMissing(filename: filename)
        }

        do {
            let data = try Data(contentsOf: coreURL)
            let coreGraph = try GraphTransferCodec.decode(data)
            try GraphTransferValidator.validate(exportFile: coreGraph)
            return coreGraph
        } catch {
            throw GraphTransferError.backupCoreGraphInvalid(underlying: String(describing: error))
        }
    }

    static func appendManifestConsistencyWarnings(
        manifest: GraphBackupManifestV2,
        coreGraph: GraphExportFileV1,
        warnings: inout [GraphBackupPreviewWarning]
    ) {
        if manifest.graphID != coreGraph.graph.id {
            warnings.append(
                .warning(
                    code: GraphBackupPreviewInspectionWarningCode.manifestGraphMismatch,
                    message: "Manifest und eingebettete Graph-Datei verweisen auf unterschiedliche Graph-IDs. Prüfe die Quelle des Backups vor einem späteren Import."
                )
            )
        }

        if manifest.counts.matches(coreGraph.counts) == false {
            warnings.append(
                .warning(
                    code: GraphBackupPreviewInspectionWarningCode.manifestCountMismatch,
                    message: "Die Zähler im Manifest weichen von der eingebetteten Graph-Datei ab. Der spätere Import sollte die Vorschau nochmals prüfen."
                )
            )
        }
    }

    static func inspectAttachmentAssets(
        manifest: GraphBackupManifestV2,
        packageURL: URL,
        fileManager: FileManager,
        warnings: inout [GraphBackupPreviewWarning],
        blockingProblems: inout [GraphBackupPreviewWarning]
    ) {
        let attachmentsDirectoryURL = GraphBackupPackageLayout.attachmentsDirectoryURL(in: packageURL)
        var isDirectory: ObjCBool = false
        let directoryExists = fileManager.fileExists(atPath: attachmentsDirectoryURL.path, isDirectory: &isDirectory)
        let expectedPaths = Set(manifest.attachments.map(\.assetRelativePath))

        if directoryExists == false || isDirectory.boolValue == false {
            if manifest.attachments.isEmpty == false {
                warnings.append(
                    .warning(
                        code: GraphBackupPreviewInspectionWarningCode.missingAttachmentsDirectory,
                        message: "Der Anhänge-Ordner fehlt. Die Graph-Struktur ist prüfbar, aber die Anhänge sind in diesem Paket nicht vollständig vorhanden."
                    )
                )
            }
            return
        }

        for entry in manifest.attachments {
            inspectAttachmentEntry(
                entry,
                packageURL: packageURL,
                fileManager: fileManager,
                warnings: &warnings,
                blockingProblems: &blockingProblems
            )
        }

        appendUnexpectedAssetWarnings(
            attachmentsDirectoryURL: attachmentsDirectoryURL,
            expectedPaths: expectedPaths,
            fileManager: fileManager,
            warnings: &warnings
        )
    }

    static func inspectAttachmentEntry(
        _ entry: GraphBackupAttachmentManifestEntry,
        packageURL: URL,
        fileManager: FileManager,
        warnings: inout [GraphBackupPreviewWarning],
        blockingProblems: inout [GraphBackupPreviewWarning]
    ) {
        let assetURL: URL
        do {
            assetURL = try GraphBackupPackageLayout.safeURL(in: packageURL, relativePath: entry.assetRelativePath)
        } catch {
            blockingProblems.append(
                .blocking(
                    code: GraphBackupPreviewInspectionWarningCode.unsafeAssetPath,
                    message: "Ein Anhang verweist auf einen unsicheren Paketpfad und wird nicht importierbar sein."
                )
            )
            return
        }

        guard fileManager.fileExists(atPath: assetURL.path) else {
            warnings.append(
                .warning(
                    code: GraphBackupPreviewInspectionWarningCode.missingAttachmentAsset,
                    message: "Anhang \"\(entry.displayTitle)\" fehlt im Paket."
                )
            )
            return
        }

        if let actualSize = fileSize(of: assetURL, fileManager: fileManager), actualSize != entry.byteCount {
            warnings.append(
                .warning(
                    code: GraphBackupPreviewInspectionWarningCode.attachmentSizeMismatch,
                    message: "Anhang \"\(entry.displayTitle)\" hat eine andere Dateigröße als im Manifest angegeben."
                )
            )
        }

        guard let expectedChecksum = entry.sha256Hex, expectedChecksum.isEmpty == false else { return }
        do {
            let actualChecksum = try GraphBackupPackageIO.sha256Hex(forFileAt: assetURL)
            if actualChecksum.caseInsensitiveCompare(expectedChecksum) != .orderedSame {
                blockingProblems.append(
                    .blocking(
                        code: GraphBackupPreviewInspectionWarningCode.checksumMismatch,
                        message: "Anhang \"\(entry.displayTitle)\" wirkt beschädigt: Die Prüfsumme stimmt nicht."
                    )
                )
            }
        } catch {
            warnings.append(
                .warning(
                    code: GraphBackupPreviewInspectionWarningCode.checksumReadFailed,
                    message: "Die Prüfsumme für Anhang \"\(entry.displayTitle)\" konnte nicht geprüft werden."
                )
            )
        }
    }

    static func appendUnexpectedAssetWarnings(
        attachmentsDirectoryURL: URL,
        expectedPaths: Set<String>,
        fileManager: FileManager,
        warnings: inout [GraphBackupPreviewWarning]
    ) {
        do {
            let urls = try fileManager.contentsOfDirectory(
                at: attachmentsDirectoryURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            let actualPaths = Set(urls.compactMap { url -> String? in
                guard isRegularFile(url, fileManager: fileManager) else { return nil }
                return "\(GraphBackupPackageLayout.attachmentsDirectoryName)/\(url.lastPathComponent)"
            })
            let unexpectedCount = actualPaths.subtracting(expectedPaths).count
            if unexpectedCount > 0 {
                warnings.append(
                    .warning(
                        code: GraphBackupPreviewInspectionWarningCode.unexpectedAttachmentAsset,
                        message: "Das Paket enthält \(unexpectedCount) zusätzliche Anhang-Datei(en), die nicht im Manifest stehen. Diese Dateien werden später ignoriert."
                    )
                )
            }
        } catch {
            warnings.append(
                .warning(
                    code: GraphBackupPreviewInspectionWarningCode.unexpectedAttachmentAsset,
                    message: "Der Anhänge-Ordner konnte nicht vollständig geprüft werden."
                )
            )
        }
    }

    static func fileSize(of url: URL, fileManager: FileManager) -> Int64? {
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            return (attributes[.size] as? NSNumber)?.int64Value
        } catch {
            return nil
        }
    }

    static func isRegularFile(_ url: URL, fileManager: FileManager) -> Bool {
        do {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            return values.isRegularFile == true
        } catch {
            return false
        }
    }
}

private nonisolated extension CountsDTO {
    func matches(_ other: CountsDTO) -> Bool {
        graphs == other.graphs
            && entities == other.entities
            && attributes == other.attributes
            && detailFieldDefinitions == other.detailFieldDefinitions
            && detailFieldValues == other.detailFieldValues
            && links == other.links
    }
}

private nonisolated extension GraphBackupAttachmentManifestEntry {
    var displayTitle: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle.isEmpty == false { return trimmedTitle }
        let original = originalFilename.trimmingCharacters(in: .whitespacesAndNewlines)
        if original.isEmpty == false { return original }
        return id.uuidString
    }
}
