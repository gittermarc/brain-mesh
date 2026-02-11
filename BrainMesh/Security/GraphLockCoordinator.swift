//
//  GraphLockCoordinator.swift
//  BrainMesh
//
//  Created by Marc Fechner on 11.02.26.
//

import SwiftUI
import SwiftData
import LocalAuthentication
import Combine

@MainActor
final class GraphLockCoordinator: ObservableObject {

    @Published var activeRequest: GraphLockRequest?

    @AppStorage("BMActiveGraphID") private var activeGraphIDString: String = ""

    private var unlockedGraphIDs: Set<UUID> = []

    func isUnlocked(graphID: UUID) -> Bool {
        unlockedGraphIDs.contains(graphID)
    }

    func lock(graphID: UUID) {
        unlockedGraphIDs.remove(graphID)
    }

    func lockAll() {
        unlockedGraphIDs.removeAll()
    }

    func requestUnlock(
        for graph: MetaGraph,
        purpose: GraphLockPurpose,
        fallbackGraphID: UUID? = nil,
        onSuccess: (@MainActor () -> Void)? = nil,
        onCancel: (@MainActor () -> Void)? = nil
    ) {
        guard graph.isProtected else { return }
        guard isUnlocked(graphID: graph.id) == false else { return }

        if let existing = activeRequest {
            if existing.graphID == graph.id { return }
            // Already presenting a request – do not stack.
            return
        }

        let req = GraphLockRequest(
            graphID: graph.id,
            graphName: graph.name,
            purpose: purpose,
            allowBiometrics: graph.lockBiometricsEnabled,
            allowPassword: (graph.lockPasswordEnabled && graph.isPasswordConfigured),
            fallbackGraphID: fallbackGraphID,
            onSuccess: onSuccess,
            onCancel: onCancel
        )
        activeRequest = req
    }

    func completeCurrentRequest(success: Bool) {
        guard let req = activeRequest else { return }

        if success {
            unlockedGraphIDs.insert(req.graphID)
            req.onSuccess?()
        } else {
            req.onCancel?()
        }

        activeRequest = nil
    }

    func switchActiveGraph(to id: UUID) {
        activeGraphIDString = id.uuidString
    }

    func enforceActiveGraphLockIfNeeded(using modelContext: ModelContext) {
        guard let gid = UUID(uuidString: activeGraphIDString) else { return }
        guard isUnlocked(graphID: gid) == false else { return }

        let graphFD = FetchDescriptor<MetaGraph>(
            predicate: #Predicate { g in g.id == gid }
        )
        guard let graph = try? modelContext.fetch(graphFD).first else { return }
        guard graph.isProtected else { return }

        let fallback = findFallbackGraphID(excluding: gid, using: modelContext)

        let cancelClosure: (@MainActor () -> Void)?
        if let fallback {
            cancelClosure = { [weak self] in
                self?.switchActiveGraph(to: fallback)
            }
        } else {
            cancelClosure = nil
        }

        requestUnlock(
            for: graph,
            purpose: .enterActiveGraph,
            fallbackGraphID: fallback,
            onSuccess: nil,
            onCancel: cancelClosure
        )
    }

    func canUseBiometrics() -> (available: Bool, label: String) {
        let ctx = LAContext()
        var err: NSError?

        // Use a policy that can fall back to device passcode to avoid lock-outs on devices without biometrics.
        let ok = ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err)

        // Determine the best label we can show.
        let label: String
        let biometry = LAContext()
        var bioErr: NSError?
        _ = biometry.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &bioErr)

        switch biometry.biometryType {
        case .faceID: label = "Face ID"
        case .touchID: label = "Touch ID"
        default: label = "Gerätecode"
        }

        return (ok, label)
    }

    func evaluateBiometrics(localizedReason: String) async -> Bool {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { return false }

        return await withCheckedContinuation { continuation in
            ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: localizedReason) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }

    func verifyPassword(_ password: String, for graph: MetaGraph) -> Bool {
        guard graph.isPasswordConfigured,
              let salt = graph.passwordSaltB64,
              let hash = graph.passwordHashB64 else {
            return false
        }
        return GraphLockCrypto.verifyPassword(
            password: password,
            saltB64: salt,
            hashB64: hash,
            iterations: graph.passwordIterations
        )
    }

    private func findFallbackGraphID(excluding graphID: UUID, using modelContext: ModelContext) -> UUID? {
        let fd = FetchDescriptor<MetaGraph>(
            sortBy: [SortDescriptor(\MetaGraph.createdAt, order: .forward)]
        )

        guard let graphs = try? modelContext.fetch(fd) else { return nil }

        var seen = Set<UUID>()
        let unique = graphs.filter { seen.insert($0.id).inserted }

        for g in unique where g.id != graphID {
            if g.isProtected == false {
                return g.id
            }
            if isUnlocked(graphID: g.id) {
                return g.id
            }
        }

        return nil
    }
}
