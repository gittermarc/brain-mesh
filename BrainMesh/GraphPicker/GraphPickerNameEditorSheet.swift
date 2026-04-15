//
//  GraphPickerNameEditorSheet.swift
//  BrainMesh
//
//  Created by Marc Fechner on 14.04.26.
//

import SwiftUI

struct GraphPickerNameEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let message: String
    let confirmTitle: String
    let initialText: String
    let placeholder: String
    let onCommit: (String) -> Void

    @State private var nameText: String

    init(
        title: String,
        message: String,
        confirmTitle: String,
        initialText: String,
        placeholder: String,
        onCommit: @escaping (String) -> Void
    ) {
        self.title = title
        self.message = message
        self.confirmTitle = confirmTitle
        self.initialText = initialText
        self.placeholder = placeholder
        self.onCommit = onCommit
        _nameText = State(initialValue: initialText)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField(placeholder, text: $nameText)
                        .textInputAutocapitalization(.words)
                        .disableAutocorrection(true)
                }

                Section {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmTitle) {
                        onCommit(cleanedName)
                        dismiss()
                    }
                    .disabled(cleanedName.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var cleanedName: String {
        nameText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
