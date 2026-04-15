import SwiftUI

struct GraphDetailsFocusEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let request: GraphCanvasScreen.GraphDetailsFocusEditorRequest
    let activeFocusState: GraphDetailsFocusState?
    let onApply: (GraphDetailsFocusState) -> Void
    let onClear: () -> Void

    @State private var selectedOperator: GraphDetailsComparisonOperator
    @State private var focusMode: GraphDetailsFocusMode
    @State private var selectedChoice: String?
    @State private var toggleValue: Bool
    @State private var numberInput: String
    @State private var dateValue: Date
    @State private var errorText: String?

    init(
        request: GraphCanvasScreen.GraphDetailsFocusEditorRequest,
        activeFocusState: GraphDetailsFocusState?,
        onApply: @escaping (GraphDetailsFocusState) -> Void,
        onClear: @escaping () -> Void
    ) {
        self.request = request
        self.activeFocusState = activeFocusState
        self.onApply = onApply
        self.onClear = onClear

        let existingComparison = activeFocusState?.entityID == request.entityID && activeFocusState?.rule.fieldID == request.field.id
        ? activeFocusState?.rule.comparison
        : nil

        _selectedOperator = State(initialValue: existingComparison?.comparisonOperator ?? GraphDetailsFocusEditorSheet.defaultOperator(for: request.field))
        _focusMode = State(initialValue: existingComparison == nil ? .highlight : (activeFocusState?.mode ?? .highlight))
        _selectedChoice = State(initialValue: GraphDetailsFocusEditorSheet.initialChoice(for: request.field, comparison: existingComparison))
        _toggleValue = State(initialValue: GraphDetailsFocusEditorSheet.initialToggle(comparison: existingComparison))
        _numberInput = State(initialValue: GraphDetailsFocusEditorSheet.initialNumberText(for: request.field, comparison: existingComparison))
        _dateValue = State(initialValue: GraphDetailsFocusEditorSheet.initialDate(comparison: existingComparison))
        _errorText = State(initialValue: nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Entität") {
                        Text(verbatim: request.entityName)
                    }

                    LabeledContent("Feld") {
                        Text(verbatim: request.field.name)
                    }

                    LabeledContent("Typ") {
                        Text(verbatim: request.field.type.title)
                    }
                }

                Section("Regel") {
                    Picker("Vergleich", selection: $selectedOperator) {
                        ForEach(request.field.supportedComparisonOperators) { comparisonOperator in
                            Text(verbatim: comparisonOperator.title).tag(comparisonOperator)
                        }
                    }

                    if selectedOperator.requiresValue {
                        valueEditor
                    }
                }

                Section("Modus") {
                    Picker("Darstellung", selection: $focusMode) {
                        Text("Hervorheben").tag(GraphDetailsFocusMode.highlight)
                        Text("Nur Treffer").tag(GraphDetailsFocusMode.onlyMatches)
                    }
                    .pickerStyle(.segmented)
                }

                if let previewText {
                    Section("Vorschau") {
                        Text(verbatim: previewText)
                            .font(.subheadline)
                    }
                }

                if let errorText {
                    Section {
                        Text(verbatim: errorText)
                            .foregroundStyle(.red)
                    }
                }

                if isEditingActiveFocus {
                    Section {
                        Button(role: .destructive) {
                            onClear()
                            dismiss()
                        } label: {
                            Label("Zurücksetzen", systemImage: "line.3.horizontal.decrease.circle.badge.xmark")
                        }
                    }
                }
            }
            .navigationTitle("Details-Fokus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Schließen") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Anwenden") {
                        applyFocus()
                    }
                    .font(.headline)
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var isEditingActiveFocus: Bool {
        activeFocusState?.entityID == request.entityID && activeFocusState?.rule.fieldID == request.field.id
    }

    @ViewBuilder
    private var valueEditor: some View {
        switch request.field.type {
        case .singleChoice:
            if request.field.options.isEmpty {
                Text("Keine Optionen definiert.")
                    .foregroundStyle(.secondary)
            } else {
                Picker(
                    "Auswahl",
                    selection: Binding(
                        get: { selectedChoice ?? request.field.options.first ?? "" },
                        set: { selectedChoice = $0.isEmpty ? nil : $0 }
                    )
                ) {
                    ForEach(request.field.options, id: \.self) { option in
                        Text(verbatim: option).tag(option)
                    }
                }
            }

        case .toggle:
            Picker("Wert", selection: $toggleValue) {
                Text("Ja").tag(true)
                Text("Nein").tag(false)
            }
            .pickerStyle(.segmented)

        case .numberInt:
            TextField("Zahl", text: $numberInput)
                .keyboardType(.numberPad)

        case .numberDouble:
            TextField("Zahl", text: $numberInput)
                .keyboardType(.decimalPad)

        case .date:
            DatePicker("Datum", selection: $dateValue, displayedComponents: [.date])

        case .singleLineText, .multiLineText:
            EmptyView()
        }
    }

    private var previewText: String? {
        guard let comparison = selectedOperator.makeComparison(value: currentMatchValue()) else {
            return nil
        }

        let focusState = GraphDetailsFocusState(
            entityID: request.entityID,
            entityName: request.entityName,
            rule: GraphDetailsMatchRule(
                fieldID: request.field.id,
                fieldName: request.field.name,
                fieldType: request.field.type,
                comparison: comparison
            ),
            mode: focusMode
        )

        return GraphDetailsFocusFormatting.ruleText(focusState: focusState, field: request.field)
    }

    private func applyFocus() {
        errorText = nil

        guard let comparison = selectedOperator.makeComparison(value: currentMatchValue()) else {
            errorText = validationErrorText
            return
        }

        let focusState = GraphDetailsFocusState(
            entityID: request.entityID,
            entityName: request.entityName,
            rule: GraphDetailsMatchRule(
                fieldID: request.field.id,
                fieldName: request.field.name,
                fieldType: request.field.type,
                comparison: comparison
            ),
            mode: focusMode
        )

        onApply(focusState)
        dismiss()
    }

    private var validationErrorText: String {
        switch request.field.type {
        case .singleChoice:
            return "Bitte wähle eine Option aus."
        case .numberInt, .numberDouble:
            return "Bitte gib einen gültigen Zahlenwert ein."
        case .date:
            return "Bitte wähle ein Datum aus."
        case .toggle:
            return "Bitte wähle Ja oder Nein."
        case .singleLineText, .multiLineText:
            return "Dieser Feldtyp wird im Graph aktuell nicht unterstützt."
        }
    }

    private func currentMatchValue() -> GraphDetailsMatchValue? {
        switch request.field.type {
        case .singleChoice:
            guard let selectedChoice, !selectedChoice.isEmpty else { return nil }
            return .choice(selectedChoice)
        case .toggle:
            return .toggle(toggleValue)
        case .numberInt:
            guard let intValue = Int(numberInput.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                return nil
            }
            return .int(intValue)
        case .numberDouble:
            let normalized = numberInput
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: ",", with: ".")
            guard let doubleValue = Double(normalized) else {
                return nil
            }
            return .double(doubleValue)
        case .date:
            return .date(dateValue)
        case .singleLineText, .multiLineText:
            return nil
        }
    }

    private static func defaultOperator(for field: GraphDetailsPreparedField) -> GraphDetailsComparisonOperator {
        switch field.type {
        case .singleChoice, .toggle:
            return .equals
        case .numberInt, .numberDouble, .date:
            return .isNotEmpty
        case .singleLineText, .multiLineText:
            return .equals
        }
    }

    private static func initialChoice(
        for field: GraphDetailsPreparedField,
        comparison: GraphDetailsMatchComparison?
    ) -> String? {
        if case .equals(.choice(let choice)) = comparison {
            return choice
        }
        return field.options.first
    }

    private static func initialToggle(comparison: GraphDetailsMatchComparison?) -> Bool {
        if case .equals(.toggle(let boolValue)) = comparison {
            return boolValue
        }
        return true
    }

    private static func initialNumberText(
        for field: GraphDetailsPreparedField,
        comparison: GraphDetailsMatchComparison?
    ) -> String {
        switch comparison?.value {
        case .int(let intValue):
            return String(intValue)
        case .double(let doubleValue):
            return doubleValue.formatted(.number.precision(.fractionLength(0...2)))
        default:
            switch field.type {
            case .numberInt, .numberDouble:
                return ""
            case .singleChoice, .toggle, .date, .singleLineText, .multiLineText:
                return ""
            }
        }
    }

    private static func initialDate(comparison: GraphDetailsMatchComparison?) -> Date {
        if case .date(let dateValue) = comparison?.value {
            return dateValue
        }
        return Date()
    }
}
