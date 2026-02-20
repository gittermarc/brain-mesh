//
//  SyncRuntime.swift
//  BrainMesh
//
//  Created by Marc Fechner on 19.02.26.
//

import Foundation
import CloudKit
import Combine

/// Small runtime helper to surface whether SwiftData is running with CloudKit enabled
/// and whether the current device has an iCloud account available.
///
/// Motivation: When CloudKit init fails (e.g. entitlements/signing mismatch), the app may fall back
/// to local-only storage in Release builds. That looks like "Sync is broken".
@MainActor
final class SyncRuntime: ObservableObject {

    enum StorageMode: String {
        case cloudKit
        case localOnly

        var title: String {
            switch self {
            case .cloudKit: return "iCloud aktiv"
            case .localOnly: return "Nur lokal"
            }
        }

        var detail: String {
            switch self {
            case .cloudKit: return "SwiftData sync über CloudKit (Private DB)."
            case .localOnly: return "SwiftData ohne CloudKit (kein Sync)."
            }
        }
    }

    static let shared = SyncRuntime()

    /// Must match `BrainMesh.entitlements`.
    static let containerIdentifier = "iCloud.de.marcfechner.BrainMesh"

    @Published private(set) var storageMode: StorageMode = .cloudKit

    @Published private(set) var iCloudAccountStatusText: String = "—"

    private init() {}

    func setStorageMode(_ mode: StorageMode) {
        storageMode = mode
    }

    /// Fetches iCloud account status for the configured container.
    /// This does NOT guarantee CloudKit syncing works, but it quickly catches the most common issues:
    /// - Not signed into iCloud
    /// - iCloud restricted / temporarily unavailable
    func refreshAccountStatus() async {
        let container = CKContainer(identifier: Self.containerIdentifier)
        do {
            let status = try await container.accountStatus()
            iCloudAccountStatusText = Self.describe(status)
        } catch {
            iCloudAccountStatusText = "Fehler: \(error.localizedDescription)"
        }
    }

    private static func describe(_ status: CKAccountStatus) -> String {
        switch status {
        case .available: return "Verfügbar"
        case .noAccount: return "Kein iCloud-Account"
        case .restricted: return "Eingeschränkt"
        case .couldNotDetermine: return "Unklar"
        @unknown default: return "Unbekannt"
        }
    }
}
