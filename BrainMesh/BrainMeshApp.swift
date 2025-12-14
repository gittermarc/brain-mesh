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

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            MetaEntity.self,
            MetaAttribute.self,
            MetaLink.self
        ])

        // CloudKit / iCloud Sync (private DB). Wenn Capabilities noch fehlen -> sauberer Local-Fallback.
        let cloudConfig = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)

        do {
            return try ModelContainer(for: schema, configurations: [cloudConfig])
        } catch {
            // Local-only fallback
            let localConfig = ModelConfiguration(schema: schema)
            do {
                return try ModelContainer(for: schema, configurations: [localConfig])
            } catch {
                fatalError("Could not create ModelContainer (cloud + local failed): \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
