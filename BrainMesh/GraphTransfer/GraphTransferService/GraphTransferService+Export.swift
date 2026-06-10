//
//  GraphTransferService+Export.swift
//  BrainMesh
//
//  Export implementation (DTO mapping + encoding + temp-file write).
//

import Foundation
import os
import SwiftData

extension GraphTransferService {

    func exportGraphImpl(graphID: UUID, options: ExportOptions) async throws -> URL {
        guard let container else { throw GraphTransferError.notConfigured }

        let context = ModelContext(container.container)
        context.autosaveEnabled = false

        let payload = try makeGraphExportFileV1(context: context, graphID: graphID, options: options)
        let data = try GraphTransferCodec.encode(payload.exportFile)
        let fileURL = try GraphTransferFileIO.makeExportFileURL(graphName: payload.graphName)

        do {
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            throw GraphTransferError.writeFailed(underlying: String(describing: error))
        }

        #if DEBUG
        log.debug("✅ Exported graph \(graphID.uuidString, privacy: .public) to \(fileURL.path, privacy: .public)")
        #endif

        return fileURL
    }
}
