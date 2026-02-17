//
//  BrainMeshApp.swift
//  BrainMesh
//
//  Created by Marc Fechner on 13.12.25.
//

import SwiftUI
import SwiftData

@main
struct BrainMeshApp: App {

    @StateObject private var appearanceStore = AppearanceStore()
    @StateObject private var onboardingCoordinator = OnboardingCoordinator()
    @StateObject private var graphLockCoordinator = GraphLockCoordinator()
    @StateObject private var systemModalCoordinator = SystemModalCoordinator()

    private let sharedModelContainer: ModelContainer

    init() {
        let schema = Schema([
            MetaGraph.self,
            MetaEntity.self,
            MetaAttribute.self,
            MetaLink.self,
            MetaAttachment.self
        ])

        // CloudKit / iCloud Sync (private DB)
        let cloudConfig = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)

        do {
            sharedModelContainer = try ModelContainer(for: schema, configurations: [cloudConfig])
            print("✅ SwiftData CloudKit: KONTAINER erstellt (cloudKitDatabase: .automatic)")
        } catch {
            #if DEBUG
            fatalError("❌ SwiftData CloudKit KONTAINER FEHLER (DEBUG, kein Fallback): \(error)")
            #else
            print("⚠️ SwiftData CloudKit failed, falling back to local-only: \(error)")
            let localConfig = ModelConfiguration(schema: schema)
            do {
                sharedModelContainer = try ModelContainer(for: schema, configurations: [localConfig])
            } catch {
                fatalError("❌ Could not create local ModelContainer: \(error)")
            }
            #endif
        }

        // Patch 4: Provide the SwiftData container to the attachment hydrator.
        // This allows cache hydration (fileData fetch + disk write) to happen off the UI thread.
        let containerForHydrator = sharedModelContainer
        Task.detached(priority: .utility) {
            await AttachmentHydrator.shared.configure(container: AnyModelContainer(containerForHydrator))
        }

        // Also provide the container to the media loader used by the "Alle" media screen.
        // This avoids blocking the main thread with SwiftData fetches during navigation.
        let containerForMediaLoader = sharedModelContainer
        Task.detached(priority: .utility) {
            await MediaAllLoader.shared.configure(container: AnyModelContainer(containerForMediaLoader))
        }

        // P0.1: Provide the container to the GraphCanvas loader.
        // GraphCanvas performs heavy SwiftData fetches (nodes/links + neighborhood BFS).
        // Running that work off the UI thread avoids main-thread stalls when switching graphs.
        let containerForGraphCanvasLoader = sharedModelContainer
        Task.detached(priority: .utility) {
            await GraphCanvasDataLoader.shared.configure(container: AnyModelContainer(containerForGraphCanvasLoader))
        }

        // P0.1: Provide the container to the GraphStats loader.
        // Stats performs multiple SwiftData counts and summary fetches.
        // Running that work off the UI thread keeps the Stats tab snappy.
        let containerForGraphStatsLoader = sharedModelContainer
        Task.detached(priority: .utility) {
            await GraphStatsLoader.shared.configure(container: AnyModelContainer(containerForGraphStatsLoader))
        }
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(appearanceStore)
                .environmentObject(onboardingCoordinator)
                .environmentObject(graphLockCoordinator)
                .environmentObject(systemModalCoordinator)
        }
        .modelContainer(sharedModelContainer)
    }
}
