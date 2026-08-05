//
//  AppRootView+ScenePhase.swift
//  BrainMesh
//

import Foundation
import SwiftUI

nonisolated enum GraphSearchIndexForegroundReconciliationPolicy {
    private static let unsetGraphID = UUID(
        uuidString: "00000000-0000-0000-0000-000000000000"
    )!

    static func scope(
        activeGraphIDString: String,
        isSystemModalPresented: Bool,
        hasActiveGraphLockRequest: Bool
    ) -> GraphScope? {
        guard isSystemModalPresented == false,
            hasActiveGraphLockRequest == false,
            let graphID = UUID(uuidString: activeGraphIDString),
            graphID != unsetGraphID
        else {
            return nil
        }
        return GraphScope(graphID: graphID)
    }
}

extension AppRootView {

    func handleScenePhaseChange(_ newPhase: ScenePhase) {
        observedScenePhase = newPhase

        if newPhase == .active {
            cancelPendingBackgroundLock()
            // If a system picker is currently presented, avoid running
            // foreground work that can disrupt it (especially after Face ID prompts).
            guard systemModals.isSystemModalPresented == false else { return }
            Task { await handleBecameActive() }
        } else if newPhase == .background {
            cancelSearchIndexForegroundMaintenance()
            // Sensitive chat state is hidden immediately so it cannot remain in an app-switcher snapshot.
            // The graph lock itself keeps its existing debounce to avoid disrupting system pickers.
            graphChatSessionStore.handleSecurityLock()
            graphChatLaunchCoordinator.handleSecurityLock(graphID: nil)
            graphCopilotWorkspaceCoordinator.clearTransientState()

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

    func cancelPendingBackgroundLock() {
        pendingBackgroundLockTask?.cancel()
        pendingBackgroundLockTask = nil
    }

    func scheduleDebouncedBackgroundLock() {
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
                while observedScenePhase == .background && systemModals.isSystemModalPresented
                    && elapsed < graceSeconds
                {
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

    func scheduleSearchIndexForegroundReconciliation(
        invalidateSearchSourceRevision: Bool = false
    ) {
        let scope = observedScenePhase == .active
            ? GraphSearchIndexForegroundReconciliationPolicy.scope(
                activeGraphIDString: activeGraphIDString,
                isSystemModalPresented: systemModals.isSystemModalPresented,
                hasActiveGraphLockRequest: graphLock.activeRequest != nil
            )
            : nil
        guard scope != nil || invalidateSearchSourceRevision else {
            return
        }

        cancelSearchIndexForegroundMaintenance()
        searchIndexForegroundMaintenanceTask = Task(priority: .utility) {
            if invalidateSearchSourceRevision {
                await GraphMutationEventBus.shared
                    .recordExternalSearchSourceChange()
            }
            guard let scope else { return }
            guard Task.isCancelled == false else { return }
            _ = await GraphSearchIndexReconciler.shared.performMaintenance(
                scope: scope,
                reason: .foreground
            )
            guard Task.isCancelled == false else { return }
            let schemaChanged = (try? await GraphSchemaService.shared
                .reconcileExternalChanges(in: scope)) ?? false
            guard Task.isCancelled == false else { return }
            if schemaChanged {
                await MainActor.run {
                    graphChatSessionStore
                        .handleExternalSchemaReconciliation(
                            graphID: scope.graphID
                        )
                }
            }
        }
    }

    func cancelSearchIndexForegroundMaintenance() {
        searchIndexForegroundMaintenanceTask?.cancel()
        searchIndexForegroundMaintenanceTask = nil
    }
}
