//
//  DetailsSchemaBuilderView.swift
//  BrainMesh
//
//  Phase 1: Details (frei konfigurierbare Felder)
//

import SwiftUI
import SwiftData

struct DetailsSchemaBuilderView: View {
    @Environment(\.modelContext) private var modelContext

    @Bindable var entity: MetaEntity

    @State private var showAddSheet: Bool = false
    @State private var editField: MetaDetailFieldDefinition? = nil

    @State private var alert: DetailsSchemaAlert? = nil

    var body: some View {
        List {
            if entity.detailFieldsList.isEmpty {
                templatesSection
            }

            Section {
                if entity.detailFieldsList.isEmpty {
                    ContentUnavailableView {
                        Label("Keine Felder", systemImage: "list.bullet.rectangle")
                    } description: {
                        Text("Lege Felder an, damit du pro Attribut strukturierte Details pflegen kannst.")
                    }
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(entity.detailFieldsList) { field in
                        Button {
                            editField = field
                        } label: {
                            DetailsFieldRow(field: field)
                        }
                        .buttonStyle(.plain)
                    }
                    .onMove(perform: moveFields)
                    .onDelete(perform: deleteFields)
                }
            } header: {
                Text("Felder")
            } footer: {
                Text("Tipp: Du kannst bis zu 3 Felder anpinnen. Die erscheinen dann als kleine Pills oben im Attribut.")
            }
        }
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }

