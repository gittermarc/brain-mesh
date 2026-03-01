//
//  GraphTransferCodec.swift
//  BrainMesh
//
//  JSON encoding/decoding for graph transfer files.
//

import Foundation

enum GraphTransferCodec {

    nonisolated static func decode(_ data: Data) throws -> GraphExportFileV1 {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(GraphExportFileV1.self, from: data)
        } catch {
            throw GraphTransferError.decodeFailed(underlying: String(describing: error))
        }
    }

    nonisolated static func encode(_ exportFile: GraphExportFileV1) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        var formatting: JSONEncoder.OutputFormatting = [.sortedKeys]
        #if DEBUG
        formatting.insert(.prettyPrinted)
        #endif

        encoder.outputFormatting = formatting
        return try encoder.encode(exportFile)
    }
}
