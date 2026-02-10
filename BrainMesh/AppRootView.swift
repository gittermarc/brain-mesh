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

    var body: some View {
        ContentView()
            .tint(appearance.appTintColor)
            .preferredColorScheme(appearance.preferredColorScheme)
            .task {
                await bootstrapGraphing()
                await ImageHydrator.hydrateAll(using: modelContext)
                await maybePresentOnboardingIfNeeded()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Task {
                        await bootstrapGraphing()
                        await ImageHydrator.hydrateAll(using: modelContext)
                        await maybePresentOnboardingIfNeeded()
                    }
                }
            }
            .sheet(isPresented: $onboarding.isPresented) {
                OnboardingSheetView()
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