            ToolbarItem(placement: .topBarLeading) {
                if !entity.detailFieldsList.isEmpty {
                    EditButton()
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            DetailsAddFieldSheet(entity: entity) { result in
                switch result {
                case .added:
                    break
                case .pinnedLimitReached:
                    alert = .pinnedLimit
                default:
                    break
                }
            }
        }
        .sheet(item: $editField) { field in
            DetailsEditFieldSheet(entity: entity, field: field) { result in
                switch result {
                case .saved:
                    break
                case .pinnedLimitReached:
                    alert = .pinnedLimit
                default:
                    break
                }
            }
        }
        .alert(item: $alert) { alert in
            switch alert {
            case .pinnedLimit:
                return Alert(
                    title: Text("Maximal 3 Pins"),
                    message: Text("Du kannst höchstens drei Felder anpinnen. Entferne zuerst einen Pin bei einem anderen Feld."),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    private var templatesSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text("Vorlagen")
                    .font(.headline)

                Text("Damit du nicht bei Null startest. Du kannst alles danach frei anpassen.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                FlowLayout(spacing: 10, lineSpacing: 10) {
                    ForEach(DetailsTemplate.allCases) { template in
                        Button {
                            applyTemplate(template)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: template.systemImage)
                                    .font(.system(size: 13, weight: .semibold))
                                Text(template.title)
                                    .font(.subheadline.weight(.semibold))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(uiColor: .tertiarySystemGroupedBackground), in: Capsule())
                            .overlay {
                                Capsule().strokeBorder(.quaternary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 4)
        } header: {
            Text("Start")
        } footer: {
            Text("Vorlagen werden nur angeboten, solange noch keine Felder existieren.")
        }
    }

    private func applyTemplate(_ template: DetailsTemplate) {
        guard entity.detailFieldsList.isEmpty else { return }

        let definitions = template.fields
        for (idx, def) in definitions.enumerated() {
            let field = MetaDetailFieldDefinition(
                entity: entity,
                name: def.name,
                type: def.type,
                sortIndex: idx,
                unit: def.unit,
                options: def.options,
                isPinned: def.isPinned
            )
            modelContext.insert(field)
            entity.addDetailField(field)
        }

        // Enforce max 3 pins (templates should already comply, but stay safe)
        enforcePinnedLimitIfNeeded()

        try? modelContext.save()
    }

    private func moveFields(from source: IndexSet, to destination: Int) {
        var working = entity.detailFieldsList
        working.move(fromOffsets: source, toOffset: destination)

        for (idx, field) in working.enumerated() {
            field.sortIndex = idx
        }

        try? modelContext.save()
    }

    private func deleteFields(at offsets: IndexSet) {
        var working = entity.detailFieldsList
        let toDelete = offsets.compactMap { idx in
            working.indices.contains(idx) ? working[idx] : nil
        }

        for field in toDelete {
            deleteAllValues(forFieldID: field.id)
            entity.removeDetailField(field)
            modelContext.delete(field)
        }

        working.remove(atOffsets: offsets)

        // Reindex
        for (idx, field) in working.enumerated() {
            field.sortIndex = idx
        }

        try? modelContext.save()
    }

    private func deleteAllValues(forFieldID fieldID: UUID) {
        let descriptor = FetchDescriptor<MetaDetailFieldValue>(predicate: #Predicate { $0.fieldID == fieldID })
        if let values = try? modelContext.fetch(descriptor) {
            for v in values {
                modelContext.delete(v)
            }
        }
    }

    private func enforcePinnedLimitIfNeeded() {
        let pinned = entity.detailFieldsList.filter { $0.isPinned }.sorted(by: { $0.sortIndex < $1.sortIndex })
        if pinned.count <= 3 { return }

        // Unpin extras (from the end)
        for field in pinned.dropFirst(3) {
            field.isPinned = false
        }
    }
}

// MARK: - Row

private struct DetailsFieldRow: View {
    let field: MetaDetailFieldDefinition

    private var subtitle: String {
        var parts: [String] = [field.type.title]
        if let unit, !unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, field.type.supportsUnit {
            parts.append("Einheit: \(unit)")
        }
        if field.type.supportsOptions {
            let count = field.options.count
            parts.append("\(count) Option\(count == 1 ? "" : "en")")
        }
        return parts.joined(separator: " · ")
    }

    private var unit: String? {
        field.unit
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: field.type.systemImage)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 24)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(field.name.isEmpty ? "Feld" : field.name)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if field.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Add / Edit Sheets

enum DetailsFieldEditResult {
    case added
    case saved
    case pinnedLimitReached
}

private struct DetailsAddFieldSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var entity: MetaEntity

    let onResult: (DetailsFieldEditResult) -> Void

    @State private var name: String = ""
    @State private var type: DetailFieldType = .singleLineText
    @State private var unit: String = ""
    @State private var isPinned: Bool = false
    @State private var optionsText: String = ""

    @State private var error: String? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DetailsQuickPresetsView { preset in
                        name = preset.name
                        type = preset.type
                        unit = preset.unit ?? ""
                        optionsText = preset.options.joined(separator: "\n")
                        isPinned = preset.isPinned
                    }
                } header: {
                    Text("Schnellstart")
                } footer: {
                    Text("Tippe auf eine Idee, um Name & Typ automatisch zu setzen.")
                }

                Section {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)

                    Picker("Typ", selection: $type) {
                        ForEach(DetailFieldType.allCases) { t in
                            Label(t.title, systemImage: t.systemImage)
                                .tag(t)
                        }
                    }

                    if type.supportsUnit {
                        TextField("Einheit (optional)", text: $unit)
                            .textInputAutocapitalization(.never)
                    }

                    if type.supportsOptions {
                        TextEditor(text: $optionsText)
                            .frame(minHeight: 120)
                            .font(.body)
                            .overlay(alignment: .topLeading) {
                                if optionsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text("Optionen – eine pro Zeile")
                                        .foregroundStyle(.tertiary)
                                        .padding(.top, 8)
                                        .padding(.leading, 4)
                                }
                            }
                    }

                    Toggle("Anpinnen (max. 3)", isOn: $isPinned)
                } header: {
                    Text("Feld")
                }

                if let error {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Neues Feld")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Abbrechen") { dismiss() }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Hinzufügen") {
                        addField()
                    }
                    .font(.headline)
                }
            }
        }
    }

    private func addField() {
        error = nil

        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanedName.isEmpty {
            error = "Bitte gib einen Namen an."
            return
        }

        if isPinned {
            let pinnedCount = entity.detailFieldsList.filter { $0.isPinned }.count
            if pinnedCount >= 3 {
                isPinned = false
                onResult(.pinnedLimitReached)
                return
            }
        }

        let sortIndex = (entity.detailFieldsList.map { $0.sortIndex }.max() ?? -1) + 1

        let options = optionsText
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if type == .singleChoice, options.isEmpty {
            error = "Für \"Auswahl\" brauchst du mindestens eine Option."
            return
        }

        let field = MetaDetailFieldDefinition(
            entity: entity,
            name: cleanedName,
            type: type,
            sortIndex: sortIndex,
            unit: unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : unit,
            options: options,
            isPinned: isPinned
        )

        modelContext.insert(field)
        entity.addDetailField(field)

        try? modelContext.save()

        onResult(.added)
        dismiss()
    }
}

