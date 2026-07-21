import Testing
@testable import BrainMesh

struct GraphChatComposerStateTests {
    @Test
    func whitespaceOnlyInputCannotBeSent() {
        let state = GraphChatComposerState(text: "  \n\t  ")

        #expect(state.canSend == false)
        #expect(state.submissionText() == nil)
    }

    @Test
    func normalizedNonEmptyInputCanBeSent() {
        let state = GraphChatComposerState(text: "  Welche Projekte sind offen?  \n")

        #expect(state.canSend)
        #expect(state.submissionText() == "Welche Projekte sind offen?")
    }

    @Test
    func generationDisablesSendAndEnablesCancel() {
        let state = GraphChatComposerState(
            text: "Welche Projekte sind offen?",
            isGenerating: true
        )

        #expect(state.canSend == false)
        #expect(state.canCancel)
        #expect(state.submissionText() == nil)
    }
}
