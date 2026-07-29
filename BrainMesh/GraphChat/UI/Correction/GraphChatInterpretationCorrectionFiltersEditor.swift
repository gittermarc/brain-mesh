//
//  GraphChatInterpretationCorrectionFiltersEditor.swift
//  BrainMesh
//
//  Type-specific filter controls backed only by current schema options. This
//  edits a correction draft; the existing compiler and validator remain the
//  sole source of executable query semantics.
//

import Foundation
import SwiftUI

struct GraphChatInterpretationCorrectionFiltersEditor:
    View
{
    let title: String
    let emptyFieldsMessage: String
    let addFilterTitle: String
    let removeFilterTitle: String
    let fieldTitle: String
    let operationTitle: String
    let valueTitle: String
    let rangeUpperTitle: String
    let yearTitle: String
    let monthTitle: String
    let noChoicesMessage: String
    let fields:
        [GraphChatInterpretationCorrectionFieldOption]
    @Binding var filters:
        [GraphChatInterpretationCorrectionFilter]
    let locale: Locale

    private var firstFilterableField:
        GraphChatInterpretationCorrectionFieldOption?
    {
        fields.first {
            $0.operators.isEmpty == false
        }
    }

    var body: some View {
        Section(title) {
            if fields.isEmpty {
                Label(
                    emptyFieldsMessage,
                    systemImage:
                        "line.3.horizontal.decrease.circle"
                )
                .foregroundStyle(.secondary)
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )
            } else {
                ForEach($filters) { $filter in
                    GraphChatInterpretationCorrectionFilterRow(
                        filter: $filter,
                        fields: fields,
                        fieldTitle: fieldTitle,
                        operationTitle:
                            operationTitle,
                        valueTitle: valueTitle,
                        removeFilterTitle:
                            removeFilterTitle,
                        rangeUpperTitle:
                            rangeUpperTitle,
                        yearTitle: yearTitle,
                        monthTitle: monthTitle,
                        noChoicesMessage:
                            noChoicesMessage,
                        locale: locale,
                        onRemove: {
                            filters.removeAll {
                                $0.id == filter.id
                            }
                        }
                    )
                }

                Button {
                    addFilter()
                } label: {
                    Label(
                        addFilterTitle,
                        systemImage: "plus"
                    )
                }
                .disabled(
                    firstFilterableField == nil
                        || filters.count
                            >= GraphChatSemanticSafety
                                .maximumFilters
                )
                .accessibilityIdentifier(
                    "graph-chat-correction-add-filter"
                )
            }
        }
    }

    private func addFilter() {
        guard
            filters.count
                < GraphChatSemanticSafety
                    .maximumFilters,
            let field = firstFilterableField,
            let operation = field.operators.first
        else {
            return
        }
        filters.append(
            GraphChatInterpretationCorrectionFilter(
                fieldID: field.id,
                operation: operation.operation,
                value:
                    GraphChatInterpretationCorrectionFilterValue
                        .defaultValue(
                            for: operation.valueEditor,
                            field: field,
                            calendar:
                                localizedCalendar
                        )
            )
        )
    }

    private var localizedCalendar: Calendar {
        var calendar = Calendar(
            identifier: .gregorian
        )
        calendar.locale = locale
        return calendar
    }
}

