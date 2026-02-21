//
//  DisplaySettingsView+Editors.swift
//  BrainMesh
//
//  PR 03: Editor helpers for DisplaySettingsView.
//

import SwiftUI

struct DisplaySettingsSectionHeader: View {
    let title: String
    let isCustomized: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer(minLength: 0)
            Text(isCustomized ? "ANGEPASST" : "PRESET")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

struct EntityDetailSectionsEditorView: View {
    @EnvironmentObject private var display: DisplaySettingsStore

    var body: some View {
        List {
            Section {
                ForEach(EntityDetailSection.allCases) { section in
                    SectionVisibilityRow(
                        title: section.title,
                        isHidden: Binding(
                            get: { display.entityDetail.hiddenSections.contains(section) },
                            set: { newValue in
                                display.updateEntityDetail { settings in
                                    settings.hiddenSections = settings.hiddenSections.toggled(section, enabled: newValue)
                                    if newValue {
                                        settings.collapsedSections.removeAll { $0 == section }
                                    }
                                }
                            }
                        ),
                        isCollapsed: Binding(
                            get: { display.entityDetail.collapsedSections.contains(section) },
                            set: { newValue in
                                display.updateEntityDetail { settings in
                                    settings.collapsedSections = settings.collapsedSections.toggled(section, enabled: newValue)
                                    if newValue {
                                        settings.hiddenSections.removeAll { $0 == section }
                                    }
                                }
                            }
                        )
                    )
                }
            } footer: {
                Text("Verborgene Sektionen werden gar nicht angezeigt. Eingeklappte Sektionen starten kompakt, können aber geöffnet werden.")
            }
        }
        .navigationTitle("Entity-Sektionen")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AttributeDetailSectionsEditorView: View {
    @EnvironmentObject private var display: DisplaySettingsStore

    var body: some View {
        List {
            Section {
                ForEach(AttributeDetailSection.allCases) { section in
                    SectionVisibilityRow(
                        title: section.title,
                        isHidden: Binding(
                            get: { display.attributeDetail.hiddenSections.contains(section) },
                            set: { newValue in
                                display.updateAttributeDetail { settings in
                                    settings.hiddenSections = settings.hiddenSections.toggled(section, enabled: newValue)
                                    if newValue {
                                        settings.collapsedSections.removeAll { $0 == section }
                                    }
                                }
                            }
                        ),
                        isCollapsed: Binding(
                            get: { display.attributeDetail.collapsedSections.contains(section) },
                            set: { newValue in
                                display.updateAttributeDetail { settings in
                                    settings.collapsedSections = settings.collapsedSections.toggled(section, enabled: newValue)
                                    if newValue {
                                        settings.hiddenSections.removeAll { $0 == section }
                                    }
                                }
                            }
                        )
                    )
                }
            } footer: {
                Text("Verborgene Sektionen werden gar nicht angezeigt. Eingeklappte Sektionen starten kompakt, können aber geöffnet werden.")
            }
        }
        .navigationTitle("Attribut-Sektionen")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SectionVisibilityRow: View {
    let title: String
    let isHidden: Binding<Bool>
    let isCollapsed: Binding<Bool>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.body.weight(.semibold))

            HStack {
                Toggle("Ausblenden", isOn: isHidden)
                Spacer(minLength: 12)
                Toggle("Einklappen", isOn: isCollapsed)
                    .disabled(isHidden.wrappedValue)
            }
            .font(.subheadline)
        }
        .padding(.vertical, 4)
    }
}

private extension Array where Element: Equatable {
    func toggled(_ element: Element, enabled: Bool) -> [Element] {
        var copy = self
        if enabled {
            if !copy.contains(element) {
                copy.append(element)
            }
        } else {
            copy.removeAll { $0 == element }
        }
        return copy
    }
}
