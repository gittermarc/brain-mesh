//
//  SettingsLegalInformationSection.swift
//  BrainMesh
//
//  Created by OpenAI on 05.03.26.
//

import Foundation
import SwiftUI

struct SettingsLegalInformationSection: View {
    private let eulaURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    private let privacyPolicyURL = URL(string: "https://apps.marcfechner.de/apps/brainmesh/datenschutzrichtlinie/")!

    var body: some View {
        Section("Rechtliche Informationen") {
            Link(destination: eulaURL) {
                Label("EULA", systemImage: "doc.text")
            }

            Link(destination: privacyPolicyURL) {
                Label("Datenschutz-Richtlinie", systemImage: "hand.raised")
            }
        }
    }
}

#Preview {
    List {
        SettingsLegalInformationSection()
    }
}
