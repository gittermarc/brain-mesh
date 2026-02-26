//
//  NodeDetailShared+Core.RenameSheet.swift
//  BrainMesh
//
//  Shared rename sheet used by detail screens.
//

import SwiftUI

// MARK: - Rename Sheet (Entity / Attribute)

/// Minimal, focused rename UI used from the detail screens.
///
/// We keep renaming explicit (via the context menu) and update link labels after saving,
/// so the Connections UI stays consistent.
@MainActor
struct NodeRenameSheet: View {
    @Environment(\.dismiss) private var dismiss

    let kindTitle: String
    let originalName: String
    let helpText: String

    let onSave: (String) async throws -> Void

    @State private var name: String
    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil

    init(
        kindTitle: String,
        originalName: String,
        helpText: String = "Aktualisiert auch bestehende Verbindungen.",
        onSave: @escaping (String) async throws -> Void
    ) {
        self.kindTitle = kindTitle
        self.originalName = originalName
        self.helpText = helpText
        self.onSave = onSave
        _name = State(initialValue: originalName)
    }

    private var cleaned: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var originalCleaned: String {
        originalName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !cleaned.isEmpty && cleaned != originalCleaned
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled(false)
                        .submitLabel(.done)
                        .disabled(isSaving)
                        .onSubmit {
                            Task { @MainActor in await commitIfPossible() }
                        }
                } footer: {
                    Text(helpText)
                }
            }
            .navigationTitle("\(kindTitle) umbenennen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Speichern") {
                            Task { @MainActor in await commitIfPossible() }
                        }
                        .disabled(!canSave)
                    }
                }
            }
            .alert("BrainMesh", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func commitIfPossible() async {
        guard canSave else { return }
        isSaving = true
        defer { isSaving = false }

        do {
            try await onSave(cleaned)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
