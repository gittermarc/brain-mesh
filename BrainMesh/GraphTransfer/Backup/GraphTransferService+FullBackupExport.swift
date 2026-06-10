//
//  GraphTransferService+FullBackupExport.swift
//  BrainMesh
//
//  Full-backup export orchestration for .bmbackup packages.
//

import Foundation
import os
import SwiftData

extension GraphTransferService {

    func exportFullBackupImpl(
        graphID: UUID,
        options: FullBackupOptions,
        progress: (@Sendable (GraphTransferProgress) -> Void)?
    ) async throws -> URL {
        guard let container else { throw GraphTransferError.notConfigured }

        let context = ModelContext(container.container)
        context.autosaveEnabled = false

        var packageURL: URL?
        do {
            progress?(GraphTransferExportProgressFactory.exportingGraph())
            let exportedAt = Date()
            let corePayload = try makeGraphExportFileV1(
                context: context,
                graphID: graphID,
                options: options.coreExportOptions,
                exportedAt: exportedAt
            )
            let coreGraphData = try GraphTransferCodec.encode(corePayload.exportFile)

            let createdPackageURL: URL
            do {
                createdPackageURL = try GraphBackupPackageIO.createTemporaryPackage(graphName: corePayload.graphName)
                packageURL = createdPackageURL
                try GraphBackupPackageIO.writeCoreGraphData(coreGraphData, to: createdPackageURL)
            } catch {
                throw GraphTransferError.backupPackageWriteFailed(underlying: String(describing: error))
            }

            let attachmentResult: GraphFullBackupAttachmentExportCollection
            if options.includeAttachments {
                attachmentResult = try exportAttachments(
                    graphID: graphID,
                    context: context,
                    packageURL: createdPackageURL,
                    progress: progress
                )
            } else {
                attachmentResult = GraphFullBackupAttachmentExportCollection(entries: [], warnings: [])
            }

            progress?(GraphTransferExportProgressFactory.writingBackupManifest())
            let manifest = GraphBackupManifestV2(
                exportedAt: exportedAt,
                appVersion: Self.appVersionString,
                appBuild: Self.appBuildString,
                graphID: graphID,
                graphName: corePayload.graphName,
                counts: corePayload.exportFile.counts,
                attachments: attachmentResult.entries,
                warnings: attachmentResult.warnings
            )

            do {
                try GraphBackupPackageIO.writeManifest(manifest, to: createdPackageURL)
            } catch {
                throw GraphTransferError.backupManifestWriteFailed(underlying: String(describing: error))
            }

            progress?(GraphTransferExportProgressFactory.done())

            #if DEBUG
            log.debug("✅ Exported full backup \(graphID.uuidString, privacy: .public) to \(createdPackageURL.path, privacy: .public)")
            #endif

            return createdPackageURL
        } catch {
            if let packageURL {
                try? FileManager.default.removeItem(at: packageURL)
            }
            throw error
        }
    }
}

private extension GraphTransferService {

    func exportAttachments(
        graphID: UUID,
        context: ModelContext,
        packageURL: URL,
        progress: (@Sendable (GraphTransferProgress) -> Void)?
    ) throws -> GraphFullBackupAttachmentExportCollection {
        let attachments = try fetchBackupAttachments(graphID: graphID, context: context)
        progress?(GraphTransferExportProgressFactory.backupAttachmentsStart(total: attachments.count))

        var entries: [GraphBackupAttachmentManifestEntry] = []
        var warnings: [GraphBackupManifestWarning] = []
        entries.reserveCapacity(attachments.count)

        for (index, attachment) in attachments.enumerated() {
            try Task.checkCancellation()

            let candidate = GraphBackupAttachmentExportCandidate(
                id: attachment.id,
                ownerKindRaw: attachment.ownerKindRaw,
                ownerID: attachment.ownerID,
                contentKindRaw: attachment.contentKindRaw,
                title: attachment.title,
                originalFilename: attachment.originalFilename,
                contentTypeIdentifier: attachment.contentTypeIdentifier,
                fileExtension: attachment.fileExtension,
                declaredByteCount: Int64(attachment.byteCount),
                fileData: attachment.fileData
            )

            let result = try GraphBackupAttachmentAssetExporter.export(candidate: candidate, to: packageURL)
            if let entry = result.entry {
                entries.append(entry)
            }
            warnings.append(contentsOf: result.warnings)

            progress?(GraphTransferExportProgressFactory.backupAttachmentStep(completed: index + 1, total: attachments.count))
        }

        return GraphFullBackupAttachmentExportCollection(entries: entries, warnings: warnings)
    }

    func fetchBackupAttachments(graphID: UUID, context: ModelContext) throws -> [MetaAttachment] {
        let gid = graphID
        let descriptor = FetchDescriptor<MetaAttachment>(
            predicate: #Predicate { attachment in
                attachment.graphID == gid
            },
            sortBy: [
                SortDescriptor(\.createdAt, order: .forward)
            ]
        )
        return try context.fetch(descriptor)
    }
}

private struct GraphFullBackupAttachmentExportCollection: Sendable {
    var entries: [GraphBackupAttachmentManifestEntry]
    var warnings: [GraphBackupManifestWarning]
}
