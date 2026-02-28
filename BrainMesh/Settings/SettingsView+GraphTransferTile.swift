//
//  SettingsView+GraphTransferTile.swift
//  BrainMesh
//
//  Created by Marc Fechner on 28.02.26.
//

import SwiftUI

extension SettingsView {
    var graphTransferTile: some View {
        NavigationLink {
            GraphTransferView()
        } label: {
            SettingsHubTile(
                systemImage: "square.and.arrow.up.on.square",
                title: "Export & Import",
                subtitle: "Graph sichern & übertragen",
                showsAccessoryIndicator: false
            )
        }
        .buttonStyle(SettingsHubTileButtonStyle())
    }
}
