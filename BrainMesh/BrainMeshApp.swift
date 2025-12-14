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
            MetaEntity.self,
            MetaAttribute.self,
            MetaLink.self
        ])

        // CloudKit / iCloud Sync (private DB)
        let cloudConfig = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)

        do {
            sharedModelContainer = try ModelContainer(for: schema, configurations: [cloudConfig])
            print("✅ SwiftData CloudKit: KONTAINER erstellt (cloudKitDatabase: .automatic)")
        } catch {
            // Debug: lieber hart scheitern, sonst merkst du nie, dass du lokal läufst.
            #if DEBUG
            fatalError("❌ SwiftData CloudKit KONTAINER FEHLER (DEBUG, kein Fallback): \(error)")
            #else
            // Release: optionaler Local-Fallback (dein ursprünglicher Ansatz)
            print("⚠️ SwiftData CloudKit failed, falling back to local-only: \(error)")
            let localConfig = ModelConfiguration(schema: schema)
            do {
                sharedModelContainer = try ModelContainer(for: schema, configurations: [localConfig])
            } catch {
                fatalError("❌ Could not create local ModelContainer: \(error)")
            }
            #endif
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
