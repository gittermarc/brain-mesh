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
    @EnvironmentObject private var graphChatLaunchCoordinator: GraphChatLaunchCoordinator
    @EnvironmentObject private var tabRouter: RootTabRouter

    @AppStorage(BMAppStorageKeys.activeGraphID) private var activeGraphIDString: String = ""

    @Bindable var entity: MetaEntity

    @Query private var savedTemplates: [MetaDetailsTemplate]

    @State private var showAddSheet: Bool = false
    @State private var showSaveTemplateSheet: Bool = false
    @State private var editField: MetaDetailFieldDefinition? = nil

    @State private var alert: DetailsSchemaAlert? = nil
    @State private var isMutating: Bool = false

    init(entity: MetaEntity) {
        self._entity = Bindable(wrappedValue: entity)

        if let graphID = entity.graphID {
            self._savedTemplates = Query(
                filter: #Predicate<MetaDetailsTemplate> { $0.graphID == graphID },
                sort: [
                    SortDescriptor(\MetaDetailsTemplate.nameFolded),
                    SortDescriptor(\MetaDetailsTemplate.createdAt, order: .reverse)
                ]
            )
        } else {
            self._savedTemplates = Query(
                filter: #Predicate<MetaDetailsTemplate> { $0.graphID == nil },
                sort: [
                    SortDescriptor(\MetaDetailsTemplate.nameFolded),
                    SortDescriptor(\MetaDetailsTemplate.createdAt, order: .reverse)
                ]
            )
        }
    }

    var body: some View {
        List {
            if entity.authoritativeDetailFieldsList.isEmpty {
                DetailsSchemaTemplatesSection { template in
                    performMutation {
                        _ = try await DetailsSchemaActions.applyTemplate(
                            template,
                            to: entity,
                            modelContext: modelContext
                        )
                    }
                }

                if !savedTemplates.isEmpty {
                    DetailsSchemaSavedSetsSection(templates: savedTemplates) { template in
                        performMutation {
                            _ = try await DetailsSchemaActions.applyTemplate(
                                template,
                                to: entity,
                                modelContext: modelContext
                            )
                        }
                    }
                }
            }

            DetailsSchemaFieldsList(
                entity: entity,
                onEditField: { field in
                    editField = field
                },
                onChatWithField: openGraphChat,
                onMove: { source, destination in
                    performMutation {
                        _ = try await DetailsSchemaActions.moveFields(
                            in: entity,
                            modelContext: modelContext,
                            from: source,
                            to: destination
                        )
                    }
                },
                onDelete: { offsets in
                    performMutation {
                        _ = try await DetailsSchemaActions.deleteFields(
                            in: entity,
                            modelContext: modelContext,
                            at: offsets
                        )
                    }
                }
            )
        }
        .disabled(isMutating)
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !entity.authoritativeDetailFieldsList.isEmpty {
                    Button {
                        showSaveTemplateSheet = true
                    } label: {
                        Image(systemName: "bookmark")
                    }
                    .accessibilityLabel("Als Set speichern")
                }

                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }

            ToolbarItem(placement: .topBarLeading) {
                if !entity.authoritativeDetailFieldsList.isEmpty {
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
        .sheet(isPresented: $showSaveTemplateSheet) {
            DetailsSchemaSaveTemplateSheet(entity: entity)
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
            case .persistence(let message):
                return Alert(
                    title: Text("Änderung fehlgeschlagen"),
                    message: Text(message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    private func openGraphChat(for field: MetaDetailFieldDefinition) {
        guard let graphID = entity.graphID,
              UUID(uuidString: activeGraphIDString) == graphID,
              field.graphID == graphID,
              field.entityID == entity.id else {
            return
        }
        let launch = GraphChatContextEntryPoint.detailField(
            graphID: graphID,
            entityID: entity.id,
            entityName: entity.name,
            fieldID: field.id,
            fieldName: field.name,
            fieldType: field.type
        )
        graphChatLaunchCoordinator.launch(
            launch,
            presentationStyle: .rootTab
        )
        tabRouter.openChat()
    }

    private func performMutation(
        _ operation: @escaping @MainActor () async throws -> Void
    ) {
        guard !isMutating else { return }
        isMutating = true

        Task { @MainActor in
            defer { isMutating = false }
            do {
                try await operation()
            } catch is CancellationError {
                modelContext.rollback()
            } catch {
                modelContext.rollback()
                alert = .persistence(error.localizedDescription)
            }
        }
    }
}

private enum DetailsSchemaAlert: Identifiable {
    case pinnedLimit
    case persistence(String)

    var id: String {
        switch self {
        case .pinnedLimit:
            return "pinned-limit"
        case .persistence(let message):
            return "persistence-\(message)"
        }
    }
}