private struct DetailsEditFieldSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var entity: MetaEntity
    @Bindable var field: MetaDetailFieldDefinition

    let onResult: (DetailsFieldEditResult) -> Void

    @State private var name: String = ""
    @State private var type: DetailFieldType = .singleLineText
    @State private var unit: String = ""
    @State private var isPinned: Bool = false
    @State private var optionsText: String = ""

    @State private var error: String? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)

                    Picker("Typ", selection: $type) {
                        ForEach(DetailFieldType.allCases) { t in
                            Label(t.title, systemImage: t.systemImage)
                                .tag(t)
                        }
                    }

                    if type.supportsUnit {
                        TextField("Einheit (optional)", text: $unit)
                            .textInputAutocapitalization(.never)
                    }

                    if type.supportsOptions {
                        TextEditor(text: $optionsText)
                            .frame(minHeight: 120)
                            .font(.body)
                            .overlay(alignment: .topLeading) {
                                if optionsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text("Optionen – eine pro Zeile")
                                        .foregroundStyle(.tertiary)
                                        .padding(.top, 8)
                                        .padding(.leading, 4)
                                }
                            }
                    }

                    Toggle("Anpinnen (max. 3)", isOn: $isPinned)
                } header: {
                    Text("Feld")
                }

                if let error {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        deleteField()
                    } label: {
                        Label("Feld löschen", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Feld bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Schließen") { dismiss() }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sichern") {
                        saveChanges()
                    }
                    .font(.headline)
                }
            }
            .onAppear {
                name = field.name
                type = field.type
                unit = field.unit ?? ""
                isPinned = field.isPinned
                optionsText = field.options.joined(separator: "\n")
            }
        }
    }

    private func saveChanges() {
        error = nil

        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanedName.isEmpty {
            error = "Bitte gib einen Namen an."
            return
        }

        if isPinned && !field.isPinned {
            let pinnedCount = entity.detailFieldsList.filter { $0.isPinned }.count
            if pinnedCount >= 3 {
                isPinned = false
                onResult(.pinnedLimitReached)
                return
            }
        }

        let options = optionsText
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if type == .singleChoice, options.isEmpty {
            error = "Für \"Auswahl\" brauchst du mindestens eine Option."
            return
        }

        field.name = cleanedName
        field.type = type
        field.unit = (type.supportsUnit && !unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ? unit : nil
        field.isPinned = isPinned

        if type.supportsOptions {
            field.setOptions(options)
        } else {
            field.optionsJSON = nil
        }

        try? modelContext.save()
        onResult(.saved)
        dismiss()
    }

    private func deleteField() {
        deleteAllValues(forFieldID: field.id)
        entity.removeDetailField(field)
        modelContext.delete(field)

        // Reindex remaining
        let remaining = entity.detailFieldsList
            .filter { $0.id != field.id }
            .sorted(by: { $0.sortIndex < $1.sortIndex })
        for (idx, f) in remaining.enumerated() {
            f.sortIndex = idx
        }

        try? modelContext.save()
        dismiss()
    }

    private func deleteAllValues(forFieldID fieldID: UUID) {
        let descriptor = FetchDescriptor<MetaDetailFieldValue>(predicate: #Predicate { $0.fieldID == fieldID })
        if let values = try? modelContext.fetch(descriptor) {
            for v in values {
                modelContext.delete(v)
            }
        }
    }
}

// MARK: - Presets

private struct DetailsQuickPresetsView: View {
    struct Preset: Identifiable {
        let id: String
        let systemImage: String
        let name: String
        let type: DetailFieldType
        let unit: String?
        let options: [String]
        let isPinned: Bool

        init(systemImage: String, name: String, type: DetailFieldType, unit: String? = nil, options: [String] = [], isPinned: Bool = false) {
            self.id = systemImage + "|" + name
            self.systemImage = systemImage
            self.name = name
            self.type = type
            self.unit = unit
            self.options = options
            self.isPinned = isPinned
        }
    }

    let onPick: (Preset) -> Void

    private let presets: [Preset] = [
        Preset(systemImage: "book", name: "Seitenzahl", type: .numberInt, unit: "S.", isPinned: true),
        Preset(systemImage: "calendar", name: "Lesedatum", type: .date, isPinned: true),
        Preset(systemImage: "checkmark.circle", name: "Status", type: .singleChoice, options: ["Geplant", "Am Lesen", "Fertig"], isPinned: true),
        Preset(systemImage: "star", name: "Bewertung", type: .numberInt),
        Preset(systemImage: "birthday.cake", name: "Geburtstag", type: .date),
        Preset(systemImage: "ruler", name: "Größe", type: .numberInt, unit: "cm"),
        Preset(systemImage: "person.2", name: "Familienstand", type: .singleChoice, options: ["Single", "Verheiratet", "Verlobt", "Geschieden", "Verwitwet"])
    ]

    var body: some View {
        FlowLayout(spacing: 10, lineSpacing: 10) {
            ForEach(presets) { preset in
                Button {
                    onPick(preset)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: preset.systemImage)
                            .font(.system(size: 13, weight: .semibold))
                        Text(preset.name)
                            .font(.subheadline)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(uiColor: .tertiarySystemGroupedBackground), in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(.quaternary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum DetailsSchemaAlert: String, Identifiable {
    case pinnedLimit

    var id: String { rawValue }
}

private enum DetailsTemplate: String, CaseIterable, Identifiable {
    case people
    case books
    case projects

    var id: String { rawValue }

    var title: String {
        switch self {
        case .people: return "People"
        case .books: return "Books"
        case .projects: return "Projects"
        }
    }

    var systemImage: String {
        switch self {
        case .people: return "person.2"
        case .books: return "book"
        case .projects: return "folder"
        }
    }

    struct FieldDef {
        let name: String
        let type: DetailFieldType
        let unit: String?
        let options: [String]
        let isPinned: Bool

        init(name: String, type: DetailFieldType, unit: String? = nil, options: [String] = [], isPinned: Bool = false) {
            self.name = name
            self.type = type
            self.unit = unit
            self.options = options
            self.isPinned = isPinned
        }
    }

    var fields: [FieldDef] {
        switch self {
        case .people:
            return [
                FieldDef(name: "Geburtstag", type: .date, isPinned: true),
                FieldDef(name: "Größe", type: .numberInt, unit: "cm"),
                FieldDef(name: "Familienstand", type: .singleChoice, options: ["Single", "Verheiratet", "Verlobt", "Geschieden", "Verwitwet"], isPinned: true),
                FieldDef(name: "Ort", type: .singleLineText)
            ]

        case .books:
            return [
                FieldDef(name: "Seitenzahl", type: .numberInt, unit: "S.", isPinned: true),
                FieldDef(name: "Status", type: .singleChoice, options: ["Geplant", "Am Lesen", "Fertig"], isPinned: true),
                FieldDef(name: "Startdatum", type: .date),
                FieldDef(name: "Enddatum", type: .date, isPinned: true),
                FieldDef(name: "Bewertung", type: .numberInt)
            ]

        case .projects:
            return [
                FieldDef(name: "Status", type: .singleChoice, options: ["Offen", "In Arbeit", "Fertig"], isPinned: true),
                FieldDef(name: "Startdatum", type: .date),
                FieldDef(name: "Deadline", type: .date, isPinned: true),
                FieldDef(name: "Priorität", type: .singleChoice, options: ["Niedrig", "Mittel", "Hoch"])
            ]
        }
    }
}
