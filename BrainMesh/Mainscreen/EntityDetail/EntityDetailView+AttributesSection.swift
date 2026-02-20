//
//  EntityDetailView+AttributesSection.swift
//  BrainMesh
//
//  P0.3 Split: Attributes card + appearance card + attributes all view
//

import Foundation
import SwiftUI
import SwiftData

struct NodeEntityAttributesCard: View {
    let entity: MetaEntity

    private var preview: [MetaAttribute] {
        Array(entity.attributesList.sorted(by: { $0.nameFolded < $1.nameFolded }).prefix(12))
    }

    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 110), spacing: 8)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NodeCardHeader(title: "Attribute", systemImage: "tag")

            if entity.attributesList.isEmpty {
                NodeEmptyStateRow(
                    text: "Noch keine Attribute.",
                    ctaTitle: "Attribute ansehen",
                    ctaSystemImage: "tag",
                    ctaAction: {}
                )
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(preview) { attr in
                        NavigationLink {
                            AttributeDetailView(attribute: attr)
                        } label: {
                            Label(attr.name.isEmpty ? "Attribut" : attr.name, systemImage: attr.iconSymbolName ?? "tag")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(uiColor: .tertiarySystemGroupedBackground), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }

                NavigationLink {
                    EntityAttributesAllView(entity: entity)
                } label: {
                    Label("Alle", systemImage: "chevron.right")
                        .font(.callout.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.secondary.opacity(0.12))
        )
    }
}


