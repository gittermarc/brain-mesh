import SwiftUI
import UIKit

extension DetailsValueEditorSheet {
    @ViewBuilder
    var editorBody: some View {
        switch field.type {
        case .singleLineText:
            DetailsValueEditorSingleLineTextEditor(
                text: $stringInput,
                suggestionText: isSingleLineTextFocused ? topCompletion?.text : nil,
                focus: $isSingleLineTextFocused,
                onTextChange: {
                    refreshTopCompletionIfPossible()
                }
            )

        case .multiLineText:
            DetailsValueEditorMultiLineTextEditor(
                text: $stringInput,
                focus: $isMultiLineTextFocused,
                suggestions: multiLineSuggestions,
                onTextChange: {
                    refreshMultiLineSuggestionsIfPossible()
                },
                onSelectSuggestion: { suggestion in
                    applyMultiLineSuggestion(suggestion)
                }
            )

        case .numberInt:
            DetailsValueEditorNumberEditor(
                title: "Zahl",
                text: $numberInput,
                keyboardType: .numberPad
            )

        case .numberDouble:
            DetailsValueEditorNumberEditor(
                title: "Zahl",
                text: $numberInput,
                keyboardType: .decimalPad
            )

        case .date:
            DetailsValueEditorDateEditor(date: $dateInput)

        case .toggle:
            DetailsValueEditorToggleEditor(isOn: $boolInput)

        case .singleChoice:
            DetailsValueEditorSingleChoiceEditor(
                options: field.options,
                selectedChoice: $selectedChoice
            )
        }
    }
}

private struct DetailsValueEditorSingleLineTextEditor: View {
    @Binding var text: String
    let suggestionText: String?
    var focus: FocusState<Bool>.Binding
    let onTextChange: () -> Void

    var body: some View {
        TextField("Text", text: $text)
            .textInputAutocapitalization(.sentences)
            .focused(focus)
            .detailsCompletionGhost(
                currentText: text,
                suggestionText: suggestionText,
                inset: .init(top: 0, leading: 4, bottom: 0, trailing: 0)
            )
            .onChange(of: text) { _, _ in
                onTextChange()
            }
    }
}

private struct DetailsValueEditorMultiLineTextEditor: View {
    @Binding var text: String
    var focus: FocusState<Bool>.Binding

    let suggestions: [DetailsCompletionSuggestion]
    let onTextChange: () -> Void
    let onSelectSuggestion: (DetailsCompletionSuggestion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextEditor(text: $text)
                .frame(minHeight: 160)
                .font(.body)
                .focused(focus)
                .overlay(alignment: .topLeading) {
                    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Text")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 4)
                    }
                }
                .onChange(of: text) { _, _ in
                    onTextChange()
                }

            DetailsCompletionSuggestionsChipsBar(
                suggestions: suggestions,
                maxVisible: 3,
                showsCounts: false,
                onSelect: { suggestion in
                    onSelectSuggestion(suggestion)
                }
            )
        }
    }
}

private struct DetailsValueEditorNumberEditor: View {
    let title: String
    @Binding var text: String
    let keyboardType: UIKeyboardType

    var body: some View {
        TextField(title, text: $text)
            .keyboardType(keyboardType)
    }
}

private struct DetailsValueEditorDateEditor: View {
    @Binding var date: Date

    var body: some View {
        DatePicker("Datum", selection: $date, displayedComponents: [.date])
    }
}

private struct DetailsValueEditorToggleEditor: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("Ja / Nein", isOn: $isOn)
    }
}

private struct DetailsValueEditorSingleChoiceEditor: View {
    let options: [String]
    @Binding var selectedChoice: String?

    var body: some View {
        if options.isEmpty {
            Text("Keine Optionen definiert.")
                .foregroundStyle(.secondary)
        } else {
            Picker("Auswahl", selection: Binding(
                get: { selectedChoice ?? "" },
                set: { selectedChoice = $0.isEmpty ? nil : $0 }
            )) {
                Text("Nicht gesetzt").tag("")
                ForEach(options, id: \.self) { opt in
                    Text(opt).tag(opt)
                }
            }
        }
    }
}
