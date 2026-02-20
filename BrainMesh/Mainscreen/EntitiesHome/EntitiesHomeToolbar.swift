//
//  EntitiesHomeToolbar.swift
//  BrainMesh
//
//  Created by Marc Fechner on 20.02.26.
//

import SwiftUI

struct EntitiesHomeToolbar: ToolbarContent {
    let activeGraphName: String
    @Binding var showGraphPicker: Bool
    @Binding var showViewOptions: Bool
    @Binding var sortSelection: EntitiesHomeSortOption
    @Binding var showAddEntity: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { showGraphPicker = true } label: {
                Label(activeGraphName, systemImage: "square.stack.3d.up")
                    .labelStyle(.titleAndIcon)
            }
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            Button { showViewOptions = true } label: {
                Image(systemName: "eye")
            }
            .accessibilityLabel("Ansicht")

            Menu {
                Picker("Sortieren", selection: $sortSelection) {
                    ForEach(EntitiesHomeSortOption.allCases) { opt in
                        Label(opt.title, systemImage: opt.systemImage)
                            .tag(opt)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .accessibilityLabel("Sortieren")

            Button { showAddEntity = true } label: { Image(systemName: "plus") }
        }
    }
}
