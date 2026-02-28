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
    static var brainMeshGraph: UTType {
        UTType(exportedAs: "de.marcfechner.brainmesh.graph", conformingTo: .json)
    }

    static let brainMeshGraphFilenameExtension: String = "bmgraph"
}
