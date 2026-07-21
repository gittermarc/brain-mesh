//
//  CommandCenterView.swift
//  BrainMesh
//
//  Global search and quick-action surface.
//

import SwiftUI

struct CommandCenterView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var commandCenter: CommandCenterCoordinator
    @EnvironmentObject private var tabRouter: RootTabRouter
    @EnvironmentObject private var graphJump: GraphJumpCoordinator
    @EnvironmentObject private var recentNodeStore: RecentNodeStore
    @EnvironmentObject private var graphChatLaunchCoordinator: GraphChatLaunchCoordinator

    @AppStorage(BMAppStorageKeys.activeGraphID) private var activeGraphIDString: String = ""
    private var activeGraphID: UUID? { UUID(uuidString: activeGraphIDString) }

    @State private var query: String
    @State private var snapshot: BrainMeshSearchSnapshot = .empty
    @State private var isSearching: Bool = false
    @State private var errorMessage: CommandCenterUserFacingErrorMessage? = nil
    @FocusState private var isSearchFocused: Bool

    init(initialQuery: String = "") {
        _query = State(initialValue: initialQuery)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchHeader

                Divider()

                ScrollView {
                    CommandCenterContentView(
                        state: contentState,
                        onQuickAction: { action in
                            perform(CommandCenterActionResolver.action(for: action))
                        },
                        onOpenRecent: { item in
                            if let action = CommandCenterActionResolver.primaryAction(for: item) {
                                perform(action)
                            }
                        },
                        onJumpRecent: { item in
                            if let action = CommandCenterActionResolver.graphAction(for: item) {
                                perform(action)
                            }
                        },
                        onOpenResult: { result in
                            perform(CommandCenterActionResolver.primaryAction(for: result))
                        },
                        onJumpResult: { result in
                            if let action = CommandCenterActionResolver.graphAction(for: result) {
                                perform(action)
                            }
                        }
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Command Center")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") {
                        commandCenter.dismiss()
                        dismiss()
                    }
                }
            }
            .task {
                await MainActor.run {
                    isSearchFocused = true
                }
            }
            .task(id: searchTaskID) {
                await runSearchIfNeeded()
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var searchHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "command.circle")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                Text("Suchen, springen, weitermachen")
                    .font(.headline)

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                TextField("Entität, Attribut, Detail oder Anhang suchen", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isSearchFocused)
                    .submitLabel(.search)

                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Suche löschen")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.secondary.opacity(0.18))
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    private var searchTaskID: String {
        "\(activeGraphIDString)|\(BMSearch.fold(query))"
    }

    private var contentState: CommandCenterContentState {
        CommandCenterStateBuilder.state(
            query: query,
            snapshot: snapshot,
            recents: recentNodeStore.recentItems(graphID: activeGraphID, limit: 8),
            isSearching: isSearching,
            error: errorMessage
        )
    }

    @MainActor
    private func runSearchIfNeeded() async {
        let foldedQuery = BMSearch.fold(query)
        guard foldedQuery.isEmpty == false else {
            snapshot = .empty
            isSearching = false
            errorMessage = nil
            return
        }

        isSearching = true
        errorMessage = nil

        try? await Task.sleep(nanoseconds: 220_000_000)
        if Task.isCancelled { return }
        guard BMSearch.fold(query) == foldedQuery else { return }

        do {
            let loadedSnapshot = try await BrainMeshSearchService.shared.search(
                graphID: activeGraphID,
                foldedQuery: foldedQuery,
                limit: 40
            )
            if Task.isCancelled { return }
            guard BMSearch.fold(query) == foldedQuery else { return }
            snapshot = loadedSnapshot
            errorMessage = nil
        } catch {
            if Task.isCancelled { return }
            guard BMSearch.fold(query) == foldedQuery else { return }
            if let mapped = CommandCenterUserFacingErrorMessage.message(for: error) {
                errorMessage = mapped
            }
            snapshot = .empty
        }

        guard BMSearch.fold(query) == foldedQuery else { return }
        isSearching = false
    }

    private func perform(_ action: CommandCenterResolvedAction) {
        Task { @MainActor in
            switch action {
            case .present(let destination):
                commandCenter.presentDestination(destination)

            case .selectTab(let tab):
                commandCenter.dismiss()
                dismiss()
                tabRouter.select(tab)

            case .openChat:
                guard let launch = CommandCenterActionResolver.graphChatLaunch(
                    activeGraphID: activeGraphID
                ) else {
                    return
                }
                graphChatLaunchCoordinator.launch(
                    scope: launch.scope,
                    prefilledQuestion: launch.prefilledQuestion,
                    presentationStyle: .rootTab
                )
                commandCenter.dismiss()
                dismiss()
                tabRouter.openChat()

            case .jumpToGraph(let graphID, let nodeKey):
                graphJump.requestJump(to: nodeKey, in: graphID, centerOnArrival: true)
                commandCenter.dismiss()
                dismiss()
                tabRouter.select(.graph)
            }
        }
    }
}
