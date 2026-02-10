//
//  AppRootView.swift
//  BrainMesh
//
//  Created by Marc Fechner on 15.12.25.
//

import SwiftUI
import SwiftData

struct AppRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @EnvironmentObject private var appearance: AppearanceStore

    @AppStorage("BMActiveGraphID") private var activeGraphIDString: String = ""

    var body: some View {
        ContentView()
            .tint(appearance.appTintColor)
            .preferredColorScheme(appearance.preferredColorScheme)
            .task {
                await bootstrapGraphing()
                await ImageHydrator.hydrateAll(using: modelContext)
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Task {
                        await bootstrapGraphing()
                        await ImageHydrator.hydrateAll(using: modelContext)
                    }
                }
            }
    }

    @MainActor
    private func bootstrapGraphing() async {
        let defaultGraph = GraphBootstrap.ensureAtLeastOneGraph(using: modelContext)

        // Active graph setzen (falls leer / kaputt)
        if UUID(uuidString: activeGraphIDString) == nil {
            activeGraphIDString = defaultGraph.id.uuidString
        }

        // Legacy Records in den Default-Graph schieben
        GraphBootstrap.migrateLegacyRecordsIfNeeded(defaultGraphID: defaultGraph.id, using: modelContext)
    }
}
