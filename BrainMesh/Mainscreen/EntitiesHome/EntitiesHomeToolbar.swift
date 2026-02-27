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
    let preferExpandedActions: Bool

    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { showGraphPicker = true } label: {
                Label(activeGraphName, systemImage: "square.stack.3d.up")
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: isPad ? 220 : nil, alignment: .leading)
            }
            .accessibilityLabel("Graph auswählen")
        }

        if isPad {
            if preferExpandedActions {
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

                    Button { showAddEntity = true } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Entität anlegen")
                }
            } else {
                // iPad mini (Portrait) can run out of top bar space quickly when the active graph name is long.
                // When SwiftUI collapses trailing toolbar items, icon-only buttons without an explicit label can
                // become effectively undiscoverable. We consolidate "Ansicht" + "Sortieren" into a single menu
                // and promote the "+" button to the primary action, so it's always reachable.
                ToolbarItem(placement: .primaryAction) {
                    Button { showAddEntity = true } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Entität anlegen")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showViewOptions = true
                        } label: {
                            Label("Ansicht", systemImage: "eye")
                        }

                        Divider()

                        Picker("Sortieren", selection: $sortSelection) {
                            ForEach(EntitiesHomeSortOption.allCases) { opt in
                                Label(opt.title, systemImage: opt.systemImage)
                                    .tag(opt)
                            }
                        }
                        .pickerStyle(.inline)

                        Divider()

                        Button {
                            showAddEntity = true
                        } label: {
                            Label("Entität anlegen", systemImage: "plus")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Mehr")
                }
            }
        } else {
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

                Button { showAddEntity = true } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Entität anlegen")
            }
        }
    }
}
