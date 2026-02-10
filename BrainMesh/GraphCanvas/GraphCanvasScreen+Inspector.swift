//
//  GraphCanvasScreen+Inspector.swift
//  BrainMesh
//

import SwiftUI

extension GraphCanvasScreen {

    // MARK: - Inspector sheet

    var inspectorSheet: some View {
        NavigationStack {
            Form {

                Section("Graph") {
                    HStack {
                        Text("Aktiv")
                        Spacer()
                        Text(activeGraphName)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Button {
                        showGraphPicker = true
                    } label: {
                        Label("Graph wechseln", systemImage: "square.stack.3d.up")
                    }
                }

                Section("Modus") {
                    HStack {
                        Text("Fokus")
                        Spacer()
                        Text(focusEntity?.name ?? "Keiner")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Picker("Arbeitsmodus", selection: $workMode) {
                            ForEach(WorkMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    Button {
                        showFocusPicker = true
                    } label: {
                        Label("Fokus wählen", systemImage: "scope")
                    }

                    Button(role: .destructive) {
                        focusEntity = nil
                        selection = nil
                        Task { await loadGraph() }
                    } label: {
                        Label("Fokus löschen", systemImage: "xmark.circle")
                    }
                    .disabled(focusEntity == nil)
                }

                Section("Neighborhood") {
                    Stepper("Hops: \(hops)", value: $hops, in: 1...3)
                        .disabled(focusEntity == nil)

                    Toggle("Attribute anzeigen", isOn: $showAttributes)
                        .disabled(focusEntity == nil)
                }

                Section("Lens") {
                    Toggle("Lens aktiv", isOn: $lensEnabled)

                    Toggle("Nicht relevante ausblenden", isOn: $lensHideNonRelevant)
                        .disabled(!lensEnabled)

                    Stepper("Lens Tiefe: \(lensDepth)", value: $lensDepth, in: 1...2)
                        .disabled(!lensEnabled)

                    if selection != nil {
                        Text("Spotlight aktiv: Selection → nur direkte Nachbarn (Tiefe 1) + Rest ausgeblendet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Wenn eine Node ausgewählt ist, werden Nachbarn hervorgehoben und der Rest gedimmt (oder ausgeblendet).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Layout & Physics") {
                    Button {
                        stabilizeLayout()
                    } label: {
                        Label("Layout stabilisieren", systemImage: "pin.circle")
                    }
                    .disabled(nodes.isEmpty)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Collisions: \(collisionStrength, format: .number.precision(.fractionLength(3)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(value: $collisionStrength, in: 0.0...0.09, step: 0.005)
                    }

                    Text("Tipp: Wenn du viel overlap hast → Collisions hoch. Wenn es „zittert“ → Collisions runter.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Limits") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Max Nodes: \(maxNodes)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Slider(
                            value: Binding(get: { Double(maxNodes) }, set: { maxNodes = Int($0) }),
                            in: 60...260,
                            step: 10
                        )
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Max Links: \(maxLinks)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Slider(
                            value: Binding(get: { Double(maxLinks) }, set: { maxLinks = Int($0) }),
                            in: 300...4000,
                            step: 100
                        )
                    }

                    Button {
                        Task { await loadGraph(resetLayout: true) }
                    } label: {
                        Label("Neu laden & layouten", systemImage: "wand.and.rays")
                    }
                }

                Section("Pins") {
                    HStack {
                        Text("Pinned")
                        Spacer()
                        Text("\(pinned.count)")
                            .foregroundStyle(.secondary)
                    }

                    Button(role: .destructive) {
                        pinned.removeAll()
                    } label: {
                        Label("Unpin all", systemImage: "pin.slash")
                    }
                    .disabled(pinned.isEmpty)
                }
            }
            .navigationTitle("Inspector")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") { showInspector = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    func stabilizeLayout() {
        let all = Set(nodes.map(\.key))
        pinned = all
        for k in all {
            velocities[k] = .zero
        }
    }
}