struct EntityAttributesAllView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var display: DisplaySettingsStore

    @Bindable var entity: MetaEntity

    @State private var searchText: String = ""

    @AppStorage(BMAppStorageKeys.entityAttributesAllSort) private var sortSelectionRaw: String = EntityAttributesAllSortSelection.default.rawValue

    @StateObject private var listModel: EntityAttributesAllListModel = EntityAttributesAllListModel()

    private var sortSelection: EntityAttributesAllSortSelection {
        EntityAttributesAllSortSelection(rawValue: sortSelectionRaw)
    }

    var body: some View {
        let visible = listModel.visibleRows
        let settings = display.attributesAllList
        let showPinnedDetails = settings.showPinnedDetails

        List {
            if showPinnedDetails {
                Section {
                    EntityAttributesAllSortChipsBar(
                        selection: sortSelection,
                        pinnedFields: listModel.pinnedSortableFields
                    ) { newSelection in
                        sortSelectionRaw = newSelection.rawValue
                    }
                    .padding(.vertical, 4)
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    .listRowBackground(Color.clear)
                }
            }

            if !searchText.isEmpty || !sortSelection.isDefault {
                Section {
                    if !searchText.isEmpty {
                        Text("Suche: \(searchText)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if !sortSelection.isDefault {
                        Text("Sortierung: \(sortTitle(for: sortSelection))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            attributesListBody(visible: visible, settings: settings)
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Attribut suchen…")
        .navigationTitle("Attribute")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Section("Anzeige") {
                        Toggle(isOn: display.attributesAllListBinding(\.showPinnedDetails)) {
                            Label("Pinned Details anzeigen", systemImage: "pin")
                        }

                        Picker("Notiz-Preview", selection: display.attributesAllListBinding(\.notesPreviewLines)) {
                            Text("Aus").tag(0)
                            Text("1 Zeile").tag(1)
                            Text("2 Zeilen").tag(2)
                        }
                    }

                    Section("Sortieren") {
                        Picker("Sortieren", selection: baseSortBinding) {
                            ForEach(EntityAttributeSortMode.allCases) { mode in
                                Label(mode.title, systemImage: mode.systemImage)
                                    .tag(mode)
                            }
                        }

                        if !listModel.pinnedSortMenuOptions.isEmpty {
                            Divider()
                            Text("Gepinnte Felder")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(listModel.pinnedSortMenuOptions) { option in
                                Button {
                                    sortSelectionRaw = option.selection.rawValue
                                } label: {
                                    Label(option.title, systemImage: option.systemImage)
                                }
                            }
                        }
                    }

                    if !searchText.isEmpty {
                        Divider()
                        Button(role: .destructive) {
                            searchText = ""
                        } label: {
                            Label("Suche zurücksetzen", systemImage: "xmark.circle")
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Sortieren")
            }
        }
        .onAppear {
            rebuild(debounce: false)
        }
        .onChange(of: searchText) { _, _ in
            rebuild(debounce: true)
        }
        .onChange(of: sortSelectionRaw) { _, _ in
            rebuild(debounce: false)
        }
        .onChange(of: settings) { _, _ in
            rebuild(debounce: false)
        }
    }

    private var baseSortBinding: Binding<EntityAttributeSortMode> {
        Binding(
            get: { sortSelection.baseModeOrDefault },
            set: { sortSelectionRaw = EntityAttributesAllSortSelection.base($0).rawValue }
        )
    }

    private func rebuild(debounce: Bool) {
        let settings = display.attributesAllList
        listModel.scheduleRebuild(
            context: modelContext,
            entity: entity,
            searchText: searchText,
            showPinnedDetails: settings.showPinnedDetails,
            includeNotesPreview: settings.notesPreviewLines > 0,
            sortSelection: sortSelection,
            grouping: settings.grouping,
            debounce: debounce
        )
    }

    private func sortTitle(for selection: EntityAttributesAllSortSelection) -> String {
        switch selection {
        case .base(let mode):
            return mode.title
        case .pinned(let fieldID, let direction):
            if let field = listModel.pinnedSortableFields.first(where: { $0.id == fieldID })
                ?? listModel.pinnedFields.first(where: { $0.id == fieldID }) {
                let name = field.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Feld" : field.name
                switch field.type {
                case .toggle:
                    return "\(name) (\(direction == .descending ? "Ja zuerst" : "Nein zuerst"))"
                case .singleChoice:
                    return "\(name) (\(direction == .descending ? "umgekehrt" : "Optionen"))"
                case .numberInt, .numberDouble, .date:
                    return "\(name) (\(direction == .descending ? "absteigend" : "aufsteigend"))"
                case .singleLineText, .multiLineText:
                    return name
                }
            }
            return "Gepinntes Feld"
        }
    }

    private func deleteAttributes(at offsets: IndexSet, rows: [EntityAttributesAllListModel.Row]) {
        for index in offsets {
            guard rows.indices.contains(index) else { continue }
            let attr = rows[index].attribute

            AttachmentCleanup.deleteAttachments(ownerKind: .attribute, ownerID: attr.id, in: modelContext)
            LinkCleanup.deleteLinks(referencing: .attribute, id: attr.id, graphID: entity.graphID, in: modelContext)

            entity.removeAttribute(attr)
            modelContext.delete(attr)
        }
        try? modelContext.save()
        rebuild(debounce: false)
    }
}

private extension EntityAttributesAllView {

    struct AttributeGroup: Identifiable {
        let id: String
        let title: String
        let systemImage: String?
        let rows: [EntityAttributesAllListModel.Row]
    }

    func attributesListBody(
        visible: [EntityAttributesAllListModel.Row],
        settings: AttributesAllListDisplaySettings
    ) -> some View {
        let groups = makeGroups(rows: visible, settings: settings)

        return Group {
            if groups.count == 1, groups.first?.title == "Alle Attribute" {
                // No grouping or a single synthetic group.
                let rows = groups.first?.rows ?? []
                if settings.stickyHeadersEnabled {
                    Section(header: Text("Alle Attribute")) {
                        rowsForEach(rows: rows, settings: settings)
                    }
                } else {
                    inlineHeaderRow(title: "Alle Attribute")
                    rowsForEach(rows: rows, settings: settings)
                }
            } else {
                ForEach(groups) { group in
                    if settings.stickyHeadersEnabled {
                        Section {
                            rowsForEach(rows: group.rows, settings: settings)
                        } header: {
                            groupHeader(title: group.title, systemImage: group.systemImage)
                        }
                    } else {
                        inlineHeaderRow(title: group.title, systemImage: group.systemImage)
                        rowsForEach(rows: group.rows, settings: settings)
                    }
                }
            }
        }
    }

    @ViewBuilder
    func rowsForEach(
        rows: [EntityAttributesAllListModel.Row],
        settings: AttributesAllListDisplaySettings
    ) -> some View {
        ForEach(rows) { row in
            attributeRow(row, settings: settings)
        }
        .onDelete { offsets in
            deleteAttributes(at: offsets, rows: rows)
        }
    }

    @ViewBuilder
    func attributeRow(
        _ row: EntityAttributesAllListModel.Row,
        settings: AttributesAllListDisplaySettings
    ) -> some View {
        NavigationLink {
            AttributeDetailView(attribute: row.attribute)
        } label: {
            HStack(spacing: 12) {
                if shouldShowIcon(row: row, settings: settings) {
                    attributeIconView(row: row)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)

                    if settings.notesPreviewLines > 0, let note = row.notePreview {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(settings.notesPreviewLines)
                    }

                    if settings.showPinnedDetails, !row.pinnedChips.isEmpty {
                        pinnedDetailsView(row: row, style: settings.pinnedDetailsStyle)
                            .padding(.top, 4)
                    }
                }
            }
            .padding(.vertical, rowVerticalPadding(settings.rowDensity))
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
    }

    func shouldShowIcon(row: EntityAttributesAllListModel.Row, settings: AttributesAllListDisplaySettings) -> Bool {
        switch settings.iconPolicy {
        case .always:
            return true
        case .onlyIfSet:
            return row.isIconSet
        case .never:
            return false
        }
    }

    func attributeIconView(row: EntityAttributesAllListModel.Row) -> some View {
        Image(systemName: row.iconSymbolName)
            .font(.system(size: 16, weight: .semibold))
            .frame(width: 22)
            .foregroundStyle(.tint)
    }

    func rowVerticalPadding(_ density: AttributesAllRowDensity) -> CGFloat {
        switch density {
        case .compact: return 6
        case .standard: return 10
        case .comfortable: return 14
        }
    }

    @ViewBuilder
    func pinnedDetailsView(
        row: EntityAttributesAllListModel.Row,
        style: AttributesAllPinnedDetailsStyle
    ) -> some View {
        switch style {
        case .chips:
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(row.pinnedChips) { chip in
                    EntityAttributesAllPinnedChipView(title: chip.title, systemImage: chip.systemImage)
                }
            }

        case .inline:
            Text(row.pinnedChips.map { $0.title }.joined(separator: " · "))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)

        case .twoColumns:
            let cols: [GridItem] = [
                GridItem(.flexible(minimum: 80), spacing: 8),
                GridItem(.flexible(minimum: 80), spacing: 8)
            ]
            LazyVGrid(columns: cols, alignment: .leading, spacing: 6) {
                ForEach(row.pinnedChips) { chip in
                    Label(chip.title, systemImage: chip.systemImage)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    func makeGroups(
        rows: [EntityAttributesAllListModel.Row],
        settings: AttributesAllListDisplaySettings
    ) -> [AttributeGroup] {
        switch settings.grouping {
        case .none:
            return [AttributeGroup(id: "all", title: "Alle Attribute", systemImage: nil, rows: rows)]

        case .az:
            var buckets: [String: [EntityAttributesAllListModel.Row]] = [:]
            var order: [String] = []
            for row in rows {
                let trimmed = row.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let first = trimmed.first.map { String($0).uppercased() } ?? "#"
                let key = first.range(of: "[A-ZÄÖÜ]", options: .regularExpression) != nil ? first : "#"
                if buckets[key] == nil { order.append(key) }
                buckets[key, default: []].append(row)
            }
            let sortedOrder = order.sorted { lhs, rhs in
                if lhs == "#" { return false }
                if rhs == "#" { return true }
                return lhs < rhs
            }
            return sortedOrder.map { key in
                AttributeGroup(id: "az:\(key)", title: key, systemImage: nil, rows: buckets[key] ?? [])
            }

        case .byIcon:
            var buckets: [String: [EntityAttributesAllListModel.Row]] = [:]
            var order: [String] = []
            for row in rows {
                let key = row.isIconSet ? row.iconSymbolName : "(none)"
                if buckets[key] == nil { order.append(key) }
                buckets[key, default: []].append(row)
            }
            return order.map { key in
                if key == "(none)" {
                    return AttributeGroup(id: "icon:none", title: "Ohne Icon", systemImage: "tag", rows: buckets[key] ?? [])
                }
                return AttributeGroup(id: "icon:\(key)", title: key, systemImage: key, rows: buckets[key] ?? [])
            }

        case .hasDetails:
            let withDetails = rows.filter { $0.hasDetails }
            let withoutDetails = rows.filter { !$0.hasDetails }
            var out: [AttributeGroup] = []
            if !withDetails.isEmpty {
                out.append(AttributeGroup(id: "details:yes", title: "Hat Details", systemImage: "square.text.square", rows: withDetails))
            }
            if !withoutDetails.isEmpty {
                out.append(AttributeGroup(id: "details:no", title: "Ohne Details", systemImage: "square", rows: withoutDetails))
            }
            return out

        case .hasMedia:
            let withMedia = rows.filter { $0.hasMedia }
            let withoutMedia = rows.filter { !$0.hasMedia }
            var out: [AttributeGroup] = []
            if !withMedia.isEmpty {
                out.append(AttributeGroup(id: "media:yes", title: "Hat Medien", systemImage: "photo.on.rectangle", rows: withMedia))
            }
            if !withoutMedia.isEmpty {
                out.append(AttributeGroup(id: "media:no", title: "Ohne Medien", systemImage: "rectangle", rows: withoutMedia))
            }
            return out
        }
    }

    @ViewBuilder
    func groupHeader(title: String, systemImage: String?) -> some View {
        if let systemImage {
            Label(title, systemImage: systemImage)
        } else {
            Text(title)
        }
    }

    @ViewBuilder
    func inlineHeaderRow(title: String, systemImage: String? = nil) -> some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 10)
        .padding(.bottom, 6)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .listRowBackground(Color.clear)
        .accessibilityAddTraits(.isHeader)
    }
}

private struct EntityAttributesAllPinnedChipView: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(uiColor: .tertiarySystemGroupedBackground), in: Capsule())
            .foregroundStyle(.secondary)
    }
}

private struct EntityAttributesAllSortChipsBar: View {
    let selection: EntityAttributesAllSortSelection
    let pinnedFields: [MetaDetailFieldDefinition]
    let onSelect: (EntityAttributesAllSortSelection) -> Void

    var body: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            sortChip(
                title: "Name",
                systemImage: "textformat.abc",
                isSelected: isNameSelected,
                accessory: nameAccessory
            ) {
                if case .base(let mode) = selection {
                    if mode == .nameAZ {
                        onSelect(.base(.nameZA))
                    } else {
                        onSelect(.base(.nameAZ))
                    }
                } else {
                    onSelect(.base(.nameAZ))
                }
            }

            sortChip(
                title: "Notizen",
                systemImage: "note.text",
                isSelected: isNotesSelected,
                accessory: nil
            ) {
                onSelect(.base(.notesFirst))
            }

            sortChip(
                title: "Fotos",
                systemImage: "photo",
                isSelected: isPhotosSelected,
                accessory: nil
            ) {
                onSelect(.base(.photosFirst))
            }

            ForEach(pinnedFields) { field in
                let chipTitle = field.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Feld" : field.name
                let sys = DetailsFormatting.systemImage(for: field)

                sortChip(
                    title: chipTitle,
                    systemImage: sys,
                    isSelected: isPinnedSelected(field.id),
                    accessory: pinnedAccessory(field.id)
                ) {
                    handlePinnedTap(field)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var isNameSelected: Bool {
        if case .base(let mode) = selection {
            return mode == .nameAZ || mode == .nameZA
        }
        return false
    }

    private var nameAccessory: String? {
        if case .base(let mode) = selection {
            return mode == .nameZA ? "arrow.down" : "arrow.up"
        }
        return nil
    }

    private var isNotesSelected: Bool {
        if case .base(let mode) = selection {
            return mode == .notesFirst
        }
        return false
    }

    private var isPhotosSelected: Bool {
        if case .base(let mode) = selection {
            return mode == .photosFirst
        }
        return false
    }

    private func isPinnedSelected(_ fieldID: UUID) -> Bool {
        if case .pinned(let id, _) = selection {
            return id == fieldID
        }
        return false
    }

    private func pinnedAccessory(_ fieldID: UUID) -> String? {
        if case .pinned(let id, let dir) = selection, id == fieldID {
            return dir == .descending ? "arrow.down" : "arrow.up"
        }
        return nil
    }

    private func handlePinnedTap(_ field: MetaDetailFieldDefinition) {
        if case .pinned(let id, var dir) = selection, id == field.id {
            dir.toggle()
            onSelect(.pinned(fieldID: field.id, direction: dir))
        } else {
            // Sensible default per type.
            switch field.type {
            case .toggle:
                onSelect(.pinned(fieldID: field.id, direction: .descending))
            default:
                onSelect(.pinned(fieldID: field.id, direction: .ascending))
            }
        }
    }

    @ViewBuilder
    private func sortChip(
        title: String,
        systemImage: String,
        isSelected: Bool,
        accessory: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)

                Text(title)
                    .lineLimit(1)

                if let accessory {
                    Image(systemName: accessory)
                        .imageScale(.small)
                }
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Color(uiColor: isSelected ? .secondarySystemGroupedBackground : .tertiarySystemGroupedBackground),
                in: Capsule()
            )
            .overlay(
                Capsule().stroke(Color.secondary.opacity(isSelected ? 0.28 : 0.12))
            )
        }
        .buttonStyle(.plain)
    }
}


