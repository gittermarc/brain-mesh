//
//  HelpSupportView.swift
//  BrainMesh
//
//  Created by Marc Fechner on 26.02.26.
//

import SwiftUI

struct HelpSupportView: View {
    @EnvironmentObject var onboarding: OnboardingCoordinator

    @State var sheet: HelpSupportSheet?

    var body: some View {
        List {
            helpSection
            infoSection
            SettingsAboutSection {
                sheet = .inAppGuide
            }
        }
        .navigationTitle("Hilfe & Support")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sheet) { item in
            switch item {
            case .detailsIntro:
                DetailsOnboardingSheetView()
            case .inAppGuide:
                NavigationStack {
                    BrainMeshGuideView()
                }
            }
        }
    }
}

enum HelpSupportSheet: Identifiable {
    case detailsIntro
    case inAppGuide

    var id: Int {
        switch self {
        case .detailsIntro: return 1
        case .inAppGuide: return 2
        }
    }
}

#Preview {
    NavigationStack {
        HelpSupportView()
            .environmentObject(OnboardingCoordinator())
    }
}
