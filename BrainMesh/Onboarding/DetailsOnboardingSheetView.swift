//
//  DetailsOnboardingSheetView.swift
//  BrainMesh
//
//  Mini-Onboarding: Details-Felder (Schema) + Werte
//

import SwiftUI
import SwiftData

struct DetailsOnboardingSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @AppStorage("BMActiveGraphID") private var activeGraphIDString: String = ""
    private var activeGraphID: UUID? { UUID(uuidString: activeGraphIDString) }

    @State private var progress: OnboardingProgress = OnboardingProgress(hasEntity: false, hasAttribute: false, hasLink: false)
    @State private var hasAnyDetailFields: Bool = false
    @State private var hasAnyDetailValues: Bool = false

    @State private var showEntityPickerForSchema: Bool = false
    @State private var pendingSchemaEntityID: UUID?
    @State private var schemaRoute: DetailsSchemaRoute? = nil

    @State private var showAttributePickerForValue: Bool = false
    @State private var pendingValueAttributeID: UUID?
    @State private var valueRoute: DetailsValueRoute? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    steps
                    recipes
                }
                .padding(18)
            }
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
            }
            .task { await refresh() }
            .onChange(of: activeGraphIDString) { _, _ in
                Task { await refresh() }
            }
            .onChange(of: showEntityPickerForSchema) { _, isShowing in
                guard !isShowing else { return }
                if let id = pendingSchemaEntityID {
                    pendingSchemaEntityID = nil
                    if let entity = fetchEntity(id: id) {
                        schemaRoute = DetailsSchemaRoute(entity: entity)
                    }
                }
            }
            .onChange(of: showAttributePickerForValue) { _, isShowing in
                guard !isShowing else { return }
                if let id = pendingValueAttributeID {
                    pendingValueAttributeID = nil
                    if let attr = fetchAttribute(id: id), let owner = attr.owner {
                        let fields = owner.detailFieldsList
                        if let field = fields.first(where: { $0.isPinned }) ?? fields.first {
                            valueRoute = DetailsValueRoute(attribute: attr, field: field)
                        } else {
                            schemaRoute = DetailsSchemaRoute(entity: owner)
                        }
                    }
                }
            }
            .sheet(isPresented: $showEntityPickerForSchema) {
                NodePickerView(kind: .entity) { picked in
                    pendingSchemaEntityID = picked.id
                    showEntityPickerForSchema = false
                }
            }
            .sheet(item: $schemaRoute) { route in
                NavigationStack {
                    DetailsSchemaBuilderView(entity: route.entity)
                }
                .onDisappear { Task { await refresh() } }
            }
            .sheet(isPresented: $showAttributePickerForValue) {
                NodePickerView(kind: .attribute) { picked in
                    pendingValueAttributeID = picked.id
                    showAttributePickerForValue = false
                }
            }
            .sheet(item: $valueRoute) { route in
                DetailsValueEditorSheet(attribute: route.attribute, field: route.field)
                    .onDisappear { Task { await refresh() } }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.tint)
                    .padding(10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(.quaternary)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Neu: Details-Felder")
                        .font(.title2.weight(.bold))
                    Text("Mach aus deinem Graph eine kleine Datenbank – ohne Excel-Frust.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            Text("Details sind frei definierbare Felder pro Entität (z.B. Jahr, Status). Du füllst die Werte pro Eintrag aus. Perfekt für Sortierung, Filter und Überblick.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("In 2 Schritten")
                .font(.headline)

            OnboardingStepCardView(
                number: nil,
                title: "Details-Felder definieren",
                subtitle: "Pro Entität, z.B. Jahr, Status, Rolle",
                systemImage: "slider.horizontal.3",
                isDone: hasAnyDetailFields,
                actionTitle: "Felder konfigurieren",
                actionEnabled: progress.hasEntity,
                disabledHint: "Dafür brauchst du mindestens eine Entität.",
                isOptional: false,
                action: { showEntityPickerForSchema = true }
            )

            OnboardingStepCardView(
                number: nil,
                title: "Ersten Wert setzen",
                subtitle: "Zum Beispiel: Jahr=1965 bei \"Dune\"",
                systemImage: "pencil.and.list.clipboard",
                isDone: hasAnyDetailValues,
                actionTitle: "Wert setzen",
                actionEnabled: progress.hasAttribute && hasAnyDetailFields,
                disabledHint: progress.hasAttribute ? "Lege zuerst Details-Felder an." : "Dafür brauchst du zuerst einen Eintrag (Attribut).",
                isOptional: false,
                action: { showAttributePickerForValue = true }
            )
        }
    }

    private var recipes: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mini-Rezepte")
                .font(.headline)

            OnboardingRecipeCard(
                title: "Bücher",
                lines: [
                    "Entität: **Bücher**",
                    "Details-Felder: Jahr, Status, Autor",
                    "Eintrag: **Dune**",
                    "Werte: Jahr=1965, Status=Gelesen"
                ]
            )

            OnboardingRecipeCard(
                title: "Projekte",
                lines: [
                    "Entität: **Projekte**",
                    "Details-Felder: Status, Start, Deadline",
                    "Eintrag: **BrainMesh Onboarding**",
                    "Werte: Status=In Arbeit"
                ]
            )
        }
    }

    @MainActor
    private func refresh() async {
        progress = OnboardingProgress.compute(using: modelContext, activeGraphID: activeGraphID)
        hasAnyDetailFields = existsDetailFieldDefinition(using: modelContext, activeGraphID: activeGraphID)
        hasAnyDetailValues = existsDetailFieldValue(using: modelContext, activeGraphID: activeGraphID)
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

private struct OnboardingRecipeCard: View {
    let title: String
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.tint)
                            .padding(.top, 1)
                        Text(.init(line))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.quaternary)
        }
    }
}
