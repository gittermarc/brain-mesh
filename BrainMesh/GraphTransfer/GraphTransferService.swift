//
//  GraphTransferService.swift
//  BrainMesh
//
//  Actor-based service for graph export/import.
//  (Skeleton only in PR GT1)
//

import Foundation
import os

actor GraphTransferService {

    static let shared = GraphTransferService()

    private var container: AnyModelContainer? = nil
    private let log = Logger(subsystem: "BrainMesh", category: "GraphTransferService")

    func configure(container: AnyModelContainer) {
        self.container = container
        #if DEBUG
        log.debug("✅ configured")
        #endif
    }

    // MARK: - Public Types

    struct ExportOptions: Sendable {
        var includeNotes: Bool
        var includeIcons: Bool
        var includeImages: Bool

        init(includeNotes: Bool = true, includeIcons: Bool = true, includeImages: Bool = false) {
            self.includeNotes = includeNotes
            self.includeIcons = includeIcons
            self.includeImages = includeImages
        }
    }

    enum ImportMode: Sendable {
        case asNewGraphRemap
    }

    struct ImportPreview: Sendable {
        var format: String
        var version: Int
        var exportedAt: Date
        var graphName: String
        var counts: CountsDTO
    }

    struct ImportResult: Sendable {
        var newGraphID: UUID
        var counts: CountsDTO
        var skippedLinksCount: Int
    }

    // MARK: - API (Stubs in PR GT1)

    func exportGraph(graphID: UUID, options: ExportOptions) async throws -> URL {
        _ = container
        _ = graphID
        _ = options
        throw GraphTransferError.notImplemented
    }

    func inspectFile(url: URL) async throws -> ImportPreview {
        _ = container
        _ = url
        throw GraphTransferError.notImplemented
    }

    func importGraph(from url: URL, mode: ImportMode) async throws -> ImportResult {
        _ = container
        _ = url
        _ = mode
        throw GraphTransferError.notImplemented
    }
}
