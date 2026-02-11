//
//  GraphLockRequest.swift
//  BrainMesh
//
//  Created by Marc Fechner on 11.02.26.
//

import Foundation

enum GraphLockPurpose: String, Sendable {
    case switchGraph
    case enterActiveGraph
}

final class GraphLockRequest: Identifiable {
    let id: UUID = UUID()

    let graphID: UUID
    let graphName: String
    let purpose: GraphLockPurpose

    let allowBiometrics: Bool
    let allowPassword: Bool

    /// Optional: When the user cancels while the active graph is locked,
    /// we can switch to a safe fallback graph (unprotected or already unlocked).
    let fallbackGraphID: UUID?

    let onSuccess: (@MainActor () -> Void)?
    let onCancel: (@MainActor () -> Void)?

    init(
        graphID: UUID,
        graphName: String,
        purpose: GraphLockPurpose,
        allowBiometrics: Bool,
        allowPassword: Bool,
        fallbackGraphID: UUID?,
        onSuccess: (@MainActor () -> Void)?,
        onCancel: (@MainActor () -> Void)?
    ) {
        self.graphID = graphID
        self.graphName = graphName
        self.purpose = purpose
        self.allowBiometrics = allowBiometrics
        self.allowPassword = allowPassword
        self.fallbackGraphID = fallbackGraphID
        self.onSuccess = onSuccess
        self.onCancel = onCancel
    }
}
