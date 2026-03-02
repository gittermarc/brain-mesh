//
//  SettingsAboutSection.swift
//  BrainMesh
//
//  Created by Marc Fechner on 12.02.26.
//

import Foundation
import SwiftUI

struct SettingsAboutSection: View {
    private let supportURL = URL(string: "https://apps.marcfechner.de/apps/brainmesh/anleitung-faq/")!

    var onOpenInAppGuide: () -> Void

    init(onOpenInAppGuide: @escaping () -> Void = {}) {
        self.onOpenInAppGuide = onOpenInAppGuide
    }

    var body: some View {
        Section("Über") {
            Text(
                "BrainMesh ist dein persönlicher Wissensraum als Graph: Entitäten, Attribute und Links – inklusive Bildern und Anhängen. " +
                "Du kannst mehrere Graphen anlegen und so Themen sauber trennen. " +
                "Wenn du irgendwo hängenbleibst, findest du hier Hilfe, Tipps und ein FAQ."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Link(destination: supportURL) {
                Label("Hilfe & Support", systemImage: "lifepreserver")
            }

            Button {
                onOpenInAppGuide()
            } label: {
                Label("Anleitung in der App", systemImage: "book.pages")
            }
        }
    }
}

#Preview {
    List {
        SettingsAboutSection()
    }
}
