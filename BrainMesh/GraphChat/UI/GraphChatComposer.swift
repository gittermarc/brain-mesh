//
//  GraphChatComposer.swift
//  BrainMesh
//
//  Multiline composer with deterministic send, cancellation, and keyboard dismissal controls.
//

import SwiftUI

struct GraphChatComposer: View {
    @Binding var text: String
    @FocusState private var isComposerFocused: Bool

    let isGenerating: Bool
    let canSend: Bool
    let onSend: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField(
                "Frage zu diesem Graphen",
                text: $text,
                axis: .vertical
            )
            .focused($isComposerFocused)
            .lineLimit(1...6)
            .textFieldStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 18))
            .submitLabel(.send)
            .onSubmit {
                guard canSend else {
                    return
                }
                isComposerFocused = false
                onSend()
            }
            .disabled(isGenerating)
            .accessibilityLabel("Frage an den Graph Chat")
            .accessibilityHint(
                isGenerating
                    ? "Die Eingabe ist während der laufenden Antwort deaktiviert."
                    : "Mehrzeilige Frage eingeben. Mit Befehl und Eingabetaste senden."
            )

            if isGenerating {
                Button {
                    isComposerFocused = false
                    onCancel()
                } label: {
                    Image(systemName: "stop.fill")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Antwort abbrechen")
                .accessibilityHint("Beendet die laufende On-Device-Generierung.")
            } else {
                Button {
                    isComposerFocused = false
                    onSend()
                } label: {
                    Image(systemName: "arrow.up")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(canSend == false)
                .keyboardShortcut(.return, modifiers: [.command])
                .accessibilityLabel("Frage senden")
                .accessibilityHint(
                    canSend
                        ? "Sendet die eingegebene Frage."
                        : "Gib zuerst eine Frage ein."
                )
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button {
                    isComposerFocused = false
                } label: {
                    Label("Tastatur ausblenden", systemImage: "keyboard.chevron.compact.down")
                }
                .accessibilityIdentifier("graph-chat-dismiss-keyboard")
            }
        }
    }
}
