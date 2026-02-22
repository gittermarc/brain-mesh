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

    @State private var errorShakeTrigger: Int = 0

    var body: some View {
        NavigationStack {
            ZStack {
                GraphUnlockBackgroundView()

                VStack(spacing: 16) {
                    Spacer(minLength: 12)

                    GraphUnlockHeroView(graphName: request.graphName)

                    if let errorMessage {
                        GraphUnlockErrorBanner(message: errorMessage, shakeTrigger: errorShakeTrigger)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    methodsSection

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
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
            .safeAreaInset(edge: .bottom) {
                if showsSecondaryActions {
                    bottomSecondaryActions
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
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

    private var methodsSection: some View {
        VStack(spacing: 12) {
            if showBiometrics {
                GraphUnlockBiometricsCard(
                    biometricsLabel: biometricsLabel,
                    biometricsIcon: biometricsIcon,
                    isWorking: isWorking,
                    action: {
                        Task { await unlockWithBiometrics() }
                    }
                )
                .disabled(isWorking)
            }

            if showBiometrics && showPassword {
                Text("oder")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule(style: .continuous))
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(.quaternary)
                    }
                    .padding(.vertical, 2)
            }

            if showPassword {
                GraphUnlockPasswordCard(
                    password: $password,
                    isWorking: isWorking,
                    onSubmit: {
                        Task { await unlockWithPassword() }
                    }
                )
            }

            if !showBiometrics && !showPassword {
                Text("Für diesen Graph ist aktuell keine Entsperr-Methode verfügbar.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .animation(.snappy(duration: 0.22), value: showBiometrics)
        .animation(.snappy(duration: 0.22), value: errorMessage != nil)
    }

    private var bottomSecondaryActions: some View {
        HStack {
            Spacer(minLength: 0)

            if let _ = request.fallbackGraphID {
                Button("Graph wechseln") {
                    graphLock.completeCurrentRequest(success: false)
                }
                .buttonStyle(.plain)
            } else if request.onCancel != nil {
                Button("Abbrechen") {
                    graphLock.completeCurrentRequest(success: false)
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.vertical, 10)
    }

    private var showsSecondaryActions: Bool {
        request.fallbackGraphID != nil || request.onCancel != nil
    }

    private var showBiometrics: Bool {
        request.allowBiometrics && biometricsAvailable
    }

    private var showPassword: Bool {
        request.allowPassword
    }

    private var biometricsIcon: String {
        switch biometricsLabel {
        case "Face ID": return "faceid"
        case "Touch ID": return "touchid"
        default: return "key.fill"
        }
    }

    private func showError(_ message: String) {
        withAnimation(.snappy(duration: 0.22)) {
            errorMessage = message
        }
        errorShakeTrigger += 1
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
            showError("Biometrische Entsperrung fehlgeschlagen.")
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
            showError("Graph nicht gefunden.")
            return
        }

        if graphLock.verifyPassword(cleaned, for: graph) {
            graphLock.completeCurrentRequest(success: true)
        } else {
            showError("Passwort ist falsch.")
        }
    }
}
