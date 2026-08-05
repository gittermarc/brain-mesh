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
    func storageMode_recoveryBlocksPersistentDataAccessAndExplainsSafety() {
        let mode = SyncRuntime.StorageMode.recovery

        #expect(mode.title == "Datenzugriff geschützt")
        #expect(mode.detail.contains("kein leerer Ersatzspeicher") == true)
        #expect(mode.trustHint.contains("weder gelöscht noch überschrieben") == true)
        #expect(mode.allowsPersistentDataAccess == false)
    }

    @Test
    func storageBootstrapFailureExposesOnlyDomainAndCode() {
        let failure = SyncRuntime.StorageBootstrapFailure(
            domain: "NSCocoaErrorDomain",
            code: 134_110
        )

        #expect(failure.reference == "NSCocoaErrorDomain (134110)")
        #expect(Mirror(reflecting: failure).children.count == 2)
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
