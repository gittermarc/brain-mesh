//
//  DetailsSchemaQuickPresetsView.swift
//  BrainMesh
//

import SwiftUI

// MARK: - Presets

struct DetailsQuickPresetsView: View {
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
