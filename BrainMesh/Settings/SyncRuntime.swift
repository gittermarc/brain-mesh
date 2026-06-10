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
            case .cloudKit:
                return "iCloud aktiv"
            case .localOnly:
                return "Nur lokal"
            }
        }

        var detail: String {
            switch self {
            case .cloudKit:
                return "BrainMesh nutzt SwiftData mit CloudKit in deiner privaten iCloud-Datenbank. Änderungen können auf deinen Geräten abgeglichen werden."
            case .localOnly:
                return "BrainMesh nutzt den lokalen Speicher dieses Geräts. Änderungen erscheinen nicht automatisch auf anderen Geräten."
            }
        }

        var trustHint: String {
            switch self {
            case .cloudKit:
                return "iCloud-Sync hält Geräte auf dem gleichen Stand, ersetzt aber kein bewusst gespeichertes Backup oder einen Export."
            case .localOnly:
                return "Lokaler Speicher ist kein Fehlerzustand: Deine Daten bleiben auf diesem Gerät erhalten, bis iCloud wieder verfügbar ist oder die App wieder mit CloudKit startet."
            }
        }
    }

    struct AccountStatusDescription: Equatable, Sendable {
        let title: String
        let detail: String
    }

    static let shared = SyncRuntime()

    /// Must match `BrainMesh.entitlements`.
    static let containerIdentifier = "iCloud.de.marcfechner.BrainMesh"

    @Published private(set) var storageMode: StorageMode = .cloudKit

    @Published private(set) var iCloudAccountStatusText: String = "Noch nicht geprüft"
    @Published private(set) var iCloudAccountStatusDetail: String = "Tippe auf Status prüfen oder öffne diesen Bereich erneut, um den iCloud-Kontostatus zu aktualisieren."

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
            let description = Self.describe(status)
            iCloudAccountStatusText = description.title
            iCloudAccountStatusDetail = description.detail
        } catch {
#if DEBUG
            print("iCloud account status check failed: \(error)")
#endif
            iCloudAccountStatusText = "Prüfung fehlgeschlagen"
            iCloudAccountStatusDetail = "Der iCloud-Status konnte gerade nicht geprüft werden. Deine lokalen Daten bleiben unverändert. Prüfe Verbindung, Apple-ID und iCloud-Einstellungen und versuche es erneut."
        }
    }

    static func describe(_ status: CKAccountStatus) -> AccountStatusDescription {
        switch status {
        case .available:
            return AccountStatusDescription(
                title: "Verfügbar",
                detail: "Dieses Gerät ist mit iCloud verbunden. Wenn BrainMesh im iCloud-Modus läuft, können Änderungen über deine private iCloud synchronisiert werden."
            )
        case .noAccount:
            return AccountStatusDescription(
                title: "Kein iCloud-Account",
                detail: "Auf diesem Gerät ist kein iCloud-Account aktiv. BrainMesh kann lokal weiter genutzt werden, aber Änderungen werden nicht automatisch mit anderen Geräten abgeglichen."
            )
        case .restricted:
            return AccountStatusDescription(
                title: "Eingeschränkt",
                detail: "iCloud ist auf diesem Gerät durch Einstellungen, Familienfreigabe, Geräteverwaltung oder Bildschirmzeit eingeschränkt. Prüfe die iOS-Einstellungen."
            )
        case .couldNotDetermine:
            return AccountStatusDescription(
                title: "Unklar",
                detail: "Der iCloud-Status konnte gerade nicht eindeutig bestimmt werden. Prüfe später erneut, wenn die Verbindung stabil ist."
            )
        case .temporarilyUnavailable:
            return AccountStatusDescription(
                title: "Vorübergehend nicht verfügbar",
                detail: "iCloud ist aktuell nicht erreichbar. Deine lokalen Daten bleiben erhalten; der Abgleich kann später weiterlaufen."
            )
        @unknown default:
            return AccountStatusDescription(
                title: "Unbekannt",
                detail: "iCloud hat einen unbekannten Status gemeldet. Deine lokalen Daten bleiben erhalten. Prüfe die iOS-Einstellungen und versuche es erneut."
            )
        }
    }
}
