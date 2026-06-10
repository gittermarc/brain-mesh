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
            supportIntroSection
            helpSection
            infoSection
            SettingsAboutSection {
                sheet = .inAppGuide
            }
            SettingsLegalInformationSection()
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


extension HelpSupportView {
    var supportIntroSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "lifepreserver")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)

                    Text("Hilfe, Sicherheit und Orientierung")
                        .font(.headline)
                }

                Text("Hier findest du den Einstieg, die ausführliche Anleitung, Versionsinfos und rechtliche Hinweise. Für Sync- oder Cache-Fragen ist der Bereich Sync & Wartung der richtige Ort.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
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
