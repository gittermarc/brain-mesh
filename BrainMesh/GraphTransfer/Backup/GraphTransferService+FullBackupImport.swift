//
//  GraphTransferService+FullBackupImport.swift
//  BrainMesh
//
//  Full-backup import orchestration for .bmbackup packages.
//

import Foundation

extension GraphTransferService {

    func importFullBackupImpl(
        from url: URL,
        mode: ImportMode,
        progress: (@Sendable (GraphTransferProgress) -> Void)?
    ) async throws -> ImportResult {
        guard let container else { throw GraphTransferError.notConfigured }

        let didStart = url.startAccessingSecurityScopedResource()
        defer {
            if didStart { url.stopAccessingSecurityScopedResource() }
        }

        let package = try Self.readValidatedBackupPackage(url: url)

        switch mode {
        case .asNewGraphRemap:
            let coordinator = GraphTransferImportCoordinator(
                file: package.coreGraph,
                container: container,
                progress: progress
            )
            _ = try await coordinator.runCoreAsNewGraphRemap()
            let attachmentSummary = try await coordinator.importBackupAttachments(
                manifest: package.manifest,
                packageURL: url
            )
            return try coordinator.finalizeImport(
                importedAttachments: attachmentSummary.importedAttachments,
                skippedAttachments: attachmentSummary.skippedAttachments,
                warnings: attachmentSummary.warnings
            )
        }
    }
}

private extension GraphTransferService {

    nonisolated struct ValidatedBackupPackage: Sendable {
        var manifest: GraphBackupManifestV2
        var coreGraph: GraphExportFileV1
    }

    nonisolated static func readValidatedBackupPackage(url: URL) throws -> ValidatedBackupPackage {
        let manifest = try readSupportedBackupManifest(url: url)
        let coreGraph = try readSupportedCoreGraph(packageURL: url, filename: manifest.coreGraphFilename)
        try validateManifest(manifest, matches: coreGraph)
        return ValidatedBackupPackage(manifest: manifest, coreGraph: coreGraph)
    }

    nonisolated static func readSupportedBackupManifest(url: URL) throws -> GraphBackupManifestV2 {
        do {
            let manifest = try GraphBackupPackageIO.readManifest(from: url)
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

    nonisolated static func readSupportedCoreGraph(packageURL: URL, filename: String) throws -> GraphExportFileV1 {
        let coreURL: URL
        do {
            coreURL = try GraphBackupPackageLayout.safeURL(in: packageURL, relativePath: filename)
        } catch {
            throw GraphTransferError.backupCoreGraphInvalid(underlying: String(describing: error))
        }

        guard FileManager.default.fileExists(atPath: coreURL.path) else {
            throw GraphTransferError.backupCoreGraphMissing(filename: filename)
        }

        do {
            let data = try Data(contentsOf: coreURL)
            let coreGraph = try GraphTransferCodec.decode(data)
            try GraphTransferValidator.validate(exportFile: coreGraph)
            return coreGraph
        } catch let error as GraphTransferError {
            throw error
        } catch {
            throw GraphTransferError.backupCoreGraphInvalid(underlying: String(describing: error))
        }
    }

    nonisolated static func validateManifest(
        _ manifest: GraphBackupManifestV2,
        matches coreGraph: GraphExportFileV1
    ) throws {
        guard manifest.graphID == coreGraph.graph.id else {
            throw GraphTransferError.backupCoreGraphMismatch
        }
        guard manifest.counts.matches(coreGraph.counts) else {
            throw GraphTransferError.backupCoreGraphMismatch
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