private struct GraphChatInterpretationCorrectionFilterRow:
    View
{
    @Binding var filter:
        GraphChatInterpretationCorrectionFilter
    let fields:
        [GraphChatInterpretationCorrectionFieldOption]
    let fieldTitle: String
    let operationTitle: String
    let valueTitle: String
    let removeFilterTitle: String
    let rangeUpperTitle: String
    let yearTitle: String
    let monthTitle: String
    let noChoicesMessage: String
    let locale: Locale
    let onRemove: () -> Void

    private var field:
        GraphChatInterpretationCorrectionFieldOption?
    {
        fields.first {
            $0.id == filter.fieldID
        }
    }

    private var operation:
        GraphChatInterpretationCorrectionOperatorOption?
    {
        field?.operators.first {
            $0.operation == filter.operation
        }
    }

    private var calendar: Calendar {
        var calendar = Calendar(
            identifier: .gregorian
        )
        calendar.locale = locale
        return calendar
    }

    private var currentYear: Int {
        calendar.component(.year, from: .now)
    }

    private var currentMonth: Int {
        calendar.component(.month, from: .now)
    }

    private var selectedYear: Int {
        switch filter.value {
        case .year(let year):
            return year
        case .month(let value):
            return value.year
        default:
            return currentYear
        }
    }

    private var selectableYears:
        ClosedRange<Int>
    {
        let lowerBound =
            min(selectedYear, currentYear - 100)
        let upperBound =
            max(selectedYear, currentYear + 100)
        return lowerBound...upperBound
    }

    private var monthSymbols: [String] {
        let symbols =
            calendar.standaloneMonthSymbols
        return symbols.isEmpty
            ? calendar.monthSymbols
            : symbols
    }

    private var usesGermanCopy: Bool {
        locale.identifier
            .lowercased()
            .hasPrefix("de")
    }

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            Picker(
                fieldTitle,
                selection: $filter.fieldID
            ) {
                ForEach(fields) { field in
                    Text(field.displayName)
                        .tag(field.id)
                }
            }

            if let field {
                if field.operators.isEmpty {
                    Label(
                        noChoicesMessage,
                        systemImage:
                            "exclamationmark.triangle"
                    )
                    .foregroundStyle(.secondary)
                } else {
                    Picker(
                        operationTitle,
                        selection:
                            $filter.operation
                    ) {
                        ForEach(field.operators) { option in
                            Text(option.displayName)
                                .tag(option.operation)
                        }
                    }
                }
            }

            valueEditor

            Button(
                role: .destructive,
                action: onRemove
            ) {
                Label(
                    removeFilterTitle,
                    systemImage: "trash"
                )
            }
            .accessibilityHint(removeFilterTitle)
            .accessibilityIdentifier(
                "graph-chat-correction-remove-filter"
            )
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .onAppear {
            ensureCompatibleOperationAndValue()
        }
        .onChange(of: filter.fieldID) { _, _ in
            ensureCompatibleOperationAndValue()
        }
        .onChange(of: filter.operation) { _, _ in
            ensureCompatibleOperationAndValue()
        }
    }

    @ViewBuilder
    private var valueEditor: some View {
        if let field,
           let operation {
            switch operation.valueEditor {
            case .noValue:
                EmptyView()

            case .text:
                TextField(
                    valueTitle,
                    text: textBinding,
                    axis:
                        field.type == .multiLineText
                            ? .vertical
                            : .horizontal
                )
                .textInputAutocapitalization(.sentences)

            case .integer:
                TextField(
                    valueLabel(for: field),
                    text: integerBinding
                )
                .keyboardType(.numbersAndPunctuation)

            case .integerRange:
                TextField(
                    valueLabel(for: field),
                    text: integerRangeLowerBinding
                )
                .keyboardType(.numbersAndPunctuation)
                TextField(
                    rangeUpperTitle,
                    text: integerRangeUpperBinding
                )
                .keyboardType(.numbersAndPunctuation)

            case .decimal:
                TextField(
                    valueLabel(for: field),
                    text: decimalBinding
                )
                .keyboardType(.decimalPad)

            case .decimalRange:
                TextField(
                    valueLabel(for: field),
                    text: decimalRangeLowerBinding
                )
                .keyboardType(.decimalPad)
                TextField(
                    rangeUpperTitle,
                    text: decimalRangeUpperBinding
                )
                .keyboardType(.decimalPad)

            case .date:
                DatePicker(
                    valueTitle,
                    selection: dateBinding,
                    displayedComponents: [.date]
                )

            case .dateRange:
                DatePicker(
                    valueTitle,
                    selection:
                        dateRangeLowerBinding,
                    displayedComponents: [.date]
                )
                DatePicker(
                    rangeUpperTitle,
                    selection:
                        dateRangeUpperBinding,
                    in:
                        dateRangeLowerBinding
                            .wrappedValue...,
                    displayedComponents: [.date]
                )

            case .year:
                Picker(
                    yearTitle,
                    selection: yearBinding
                ) {
                    ForEach(
                        selectableYears,
                        id: \.self
                    ) { year in
                        Text(
                            localizedYear(year)
                        )
                        .tag(year)
                    }
                }

            case .month:
                Picker(
                    monthTitle,
                    selection: monthBinding
                ) {
                    ForEach(1...12, id: \.self) { month in
                        Text(
                            localizedMonth(month)
                        )
                        .tag(month)
                    }
                }
                Picker(
                    yearTitle,
                    selection: monthYearBinding
                ) {
                    ForEach(
                        selectableYears,
                        id: \.self
                    ) { year in
                        Text(
                            localizedYear(year)
                        )
                        .tag(year)
                    }
                }

            case .toggle:
                Picker(
                    valueTitle,
                    selection: toggleBinding
                ) {
                    Text(
                        usesGermanCopy
                            ? "Ja"
                            : "Yes"
                    )
                    .tag(true)
                    Text(
                        usesGermanCopy
                            ? "Nein"
                            : "No"
                    )
                    .tag(false)
                }

            case .singleChoice:
                choiceEditor(
                    field: field,
                    allowsMultiple: false
                )

            case .multipleChoice:
                choiceEditor(
                    field: field,
                    allowsMultiple: true
                )
            }
        }
    }

    @ViewBuilder
    private func choiceEditor(
        field:
            GraphChatInterpretationCorrectionFieldOption,
        allowsMultiple: Bool
    ) -> some View {
        if field.choiceOptions.isEmpty {
            Label(
                noChoicesMessage,
                systemImage: "list.bullet.rectangle"
            )
            .foregroundStyle(.secondary)
            .fixedSize(
                horizontal: false,
                vertical: true
            )
        } else if allowsMultiple {
            ForEach(field.choiceOptions) { option in
                Toggle(
                    option.displayName,
                    isOn:
                        choiceMembershipBinding(
                            option.value
                        )
                )
                .disabled(
                    choiceIsDisabled(
                        option.value
                    )
                )
            }
        } else {
            Picker(
                valueTitle,
                selection: singleChoiceBinding
            ) {
                ForEach(field.choiceOptions) { option in
                    Text(option.displayName)
                        .tag(option.value)
                }
            }
        }
    }

    private func valueLabel(
        for field:
            GraphChatInterpretationCorrectionFieldOption
    ) -> String {
        guard let unit = field.unit,
              unit.isEmpty == false else {
            return valueTitle
        }
        return "\(valueTitle) (\(unit))"
    }

    private func localizedYear(
        _ year: Int
    ) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .none
        formatter.usesGroupingSeparator = false
        return formatter.string(
            from: NSNumber(value: year)
        ) ?? String(year)
    }

    private func localizedMonth(
        _ month: Int
    ) -> String {
        let index = month - 1
        guard monthSymbols.indices.contains(index) else {
            return String(month)
        }
        return monthSymbols[index]
    }

    private var textBinding: Binding<String> {
        Binding(
            get: {
                if case .text(let value) =
                        filter.value {
                    return value
                }
                return ""
            },
            set: {
                filter.value = .text($0)
            }
        )
    }

    private var integerBinding:
        Binding<String>
    {
        Binding(
            get: {
                if case .integerInput(let value) =
                        filter.value {
                    return value
                }
                return ""
            },
            set: {
                filter.value =
                    .integerInput($0)
            }
        )
    }

    private var integerRangeLowerBinding:
        Binding<String>
    {
        Binding(
            get: {
                if case .integerRangeInput(
                    let lowerBound,
                    _
                ) = filter.value {
                    return lowerBound
                }
                return ""
            },
            set: { value in
                filter.value =
                    .integerRangeInput(
                        lowerBound: value,
                        upperBound:
                            integerRangeUpperBinding
                                .wrappedValue
                    )
            }
        )
    }

    private var integerRangeUpperBinding:
        Binding<String>
    {
        Binding(
            get: {
                if case .integerRangeInput(
                    _,
                    let upperBound
                ) = filter.value {
                    return upperBound
                }
                return ""
            },
            set: { value in
                filter.value =
                    .integerRangeInput(
                        lowerBound:
                            integerRangeLowerBinding
                                .wrappedValue,
                        upperBound: value
                    )
            }
        )
    }

    private var decimalBinding:
        Binding<String>
    {
        Binding(
            get: {
                if case .decimalInput(let value) =
                        filter.value {
                    return value
                }
                return ""
            },
            set: {
                filter.value =
                    .decimalInput($0)
            }
        )
    }

    private var decimalRangeLowerBinding:
        Binding<String>
    {
        Binding(
            get: {
                if case .decimalRangeInput(
                    let lowerBound,
                    _
                ) = filter.value {
                    return lowerBound
                }
                return ""
            },
            set: { value in
                filter.value =
                    .decimalRangeInput(
                        lowerBound: value,
                        upperBound:
                            decimalRangeUpperBinding
                                .wrappedValue
                    )
            }
        )
    }

    private var decimalRangeUpperBinding:
        Binding<String>
    {
        Binding(
            get: {
                if case .decimalRangeInput(
                    _,
                    let upperBound
                ) = filter.value {
                    return upperBound
                }
                return ""
            },
            set: { value in
                filter.value =
                    .decimalRangeInput(
                        lowerBound:
                            decimalRangeLowerBinding
                                .wrappedValue,
                        upperBound: value
                    )
            }
        )
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: {
                if case .date(let value) =
                        filter.value {
                    return value
                }
                return .now
            },
            set: {
                filter.value = .date($0)
            }
        )
    }

    private var dateRangeLowerBinding:
        Binding<Date>
    {
        Binding(
            get: {
                if case .dateRange(
                    let lowerBound,
                    _
                ) = filter.value {
                    return lowerBound
                }
                return .now
            },
            set: { value in
                let upper = max(
                    value,
                    dateRangeUpperBinding
                        .wrappedValue
                )
                filter.value = .dateRange(
                    lowerBound: value,
                    upperBound: upper
                )
            }
        )
    }

    private var dateRangeUpperBinding:
        Binding<Date>
    {
        Binding(
            get: {
                if case .dateRange(
                    _,
                    let upperBound
                ) = filter.value {
                    return upperBound
                }
                return dateRangeLowerBinding
                    .wrappedValue
            },
            set: { value in
                filter.value = .dateRange(
                    lowerBound:
                        dateRangeLowerBinding
                            .wrappedValue,
                    upperBound: value
                )
            }
        )
    }

    private var yearBinding:
        Binding<Int>
    {
        Binding(
            get: {
                if case .year(let year) =
                        filter.value {
                    return year
                }
                return currentYear
            },
            set: {
                filter.value = .year($0)
            }
        )
    }

    private var monthBinding:
        Binding<Int>
    {
        Binding(
            get: {
                if case .month(let value) =
                        filter.value {
                    return value.month
                }
                return currentMonth
            },
            set: { month in
                filter.value = .month(
                    GraphQueryYearMonth(
                        year:
                            monthYearBinding
                                .wrappedValue,
                        month: month
                    )
                )
            }
        )
    }

    private var monthYearBinding:
        Binding<Int>
    {
        Binding(
            get: {
                if case .month(let value) =
                        filter.value {
                    return value.year
                }
                return currentYear
            },
            set: { year in
                filter.value = .month(
                    GraphQueryYearMonth(
                        year: year,
                        month:
                            monthBinding
                                .wrappedValue
                    )
                )
            }
        )
    }

    private var toggleBinding: Binding<Bool> {
        Binding(
            get: {
                if case .toggle(let value) =
                        filter.value {
                    return value
                }
                return true
            },
            set: {
                filter.value = .toggle($0)
            }
        )
    }

    private var singleChoiceBinding:
        Binding<String>
    {
        Binding(
            get: {
                if case .choice(let value) =
                        filter.value {
                    return value
                }
                return field?.choiceOptions
                    .first?.value ?? ""
            },
            set: {
                filter.value = .choice($0)
            }
        )
    }

    private func choiceMembershipBinding(
        _ value: String
    ) -> Binding<Bool> {
        Binding(
            get: {
                if case .choices(let values) =
                        filter.value {
                    return values.contains(value)
                }
                return false
            },
            set: { isSelected in
                var values: [String]
                if case .choices(let current) =
                        filter.value {
                    values = current
                } else {
                    values = []
                }
                if isSelected {
                    guard
                        values.contains(value) == false,
                        values.count
                            < GraphChatSemanticSafety
                                .maximumValuesPerFilter
                    else {
                        return
                    }
                    values.append(value)
                } else {
                    values.removeAll {
                        $0 == value
                    }
                }
                filter.value = .choices(values)
            }
        )
    }

    private func choiceIsDisabled(
        _ value: String
    ) -> Bool {
        guard
            case .choices(let values) =
                filter.value
        else {
            return false
        }
        return values.contains(value) == false
            && values.count
                >= GraphChatSemanticSafety
                    .maximumValuesPerFilter
    }

    private func ensureCompatibleOperationAndValue() {
        guard let field else {
            return
        }
        let selectedOperation =
            field.operators.first {
                $0.operation == filter.operation
            } ?? field.operators.first
        guard let selectedOperation else {
            filter.value = .noValue
            return
        }
        filter.operation =
            selectedOperation.operation
        filter.value =
            filter.value.normalized(
                for:
                    selectedOperation
                        .valueEditor,
                field: field,
                calendar: calendar
            )
    }
}

