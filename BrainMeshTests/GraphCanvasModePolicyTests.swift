import Testing
@testable import BrainMesh

struct GraphCanvasModePolicyTests {

    @Test
    func exploreModeDoesNotAllowLayoutEditing() {
        let policy = GraphCanvasModePolicy.policy(for: .explore)

        #expect(policy.allowsNodeDragging == false)
        #expect(policy.allowsDoubleTapPinning == false)
        #expect(policy.allowsLayoutEditing == false)
        #expect(policy.usesQuietChrome == false)
    }

    @Test
    func organizeModeAllowsNodeDragAndPinning() {
        let policy = GraphCanvasModePolicy.policy(for: .organize)

        #expect(policy.allowsNodeDragging == true)
        #expect(policy.allowsDoubleTapPinning == true)
        #expect(policy.allowsLayoutEditing == true)
        #expect(policy.usesQuietChrome == false)
    }

    @Test
    func presentModeDoesNotAllowLayoutEditing() {
        let policy = GraphCanvasModePolicy.policy(for: .present)

        #expect(policy.allowsNodeDragging == false)
        #expect(policy.allowsDoubleTapPinning == false)
        #expect(policy.allowsLayoutEditing == false)
        #expect(policy.usesQuietChrome == true)
    }

    @Test
    func legacyEditRawValueMapsToOrganize() {
        #expect(WorkMode.canonical(rawValue: "edit") == .organize)
        #expect(WorkMode.canonical(rawValue: "explore") == .explore)
        #expect(WorkMode.canonical(rawValue: "present") == .present)
        #expect(WorkMode.canonical(rawValue: "unknown") == .explore)
    }
}
