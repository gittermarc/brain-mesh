//
//  DetailsCompletionKeyboardToolbar.swift
//  BrainMesh
//
//  Keyboard toolbar helper for accepting a completion suggestion.
//

import SwiftUI

/// A keyboard toolbar item that triggers accepting the current completion suggestion.
///
/// Use inside `.toolbar { DetailsCompletionKeyboardToolbar(...) }`.
struct DetailsCompletionKeyboardToolbar: ToolbarContent {
    let isEnabled: Bool
    let title: String
    let action: () -> Void

    init(
        isEnabled: Bool,
        title: String = "→ Vervollständigen",
        action: @escaping () -> Void
    ) {
        self.isEnabled = isEnabled
        self.title = title
        self.action = action
    }

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button(title) {
                action()
            }
            .disabled(!isEnabled)
            .font(.headline)
        }
    }
}

#Preview {
    struct Demo: View {
        @State private var enabled: Bool = true

        var body: some View {
            Form {
                Section {
                    Toggle("Enabled", isOn: $enabled)

                    TextField("Text", text: .constant("Mün"))
                        .toolbar {
                            DetailsCompletionKeyboardToolbar(isEnabled: enabled) {}
                        }
                }
            }
        }
    }

    return Demo()
}
