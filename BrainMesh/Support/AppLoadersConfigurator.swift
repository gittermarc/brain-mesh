//
//  AppLoadersConfigurator.swift
//  BrainMesh
//
//  Central place to configure all SwiftData-backed loaders/hydrators off the main thread.
//

import Foundation
import SwiftData

enum AppLoadersConfigurator {

    /// Configures all app-wide loaders/hydrators that need access to the SwiftData `ModelContainer`.
    ///
    /// Important:
    /// - This function is intentionally "fire-and-forget".
    /// - Each loader stores the container internally and uses its own throttling / background work strategy.
    static func configureAllLoaders(with modelContainer: ModelContainer) {
        let anyContainer = AnyModelContainer(modelContainer)

        Task.detached(priority: .utility) { [anyContainer] in
            // Patch 4: Attachment cache hydration (fileData fetch + disk write) off the UI thread.
            await AttachmentHydrator.shared.configure(container: anyContainer)

            // P0.1: Image hydration (SwiftData fetch + cache file write) off-main.
            await ImageHydrator.shared.configure(container: anyContainer)

            // Media list ("Alle" media screen) uses SwiftData fetches during navigation.
            await MediaAllLoader.shared.configure(container: anyContainer)

            // GraphCanvas performs heavy fetches (nodes/links + neighborhood BFS) – keep it off-main.
            await GraphCanvasDataLoader.shared.configure(container: anyContainer)

            // Stats performs multiple SwiftData counts and summary fetches – keep it off-main.
            await GraphStatsLoader.shared.configure(container: anyContainer)

            // EntitiesHome performs SwiftData fetches for entity + attribute search – keep it off-main.
            await EntitiesHomeLoader.shared.configure(container: anyContainer)

            // "Alle" connections screen can include hundreds of links; loading off-main avoids UI stalls.
            await NodeConnectionsLoader.shared.configure(container: anyContainer)

            // Node pickers are used across many flows; loading off-main avoids stalls while opening/typing.
            await NodePickerLoader.shared.configure(container: anyContainer)

            // Renaming entities/attributes updates denormalized link labels; do it off-main.
            await NodeRenameService.shared.configure(container: anyContainer)
        }
    }
}
