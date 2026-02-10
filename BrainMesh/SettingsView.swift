//
//  SettingsView.swift
//  BrainMesh
//
//  Created by Marc Fechner on 10.02.26.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var onboarding: OnboardingCoordinator

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "–"
    }

    var body: some View {
        List {
            Section("Hilfe") {
                Button {
                    onboarding.isPresented = true
                } label: {
                    Label("Onboarding anzeigen", systemImage: "questionmark.circle")
                }
            }

            Section("Darstellung") {
                NavigationLink {
                    DisplaySettingsView()
                } label: {
                    Label("Darstellung", systemImage: "paintpalette")
                }
            }

            Section("Info") {
                LabeledContent("Version", value: appVersion)
                LabeledContent("Build", value: buildNumber)
            }
        }
        .navigationTitle("Einstellungen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Fertig") { dismiss() }
            }
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(OnboardingCoordinator())
    }
}
