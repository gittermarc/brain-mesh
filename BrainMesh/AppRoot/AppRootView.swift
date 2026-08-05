//
//  AppRootView.swift
//  BrainMesh
//
//  Created by Marc Fechner on 15.12.25.
//

import SwiftData
import SwiftUI
import UIKit

struct AppRootView: View {
    @Environment(\.modelContext) var modelContext
    @Environment(\.scenePhase) var scenePhase

    @EnvironmentObject var appearance: AppearanceStore
    @EnvironmentObject var onboarding: OnboardingCoordinator

    @EnvironmentObject var graphLock: GraphLockCoordinator
    @EnvironmentObject var systemModals: SystemModalCoordinator
    @EnvironmentObject var proStore: ProEntitlementStore
    @EnvironmentObject var graphChatLaunchCoordinator: GraphChatLaunchCoordinator
    @EnvironmentObject var graphChatSessionStore: GraphChatSessionStore
    @EnvironmentObject var graphCopilotWorkspaceCoordinator: GraphCopilotWorkspaceCoordinator

    @AppStorage(BMAppStorageKeys.activeGraphID) var activeGraphIDString: String = ""

    @AppStorage(BMAppStorageKeys.onboardingHidden) var onboardingHidden: Bool = false
    @AppStorage(BMAppStorageKeys.onboardingCompleted) var onboardingCompleted: Bool = false
    @AppStorage(BMAppStorageKeys.onboardingAutoShown) var onboardingAutoShown: Bool = false

    /// Throttle auto image hydration to avoid doing full-ish scans on every foreground.
    /// Stored as UNIX time (seconds).
    @AppStorage(BMAppStorageKeys.imageHydratorLastAutoRun) var imageHydratorLastAutoRun: Double = 0

    @State var didRunStartupOnce: Bool = false
    @State var isRunningStartup: Bool = false

    // Track scene phase locally so delayed tasks can reliably check the latest value.
    @State var observedScenePhase: ScenePhase = .active
    @State var pendingBackgroundLockTask: Task<Void, Never>? = nil
    @State var searchIndexForegroundMaintenanceTask: Task<Void, Never>? = nil

    var body: some View {
        ContentView()
            .tint(appearance.appTintColor)
            .preferredColorScheme(appearance.preferredColorScheme)
            .task {
                await runStartupIfNeeded()
            }
            .onChange(of: scenePhase) { _, newPhase in
                handleScenePhaseChange(newPhase)
            }
            .onChange(of: activeGraphIDString) { _, newValue in
                cancelSearchIndexForegroundMaintenance()
                graphChatSessionStore.handleActiveGraphChange()
                let graphID = UUID(uuidString: newValue)
                graphChatLaunchCoordinator.handleActiveGraphChange(to: graphID)
                graphCopilotWorkspaceCoordinator.handleActiveGraphChange(to: graphID)

                // Avoid forcing lock sheets on top of system pickers.
                guard systemModals.isSystemModalPresented == false else { return }
                Task { await enforceLockIfNeeded() }
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIApplication.willTerminateNotification
                )
            ) { _ in
                cancelSearchIndexForegroundMaintenance()
                graphChatSessionStore.handleAppTermination()
                graphChatLaunchCoordinator.handleAppTermination()
                graphCopilotWorkspaceCoordinator.clearTransientState()
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIApplication
                        .didReceiveMemoryWarningNotification
                )
            ) { _ in
                cancelSearchIndexForegroundMaintenance()
                graphChatSessionStore.handleMemoryPressure()
                graphCopilotWorkspaceCoordinator.clearTransientState()
            }
            .onChange(of: proStore.entitlement) { _, entitlement in
                guard entitlement != .pro else {
                    return
                }
                graphChatSessionStore.handleEntitlementRevocation()
                graphCopilotWorkspaceCoordinator.clearTransientState()
                if let activeGraphID = UUID(uuidString: activeGraphIDString) {
                    graphChatLaunchCoordinator.resetToWholeGraph(activeGraphID)
                } else {
                    graphChatLaunchCoordinator.invalidate()
                }
            }
            .sheet(isPresented: $onboarding.isPresented) {
                OnboardingSheetView()
            }
            .fullScreenCover(item: $graphLock.activeRequest) { req in
                GraphUnlockView(request: req)
            }
    }
}
