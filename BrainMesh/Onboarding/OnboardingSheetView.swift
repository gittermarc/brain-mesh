//
//  OnboardingSheetView.swift
//  BrainMesh
//

import SwiftUI
import SwiftData

struct OnboardingSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var onboarding: OnboardingCoordinator

    @AppStorage(BMAppStorageKeys.activeGraphID) private var activeGraphIDString: String = ""
    private var activeGraphID: UUID? { UUID(uuidString: activeGraphIDString) }

    @AppStorage(BMAppStorageKeys.onboardingHidden) private var onboardingHidden: Bool = false
    @AppStorage(BMAppStorageKeys.onboardingCompleted) private var onboardingCompleted: Bool = false

    @State private var progress: OnboardingProgress = OnboardingProgress(hasEntity: false, hasAttribute: false, hasLink: false)
    @State private var hasAnyDetailFields: Bool = false
    @State private var hasAnyDetailValues: Bool = false

    @State private var showAddEntity: Bool = false

    @State private var showEntityPickerForAttribute: Bool = false
    @State private var pendingAttributeEntityID: UUID?
    @State private var attributeEntity: MetaEntity?

    @State private var showEntityPickerForLink: Bool = false
    @State private var pendingLinkSource: NodeRef?
    @State private var linkSource: NodeRef?

    // Turbo: Details
    @State private var showEntityPickerForDetailsSchema: Bool = false
    @State private var pendingDetailsSchemaEntityID: UUID?
    @State private var detailsSchemaRoute: DetailsSchemaRoute? = nil

    @State private var showAttributePickerForDetailsValue: Bool = false
    @State private var pendingDetailsValueAttributeID: UUID?
    @State private var detailsValueRoute: DetailsValueRoute? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    OnboardingHeroView(progress: progress)

                    OnboardingStepListView(
                        progress: progress,
                        onAddEntity: { showAddEntity = true },
                        onPickEntityForAttribute: { showEntityPickerForAttribute = true },
                        onPickEntityForLink: { showEntityPickerForLink = true }
                    )

                    OnboardingDetailsTurboView(
                        progress: progress,
                        hasAnyDetailFields: hasAnyDetailFields,
                        hasAnyDetailValues: hasAnyDetailValues,
                        onPickEntityForSchema: { showEntityPickerForDetailsSchema = true },
                        onPickAttributeForValue: { showAttributePickerForDetailsValue = true }
                    )

                    OnboardingRecipesView()

                    OnboardingActionsView(
                        isComplete: progress.isComplete,
                        onboardingHidden: $onboardingHidden,
                        onClose: { close() }
                    )
                }
                .padding(18)
            }
            .navigationTitle("Onboarding")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { close() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        onboardingCompleted = true
                        close()
                    }
                    .disabled(!progress.isComplete)
                }
            }
            .task { await refreshProgress() }
            .onChange(of: activeGraphIDString) { _, _ in
                Task { await refreshProgress() }
            }
            .onChange(of: showEntityPickerForAttribute) { _, isShowing in
                guard !isShowing else { return }
                if let id = pendingAttributeEntityID {
                    pendingAttributeEntityID = nil
                    attributeEntity = fetchEntity(id: id)
                }
            }
            .onChange(of: showEntityPickerForLink) { _, isShowing in
                guard !isShowing else { return }
                if let src = pendingLinkSource {
                    pendingLinkSource = nil
                    linkSource = src
                }
            }
            .onChange(of: showEntityPickerForDetailsSchema) { _, isShowing in
                guard !isShowing else { return }
                if let id = pendingDetailsSchemaEntityID {
                    pendingDetailsSchemaEntityID = nil
                    if let entity = fetchEntity(id: id) {
                        detailsSchemaRoute = DetailsSchemaRoute(entity: entity)
                    }
                }
            }
            .onChange(of: showAttributePickerForDetailsValue) { _, isShowing in
                guard !isShowing else { return }
                if let id = pendingDetailsValueAttributeID {
                    pendingDetailsValueAttributeID = nil
                    if let attr = fetchAttribute(id: id), let owner = attr.owner {
                        let fields = owner.detailFieldsList
                        if let field = fields.first(where: { $0.isPinned }) ?? fields.first {
                            detailsValueRoute = DetailsValueRoute(attribute: attr, field: field)
                        } else {
                            detailsSchemaRoute = DetailsSchemaRoute(entity: owner)
                        }
                    }
                }
            }
            .sheet(isPresented: $showAddEntity) {
                AddEntityView()
                    .onDisappear { Task { await refreshProgress() } }
            }
            .sheet(isPresented: $showEntityPickerForAttribute) {
                NodePickerView(kind: .entity) { picked in
                    pendingAttributeEntityID = picked.id
                    showEntityPickerForAttribute = false
                }
            }
            .sheet(item: $attributeEntity) { entity in
                AddAttributeView(entity: entity)
                    .onDisappear { Task { await refreshProgress() } }
            }
            .sheet(isPresented: $showEntityPickerForLink) {
                NodePickerView(kind: .entity) { picked in
                    pendingLinkSource = picked
                    showEntityPickerForLink = false
                }
            }
            .sheet(item: $linkSource) { source in
                AddLinkView(source: source, graphID: activeGraphID)
                    .onDisappear { Task { await refreshProgress() } }
            }
            .sheet(isPresented: $showEntityPickerForDetailsSchema) {
                NodePickerView(kind: .entity) { picked in
                    pendingDetailsSchemaEntityID = picked.id
                    showEntityPickerForDetailsSchema = false
                }
            }
            .sheet(item: $detailsSchemaRoute) { route in
                NavigationStack {
                    DetailsSchemaBuilderView(entity: route.entity)
                }
                .onDisappear { Task { await refreshProgress() } }
            }
            .sheet(isPresented: $showAttributePickerForDetailsValue) {
                NodePickerView(kind: .attribute) { picked in
                    pendingDetailsValueAttributeID = picked.id
                    showAttributePickerForDetailsValue = false
                }
            }
            .sheet(item: $detailsValueRoute) { route in
                DetailsValueEditorSheet(attribute: route.attribute, field: route.field)
                    .onDisappear { Task { await refreshProgress() } }
            }
        }
    }

    @MainActor
    private func refreshProgress() async {
        progress = OnboardingProgress.compute(using: modelContext, activeGraphID: activeGraphID)
        hasAnyDetailFields = existsDetailFieldDefinition(using: modelContext, activeGraphID: activeGraphID)
        hasAnyDetailValues = existsDetailFieldValue(using: modelContext, activeGraphID: activeGraphID)
        if progress.isComplete {
            onboardingCompleted = true
        }
    }

    private func close() {
        onboarding.isPresented = false
        dismiss()
    }

    private func fetchEntity(id: UUID) -> MetaEntity? {
        let nID = id
        let gid = activeGraphID

        var fd: FetchDescriptor<MetaEntity>
        if let gid {
            fd = FetchDescriptor(
                predicate: #Predicate<MetaEntity> { e in
                    e.id == nID && (e.graphID == gid || e.graphID == nil)
                }
            )
        } else {
            fd = FetchDescriptor(predicate: #Predicate<MetaEntity> { e in e.id == nID })
        }
        fd.fetchLimit = 1
        return (try? modelContext.fetch(fd))?.first
    }

    private func fetchAttribute(id: UUID) -> MetaAttribute? {
        let nID = id
        let gid = activeGraphID

        var fd: FetchDescriptor<MetaAttribute>
        if let gid {
            fd = FetchDescriptor(
                predicate: #Predicate<MetaAttribute> { a in
                    a.id == nID && (a.graphID == gid || a.graphID == nil)
                }
            )
        } else {
            fd = FetchDescriptor(predicate: #Predicate<MetaAttribute> { a in a.id == nID })
        }
        fd.fetchLimit = 1
        return (try? modelContext.fetch(fd))?.first
    }

    @MainActor
    private func existsDetailFieldDefinition(using modelContext: ModelContext, activeGraphID: UUID?) -> Bool {
        var fd: FetchDescriptor<MetaDetailFieldDefinition>
        if let gid = activeGraphID {
            fd = FetchDescriptor(
                predicate: #Predicate<MetaDetailFieldDefinition> { f in
                    f.graphID == gid || f.graphID == nil
                }
            )
        } else {
            fd = FetchDescriptor()
        }
        fd.fetchLimit = 1
        let result = (try? modelContext.fetch(fd)) ?? []
        return !result.isEmpty
    }

    @MainActor
    private func existsDetailFieldValue(using modelContext: ModelContext, activeGraphID: UUID?) -> Bool {
        var fd: FetchDescriptor<MetaDetailFieldValue>
        if let gid = activeGraphID {
            fd = FetchDescriptor(
                predicate: #Predicate<MetaDetailFieldValue> { v in
                    v.graphID == gid || v.graphID == nil
                }
            )
        } else {
            fd = FetchDescriptor()
        }
        fd.fetchLimit = 1
        let result = (try? modelContext.fetch(fd)) ?? []
        return !result.isEmpty
    }
}

private struct DetailsSchemaRoute: Identifiable {
    let id: UUID = UUID()
    let entity: MetaEntity
}

private struct DetailsValueRoute: Identifiable {
    let id: UUID = UUID()
    let attribute: MetaAttribute
    let field: MetaDetailFieldDefinition
}
