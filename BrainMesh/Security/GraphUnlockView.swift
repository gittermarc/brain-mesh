//
//  GraphUnlockView.swift
//  BrainMesh
//
//  Created by Marc Fechner on 11.02.26.
//

import SwiftUI
import SwiftData

struct GraphUnlockView: View {

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var graphLock: GraphLockCoordinator

    let request: GraphLockRequest

    @State private var password: String = ""
    @State private var errorMessage: String?
    @State private var isWorking: Bool = false

    @State private var biometricsAvailable: Bool = false
    @State private var biometricsLabel: String = "Biometrie"

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Spacer(minLength: 8)

                Image(systemName: "lock.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.secondary)

                VStack(spacing: 6) {
                    Text("Graph gesperrt")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text(request.graphName)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                }
                .padding(.horizontal)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                VStack(spacing: 12) {
                    if request.allowBiometrics, biometricsAvailable {
                        Button {
                            Task { await unlockWithBiometrics() }
                        } label: {
                            HStack {
                                Image(systemName: biometricsIcon)
                                Text("Mit \(biometricsLabel) entsperren")
                                Spacer()
                                if isWorking {
                                    ProgressView()
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isWorking)
                    }

                    if request.allowPassword {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Passwort")
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            SecureField("Passwort eingeben", text: $password)
                                .textContentType(.password)
                                .submitLabel(.go)
                                .onSubmit {
                                    Task { await unlockWithPassword() }
                                }

                            Button {
                                Task { await unlockWithPassword() }
                            } label: {
                                HStack {
                                    Text("Mit Passwort entsperren")
                                    Spacer()
                                    if isWorking {
                                        ProgressView()
                                    }
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(isWorking || password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        .padding()
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal)
                    }

                    if !request.allowBiometrics && !request.allowPassword {
                        Text("Für diesen Graph ist aktuell keine Entsperr-Methode verfügbar.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }

                Spacer(minLength: 20)
            }
            .padding(.top, 12)
            .navigationTitle("Entsperren")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if let _ = request.fallbackGraphID {
                        Button("Wechseln") {
                            graphLock.completeCurrentRequest(success: false)
                        }
                    } else if request.onCancel != nil {
                        Button("Abbrechen") {
                            graphLock.completeCurrentRequest(success: false)
                        }
                    }
                }
            }
            .interactiveDismissDisabled(true)
            .task {
                let info = graphLock.canUseBiometrics()
                biometricsAvailable = info.available
                biometricsLabel = info.label

                // Wenn keine Biometrics verfügbar sind, aber in der App ein Toggle gesetzt ist,
                // vermeiden wir eine "Nichts geht"-Situation: Nutzer kann immer noch per Passwort.
            }
        }
    }

    private var biometricsIcon: String {
        switch biometricsLabel {
        case "Face ID": return "faceid"
        case "Touch ID": return "touchid"
        default: return "key.fill"
        }
    }

    private func unlockWithBiometrics() async {
        guard isWorking == false else { return }
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }

        let ok = await graphLock.evaluateBiometrics(localizedReason: "Entsperre deinen geschützten Graph in BrainMesh.")
        if ok {
            graphLock.completeCurrentRequest(success: true)
        } else {
            errorMessage = "Biometrische Entsperrung fehlgeschlagen."
        }
    }

    @MainActor
    private func unlockWithPassword() async {
        guard isWorking == false else { return }
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }

        let cleaned = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.isEmpty == false else { return }

        // IMPORTANT:
        // Do not reference `request.graphID` directly inside `#Predicate`.
        // SwiftData's macro system can struggle to type-check predicates that
        // capture key paths into non-model structs (like `GraphLockRequest`).
        // Capturing a plain UUID value is safe.
        let graphID = request.graphID

        let fd = FetchDescriptor<MetaGraph>(
            predicate: #Predicate { g in g.id == graphID }
        )

        guard let graph = try? modelContext.fetch(fd).first else {
            errorMessage = "Graph nicht gefunden."
            return
        }

        if graphLock.verifyPassword(cleaned, for: graph) {
            graphLock.completeCurrentRequest(success: true)
        } else {
            errorMessage = "Passwort ist falsch."
        }
    }
}
