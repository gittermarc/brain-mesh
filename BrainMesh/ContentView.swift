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
    @EnvironmentObject private var commandCenter: CommandCenterCoordinator

    var body: some View {
        TabView(selection: $tabRouter.selection) {
            ForEach(RootTab.visibleOrder, id: \.self) { tab in
                rootContent(for: tab)
                    .tabItem {
                        Label(tab.title, systemImage: tab.systemImage)
                    }
                    .tag(tab)
            }
        }
        .sheet(isPresented: $commandCenter.isPresented) {
            CommandCenterView(initialQuery: commandCenter.initialQuery)
        }
        .sheet(item: $commandCenter.destination, onDismiss: {
            commandCenter.clearDestination()
        }) { destination in
            CommandCenterDestinationSheet(destination: destination)
        }
    }

    @ViewBuilder
    private func rootContent(for tab: RootTab) -> some View {
        switch tab {
        case .entities:
            EntitiesHomeView()
        case .graph:
            GraphCanvasScreen()
        case .chat:
            GraphChatTabView()
        case .stats:
            GraphStatsView()
        case .settings:
            NavigationStack {
                SettingsView(showDoneButton: false)
            }
        }
    }
}
