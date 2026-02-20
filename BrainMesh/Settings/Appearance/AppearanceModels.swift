//
//  AppearanceModels.swift
//  BrainMesh
//
//  Created by Marc Fechner on 10.02.26.
//

import SwiftUI
import UIKit

// MARK: - ColorRef

/// Persistable color representation (sRGB RGBA, 0...1).
///
/// Note: In PR 01 we split the former monolithic AppearanceModels.swift into multiple files.
/// This file intentionally keeps only the shared color persistence helper used across the
/// appearance models.
struct ColorRef: Codable, Hashable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = ColorRef.clamp01(red)
        self.green = ColorRef.clamp01(green)
        self.blue = ColorRef.clamp01(blue)
        self.alpha = ColorRef.clamp01(alpha)
    }

    init(_ color: Color) {
        let ui = UIColor(color)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0

        if ui.getRed(&r, green: &g, blue: &b, alpha: &a) {
            self.init(red: Double(r), green: Double(g), blue: Double(b), alpha: Double(a))
        } else {
            // Fallback: try CGColor components (can be grayscale).
            let comps = ui.cgColor.components ?? [0, 0, 0, 1]
            if comps.count >= 4 {
                self.init(red: Double(comps[0]), green: Double(comps[1]), blue: Double(comps[2]), alpha: Double(comps[3]))
            } else if comps.count == 2 {
                self.init(red: Double(comps[0]), green: Double(comps[0]), blue: Double(comps[0]), alpha: Double(comps[1]))
            } else {
                self.init(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
            }
        }
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    var hexRGBA: String {
        let r = Int((red * 255.0).rounded())
        let g = Int((green * 255.0).rounded())
        let b = Int((blue * 255.0).rounded())
        let a = Int((alpha * 255.0).rounded())
        return String(format: "#%02X%02X%02X%02X", r, g, b, a)
    }

    private static func clamp01(_ v: Double) -> Double {
        min(1.0, max(0.0, v))
    }
}
