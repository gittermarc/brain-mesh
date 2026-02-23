//
//  DetailsValueEditorSheet.swift
//  BrainMesh
//
//  Phase 1: Details (frei konfigurierbare Felder)
//

import SwiftUI
import SwiftData
import Foundation

struct DetailsValueEditorSheet: View {
    @Environment(\.modelContext) var modelContext
    @Environment(\.dismiss) var dismiss
    @AppStorage(BMAppStorageKeys.activeGraphID) var activeGraphIDString: String = ""

    @Bindable var attribute: MetaAttribute
    let field: MetaDetailFieldDefinition

    @State var stringInput: String = ""
    @State var numberInput: String = ""
    @State var dateInput: Date = Date()
    @State var boolInput: Bool = false
    @State var selectedChoice: String? = nil

    @State var hasExistingValue: Bool = false
    @State var error: String? = nil

    // MARK: - Completion (singleLineText + multiLineText)

    @FocusState var isSingleLineTextFocused: Bool
    @FocusState var isMultiLineTextFocused: Bool
    @State var didWarmUpCompletionIndex: Bool = false
    @State var topCompletion: DetailsCompletionSuggestion? = nil
    @State var completionTask: Task<Void, Never>? = nil

    @State var multiLineSuggestions: [DetailsCompletionSuggestion] = []
    @State var multiLineTask: Task<Void, Never>? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    editorBody
                } header: {
                    Text(field.name.isEmpty ? "Feld" : field.name)
                } footer: {
                    if let unit = field.unit, field.type.supportsUnit {
                        Text(unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "Einheit: \(unit)")
                    }
                }

                if let error {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }

                if hasExistingValue {
                    Section {
                        Button(role: .destructive) {
                            deleteValue()
                        } label: {
                            Label("Wert löschen", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Schließen") { dismiss() }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sichern") {
                        saveValue()
                    }
                    .font(.headline)
                }

                if field.type == .singleLineText {
                    DetailsCompletionKeyboardToolbar(isEnabled: isSingleLineTextFocused && topCompletion != nil) {
                        acceptTopCompletionIfPossible()
                    }
                }
            }
            .onAppear {
                loadExistingValue()
                warmUpCompletionIndexIfNeeded()
            }
            .onDisappear {
                completionTask?.cancel()
                completionTask = nil
                topCompletion = nil

                multiLineTask?.cancel()
                multiLineTask = nil
                multiLineSuggestions = []
            }
            .onChange(of: isSingleLineTextFocused) { _, newValue in
                if newValue {
                    warmUpCompletionIndexIfNeeded()
                    refreshTopCompletionIfPossible()
                } else {
                    // Hide ghost and disable toolbar when leaving the field.
                    completionTask?.cancel()
                    completionTask = nil
                    topCompletion = nil
                }
            }
            .onChange(of: isMultiLineTextFocused) { _, newValue in
                if newValue {
                    warmUpCompletionIndexIfNeeded()
                    refreshMultiLineSuggestionsIfPossible()
                } else {
                    multiLineTask?.cancel()
                    multiLineTask = nil
                    multiLineSuggestions = []
                }
            }
        }
    }
}
