//
//  UTType+BrainMesh.swift
//  BrainMesh
//
//  Graph transfer: exported file types for graph exports (.bmgraph) and full backups (.bmbackup)
//

import Foundation
import UniformTypeIdentifiers

extension UTType {

    /// BrainMesh Graph Export (JSON envelope).
    ///
    /// Backed by Info.plist `UTExportedTypeDeclarations`.
    nonisolated static var brainMeshGraph: UTType {
        UTType(exportedAs: "de.marcfechner.brainmesh.graph", conformingTo: .json)
    }

    nonisolated static let brainMeshGraphFilenameExtension: String = "bmgraph"

    /// BrainMesh Full Backup package.
    ///
    /// Backed by Info.plist `UTExportedTypeDeclarations`.
    nonisolated static var brainMeshBackup: UTType {
        UTType(exportedAs: GraphBackupFormat.exportedTypeIdentifier, conformingTo: .package)
    }

    nonisolated static let brainMeshBackupFilenameExtension: String = GraphBackupFormat.filenameExtension
}
