//
//  NodeDetailCustomizeSheets.swift
//  BrainMesh
//
//  PR 06: Quick "Anpassen…" sheets for Entity/Attribute detail screens.
//

import SwiftUI

struct EntityDetailCustomizeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var display: DisplaySettingsStore

    var body: some View {
        NavigationStack {
            List {
                Section("Header") {
                    Picker("Header-Bild", selection: display.entityDetailBinding(\.heroImageStyle)) {
                        ForEach(EntityDetailHeroImageStyle.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }

                    Toggle("Hero-Pills", isOn: display.entityDetailBinding(\.showHeroPills))

                    Stepper(value: heroPillLimitBinding, in: 0...10) {
                        HStack {
                            Text("Max. Pills")
                            Spacer(minLength: 0)
                            Text("\(display.entityDetail.heroPillLimit)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(!display.entityDetail.showHeroPills)
                }

                Section("Sektionen") {
                    NavigationLink {
                        EntityDetailSectionsEditorView()
                    } label: {
                        Label("Sichtbarkeit & Einklappen", systemImage: "rectangle.3.group")
                    }
                }

                Section {
                    Button {
                        display.resetEntityDetail()
                    } label: {
                        Label("Auf Preset zurücksetzen", systemImage: "arrow.counterclockwise")
                    }
                }
            }
            .navigationTitle("Anpassen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Fertig") {
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                }
            }
        }
    }

    private var heroPillLimitBinding: Binding<Int> {
        Binding(
            get: { display.entityDetail.heroPillLimit },
            set: { newValue in
                display.updateEntityDetail { $0.heroPillLimit = newValue }
            }
        )
    }
}


struct AttributeDetailCustomizeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var display: DisplaySettingsStore

    var body: some View {
        NavigationStack {
            List {
                Section("Details") {
                    Picker("Fokusmodus", selection: display.attributeDetailBinding(\.focusMode)) {
                        ForEach(AttributeDetailFocusMode.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }

                    Picker("Layout", selection: display.attributeDetailBinding(\.detailsLayout)) {
                        ForEach(AttributeDetailDetailsLayout.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }

                    Toggle("Leere Felder ausblenden", isOn: display.attributeDetailBinding(\.hideEmptyDetails))
                }

                Section("Sektionen") {
                    NavigationLink {
                        AttributeDetailSectionsEditorView()
                    } label: {
                        Label("Sichtbarkeit & Einklappen", systemImage: "rectangle.3.group")
                    }
                }

                Section {
                    Button {
                        display.resetAttributeDetail()
                    } label: {
                        Label("Auf Preset zurücksetzen", systemImage: "arrow.counterclockwise")
                    }
                }
            }
            .navigationTitle("Anpassen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Fertig") {
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                }
            }
        }
    }
}
