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
                    header
                    progressCard
                    steps
                    detailsTurbo
                    examples
                    footer
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "circle.grid.cross")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.tint)
                    .padding(10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(.quaternary)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Willkommen in BrainMesh")
                        .font(.title2.weight(.bold))
                    Text("In 3 kleinen Schritten zum ersten sinnvollen Graphen.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            Text("Keine Sorge: Du musst kein Graph-Theorie-Semester absolvieren. Du baust einfach dein Wissen wie LEGO zusammen – Node für Node.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Fortschritt")
                    .font(.headline)
                Spacer()
                Text("\(progress.completedSteps)/\(progress.totalSteps)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: Double(progress.completedSteps), total: Double(progress.totalSteps))

            OnboardingMiniExplainerView()
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.quaternary)
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Die 3 Schritte")
                .font(.headline)

            OnboardingStepCardView(
                number: 1,
                title: "Erste Entität anlegen",
                subtitle: "Zum Beispiel: \"Bücher\", \"Projekte\" oder \"Personen\"",
                systemImage: "plus.circle",
                isDone: progress.hasEntity,
                actionTitle: "Entität anlegen",
                actionEnabled: true,
                disabledHint: "",
                isOptional: false,
                action: { showAddEntity = true }
            )

            OnboardingStepCardView(
                number: 2,
                title: "Ersten Eintrag hinzufügen",
                subtitle: "Zum Beispiel: \"Dune\", \"Apollo 11\" oder \"Claudia\"",
                systemImage: "tag.circle",
                isDone: progress.hasAttribute,
                actionTitle: "Eintrag hinzufügen",
                actionEnabled: progress.hasEntity,
                disabledHint: "Dafür brauchst du mindestens eine Entität.",
                isOptional: false,
                action: { showEntityPickerForAttribute = true }
            )

            OnboardingStepCardView(
                number: 3,
                title: "Link erstellen",
                subtitle: "Verbinde zwei Nodes (optional mit Notiz)",
                systemImage: "arrow.triangle.branch.circle",
                isDone: progress.hasLink,
                actionTitle: "Link erstellen",
                actionEnabled: progress.hasEntity,
                disabledHint: "Dafür brauchst du mindestens eine Entität.",
                isOptional: false,
                action: { showEntityPickerForLink = true }
            )

            if !progress.hasEntity {
                Text("Tipp: Leg zuerst 2 Entitäten an, dann kannst du direkt einen Link zwischen ihnen bauen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var detailsTurbo: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Turbo: Details")
                .font(.headline)

            Text("Details sind frei definierbare Felder pro Entität (z.B. Jahr, Status). Du kannst sie später für Sortierung, Filter und Überblick nutzen.")
                .font(.callout)
                .foregroundStyle(.secondary)

            OnboardingStepCardView(
                number: nil,
                title: "Details-Felder definieren",
                subtitle: "Pro Entität, z.B. Jahr, Status, Rolle",
                systemImage: "list.bullet.rectangle",
                isDone: hasAnyDetailFields,
                actionTitle: "Felder konfigurieren",
                actionEnabled: progress.hasEntity,
                disabledHint: "Dafür brauchst du mindestens eine Entität.",
                isOptional: true,
                action: { showEntityPickerForDetailsSchema = true }
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
                isOptional: true,
                action: { showAttributePickerForDetailsValue = true }
            )
        }
    }

    private var examples: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rezepte")
                .font(.headline)

            OnboardingRecipeCard(
                title: "Rezept: Bücher",
                lines: [
                    "Entität: **Bücher**",
                    "Eintrag: **Dune**",
                    "Details: Jahr=1965, Status=Gelesen (optional)",
                    "Link: Dune —(Autor)—> Frank Herbert"
                ]
            )

            OnboardingRecipeCard(
                title: "Rezept: Projekte",
                lines: [
                    "Entität: **Projekte**",
                    "Eintrag: **BrainMesh Onboarding**",
                    "Details: Status=In Arbeit, Deadline=… (optional)",
                    "Link: BrainMesh Onboarding —(gehört zu)—> BrainMesh"
                ]
            )
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if progress.isComplete {
                Label("Nice! Dein Graph lebt.", systemImage: "checkmark.seal")
                    .font(.headline)
            }

            Button {
                onboardingHidden = true
                close()
            } label: {
                Label("Onboarding nicht mehr automatisch anzeigen", systemImage: "eye.slash")
            }
            .buttonStyle(.bordered)

            Text("Du findest das Onboarding jederzeit in Einstellungen → Hilfe.")
                .font(.footnote)
                .foregroundStyle(.secondary)
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

// MARK: - Simple Flow Chips

private struct FlowChipsView: View {
    let chips: [(systemImage: String, title: String)]

    var body: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(Array(chips.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 6) {
                    Image(systemName: item.systemImage)
                        .font(.system(size: 13, weight: .semibold))
                    Text(item.title)
                        .font(.subheadline)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.thinMaterial, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(.quaternary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
