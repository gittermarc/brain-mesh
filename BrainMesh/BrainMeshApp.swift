//
//  BrainMeshApp.swift
//  BrainMesh
//
//  Created by Marc Fechner on 13.12.25.
//

import SwiftData
import SwiftUI
import os

@main
struct BrainMeshApp: App {

    @StateObject private var appearanceStore = AppearanceStore()
    @StateObject private var displaySettingsStore = DisplaySettingsStore()
    @StateObject private var onboardingCoordinator = OnboardingCoordinator()
    @StateObject private var graphLockCoordinator: GraphLockCoordinator
    @StateObject private var systemModalCoordinator = SystemModalCoordinator()
    @StateObject private var proStore = ProEntitlementStore()
    @StateObject private var tabRouter = RootTabRouter()
    @StateObject private var graphJump = GraphJumpCoordinator()
    @StateObject private var commandCenter = CommandCenterCoordinator()
    @StateObject private var recentNodeStore = RecentNodeStore()
    @StateObject private var entitiesHomeRouting = EntitiesHomeRoutingCoordinator()
    @StateObject private var graphChatLaunchCoordinator: GraphChatLaunchCoordinator
    @StateObject private var graphChatSessionStore: GraphChatSessionStore
    @StateObject private var graphCopilotWorkspaceCoordinator: GraphCopilotWorkspaceCoordinator

    private let sharedModelContainer: ModelContainer
    private let graphChatLaunchAction: GraphChatLaunchAction

    init() {
        let graphLockCoordinator = GraphLockCoordinator()
        let graphChatLaunchCoordinator = GraphChatLaunchCoordinator()
        let graphCopilotWorkspaceCoordinator = GraphCopilotWorkspaceCoordinator()

        let schema = Schema([
            MetaGraph.self,
            MetaEntity.self,
            MetaAttribute.self,
            MetaLink.self,
            MetaAttachment.self,
            MetaDetailFieldDefinition.self,
            MetaDetailFieldValue.self,
            MetaDetailsTemplate.self,
        ])

        // CloudKit / iCloud Sync (private DB)
        let cloudConfig = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)

        do {
            sharedModelContainer = try ModelContainer(for: schema, configurations: [cloudConfig])
            BMLog.storage.info(
                "storage_container_open mode=cloudkit outcome=success"
            )
            SyncRuntime.shared.setStorageMode(.cloudKit)
        } catch {
            let nsError = error as NSError
            BMLog.storage.fault(
                "storage_container_open mode=cloudkit outcome=recovery domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)"
            )
            SyncRuntime.shared.enterStorageRecovery(for: error)

            // Never replace an unreadable production store with a persistent,
            // empty local branch. The in-memory container exists only so the
            // app can render a blocking recovery explanation without touching
            // the user's on-disk or CloudKit data.
            let recoveryConfig = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true
            )
            do {
                sharedModelContainer = try ModelContainer(
                    for: schema,
                    configurations: [recoveryConfig]
                )
            } catch {
                fatalError("Could not create the in-memory recovery container: \(error)")
            }
        }

        let graphChatSessionStore = GraphChatSessionStore(
            modelContainer: sharedModelContainer
        )
        graphLockCoordinator.setLockHandler {
            [
                weak graphChatSessionStore, weak graphChatLaunchCoordinator,
                weak graphCopilotWorkspaceCoordinator
            ] graphID in
            graphChatSessionStore?.handleSecurityLock(graphID: graphID)
            graphChatLaunchCoordinator?.handleSecurityLock(graphID: graphID)
            graphCopilotWorkspaceCoordinator?.handleSensitiveStateInvalidation(graphID: graphID)
        }

        _graphLockCoordinator = StateObject(wrappedValue: graphLockCoordinator)
        _graphChatLaunchCoordinator = StateObject(wrappedValue: graphChatLaunchCoordinator)
        _graphChatSessionStore = StateObject(wrappedValue: graphChatSessionStore)
        _graphCopilotWorkspaceCoordinator = StateObject(wrappedValue: graphCopilotWorkspaceCoordinator)
        graphChatLaunchAction = GraphChatLaunchAction {
            [weak graphChatLaunchCoordinator] launch, style in
            graphChatLaunchCoordinator?.launch(
                launch,
                presentationStyle: style
            )
        }

        // App-level loader/hydrator configuration (off-main).
        AppLoadersConfigurator.configureAllLoaders(with: sharedModelContainer)
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(appearanceStore)
                .environmentObject(displaySettingsStore)
                .environmentObject(onboardingCoordinator)
                .environmentObject(graphLockCoordinator)
                .environmentObject(systemModalCoordinator)
                .environmentObject(proStore)
                .environmentObject(tabRouter)
                .environmentObject(graphJump)
                .environmentObject(commandCenter)
                .environmentObject(recentNodeStore)
                .environmentObject(entitiesHomeRouting)
                .environmentObject(graphChatLaunchCoordinator)
                .environment(
                    \.graphChatLaunchAction,
                    graphChatLaunchAction
                )
                .environmentObject(graphChatSessionStore)
                .environmentObject(graphCopilotWorkspaceCoordinator)
        }
        .modelContainer(sharedModelContainer)
    }
}
