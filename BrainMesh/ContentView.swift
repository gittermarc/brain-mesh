//
//  ContentView.swift
//  BrainMesh
//
//  Created by Marc Fechner on 13.12.25.
//

import SwiftUI

// MARK: - Root Tabs

struct ContentView: View {
    @EnvironmentObject private var tabRouter: RootTabRouter

    var body: some View {
        TabView(selection: $tabRouter.selection) {
            EntitiesHomeView()
                .tabItem { Label("Entitäten", systemImage: "list.bullet") }
                .tag(RootTab.entities)

            GraphCanvasScreen()
                .tabItem { Label("Graph", systemImage: "circle.grid.cross") }
                .tag(RootTab.graph)

            GraphStatsView()
                .tabItem { Label("Stats", systemImage: "chart.bar") }
                .tag(RootTab.stats)

            NavigationStack {
                SettingsView(showDoneButton: false)
            }
            .tabItem { Label("Einstellungen", systemImage: "gearshape") }
            .tag(RootTab.settings)
        }
    }
}
