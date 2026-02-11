//
//  GraphPickerRenameSheet.swift
//  BrainMesh
//
//  Created by Marc Fechner on 11.02.26.
//

import SwiftUI
import SwiftData

struct GraphPickerRenameSheet: ViewModifier {
    @Environment(\.modelContext) private var modelContext

    @Binding var renameGraph: MetaGraph?
    @Binding var renameText: String

    func body(content: Content) -> some View {
        content
            .alert("Graph umbenennen", isPresented: Binding(
                get: { renameGraph != nil },
                set: { if !$0 { renameGraph = nil } }
            )) {
                TextField("Name", text: $renameText)
                Button("Abbrechen", role: .cancel) { renameGraph = nil }
                Button("Speichern") {
                    guard let g = renameGraph else { return }
                    let cleaned = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    g.name = cleaned.isEmpty ? g.name : cleaned
                    try? modelContext.save()
                    renameGraph = nil
                }
            }
    }
}

extension View {
    func graphPickerRenameSheet(renameGraph: Binding<MetaGraph?>, renameText: Binding<String>) -> some View {
        modifier(GraphPickerRenameSheet(renameGraph: renameGraph, renameText: renameText))
    }
}
