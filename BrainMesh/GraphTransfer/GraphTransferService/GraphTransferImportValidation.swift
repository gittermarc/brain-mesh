//
//  GraphTransferImportValidation.swift
//  BrainMesh
//
//  Shared import validation and tuning values.
//

import Foundation

extension GraphTransferService {

    enum ImportTuning {
        static let saveBatchSize: Int = 500
        static let cancellationStride: Int = 50
        static let yieldStride: Int = 200
        static let cancellationStrideValuesAndLinks: Int = 100
        static let yieldStrideValuesAndLinks: Int = 300
    }

    nonisolated static func decodeValidatedImportFile(url: URL) throws -> GraphExportFileV1 {
        let data = try GraphTransferFileIO.readFileData(url: url)
        let file = try GraphTransferCodec.decode(data)
        try GraphTransferValidator.validate(exportFile: file)
        return file
    }
}
