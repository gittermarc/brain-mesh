//
//  ContentView.swift
//  BrainMesh
//
//  Created by Marc Fechner on 13.12.25.
//

import SwiftUI

// MARK: - Root Tabs

struct ContentView: View {
    var body: some View {
        TabView {
            EntitiesHomeView()
                .tabItem { Label("Entitäten", systemImage: "list.bullet") }

            GraphCanvasScreen()
                .tabItem { Label("Graph", systemImage: "circle.grid.cross") }

            GraphStatsView()
                .tabItem { Label("Stats", systemImage: "chart.bar") }
        }
    }
}
