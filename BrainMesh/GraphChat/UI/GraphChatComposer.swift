//
//  GraphChatComposer.swift
//  BrainMesh
//
//  Multiline composer with deterministic send and cancellation controls.
//

import SwiftUI

struct GraphChatComposer: View {
    @Binding var text: String

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
                Button(action: onCancel) {
                    Image(systemName: "stop.fill")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Antwort abbrechen")
                .accessibilityHint("Beendet die laufende On-Device-Generierung.")
            } else {
                Button(action: onSend) {
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
    }
}
