import Foundation
import Testing
@testable import BrainMesh

struct EntitiesHomeSearchEmptyStateTests {

    @Test
    func emptyStateCopyMentionsCommandCenterScope() {
        let copy = EntitiesHomeSearchEmptyStateBuilder.copy(for: "Atlas")

        #expect(copy.title == "Keine Treffer")
        #expect(copy.message.contains("Entität"))
        #expect(copy.message.contains("Attribut"))
        #expect(copy.message.contains("Details"))
        #expect(copy.message.contains("Links"))
        #expect(copy.message.contains("Anhänge"))
        #expect(copy.actionTitle == "Mehr im Command Center suchen")
        #expect(copy.commandCenterQuery == "Atlas")
    }

    @Test
    func emptyStateCopyTrimsCommandCenterQuery() {
        let copy = EntitiesHomeSearchEmptyStateBuilder.copy(for: "  Atlas  ")

        #expect(copy.commandCenterQuery == "Atlas")
        #expect(copy.message.contains("Atlas"))
    }
}
