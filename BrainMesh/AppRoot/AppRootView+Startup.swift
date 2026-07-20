//
//  AppRootView+Startup.swift
//  BrainMesh
//

import Foundation
import os

private let appRootStartupLog = Logger(subsystem: "BrainMesh", category: "AppRootStartup")

extension AppRootView {

    @MainActor
    func runStartupIfNeeded() async {
        guard didRunStartupOnce == false else {
            await maybePresentOnboardingIfNeeded()
            return
        }
        guard isRunningStartup == false else {
            return
        }

        isRunningStartup = true
        defer { isRunningStartup = false }

        do {
            try await AppLoadersConfigurator.waitUntilReady()
        } catch is CancellationError {
            appRootStartupLog.notice("startup cancelled while waiting for service readiness")
            return
        } catch {
            let nsError = error as NSError
            appRootStartupLog.error(
                "startup readiness failed domain=\(nsError.domain, privacy: .public) code=\(nsError.code)"
            )
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
        if didRunStartupOnce == false {
            await runStartupIfNeeded()
            return
        }

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
        do {
            let defaultGraph = try await GraphBootstrap.ensureAtLeastOneGraph(
                using: modelContext
            )

            if UUID(uuidString: activeGraphIDString) == nil {
                activeGraphIDString = defaultGraph.id.uuidString
            }

            try await GraphBootstrap.migrateLegacyRecordsIfNeeded(
                defaultGraphID: defaultGraph.id,
                using: modelContext
            )
            try await GraphBootstrap.backfillFoldedNotesIfNeeded(
                using: modelContext
            )
        } catch is CancellationError {
            appRootStartupLog.notice("graph bootstrap cancelled")
        } catch {
            let nsError = error as NSError
            appRootStartupLog.error(
                "graph bootstrap failed domain=\(nsError.domain, privacy: .public) code=\(nsError.code)"
            )
        }
    }

    @MainActor
    func enforceLockIfNeeded() async {
        graphLock.enforceActiveGraphLockIfNeeded(using: modelContext)
    }
}
