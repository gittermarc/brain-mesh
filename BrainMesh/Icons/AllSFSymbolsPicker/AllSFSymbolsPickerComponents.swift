//
//  AllSFSymbolsPickerComponents.swift
//  BrainMesh
//
//  UI components extracted from AllSFSymbolsPickerView.swift
//

import SwiftUI

struct AllSFSymbolsPickerErrorCard: View {

    let message: String
    let onReload: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Katalog nicht verfügbar", systemImage: "exclamationmark.triangle")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(action: onReload) {
                Text("Neu laden")
                    .font(.callout)
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
        )
    }
}

struct AllSFSymbolsPickerDirectEntryButton: View {

    let symbolName: String
    let onPick: () -> Void

    var body: some View {
        Button(action: onPick) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(AnyShapeStyle(Color.secondary.opacity(0.35)), lineWidth: 1)
                        )
                    Image(systemName: symbolName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .frame(width: 56, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Direkt verwenden")
                        .font(.body)
                    Text(symbolName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
}

struct AllSFSymbolsPickerSymbolCell: View {

    let symbol: String
    let isSelected: Bool
    let onPick: () -> Void

    var body: some View {
        Button(action: onPick) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(
                                AnyShapeStyle(isSelected ? Color.accentColor.opacity(0.75) : Color.secondary.opacity(0.25)),
                                lineWidth: isSelected ? 2 : 1
                            )
                    )

                VStack(spacing: 6) {
                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(symbol)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 8)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(symbol))
    }
}
