//
//  GraphPickerRow.swift
//  BrainMesh
//
//  Created by Marc Fechner on 11.02.26.
//

import SwiftUI

struct GraphPickerRow: View {
    let graph: MetaGraph
    let isActive: Bool
    let isDeleting: Bool

    let onSelect: () -> Void
    let onOpenSecurity: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    @EnvironmentObject private var graphLock: GraphLockCoordinator

    private var isUnlocked: Bool {
        graphLock.isUnlocked(graphID: graph.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                GraphPickerRowIcon(isActive: isActive)

                VStack(alignment: .leading, spacing: 4) {
                    Text(graph.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    if isActive {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                    }

                    Menu {
                        Button {
                            onOpenSecurity()
                        } label: {
                            Label("Schutz", systemImage: "lock")
                        }

                        Button {
                            onRename()
                        } label: {
                            Label("Umbenennen", systemImage: "pencil")
                        }

                        Button(role: .destructive) {
                            onDelete()
                        } label: {
                            Label("Löschen", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .background(Color(uiColor: .tertiarySystemGroupedBackground), in: Circle())
                            .overlay {
                                Circle()
                                    .strokeBorder(.quaternary)
                            }
                    }
                    .buttonStyle(.plain)
                    .disabled(isDeleting)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    GraphPickerStatusBadge(
                        title: isActive ? "Aktiv" : "Antippen zum Wechseln",
                        systemImage: isActive ? "checkmark" : "arrow.left.arrow.right",
                        isTinted: isActive
                    )

                    if graph.isProtected {
                        GraphPickerStatusBadge(
                            title: isUnlocked ? "Entsperrt" : "Geschützt",
                            systemImage: isUnlocked ? "lock.open" : "lock.fill"
                        )
                    }
                }

                GraphPickerStatusBadge(
                    title: createdLabel,
                    systemImage: "calendar"
                )
            }
        }
        .graphPickerRowCardStyle(isActive: isActive)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onTapGesture {
            guard !isDeleting else { return }
            onSelect()
        }
        .allowsHitTesting(!isDeleting)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    private var subtitle: String {
        if isActive {
            return graph.isProtected
                ? "Dieser Graph ist aktuell aktiv und zusätzlich geschützt."
                : "Dieser Graph ist aktuell aktiv."
        }

        return graph.isProtected
            ? "Geschützter Graph. Beim Wechseln musst du ihn erst entsperren."
            : "Separater Wissensraum für eigene Themen, Projekte oder Bereiche."
    }

    private var createdLabel: String {
        graph.createdAt.formatted(.dateTime.day().month(.abbreviated).year())
    }
}

private struct GraphPickerRowIcon: View {
    let isActive: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isActive ? Color.accentColor.opacity(0.16) : Color(uiColor: .tertiarySystemGroupedBackground))
                .frame(width: 46, height: 46)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(isActive ? Color.accentColor.opacity(0.22) : Color(.separator).opacity(0.12))
                }

            Image(systemName: "circle.grid.2x2.fill")
                .font(.system(size: 17, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(
                    isActive
                        ? AnyShapeStyle(Color.accentColor)
                        : AnyShapeStyle(Color.secondary)
                )
        }
        .accessibilityHidden(true)
    }
}

private struct GraphPickerStatusBadge: View {
    let title: String
    let systemImage: String
    var isTinted: Bool = false

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .foregroundStyle(isTinted ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.secondary))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(backgroundStyle, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(borderStyle)
            }
    }

    private var backgroundStyle: AnyShapeStyle {
        if isTinted {
            return AnyShapeStyle(Color.accentColor.opacity(0.10))
        }
        return AnyShapeStyle(Color(uiColor: .tertiarySystemGroupedBackground))
    }

    private var borderStyle: AnyShapeStyle {
        if isTinted {
            return AnyShapeStyle(Color.accentColor.opacity(0.18))
        }
        return AnyShapeStyle(.quaternary)
    }
}

private extension View {
    func graphPickerRowCardStyle(isActive: Bool) -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(backgroundStyle(isActive: isActive), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(borderColor(isActive: isActive), lineWidth: isActive ? 1 : 0.75)
            }
    }

    private func backgroundStyle(isActive: Bool) -> AnyShapeStyle {
        if isActive {
            return AnyShapeStyle(Color.accentColor.opacity(0.08))
        }
        return AnyShapeStyle(Color(uiColor: .secondarySystemGroupedBackground))
    }

    private func borderColor(isActive: Bool) -> Color {
        if isActive {
            return Color.accentColor.opacity(0.22)
        }
        return Color(.separator).opacity(0.12)
    }
}
