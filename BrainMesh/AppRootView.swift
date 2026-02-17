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

    @EnvironmentObject private var graphLock: GraphLockCoordinator
    @EnvironmentObject private var systemModals: SystemModalCoordinator

    @AppStorage("BMActiveGraphID") private var activeGraphIDString: String = ""

    @AppStorage("BMOnboardingHidden") private var onboardingHidden: Bool = false
    @AppStorage("BMOnboardingCompleted") private var onboardingCompleted: Bool = false
    @AppStorage("BMOnboardingAutoShown") private var onboardingAutoShown: Bool = false

    /// Throttle auto image hydration to avoid doing full-ish scans on every foreground.
    /// Stored as UNIX time (seconds).
    @AppStorage("BMImageHydratorLastAutoRun") private var imageHydratorLastAutoRun: Double = 0

    @State private var didRunStartupOnce: Bool = false

    // Track scene phase locally so delayed tasks can reliably check the latest value.
    @State private var observedScenePhase: ScenePhase = .active
    @State private var pendingBackgroundLockTask: Task<Void, Never>? = nil

    var body: some View {
        ContentView()
            .tint(appearance.appTintColor)
            .preferredColorScheme(appearance.preferredColorScheme)
            .task {
                await runStartupIfNeeded()
            }
            .onChange(of: scenePhase) { _, newPhase in
                observedScenePhase = newPhase

                if newPhase == .active {
                    cancelPendingBackgroundLock()
                    // If a system picker is currently presented, avoid running
                    // foreground work that can disrupt it (especially after Face ID prompts).
                    guard systemModals.isSystemModalPresented == false else { return }
                    Task { await handleBecameActive() }
                } else if newPhase == .background {
                    // Auto-lock when the app actually goes to background — but debounce the lock.
                    //
                    // Why: When the system presents a Face ID prompt from inside a picker (notably
                    // Photos' "Hidden" album), the scene can briefly flip to `.background` on some
                    // devices/OS versions. If we lock immediately, the unlock fullScreenCover
                    // dismisses the Photos picker mid-selection.
                    //
                    // Fix: Schedule the lock with a short delay and cancel it if we become active
                    // again quickly. Real "user backgrounded the app" cases still lock reliably.
                    scheduleDebouncedBackgroundLock()
                } else {
                    // Intentionally do nothing on `.inactive` — system overlays and auth prompts
                    // can trigger it transiently, and locking there would be disruptive.
                }
            }
            .onChange(of: activeGraphIDString) { _, _ in
                // Avoid forcing lock sheets on top of system pickers.
                guard systemModals.isSystemModalPresented == false else { return }
                Task { await enforceLockIfNeeded() }
            }
            .sheet(isPresented: $onboarding.isPresented) {
                OnboardingSheetView()
            }
            .fullScreenCover(item: $graphLock.activeRequest) { req in
                GraphUnlockView(request: req)
            }
    }

    private func cancelPendingBackgroundLock() {
        pendingBackgroundLockTask?.cancel()
        pendingBackgroundLockTask = nil
    }

    private func scheduleDebouncedBackgroundLock() {
        cancelPendingBackgroundLock()

        // We want to auto-lock quickly when the user really backgrounds the app.
        // But while a system picker is open (Photos/Hidden album Face ID, etc.), iOS can
        // keep reporting `.background` and locking will dismiss/reset the picker.
        //
        // Strategy:
        // - wait a short moment (debounce)
        // - if still in background AND a picker is open, grant a short grace window
        // - after grace (or if no picker), lock
        let debounceNanos: UInt64 = 900_000_000
        let graceSeconds: TimeInterval = 6.0
        let gracePollNanos: UInt64 = 500_000_000

        pendingBackgroundLockTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: debounceNanos)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            guard observedScenePhase == .background else { return }

            if systemModals.isSystemModalPresented {
                var elapsed: TimeInterval = 0
                while observedScenePhase == .background && systemModals.isSystemModalPresented && elapsed < graceSeconds {
                    do {
                        try await Task.sleep(nanoseconds: gracePollNanos)
                    } catch {
                        return
                    }
                    guard !Task.isCancelled else { return }
                    elapsed += 0.5
                }
            }

            guard !Task.isCancelled else { return }
            guard observedScenePhase == .background else { return }

            graphLock.lockAll()
        }
    }

    @MainActor
    private func runStartupIfNeeded() async {
        guard didRunStartupOnce == false else {
            await maybePresentOnboardingIfNeeded()
            return
        }

        didRunStartupOnce = true

        // ✅ Prewarm SF Symbols catalog off-main to avoid the first Icon-Picker stutter.
        Task.detached(priority: .utility) {
            IconCatalog.prewarm()
        }

        await bootstrapGraphing()
        await enforceLockIfNeeded()
        await autoHydrateImagesIfDue()
        await enforceLockIfNeeded()
        await maybePresentOnboardingIfNeeded()
    }

    @MainActor
    private func handleBecameActive() async {
        // During cold start, `.task` performs startup work already.
        guard didRunStartupOnce else { return }

        // Keep foreground work lightweight.
        await autoHydrateImagesIfDue()
        await enforceLockIfNeeded()
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
        // If the active graph is locked, don't pop onboarding on top.
        guard graphLock.activeRequest == nil else { return }

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


    @MainActor
    private func enforceLockIfNeeded() async {
        graphLock.enforceActiveGraphLockIfNeeded(using: modelContext)
    }
}
