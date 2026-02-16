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
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(appearanceStore)
                .environmentObject(onboardingCoordinator)
                .environmentObject(graphLockCoordinator)
        }
        .modelContainer(sharedModelContainer)
    }
}
