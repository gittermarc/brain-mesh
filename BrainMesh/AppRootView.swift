//
//  AppRootView.swift
//  BrainMesh
//
//  Created by Marc Fechner on 15.12.25.
//

import SwiftUI
import SwiftData

struct AppRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @EnvironmentObject private var appearance: AppearanceStore
    @EnvironmentObject private var onboarding: OnboardingCoordinator

    @AppStorage("BMActiveGraphID") private var activeGraphIDString: String = ""

    @AppStorage("BMOnboardingHidden") private var onboardingHidden: Bool = false
    @AppStorage("BMOnboardingCompleted") private var onboardingCompleted: Bool = false
    @AppStorage("BMOnboardingAutoShown") private var onboardingAutoShown: Bool = false

    /// Throttle auto image hydration to avoid doing full-ish scans on every foreground.
    /// Stored as UNIX time (seconds).
    @AppStorage("BMImageHydratorLastAutoRun") private var imageHydratorLastAutoRun: Double = 0

    @State private var didRunStartupOnce: Bool = false

    var body: some View {
        ContentView()
            .tint(appearance.appTintColor)
            .preferredColorScheme(appearance.preferredColorScheme)
            .task {
                await runStartupIfNeeded()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Task {
                        await handleBecameActive()
                    }
                }
            }
            .sheet(isPresented: $onboarding.isPresented) {
                OnboardingSheetView()
            }
    }

    @MainActor
    private func runStartupIfNeeded() async {
        guard didRunStartupOnce == false else {
            await maybePresentOnboardingIfNeeded()
            return
        }

        didRunStartupOnce = true

        await bootstrapGraphing()
        await autoHydrateImagesIfDue()
        await maybePresentOnboardingIfNeeded()
    }

    @MainActor
    private func handleBecameActive() async {
        // During cold start, `.task` performs startup work already.
        guard didRunStartupOnce else { return }

        // Keep foreground work lightweight.
        await autoHydrateImagesIfDue()
        await maybePresentOnboardingIfNeeded()
    }

    @MainActor
    private func autoHydrateImagesIfDue() async {
        // "Rare" auto-hydration: at most once per 24 hours.
        let now = Date().timeIntervalSince1970
        let minInterval: TimeInterval = 60 * 60 * 24
        guard (now - imageHydratorLastAutoRun) >= minInterval else { return }

        // Only update the timestamp if a pass actually executed (run-once guard might skip).
        let didRun = await ImageHydrator.hydrateIncremental(using: modelContext, runOncePerLaunch: true)
        if didRun {
            imageHydratorLastAutoRun = now
        }
    }

    @MainActor
    private func bootstrapGraphing() async {
        let defaultGraph = GraphBootstrap.ensureAtLeastOneGraph(using: modelContext)

        // Active graph setzen (falls leer / kaputt)
        if UUID(uuidString: activeGraphIDString) == nil {
            activeGraphIDString = defaultGraph.id.uuidString
        }

        // Legacy Records in den Default-Graph schieben
        GraphBootstrap.migrateLegacyRecordsIfNeeded(defaultGraphID: defaultGraph.id, using: modelContext)
    }

    @MainActor
    private func maybePresentOnboardingIfNeeded() async {
        guard !onboardingHidden else { return }
        guard !onboardingCompleted else { return }
        guard !onboardingAutoShown else { return }

        let gid = UUID(uuidString: activeGraphIDString)
        let progress = OnboardingProgress.compute(using: modelContext, activeGraphID: gid)

        // Wenn der User schon Daten hat (z.B. Update), niemals automatisch aufploppen.
        onboardingAutoShown = true
        guard progress.completedSteps == 0 else { return }

        onboarding.isPresented = true
    }
}
