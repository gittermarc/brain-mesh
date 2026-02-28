//
//  UTType+BrainMesh.swift
//  BrainMesh
//
//  Graph transfer: exported file type for graph exports (.bmgraph)
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
}
