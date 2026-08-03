//
//  GraphChatComposer.swift
//  BrainMesh
//
//  Multiline composer with deterministic send, edit, cancellation, and keyboard controls.
//

import SwiftUI

struct GraphChatComposer: View {
    @Binding var text: String
    @FocusState private var isComposerFocused: Bool

    let isGenerating: Bool
    let canSend: Bool
    let editingState: GraphChatEditingState?
    let isPerformingSessionMutation: Bool
    let focusRequestID: UUID?
    let onSend: () -> Void
    let onCancel: () -> Void
    let onCancelEditing: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if editingState != nil {
                HStack(spacing: 10) {
                    Label("Frühere Frage bearbeiten", systemImage: "pencil")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Button {
                        onCancelEditing()
                    } label: {
                        Label("Bearbeiten abbrechen", systemImage: "xmark")
                            .labelStyle(.iconOnly)
                            .frame(width: 36, height: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Bearbeiten abbrechen")
                    .accessibilityHint("Verwirft die Bearbeitung und lässt den bisherigen Verlauf unverändert.")
                }
                .accessibilityElement(children: .contain)
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField(
                    editingState == nil
                        ? "Frage zu diesem Graphen"
                        : "Geänderte Frage",
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
                .accessibilityLabel(
                    editingState == nil
                        ? "Frage an den Graph Chat"
                        : "Geänderte Frage an den Graph Chat"
                )
                .accessibilityHint(composerHint)

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
                    .accessibilityLabel(
                        editingState == nil
                            ? "Frage senden"
                            : "Geänderte Frage senden"
                    )
                    .accessibilityHint(sendHint)
                }
            }

            if isPerformingSessionMutation && isGenerating == false {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Laufende Chat-Aktion wird sauber abgeschlossen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
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
        .onChange(of: focusRequestID) { _, requestID in
            guard requestID != nil,
                  isGenerating == false,
                  isPerformingSessionMutation == false else {
                return
            }
            isComposerFocused = true
        }
    }

    private var composerHint: String {
        if isGenerating {
            return "Die Eingabe ist während der laufenden Antwort deaktiviert."
        }
        if editingState != nil {
            return "Beim Senden wird der bisherige Gesprächszweig ab dieser Frage ersetzt."
        }
        return "Mehrzeilige Frage eingeben. Mit Befehl und Eingabetaste senden."
    }

    private var sendHint: String {
        guard canSend else {
            return "Gib zuerst eine Frage ein und warte, bis laufende Chat-Aktionen abgeschlossen sind."
        }
        if editingState != nil {
            return "Setzt den Conversation State vor dieser Frage zurück und führt die geänderte Frage erneut aus."
        }
        return "Sendet die eingegebene Frage."
    }
}
