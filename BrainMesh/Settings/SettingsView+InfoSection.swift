//
//  SettingsView+InfoSection.swift
//  BrainMesh
//
//  Created by Marc Fechner on 10.02.26.
//

import SwiftUI

extension SettingsView {
    var infoSection: some View {
        Section("Info") {
            LabeledContent("Version", value: appVersion)
            LabeledContent("Build", value: buildNumber)
        }
    }
}