extension GraphChatInterpretationCorrectionFilter {
    nonisolated func isComplete(
        fields:
            [GraphChatInterpretationCorrectionFieldOption]
    ) -> Bool {
        guard
            let field = fields.first(
                where: {
                    $0.id == fieldID
                }
            ),
            let option = field.operators.first(
                where: {
                    $0.operation == operation
                }
            )
        else {
            return false
        }

        switch (option.valueEditor, value) {
        case (.noValue, .noValue):
            return true
        case (.text, .text(let value)),
            (.integer, .integerInput(let value)),
            (.decimal, .decimalInput(let value)):
            return value
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty == false
        case (
            .integerRange,
            .integerRangeInput(
                let lowerBound,
                let upperBound
            )
        ),
            (
                .decimalRange,
                .decimalRangeInput(
                    let lowerBound,
                    let upperBound
                )
            ):
            return [lowerBound, upperBound]
                .allSatisfy {
                    $0.trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    ).isEmpty == false
                }
        case (.date, .date),
            (.dateRange, .dateRange),
            (.toggle, .toggle):
            return true
        case (.year, .year(let year)):
            return year > 0
        case (.month, .month(let month)):
            return month.year > 0
                && (1...12).contains(
                    month.month
                )
        case (.singleChoice, .choice(let value)):
            return field.choiceOptions.contains {
                $0.value == value
            }
        case (.multipleChoice, .choices(let values)):
            let available =
                Set(
                    field.choiceOptions
                        .map(\.value)
                )
            return values.isEmpty == false
                && values.allSatisfy(
                    available.contains
                )
                && values.count
                    <= GraphChatSemanticSafety
                        .maximumValuesPerFilter
        default:
            return false
        }
    }
}

