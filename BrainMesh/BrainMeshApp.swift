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

    private let sharedModelContainer: ModelContainer

    init() {
        let schema = Schema([
            MetaGraph.self,       // ✅ NEU
            MetaEntity.self,
            MetaAttribute.self,
            MetaLink.self
        ])

        // CloudKit / iCloud Sync (private DB)
        let cloudConfig = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)

        do {
            sharedModelContainer = try ModelContainer(for: schema, configurations: [cloudConfig])
            print("✅ SwiftData CloudKit: KONTAINER erstellt (cloudKitDatabase: .automatic)")

            // ✅ Bootstrap: Default-Graph + Backfill für bestehende Daten
            let ctx = ModelContext(sharedModelContainer)
            GraphBootstrap.bootstrap(using: ctx)

        } catch {
            #if DEBUG
            fatalError("❌ SwiftData CloudKit KONTAINER FEHLER (DEBUG, kein Fallback): \(error)")
            #else
            print("⚠️ SwiftData CloudKit failed, falling back to local-only: \(error)")
            let localConfig = ModelConfiguration(schema: schema)
            do {
                sharedModelContainer = try ModelContainer(for: schema, configurations: [localConfig])

                // ✅ Bootstrap auch im Local-Fallback
                let ctx = ModelContext(sharedModelContainer)
                GraphBootstrap.bootstrap(using: ctx)

            } catch {
                fatalError("❌ Could not create local ModelContainer: \(error)")
            }
            #endif
        }
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                // ✅ GraphSession wird später für Picker/Filter genutzt – stört jetzt nicht.
                .environmentObject(GraphSession.shared)
        }
        .modelContainer(sharedModelContainer)
    }
}
