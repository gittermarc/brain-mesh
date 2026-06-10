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

        let file = try Self.decodeValidatedImportFile(url: url)
        return ImportPreview(
            graphName: file.graph.name,
            exportedAt: file.exportedAt,
            version: file.version,
            counts: file.counts
        )
    }

    func importGraphImpl(
        from url: URL,
        mode: ImportMode,
        progress: (@Sendable (GraphTransferProgress) -> Void)?
    ) async throws -> ImportResult {
        guard let container else { throw GraphTransferError.notConfigured }

        progress?(GraphTransferImportProgressFactory.inspecting())
        let file = try Self.decodeValidatedImportFile(url: url)

        switch mode {
        case .asNewGraphRemap:
            let coordinator = GraphTransferImportCoordinator(
                file: file,
                container: container,
                progress: progress
            )
            return try await coordinator.runAsNewGraphRemap()
        }
    }
}
