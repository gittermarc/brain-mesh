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
    let onCommit: @MainActor (String) async throws -> Void

    @State private var nameText: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        title: String,
        message: String,
        confirmTitle: String,
        initialText: String,
        placeholder: String,
        onCommit: @MainActor @escaping (String) async throws -> Void
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
                        .disabled(isSaving)
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
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmTitle) {
                        commit()
                    }
                    .disabled(cleanedName.isEmpty || isSaving)
                }
            }
            .overlay {
                if isSaving {
                    ProgressView()
                        .controlSize(.large)
                }
            }
            .alert("Speichern fehlgeschlagen", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if $0 == false { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .presentationDetents([.medium])
    }

    private var cleanedName: String {
        nameText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor
    private func commit() {
        guard isSaving == false else { return }
        isSaving = true
        errorMessage = nil

        Task { @MainActor in
            do {
                try await onCommit(cleanedName)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}
