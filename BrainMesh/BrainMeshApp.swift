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
    @StateObject private var displaySettingsStore = DisplaySettingsStore()
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
            MetaAttachment.self,
            MetaDetailFieldDefinition.self,
            MetaDetailFieldValue.self
        ])

        // CloudKit / iCloud Sync (private DB)
        let cloudConfig = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)

        do {
            sharedModelContainer = try ModelContainer(for: schema, configurations: [cloudConfig])
            print("✅ SwiftData CloudKit: KONTAINER erstellt (cloudKitDatabase: .automatic)")
            SyncRuntime.shared.setStorageMode(.cloudKit)
        } catch {
            #if DEBUG
            fatalError("❌ SwiftData CloudKit KONTAINER FEHLER (DEBUG, kein Fallback): \(error)")
            #else
            print("⚠️ SwiftData CloudKit failed, falling back to local-only: \(error)")
            let localConfig = ModelConfiguration(schema: schema)
            do {
                sharedModelContainer = try ModelContainer(for: schema, configurations: [localConfig])
                SyncRuntime.shared.setStorageMode(.localOnly)
            } catch {
                fatalError("❌ Could not create local ModelContainer: \(error)")
            }
            #endif
        }

        // Refresh iCloud account status once on launch (shows up in Settings → Sync).
        Task.detached(priority: .utility) {
            await SyncRuntime.shared.refreshAccountStatus()
        }

        // App-level loader/hydrator configuration (off-main).
        AppLoadersConfigurator.configureAllLoaders(with: sharedModelContainer)
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(appearanceStore)
                .environmentObject(displaySettingsStore)
                .environmentObject(onboardingCoordinator)
                .environmentObject(graphLockCoordinator)
                .environmentObject(systemModalCoordinator)
        }
        .modelContainer(sharedModelContainer)
    }
}
