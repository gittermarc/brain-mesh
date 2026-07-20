//
//  GraphTransferService.swift
//  BrainMesh
//
//  Actor-based service for graph export/import.
//  This file intentionally stays small: orchestration + shared state.
//

import Foundation
import os
import SwiftData

actor GraphTransferService {

    static let shared = GraphTransferService()

    private(set) var container: AnyModelContainer? = nil
    let mutationPublisher: any GraphMutationPublishing
    let importSaveOperation: GraphTransferImportSaveOperation
    let log = Logger(subsystem: "BrainMesh", category: "GraphTransferService")

    init(
        mutationPublisher: any GraphMutationPublishing = GraphMutationEventBus.shared,
        importSaveOperation: @escaping GraphTransferImportSaveOperation = { context in
            try context.save()
        }
    ) {
        self.mutationPublisher = mutationPublisher
        self.importSaveOperation = importSaveOperation
    }

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

    struct FullBackupOptions: Sendable {
        var includeNotes: Bool
        var includeIcons: Bool
        var includeHeaderImages: Bool
        var includeAttachments: Bool

        init(
            includeNotes: Bool = true,
            includeIcons: Bool = true,
            includeHeaderImages: Bool = true,
            includeAttachments: Bool = true
        ) {
            self.includeNotes = includeNotes
            self.includeIcons = includeIcons
            self.includeHeaderImages = includeHeaderImages
            self.includeAttachments = includeAttachments
        }

        var coreExportOptions: ExportOptions {
            ExportOptions(
                includeNotes: includeNotes,
                includeIcons: includeIcons,
                includeImages: includeHeaderImages
            )
        }
    }

    // MARK: - API

    func exportGraph(graphID: UUID, options: ExportOptions) async throws -> URL {
        try await exportGraphImpl(graphID: graphID, options: options)
    }

    func exportFullBackup(
        graphID: UUID,
        options: FullBackupOptions = FullBackupOptions(),
        progress: (@Sendable (GraphTransferProgress) -> Void)? = nil
    ) async throws -> URL {
        try await exportFullBackupImpl(graphID: graphID, options: options, progress: progress)
    }

    func inspectFile(url: URL) async throws -> ImportPreview {
        try await inspectFileImpl(url: url)
    }

    func importGraph(
        from url: URL,
        mode: ImportMode,
        progress: (@Sendable (GraphTransferProgress) -> Void)? = nil
    ) async throws -> ImportResult {
        try await importGraphImpl(from: url, mode: mode, progress: progress)
    }
}

// MARK: - App Info

extension GraphTransferService {
    nonisolated static var appVersionString: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    nonisolated static var appBuildString: String? {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String
    }
}
