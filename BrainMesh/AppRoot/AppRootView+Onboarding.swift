//
//  AppRootView+Onboarding.swift
//  BrainMesh
//

import Foundation

extension AppRootView {

    @MainActor
    func maybePresentOnboardingIfNeeded() async {
        // If the active graph is locked, don't pop onboarding on top.
        guard graphLock.activeRequest == nil else { return }

        guard onboardingHidden == false else { return }
        guard onboardingCompleted == false else { return }
        guard onboardingAutoShown == false else { return }

        let gid = UUID(uuidString: activeGraphIDString)
        let progress = OnboardingProgress.compute(using: modelContext, activeGraphID: gid)

        // Wenn der User schon Daten hat (z.B. Update), niemals automatisch aufploppen.
        onboardingAutoShown = true
        guard progress.completedSteps == 0 else { return }

        onboarding.isPresented = true
    }
}
