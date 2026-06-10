import Foundation
import Testing
@testable import BrainMesh

struct GraphStatsUserFacingErrorMessageTests {

    @Test
    func make_unknownDashboardError_returnsRecoverableDashboardMessage() {
        let error = NSError(domain: "BrainMeshTests.Unknown", code: 42)

        let message = GraphStatsUserFacingErrorMessage.make(for: error, context: .dashboard)

        #expect(message?.title == "Statistiken konnten nicht geladen werden")
        #expect(message?.message.contains("Unerwartetes") == true)
        #expect(message?.recoverySuggestion.contains("Erneut laden") == true)
    }

    @Test
    func make_storageRelatedError_returnsStorageRecoveryMessage() {
        let error = NSError(domain: NSCocoaErrorDomain, code: 134060)

        let message = GraphStatsUserFacingErrorMessage.make(for: error, context: .dashboard)

        #expect(message?.title == "Statistiken konnten nicht geladen werden")
        #expect(message?.message.contains("lokalen Datenspeicher") == true)
        #expect(message?.recoverySuggestion.contains("Sync & Wartung") == true)
        #expect(message?.systemImage == "externaldrive.badge.exclamationmark")
    }

    @Test
    func make_swiftDataLikeError_returnsPerGraphStorageMessage() {
        let error = NSError(domain: "SwiftData.ModelContext", code: 7)

        let message = GraphStatsUserFacingErrorMessage.make(for: error, context: .perGraph)

        #expect(message?.title == "Graph-Zahlen konnten nicht geladen werden")
        #expect(message?.message.contains("Datenspeicher") == true)
        #expect(message?.recoverySuggestion.contains("Erneut laden") == true)
    }

    @Test
    func make_cancellationError_returnsNil() {
        let message = GraphStatsUserFacingErrorMessage.make(for: CancellationError(), context: .dashboard)

        #expect(message == nil)
    }
}
