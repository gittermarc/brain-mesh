//
//  GraphTransferService+Import.swift
//  BrainMesh
//
//  Import implementation entry points (inspect + import modes).
//

import Foundation

extension GraphTransferService {

    func inspectFileImpl(url: URL) async throws -> ImportPreview {
        guard container != nil else { throw GraphTransferError.notConfigured }
        return try GraphTransferFileInspection.inspect(url: url)
    }

    func importGraphImpl(
        from url: URL,
        mode: ImportMode,
        progress: (@Sendable (GraphTransferProgress) -> Void)?
    ) async throws -> ImportResult {
        guard let container else { throw GraphTransferError.notConfigured }

        progress?(GraphTransferImportProgressFactory.inspecting())
        if GraphTransferFileInspection.isBackupTransfer(url: url) {
            return try await importFullBackupImpl(from: url, mode: mode, progress: progress)
        }

        let file = try Self.decodeValidatedImportFile(url: url)

        let coordinator = GraphTransferImportCoordinator(
            file: file,
            container: container,
            progress: progress,
            mutationPublisher: mutationPublisher,
            completionKind: mode.completionKind,
            saveOperation: importSaveOperation
        )
        return try await coordinator.runAsNewGraphRemap()
    }
}
