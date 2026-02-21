//
//  DetailsSchemaTemplatesSection.swift
//  BrainMesh
//

import SwiftUI

struct DetailsSchemaTemplatesSection: View {
    let onApply: (DetailsTemplate) -> Void

    var body: some View {
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
                            onApply(template)
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
}

enum DetailsTemplate: String, CaseIterable, Identifiable {
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
