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

                    NavigationLink {
                        GraphPickerSheet()
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
                        scheduleLoadGraph(resetLayout: true)
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

                Section("Kamera") {
                    Button {
                        if let sel = selection {
                            cameraCommand = CameraCommand(kind: .center(sel))
                        } else if let f = focusEntity {
                            cameraCommand = CameraCommand(kind: .center(NodeKey(kind: .entity, uuid: f.id)))
                        }
                    } label: {
                        Label("Zentrieren", systemImage: "dot.scope")
                    }
                    .disabled(selection == nil && focusEntity == nil)

                    Button {
                        cameraCommand = CameraCommand(kind: .fitAll)
                    } label: {
                        Label("Alles einpassen", systemImage: "arrow.up.left.and.down.right.magnifyingglass")
                    }
                    .disabled(nodes.isEmpty)

                    Button {
                        cameraCommand = CameraCommand(kind: .reset)
                    } label: {
                        Label("Ansicht zurücksetzen", systemImage: "arrow.counterclockwise")
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
                        scheduleLoadGraph(resetLayout: true)
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

                Section("App") {
                    NavigationLink {
                        SettingsView(showDoneButton: false)
                    } label: {
                        Label("Einstellungen", systemImage: "gearshape")
                    }
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
