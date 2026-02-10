//
//  OnboardingView.swift
//  BrainMesh
//
//  Onboarding + Coordinator
//

import SwiftUI
import SwiftData
import Combine

// MARK: - Coordinator

final class OnboardingCoordinator: ObservableObject {
    @Published var isPresented: Bool = false
}

// MARK: - Progress

struct OnboardingProgress: Equatable {
    let hasEntity: Bool
    let hasAttribute: Bool
    let hasLink: Bool

    var totalSteps: Int { 3 }
    var completedSteps: Int {
        var c = 0
        if hasEntity { c += 1 }
        if hasAttribute { c += 1 }
        if hasLink { c += 1 }
        return c
    }

    var isComplete: Bool { completedSteps >= totalSteps }

    @MainActor
    static func compute(using modelContext: ModelContext, activeGraphID: UUID?) -> OnboardingProgress {
        let e = existsEntity(using: modelContext, activeGraphID: activeGraphID)
        let a = existsAttribute(using: modelContext, activeGraphID: activeGraphID)
        let l = existsLink(using: modelContext, activeGraphID: activeGraphID)
        return OnboardingProgress(hasEntity: e, hasAttribute: a, hasLink: l)
    }

    @MainActor
    private static func existsEntity(using modelContext: ModelContext, activeGraphID: UUID?) -> Bool {
        var fd: FetchDescriptor<MetaEntity>
        if let gid = activeGraphID {
            fd = FetchDescriptor(
                predicate: #Predicate<MetaEntity> { e in
                    e.graphID == gid || e.graphID == nil
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
    private static func existsAttribute(using modelContext: ModelContext, activeGraphID: UUID?) -> Bool {
        var fd: FetchDescriptor<MetaAttribute>
        if let gid = activeGraphID {
            fd = FetchDescriptor(
                predicate: #Predicate<MetaAttribute> { a in
                    a.graphID == gid || a.graphID == nil
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
    private static func existsLink(using modelContext: ModelContext, activeGraphID: UUID?) -> Bool {
        var fd: FetchDescriptor<MetaLink>
        if let gid = activeGraphID {
            fd = FetchDescriptor(
                predicate: #Predicate<MetaLink> { l in
                    l.graphID == gid || l.graphID == nil
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

// MARK: - Mini Explainer (für Empty States)

struct OnboardingMiniExplainerView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Was ist was?", systemImage: "sparkles")
                .font(.headline)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "cube")
                        .foregroundStyle(.tint)
                        .frame(width: 20)
                    Text("**Entität** = ein Ding in deinem Wissen: Person, Projekt, Begriff, Ort, Buch …")
                }
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "tag")
                        .foregroundStyle(.tint)
                        .frame(width: 20)
                    Text("**Attribut** = ein Detail dazu: Rolle, Status, Datum, Tag, Kategorie …")
                }
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "arrow.triangle.branch")
                        .foregroundStyle(.tint)
                        .frame(width: 20)
                    Text("**Link** = Beziehung zwischen zwei Nodes: *arbeitet an*, *liegt in*, *gehört zu* …")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.quaternary)
        }
    }
}

// MARK: - Onboarding Sheet

struct OnboardingSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var onboarding: OnboardingCoordinator

    @AppStorage("BMActiveGraphID") private var activeGraphIDString: String = ""
    private var activeGraphID: UUID? { UUID(uuidString: activeGraphIDString) }

    @AppStorage("BMOnboardingHidden") private var onboardingHidden: Bool = false
    @AppStorage("BMOnboardingCompleted") private var onboardingCompleted: Bool = false

    @State private var progress: OnboardingProgress = OnboardingProgress(hasEntity: false, hasAttribute: false, hasLink: false)

    @State private var showAddEntity: Bool = false

    @State private var showEntityPickerForAttribute: Bool = false
    @State private var pendingAttributeEntityID: UUID?
    @State private var attributeEntity: MetaEntity?

    @State private var showEntityPickerForLink: Bool = false
    @State private var pendingLinkSource: NodeRef?
    @State private var linkSource: NodeRef?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    progressCard
                    steps
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
                subtitle: "Zum Beispiel: \"Projekt Apollo\" oder \"Claudia\"",
                systemImage: "plus.circle",
                isDone: progress.hasEntity,
                actionTitle: "Entität anlegen",
                actionEnabled: true,
                action: { showAddEntity = true }
            )

            OnboardingStepCardView(
                number: 2,
                title: "Attribut hinzufügen",
                subtitle: "Zum Beispiel: Status, Jahr, Rolle oder Tag",
                systemImage: "tag.circle",
                isDone: progress.hasAttribute,
                actionTitle: "Attribut hinzufügen",
                actionEnabled: progress.hasEntity,
                action: { showEntityPickerForAttribute = true }
            )

            OnboardingStepCardView(
                number: 3,
                title: "Link erstellen",
                subtitle: "Verbinde zwei Nodes (mit optionaler Notiz)",
                systemImage: "arrow.triangle.branch.circle",
                isDone: progress.hasLink,
                actionTitle: "Link erstellen",
                actionEnabled: progress.hasEntity,
                action: { showEntityPickerForLink = true }
            )

            if !progress.hasEntity {
                Text("Tipp: Leg zuerst 2 Entitäten an, dann kannst du direkt einen Link zwischen ihnen bauen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var examples: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ideen, um loszulegen")
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                Text("**Entitäten**")
                    .font(.subheadline.weight(.semibold))
                FlowChipsView(chips: [
                    ("person", "Person"),
                    ("briefcase", "Projekt"),
                    ("book", "Buch"),
                    ("mappin.and.ellipse", "Ort"),
                    ("lightbulb", "Begriff"),
                    ("film", "Film")
                ])

                Divider()

                Text("**Attribute**")
                    .font(.subheadline.weight(.semibold))
                FlowChipsView(chips: [
                    ("calendar", "Jahr"),
                    ("flag", "Status"),
                    ("tag", "Tag"),
                    ("person.badge.key", "Rolle"),
                    ("link", "URL"),
                    ("note.text", "Notiz")
                ])
            }
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.quaternary)
            }
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
}

// MARK: - Step Card

private struct OnboardingStepCardView: View {
    let number: Int
    let title: String
    let subtitle: String
    let systemImage: String
    let isDone: Bool
    let actionTitle: String
    let actionEnabled: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(.thinMaterial)
                        .frame(width: 40, height: 40)
                    Image(systemName: isDone ? "checkmark" : systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isDone ? AnyShapeStyle(Color.green) : AnyShapeStyle(.tint))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(number). \(title)")
                        .font(.headline)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            if isDone {
                Label("Erledigt", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            } else {
                Button(action: action) {
                    Label(actionTitle, systemImage: "arrow.right")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!actionEnabled)

                if !actionEnabled {
                    Text("Dafür brauchst du mindestens eine Entität.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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

/// Wrap-/Flow-Layout für Chips.
///
/// Warum nicht der alte AlignmentGuide-ZStack?
/// Der hat in ScrollViews gerne eine "zu kleine" Höhe reportet → dann liegen Views optisch übereinander.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = (proposal.width ?? .greatestFiniteMagnitude)

        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var measuredWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if x > 0, x + size.width > maxWidth {
                measuredWidth = max(measuredWidth, x - spacing)
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }

            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        measuredWidth = max(measuredWidth, x > 0 ? (x - spacing) : 0)
        let height = y + rowHeight

        return CGSize(width: proposal.width ?? measuredWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width > 0 ? bounds.width : .greatestFiniteMagnitude

        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }

            subview.place(
                at: CGPoint(x: bounds.minX + x, y: bounds.minY + y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )

            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
