//
//  HelpSupportView+InfoSection.swift
//  BrainMesh
//
//  Created by Marc Fechner on 10.02.26.
//

import SwiftUI

extension HelpSupportView {
    var infoSection: some View {
        Section("App-Info") {
            LabeledContent("Version", value: appVersion)
            LabeledContent("Build", value: buildNumber)

            Text("Halte BrainMesh aktuell, damit Sync-, Import- und Wartungsverbesserungen zuverlässig auf allen Geräten ankommen.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
