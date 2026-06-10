import CloudKit
import Foundation
import Testing
@testable import BrainMesh

@MainActor
struct SyncRuntimeCopyTests {

    @Test
    func storageMode_cloudKitExplainsSyncAndBackupBoundary() {
        let mode = SyncRuntime.StorageMode.cloudKit

        #expect(mode.title == "iCloud aktiv")
        #expect(mode.detail.contains("CloudKit") == true)
        #expect(mode.trustHint.contains("ersetzt aber kein") == true)
    }

    @Test
    func storageMode_localOnlyExplainsDeviceScope() {
        let mode = SyncRuntime.StorageMode.localOnly

        #expect(mode.title == "Nur lokal")
        #expect(mode.detail.contains("lokalen Speicher") == true)
        #expect(mode.trustHint.contains("diesem Gerät") == true)
    }

    @Test
    func accountStatus_availableExplainsPrivateICloudSync() {
        let description = SyncRuntime.describe(.available)

        #expect(description.title == "Verfügbar")
        #expect(description.detail.contains("private iCloud") == true)
    }

    @Test
    func accountStatus_noAccountExplainsLocalUsage() {
        let description = SyncRuntime.describe(.noAccount)

        #expect(description.title == "Kein iCloud-Account")
        #expect(description.detail.contains("lokal weiter genutzt") == true)
    }
}
