//
//  SettingsView+State.swift
//  BrainMesh
//
//  Created by Marc Fechner on 10.02.26.
//

import Foundation
import SwiftUI

extension SettingsView {
    var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
    }

    var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "–"
    }
}
