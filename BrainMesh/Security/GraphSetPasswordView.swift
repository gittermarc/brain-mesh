//
//  GraphSetPasswordView.swift
//  BrainMesh
//
//  Created by Marc Fechner on 11.02.26.
//

import SwiftUI
import SwiftData
import Combine

struct GraphSetPasswordView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var graphLock: GraphLockCoordinator

    @Bindable var graph: MetaGraph

    @State private var password1: String = ""
    @State private var password2: String = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Neues Passwort", text: $password1)
                        .textContentType(.newPassword)

                    SecureField("Passwort wiederholen", text: $password2)
                        .textContentType(.newPassword)
                } header: {
                    Text("Passwort setzen")
                } footer: {
                    Text("Wir speichern dein Passwort nicht im Klartext – nur einen Hash (mit Salt).")
                        .font(.footnote)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Passwort")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        savePassword()
                    }
                }
            }
        }
    }

    private func savePassword() {
        errorMessage = nil

        let p1 = password1.trimmingCharacters(in: .whitespacesAndNewlines)
        let p2 = password2.trimmingCharacters(in: .whitespacesAndNewlines)

        guard p1.count >= 4 else {
            errorMessage = "Bitte mindestens 4 Zeichen."
            return
        }

        guard p1 == p2 else {
            errorMessage = "Die Passwörter stimmen nicht überein."
            return
        }

        guard let hash = GraphLockCrypto.makePasswordHash(password: p1) else {
            errorMessage = "Konnte Passwort nicht sichern."
            return
        }

        graph.passwordSaltB64 = hash.saltB64
        graph.passwordHashB64 = hash.hashB64
        graph.passwordIterations = hash.iterations
        graph.lockPasswordEnabled = true

        // Wenn Passwort geändert wird, sollte der Graph neu entsperrt werden.
        graphLock.lock(graphID: graph.id)

        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
