//
//  GraphBackupFormat.swift
//  BrainMesh
//
//  Full-backup package format constants. The existing .bmgraph format stays V1.
//

import Foundation

nonisolated enum GraphBackupFormat {
    static let formatID: String = "brainmesh.backup"
    static let version: Int = 2
    static let exportedTypeIdentifier: String = "de.marcfechner.brainmesh.backup"
    static let filenameExtension: String = "bmbackup"
    static let mimeType: String = "application/vnd.brainmesh.backup"
}
