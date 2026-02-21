//
//  DisplaySettingsSection+GraphCanvas.swift
//  BrainMesh
//
//  PR 03: Split DisplaySettingsView into section files.
//

import SwiftUI

struct DisplaySettingsGraphSection: View {
    @EnvironmentObject private var appearance: AppearanceStore

    var body: some View {
        Section("Graph") {
            Picker("Hintergrund", selection: backgroundStyleBinding) {
                ForEach(GraphBackgroundStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }

            if appearance.settings.graph.backgroundStyle.needsPrimaryColor {
                ColorPicker("Hintergrund (Primär)", selection: backgroundPrimaryBinding)
            }
            if appearance.settings.graph.backgroundStyle.needsSecondaryColor {
                ColorPicker("Hintergrund (Sekundär)", selection: backgroundSecondaryBinding)
            }

            SettingsInlineHeaderRow(title: "Knotenfarben")
            ColorPicker("Entitäten", selection: entityColorBinding)
            ColorPicker("Attribute", selection: attributeColorBinding)

            SettingsInlineHeaderRow(title: "Kantenfarben")
            ColorPicker("Links", selection: linkColorBinding)
            ColorPicker("Containment", selection: containmentColorBinding)

            SettingsInlineHeaderRow(title: "Interaktion")
            ColorPicker("Highlight / Auswahl", selection: highlightColorBinding)
            Toggle("Label-Halo", isOn: labelHaloBinding)
        }
    }

    // MARK: - Bindings

    private var backgroundStyleBinding: Binding<GraphBackgroundStyle> {
        Binding(
            get: { appearance.settings.graph.backgroundStyle },
            set: { appearance.setGraphBackgroundStyle($0) }
        )
    }

    private var backgroundPrimaryBinding: Binding<Color> {
        Binding(
            get: { appearance.settings.graph.backgroundPrimary.color },
            set: { appearance.setGraphBackgroundPrimary($0) }
        )
    }

    private var backgroundSecondaryBinding: Binding<Color> {
        Binding(
            get: { appearance.settings.graph.backgroundSecondary.color },
            set: { appearance.setGraphBackgroundSecondary($0) }
        )
    }

    private var entityColorBinding: Binding<Color> {
        Binding(
            get: { appearance.settings.graph.entityColor.color },
            set: { appearance.setEntityColor($0) }
        )
    }

    private var attributeColorBinding: Binding<Color> {
        Binding(
            get: { appearance.settings.graph.attributeColor.color },
            set: { appearance.setAttributeColor($0) }
        )
    }

    private var linkColorBinding: Binding<Color> {
        Binding(
            get: { appearance.settings.graph.linkColor.color },
            set: { appearance.setLinkColor($0) }
        )
    }

    private var containmentColorBinding: Binding<Color> {
        Binding(
            get: { appearance.settings.graph.containmentColor.color },
            set: { appearance.setContainmentColor($0) }
        )
    }

    private var highlightColorBinding: Binding<Color> {
        Binding(
            get: { appearance.settings.graph.highlightColor.color },
            set: { appearance.setHighlightColor($0) }
        )
    }

    private var labelHaloBinding: Binding<Bool> {
        Binding(
            get: { appearance.settings.graph.labelHaloEnabled },
            set: { appearance.setLabelHaloEnabled($0) }
        )
    }
}
