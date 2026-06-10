//
//  GraphBackupInspection.swift
//  BrainMesh
//
//  Lightweight package inspection for .bmbackup files.
//

import Foundation

nonisolated struct GraphBackupInspectionResult: Sendable {
    var packageURL: URL
    var manifest: GraphBackupManifestV2
    var coreGraphURL: URL
    var attachmentsDirectoryURL: URL

    var attachmentCount: Int {
        manifest.attachmentCount
    }

    var attachmentBytes: Int64 {
        manifest.attachmentBytes
    }
}

nonisolated enum GraphBackupInspection {
    static func inspectPackage(
        at packageURL: URL,
        fileManager: FileManager = .default
    ) throws -> GraphBackupInspectionResult {
        let manifest = try GraphBackupPackageIO.readManifest(from: packageURL, fileManager: fileManager)
        guard manifest.format == GraphBackupFormat.formatID else {
            throw GraphBackupInspectionError.invalidFormat(found: manifest.format)
        }
        guard manifest.version == GraphBackupFormat.version else {
            throw GraphBackupInspectionError.unsupportedVersion(found: manifest.version)
        }

        let coreGraphURL = try GraphBackupPackageLayout.safeURL(
            in: packageURL,
            relativePath: manifest.coreGraphFilename
        )
        guard fileManager.fileExists(atPath: coreGraphURL.path) else {
            throw GraphBackupInspectionError.missingCoreGraph(filename: manifest.coreGraphFilename)
        }

        let attachmentsDirectoryURL = GraphBackupPackageLayout.attachmentsDirectoryURL(in: packageURL)
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: attachmentsDirectoryURL.path, isDirectory: &isDirectory)
        guard exists, isDirectory.boolValue else {
            throw GraphBackupInspectionError.missingAttachmentsDirectory
        }

        return GraphBackupInspectionResult(
            packageURL: packageURL,
            manifest: manifest,
            coreGraphURL: coreGraphURL,
            attachmentsDirectoryURL: attachmentsDirectoryURL
        )
    }
}

nonisolated enum GraphBackupInspectionError: Error, Equatable, Sendable {
    case invalidFormat(found: String)
    case unsupportedVersion(found: Int)
    case missingCoreGraph(filename: String)
    case missingAttachmentsDirectory
}
