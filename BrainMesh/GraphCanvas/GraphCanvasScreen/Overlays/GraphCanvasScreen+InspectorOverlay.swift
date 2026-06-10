//
//  GraphCanvasScreen+InspectorOverlay.swift
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

                Section("Canvas-Modus") {
                    Picker("Modus", selection: $workMode) {
                        ForEach(WorkMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: workMode.icon)
                            .foregroundStyle(.tint)
                            .frame(width: 22)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(workMode.title)
                                .font(.subheadline.weight(.semibold))

                            Text(workMode.inspectorDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }

                Section("Fokus") {
                    HStack {
                        Text("Aktuell")
                        Spacer()
                        Text(focusEntity?.name ?? "Keiner")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Button {
                        showFocusPicker = true
                    } label: {
                        Label("Fokus wählen", systemImage: "scope")
                    }

                    Button(role: .destructive) {
                        clearFocusEntity(scheduleReload: true)
                    } label: {
                        Label("Fokus löschen", systemImage: "xmark.circle")
                    }
                    .disabled(focusEntity == nil)
                }

                Section("Fokus-Verlauf") {
                    focusHistorySectionContent
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


                Section("Details-Fokus") {
                    if let activeFocus = detailsFocusSummaryCache.activeFocus {
                        let field = detailsFocusSummaryCache.field

                        LabeledContent("Regel") {
                            Text(verbatim: GraphDetailsFocusFormatting.ruleText(focusState: activeFocus, field: field))
                                .multilineTextAlignment(.trailing)
                        }

                        LabeledContent("Modus") {
                            Text(verbatim: activeFocus.mode.title)
                        }

                        LabeledContent("Treffer") {
                            Text(verbatim: "\(detailsFocusSummaryCache.matchCount) / \(detailsFocusSummaryCache.inspectedAttributeCount)")
                        }

                        if detailsFocusSummaryCache.isFieldAvailable == false {
                            Text("Aktuell sind keine sichtbaren Attribute mit diesem Feld im Graph vorhanden.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Button(role: .destructive) {
                            clearDetailsFocus()
                        } label: {
                            Label("Zurücksetzen", systemImage: "line.3.horizontal.decrease.circle.badge.xmark")
                        }
                    } else {
                        Text("Noch kein Details-Fokus aktiv.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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

    @ViewBuilder
    var focusHistorySectionContent: some View {
        let recentItems = focusHistoryItemsForActiveGraph(limit: 8)
        let previousItem = previousFocusHistoryItem()

        if let previousItem {
            Button {
                applyFocusHistoryItem(previousItem)
            } label: {
                Label("Vorherigen Fokus anwenden", systemImage: "arrow.uturn.backward.circle")
            }
            .accessibilityLabel("Vorherigen Fokus anwenden")
        } else {
            Text("Noch kein vorheriger Fokus für diesen Graph vorhanden.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if recentItems.isEmpty {
            Text("Sobald du eine Entität fokussierst, landet sie hier lokal auf diesem Gerät.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            ForEach(recentItems) { item in
                Button {
                    applyFocusHistoryItem(item)
                } label: {
                    GraphCanvasFocusHistoryRow(
                        item: item,
                        isCurrent: item.entityID == focusEntity?.id
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(focusHistoryAccessibilityLabel(for: item))
            }

            Button(role: .destructive) {
                clearFocusHistoryForActiveGraph()
            } label: {
                Label("Verlauf für diesen Graph löschen", systemImage: "trash")
            }
        }
    }

    func focusHistoryAccessibilityLabel(for item: GraphCanvasFocusHistoryItem) -> String {
        if item.entityID == focusEntity?.id {
            return "Aktueller Fokus: \(item.label)"
        }
        return "Fokus anwenden: \(item.label)"
    }

    func stabilizeLayout() {
        let all = Set(nodes.map(\.key))
        pinned = all
        for k in all {
            velocities[k] = .zero
        }
    }
}

private struct GraphCanvasFocusHistoryRow: View {
    let item: GraphCanvasFocusHistoryItem
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isCurrent ? "scope" : "clock.arrow.circlepath")
                .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: item.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(item.focusedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if isCurrent {
                Text("Aktuell")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.thinMaterial, in: Capsule())
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }
}
