//
//  StatsComponents+Typography.swift
//  BrainMesh
//

import Foundation

// MARK: - Formatting helpers

func formatBytes(_ bytes: Int64?) -> String? {
    guard let bytes else { return nil }
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
}

func formatInt(_ value: Int?) -> String {
    guard let value else { return "—" }
    return "\(value)"
}

func formatInt(_ a: Int?, plus b: Int?) -> String {
    guard let a, let b else { return "—" }
    return "\(a + b)"
}

func formatRatio(numerator: Int, denominator: Int) -> String {
    if denominator <= 0 { return "—" }
    let value = Double(numerator) / Double(denominator)
    let rounded = (value * 100).rounded() / 100
    return "\(rounded)"
}
