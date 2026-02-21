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
                DetailsSchemaTemplatesSection { template in
                    DetailsSchemaActions.applyTemplate(template, to: entity, modelContext: modelContext)
                }
            }

            DetailsSchemaFieldsList(
                entity: entity,
                onEditField: { field in
                    editField = field
                },
                onMove: { source, destination in
                    DetailsSchemaActions.moveFields(in: entity, modelContext: modelContext, from: source, to: destination)
                },
                onDelete: { offsets in
                    DetailsSchemaActions.deleteFields(in: entity, modelContext: modelContext, at: offsets)
                }
            )
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
}

private enum DetailsSchemaAlert: String, Identifiable {
    case pinnedLimit

    var id: String { rawValue }
}
