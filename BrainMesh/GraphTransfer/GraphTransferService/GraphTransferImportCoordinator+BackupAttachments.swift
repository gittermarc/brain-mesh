//
//  GraphTransferImportCoordinator+BackupAttachments.swift
//  BrainMesh
//
//  Attachment import phase for .bmbackup packages.
//

import Foundation
import SwiftData

nonisolated extension GraphTransferImportCoordinator {

    func importBackupAttachments(
        manifest: GraphBackupManifestV2,
        packageURL: URL,
        fileManager: FileManager = .default
    ) async throws -> GraphBackupAttachmentImportSummary {
        let totalAttachments = manifest.attachments.count
        progress?(GraphTransferImportProgressFactory.importingAttachmentsStart(total: totalAttachments))

        var summary = GraphBackupAttachmentImportSummary(
            importedAttachments: 0,
            skippedAttachments: 0,
            warnings: manifest.warnings.map { warning in
                "Backup-Hinweis: \(warning.message)"
            }
        )

        for (index, entry) in manifest.attachments.enumerated() {
            try await performCheckpoint(
                index: index,
                cancellationStride: GraphTransferService.ImportTuning.cancellationStride,
                yieldStride: GraphTransferService.ImportTuning.yieldStride
            )

            do {
                guard let plan = GraphBackupAttachmentImportPlanner.makePlan(
                    entry: entry,
                    entityIDMap: entityIDMap,
                    attributeIDMap: attributeIDMap
                ) else {
                    summary.skippedAttachments += 1
                    summary.warnings.append(unmappedOwnerWarning(for: entry))
                    reportAttachmentProgress(index: index, total: totalAttachments)
                    continue
                }

                let data = try GraphBackupAttachmentAssetReader.readValidatedData(
                    for: entry,
                    packageURL: packageURL,
                    fileManager: fileManager
                )

                let cacheFilename = writeCacheIfPossible(
                    data: data,
                    attachmentID: plan.importedAttachmentID,
                    fileExtension: plan.fileExtension,
                    entry: entry,
                    warnings: &summary.warnings
                )

                let attachment = MetaAttachment(
                    id: plan.importedAttachmentID,
                    ownerKind: NodeKind(rawValue: plan.ownerKindRaw) ?? .entity,
                    ownerID: plan.remappedOwnerID,
                    graphID: newGraphID,
                    contentKind: AttachmentContentKind(rawValue: plan.contentKindRaw) ?? .file,
                    title: plan.title,
                    originalFilename: plan.originalFilename,
                    contentTypeIdentifier: plan.contentTypeIdentifier,
                    fileExtension: plan.fileExtension,
                    byteCount: data.count,
                    fileData: data,
                    localPath: cacheFilename
                )
                attachment.contentKindRaw = plan.contentKindRaw
                context.insert(attachment)

                summary.importedAttachments += 1
                try recordInsertion()
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as GraphTransferError {
                guard error.isSkippableBackupAttachmentFailure else {
                    throw error
                }
                summary.skippedAttachments += 1
                summary.warnings.append(importWarning(for: entry, error: error))
            } catch {
                summary.skippedAttachments += 1
                summary.warnings.append("Anhang \"\(entry.importDisplayTitle)\" wurde übersprungen, weil er nicht gelesen werden konnte.")
            }

            reportAttachmentProgress(index: index, total: totalAttachments)
        }

        return summary
    }
}

private nonisolated extension GraphTransferImportCoordinator {

    func reportAttachmentProgress(index: Int, total: Int) {
        guard shouldReportProgress(
            index: index,
            total: total,
            stride: GraphTransferService.ImportTuning.cancellationStride
        ) else { return }

        progress?(GraphTransferImportProgressFactory.importingAttachmentStep(
            completed: index + 1,
            total: total
        ))
    }

    func writeCacheIfPossible(
        data: Data,
        attachmentID: UUID,
        fileExtension: String,
        entry: GraphBackupAttachmentManifestEntry,
        warnings: inout [String]
    ) -> String? {
        do {
            let localPath = try AttachmentStore.writeToCache(
                data: data,
                attachmentID: attachmentID,
                fileExtension: fileExtension
            )
            preparedAttachmentCachePaths.insert(localPath)
            return localPath
        } catch {
            warnings.append("Anhang \"\(entry.importDisplayTitle)\" wurde importiert, aber die lokale Cache-Datei konnte nicht erzeugt werden.")
            return nil
        }
    }

    func unmappedOwnerWarning(for entry: GraphBackupAttachmentManifestEntry) -> String {
        "Anhang \"\(entry.importDisplayTitle)\" wurde übersprungen, weil der zugehörige Knoten im importierten Graph nicht gefunden wurde."
    }

    func importWarning(for entry: GraphBackupAttachmentManifestEntry, error: GraphTransferError) -> String {
        switch error {
        case .backupAttachmentMissing:
            return "Anhang \"\(entry.importDisplayTitle)\" fehlt im Backup-Paket und wurde übersprungen."
        case .backupAttachmentSizeMismatch:
            return "Anhang \"\(entry.importDisplayTitle)\" hat eine andere Dateigröße als im Manifest angegeben und wurde übersprungen."
        case .backupAttachmentChecksumMismatch:
            return "Anhang \"\(entry.importDisplayTitle)\" wirkt beschädigt: Die Prüfsumme stimmt nicht. Er wurde übersprungen."
        case .backupAttachmentReadFailed:
            return "Anhang \"\(entry.importDisplayTitle)\" konnte nicht gelesen werden und wurde übersprungen."
        default:
            return "Anhang \"\(entry.importDisplayTitle)\" wurde übersprungen."
        }
    }
}

private nonisolated extension GraphTransferError {
    var isSkippableBackupAttachmentFailure: Bool {
        switch self {
        case .backupAttachmentMissing,
             .backupAttachmentSizeMismatch,
             .backupAttachmentChecksumMismatch,
             .backupAttachmentReadFailed:
            return true
        default:
            return false
        }
    }
}

private nonisolated extension GraphBackupAttachmentManifestEntry {
    var importDisplayTitle: String {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanTitle.isEmpty == false { return cleanTitle }
        let cleanFilename = originalFilename.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanFilename.isEmpty == false { return cleanFilename }
        return id.uuidString
    }
}