private extension
    GraphChatInterpretationCorrectionFilterValue
{
    static func defaultValue(
        for editor:
            GraphChatInterpretationCorrectionFilterValueEditor,
        field:
            GraphChatInterpretationCorrectionFieldOption,
        calendar: Calendar
    ) -> Self {
        switch editor {
        case .noValue:
            return .noValue
        case .text:
            return .text("")
        case .integer:
            return .integerInput("")
        case .integerRange:
            return .integerRangeInput(
                lowerBound: "",
                upperBound: ""
            )
        case .decimal:
            return .decimalInput("")
        case .decimalRange:
            return .decimalRangeInput(
                lowerBound: "",
                upperBound: ""
            )
        case .date:
            return .date(.now)
        case .dateRange:
            return .dateRange(
                lowerBound: .now,
                upperBound: .now
            )
        case .year:
            return .year(
                calendar.component(
                    .year,
                    from: .now
                )
            )
        case .month:
            return .month(
                GraphQueryYearMonth(
                    year:
                        calendar.component(
                            .year,
                            from: .now
                        ),
                    month:
                        calendar.component(
                            .month,
                            from: .now
                        )
                )
            )
        case .toggle:
            return .toggle(true)
        case .singleChoice:
            return .choice(
                field.choiceOptions
                    .first?.value ?? ""
            )
        case .multipleChoice:
            return .choices([])
        }
    }

    func normalized(
        for editor:
            GraphChatInterpretationCorrectionFilterValueEditor,
        field:
            GraphChatInterpretationCorrectionFieldOption,
        calendar: Calendar
    ) -> Self {
        switch (editor, self) {
        case (.noValue, .noValue),
            (.text, .text),
            (.integer, .integerInput),
            (.integerRange, .integerRangeInput),
            (.decimal, .decimalInput),
            (.decimalRange, .decimalRangeInput),
            (.date, .date),
            (.dateRange, .dateRange),
            (.year, .year),
            (.month, .month),
            (.toggle, .toggle):
            return self

        case (.singleChoice, .choice(let value)):
            if field.choiceOptions.contains(
                where: {
                    $0.value == value
                }
            ) {
                return self
            }

        case (.multipleChoice, .choices(let values)):
            let available =
                Set(
                    field.choiceOptions
                        .map(\.value)
                )
            var seen = Set<String>()
            let normalized = values.filter {
                available.contains($0)
                    && seen.insert($0).inserted
            }
            return .choices(
                Array(
                    normalized.prefix(
                        GraphChatSemanticSafety
                            .maximumValuesPerFilter
                    )
                )
            )

        default:
            break
        }

        return .defaultValue(
            for: editor,
            field: field,
            calendar: calendar
        )
    }
}
