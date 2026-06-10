//
//  GraphTransferFileInspection.swift
//  BrainMesh
//
//  Lightweight inspection for supported transfer files.
//

import Foundation

nonisolated enum GraphTransferFileInspection {

    static func inspect(url: URL, fileManager: FileManager = .default) throws -> ImportPreview {
        if isBackupPackage(url: url, fileManager: fileManager) {
            return try GraphBackupPreviewInspection.makePreview(packageURL: url, fileManager: fileManager)
        }
        return try makeGraphStructurePreview(url: url)
    }
}

private extension GraphTransferFileInspection {

    static func isBackupPackage(url: URL, fileManager: FileManager) -> Bool {
        if url.pathExtension.lowercased() == GraphBackupFormat.filenameExtension {
            return true
        }

        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
        guard exists, isDirectory.boolValue else { return false }
        return fileManager.fileExists(atPath: GraphBackupPackageLayout.manifestURL(in: url).path)
    }

    static func makeGraphStructurePreview(url: URL) throws -> ImportPreview {
        let file = try GraphTransferService.decodeValidatedImportFile(url: url)
        return ImportPreview(
            kind: .graphStructure,
            graphName: file.graph.name,
            exportedAt: file.exportedAt,
            version: file.version,
            counts: file.counts
        )
    }
}
