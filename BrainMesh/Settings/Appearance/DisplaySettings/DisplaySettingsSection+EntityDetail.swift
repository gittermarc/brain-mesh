//
//  DisplaySettingsSection+EntityDetail.swift
//  BrainMesh
//
//  PR 03: Split DisplaySettingsView into section files.
//

import SwiftUI

struct DisplaySettingsEntityDetailSection: View {
    @EnvironmentObject private var display: DisplaySettingsStore

    var body: some View {
        Section {
            Picker("Header-Bild", selection: display.entityDetailBinding(\.heroImageStyle)) {
                ForEach(EntityDetailHeroImageStyle.allCases) { item in
                    Text(item.title).tag(item)
                }
            }

            Toggle("Hero-Pills anzeigen", isOn: display.entityDetailBinding(\.showHeroPills))

            Stepper(value: heroPillLimitBinding, in: 0...10) {
                HStack {
                    Text("Max. Pills")
                    Spacer(minLength: 0)
                    Text("\(display.entityDetail.heroPillLimit)")
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!display.entityDetail.showHeroPills)

            NavigationLink {
                EntityDetailSectionsEditorView()
            } label: {
                HStack {
                    Text("Sektionen")
                    Spacer(minLength: 0)
                    Text(entityDetailSectionsSummary)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                display.resetEntityDetail()
            } label: {
                Text("Entity-Detail auf Preset zurücksetzen")
            }
        } header: {
            DisplaySettingsSectionHeader(title: "Entity-Detail", isCustomized: display.state.entityDetailOverride != nil)
        } footer: {
            Text("Hier stellst du ein, wie Entity-Detailseiten grundsätzlich aufgebaut sind (Header + Sektionen).")
        }
    }

    private var entityDetailSectionsSummary: String {
        let hidden = display.entityDetail.hiddenSections.count
        let collapsed = display.entityDetail.collapsedSections.count
        if hidden == 0 && collapsed == 0 { return "Standard" }
        if hidden == 0 { return "\(collapsed) eingeklappt" }
        if collapsed == 0 { return "\(hidden) verborgen" }
        return "\(hidden) verborgen, \(collapsed) eingeklappt"
    }

    private var heroPillLimitBinding: Binding<Int> {
        Binding(
            get: { display.entityDetail.heroPillLimit },
            set: { newValue in
                display.updateEntityDetail { settings in
                    settings.heroPillLimit = max(0, min(10, newValue))
                }
            }
        )
    }
}

struct DisplaySettingsAttributeDetailSection: View {
    @EnvironmentObject private var display: DisplaySettingsStore

    var body: some View {
        Section {
            Picker("Fokusmodus", selection: display.attributeDetailBinding(\.focusMode)) {
                ForEach(AttributeDetailFocusMode.allCases) { item in
                    Text(item.title).tag(item)
                }
            }

            Picker("Details-Layout", selection: display.attributeDetailBinding(\.detailsLayout)) {
                ForEach(AttributeDetailDetailsLayout.allCases) { item in
                    Text(item.title).tag(item)
                }
            }

            Toggle("Leere Felder ausblenden", isOn: display.attributeDetailBinding(\.hideEmptyDetails))

            NavigationLink {
                AttributeDetailSectionsEditorView()
            } label: {
                HStack {
                    Text("Sektionen")
                    Spacer(minLength: 0)
                    Text(attributeDetailSectionsSummary)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                display.resetAttributeDetail()
            } label: {
                Text("Attribute-Detail auf Preset zurücksetzen")
            }
        } header: {
            DisplaySettingsSectionHeader(title: "Attribute-Detail", isCustomized: display.state.attributeDetailOverride != nil)
        } footer: {
            Text("Diese Optionen betreffen die Detailansicht eines Attributs (Fokus + Layout + Sektionen).")
        }
    }

    private var attributeDetailSectionsSummary: String {
        let hidden = display.attributeDetail.hiddenSections.count
        let collapsed = display.attributeDetail.collapsedSections.count
        if hidden == 0 && collapsed == 0 { return "Standard" }
        if hidden == 0 { return "\(collapsed) eingeklappt" }
        if collapsed == 0 { return "\(hidden) verborgen" }
        return "\(hidden) verborgen, \(collapsed) eingeklappt"
    }
}

struct DisplaySettingsAttributesAllListSection: View {
    @EnvironmentObject private var display: DisplaySettingsStore

    var body: some View {
        Section {
            Picker("Dichte", selection: display.attributesAllListBinding(\.rowDensity)) {
                ForEach(AttributesAllRowDensity.allCases) { item in
                    Text(item.title).tag(item)
                }
            }

            Picker("Icons", selection: display.attributesAllListBinding(\.iconPolicy)) {
                ForEach(AttributesAllIconPolicy.allCases) { item in
                    Text(item.title).tag(item)
                }
            }

            Picker("Notiz-Preview", selection: display.attributesAllListBinding(\.notesPreviewLines)) {
                Text("Aus").tag(0)
                Text("1 Zeile").tag(1)
                Text("2 Zeilen").tag(2)
            }

            Toggle("Pinned Details anzeigen", isOn: display.attributesAllListBinding(\.showPinnedDetails))

            if display.attributesAllList.showPinnedDetails {
                Picker("Pinned-Details", selection: display.attributesAllListBinding(\.pinnedDetailsStyle)) {
                    ForEach(AttributesAllPinnedDetailsStyle.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
            }

            Picker("Gruppierung", selection: display.attributesAllListBinding(\.grouping)) {
                ForEach(AttributesAllGrouping.allCases) { item in
                    Text(item.title).tag(item)
                }
            }

            Toggle("Sticky Header", isOn: display.attributesAllListBinding(\.stickyHeadersEnabled))

            Button {
                display.resetAttributesAllList()
            } label: {
                Text("Alle Attribute auf Preset zurücksetzen")
            }
        } header: {
            DisplaySettingsSectionHeader(title: "Alle Attribute", isCustomized: display.state.attributesAllListOverride != nil)
        } footer: {
            Text("Diese Einstellungen gelten für die \"Alle Attribute\"-Liste innerhalb einer Entity.")
        }
    }
}
