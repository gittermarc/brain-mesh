//
//  HelpSupportView.swift
//  BrainMesh
//
//  Created by Marc Fechner on 26.02.26.
//

import SwiftUI

struct HelpSupportView: View {
    @EnvironmentObject var onboarding: OnboardingCoordinator

    @State var showDetailsIntro: Bool = false

    var body: some View {
        List {
            helpSection
            infoSection
            SettingsAboutSection()
        }
        .navigationTitle("Hilfe & Support")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showDetailsIntro) {
            DetailsOnboardingSheetView()
        }
    }
}

#Preview {
    NavigationStack {
        HelpSupportView()
            .environmentObject(OnboardingCoordinator())
    }
}
