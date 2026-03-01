//
//  AppLoadersConfigurator.swift
//  BrainMesh
//
//  Central place to configure all SwiftData-backed loaders/hydrators off the main thread.
//

import Foundation
import SwiftData

enum AppLoadersConfigurator {

    private static var configureTask: Task<Void, Never>? = nil

    /// Configures all app-wide loaders/hydrators that need access to the SwiftData `ModelContainer`.
    ///
    /// Important:
    /// - This function is intentionally "fire-and-forget".
    /// - Each loader stores the container internally and uses its own throttling / background work strategy.
    static func configureAllLoaders(with modelContainer: ModelContainer) {
        let anyContainer = AnyModelContainer(modelContainer)

        configureTask?.cancel()
        configureTask = Task(priority: .utility) { [anyContainer] in
            if Task.isCancelled { return }

            // Patch 4: Attachment cache hydration (fileData fetch + disk write) off the UI thread.
            await AttachmentHydrator.shared.configure(container: anyContainer)
            if Task.isCancelled { return }

            // P0.1: Image hydration (SwiftData fetch + cache file write) off-main.
            await ImageHydrator.shared.configure(container: anyContainer)
            if Task.isCancelled { return }

            // Media list ("Alle" media screen) uses SwiftData fetches during navigation.
            await MediaAllLoader.shared.configure(container: anyContainer)
            if Task.isCancelled { return }

            // GraphCanvas performs heavy fetches (nodes/links + neighborhood BFS) – keep it off-main.
            await GraphCanvasDataLoader.shared.configure(container: anyContainer)
            if Task.isCancelled { return }

            // Stats performs multiple SwiftData counts and summary fetches – keep it off-main.
            await GraphStatsLoader.shared.configure(container: anyContainer)
            if Task.isCancelled { return }

            // EntitiesHome performs SwiftData fetches for entity + attribute search – keep it off-main.
            await EntitiesHomeLoader.shared.configure(container: anyContainer)
            if Task.isCancelled { return }

            // "Alle" connections screen can include hundreds of links; loading off-main avoids UI stalls.
            await NodeConnectionsLoader.shared.configure(container: anyContainer)
            if Task.isCancelled { return }

            // Node pickers are used across many flows; loading off-main avoids stalls while opening/typing.
            await NodePickerLoader.shared.configure(container: anyContainer)
            if Task.isCancelled { return }

            // Bulk link flow needs existing link sets for duplicate detection – load off-main.
            await BulkLinkLoader.shared.configure(container: anyContainer)
            if Task.isCancelled { return }

            // Renaming entities/attributes updates denormalized link labels; do it off-main.
            await NodeRenameService.shared.configure(container: anyContainer)
        }

    }
}
