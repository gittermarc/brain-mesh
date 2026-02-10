//
//  IconPickerRow.swift
//  BrainMesh
//
//  Created by Marc Fechner on 10.02.26.
//

import SwiftUI

struct IconPickerRow: View {
    let title: String
    @Binding var symbolName: String?

    @State private var showPicker = false

    var body: some View {
        Button { showPicker = true } label: {
            HStack(spacing: 12) {
                Text(title)
                Spacer()
                HStack(spacing: 8) {
                    Image(systemName: symbolName ?? "square.dashed")
                        .font(.system(size: 18, weight: .semibold))
                    if symbolName == nil {
                        Text("Keins")
                            .foregroundStyle(.secondary)
                    }
                }
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showPicker) {
            IconPickerView(selection: $symbolName)
        }
    }
}
