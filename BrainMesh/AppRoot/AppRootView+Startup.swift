//
//  AppRootView+Startup.swift
//  BrainMesh
//

import Foundation

extension AppRootView {

    @MainActor
    func runStartupIfNeeded() async {
        guard didRunStartupOnce == false else {
            await maybePresentOnboardingIfNeeded()
            return
        }

        didRunStartupOnce = true

        // SF Symbols catalog loads lazily when opening the icon picker (no startup work here).

        await bootstrapGraphing()
        await enforceLockIfNeeded()
        await autoHydrateImagesIfDue()
        await enforceLockIfNeeded()
        await maybePresentOnboardingIfNeeded()
    }

    @MainActor
    func handleBecameActive() async {
        // During cold start, `.task` performs startup work already.
        guard didRunStartupOnce else { return }

        // Keep foreground work lightweight.
        await autoHydrateImagesIfDue()
        await enforceLockIfNeeded()
        await maybePresentOnboardingIfNeeded()
    }

    @MainActor
    func autoHydrateImagesIfDue() async {
        // "Rare" auto-hydration: at most once per 24 hours.
        let now = Date().timeIntervalSince1970
        let minInterval: TimeInterval = 60 * 60 * 24
        guard (now - imageHydratorLastAutoRun) >= minInterval else { return }

        // Only update the timestamp if a pass actually executed (run-once guard might skip).
        let didRun = await ImageHydrator.shared.hydrateIncremental(runOncePerLaunch: true)
        if didRun {
            imageHydratorLastAutoRun = now
        }
    }

    @MainActor
    func bootstrapGraphing() async {
        let defaultGraph = GraphBootstrap.ensureAtLeastOneGraph(using: modelContext)

        // Active graph setzen (falls leer / kaputt)
        if UUID(uuidString: activeGraphIDString) == nil {
            activeGraphIDString = defaultGraph.id.uuidString
        }

        // Legacy Records in den Default-Graph schieben
        GraphBootstrap.migrateLegacyRecordsIfNeeded(defaultGraphID: defaultGraph.id, using: modelContext)

        // Backfill stored notes search indices (notesFolded) for existing data
        GraphBootstrap.backfillFoldedNotesIfNeeded(using: modelContext)
    }

    @MainActor
    func enforceLockIfNeeded() async {
        graphLock.enforceActiveGraphLockIfNeeded(using: modelContext)
    }
}
