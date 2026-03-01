//
//  GraphTransferValidator.swift
//  BrainMesh
//
//  Format + version validation for export/import files.
//

import Foundation

enum GraphTransferValidator {
    static func validate(exportFile: GraphExportFileV1) throws {
        guard exportFile.format == GraphTransferFormat.formatID else {
            throw GraphTransferError.invalidFormat
        }
        guard exportFile.version == GraphTransferFormat.version else {
            throw GraphTransferError.unsupportedVersion(found: exportFile.version)
        }
    }
}
