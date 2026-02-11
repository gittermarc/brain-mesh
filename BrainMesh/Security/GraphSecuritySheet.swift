//
//  GraphSecuritySheet.swift
//  BrainMesh
//
//  Created by Marc Fechner on 11.02.26.
//

import SwiftUI
import SwiftData

struct GraphSecuritySheet: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var graphLock: GraphLockCoordinator

    @Bindable var graph: MetaGraph

    @State private var showSetPassword: Bool = false
    @State private var showRemovePasswordConfirm: Bool = false
    @State private var showBiometricsUnavailable: Bool = false

    @State private var biometricsAvailable: Bool = false
    @State private var biometricsLabel: String = "Biometrie"

    var body: some View {
        NavigationStack {
            Form {
                Section("Status") {
                    HStack {
                        Label(graph.name, systemImage: "circle.grid.2x2")
                        Spacer()
                        if graph.isProtected {
                            Image(systemName: "lock.fill")
                                .foregroundStyle(.secondary)
                        } else {
                            Image(systemName: "lock.open")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(graph.isProtected ? "Dieser Graph ist geschützt." : "Dieser Graph ist nicht geschützt.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Entsperren") {
                    Toggle(isOn: biometricToggleBinding) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Systemschutz")
                            Text("Entsperren mit \(biometricsLabel)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(!biometricsAvailable)

                    Toggle(isOn: passwordToggleBinding) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Passwort")
                            Text("Eigenes Passwort für diesen Graph")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if graph.lockPasswordEnabled && graph.isPasswordConfigured == false {
                        Text("Passwort ist noch nicht gesetzt.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if graph.lockPasswordEnabled {
                        if graph.isPasswordConfigured {
                            Button {
                                showSetPassword = true
                            } label: {
                                Label("Passwort ändern", systemImage: "key")
                            }

                            Button(role: .destructive) {
                                showRemovePasswordConfirm = true
                            } label: {
                                Label("Passwort entfernen", systemImage: "trash")
                            }
                        } else {
                            Button {
                                showSetPassword = true
                            } label: {
                                Label("Passwort setzen", systemImage: "key")
                            }
                        }
                    }
                }

                Section {
                    Text("Tipp: Beim Wechseln eines geschützten Graphen musst du ihn entsperren. Beim Hintergrund/Foreground wird wieder gesperrt.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Schutz")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .alert("Biometrie nicht verfügbar", isPresented: $showBiometricsUnavailable) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Auf diesem Gerät ist keine System-Authentifizierung (Face ID / Touch ID / Gerätecode) verfügbar oder eingerichtet.")
            }
            .confirmationDialog("Passwort entfernen?", isPresented: $showRemovePasswordConfirm, titleVisibility: .visible) {
                Button("Passwort entfernen", role: .destructive) {
                    removePassword()
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Danach ist der Graph nicht mehr per Passwort geschützt.")
            }
            .sheet(isPresented: $showSetPassword) {
                GraphSetPasswordView(graph: graph)
            }
            .task {
                let info = graphLock.canUseBiometrics()
                biometricsAvailable = info.available
                biometricsLabel = info.label
            }
        }
    }

    private var biometricToggleBinding: Binding<Bool> {
        Binding(
            get: { graph.lockBiometricsEnabled },
            set: { newValue in
                if newValue {
                    if biometricsAvailable {
                        graph.lockBiometricsEnabled = true
                        graphLock.lock(graphID: graph.id)
                        save()
                    } else {
                        showBiometricsUnavailable = true
                    }
                } else {
                    graph.lockBiometricsEnabled = false
                    graphLock.lock(graphID: graph.id)
                    save()
                }
            }
        )
    }

    private var passwordToggleBinding: Binding<Bool> {
        Binding(
            get: { graph.lockPasswordEnabled },
            set: { newValue in
                if newValue {
                    graph.lockPasswordEnabled = true
                    graphLock.lock(graphID: graph.id)
                    save()

                    if graph.isPasswordConfigured == false {
                        showSetPassword = true
                    }
                } else {
                    graph.lockPasswordEnabled = false
                    graph.passwordSaltB64 = nil
                    graph.passwordHashB64 = nil
                    graph.passwordIterations = GraphLockCrypto.defaultIterations
                    graphLock.lock(graphID: graph.id)
                    save()
                }
            }
        )
    }

    private func removePassword() {
        graph.lockPasswordEnabled = false
        graph.passwordSaltB64 = nil
        graph.passwordHashB64 = nil
        graph.passwordIterations = GraphLockCrypto.defaultIterations
        graphLock.lock(graphID: graph.id)
        save()
    }

    private func save() {
        do {
            try modelContext.save()
        } catch {
            // silent; settings view should never hard-crash
            print("⚠️ GraphSecurity save failed: \(error)")
        }
    }
}
