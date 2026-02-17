//
//  ImportProgressCard.swift
//  BrainMesh
//
//  A compact, modern progress bar card you can place inside Lists or as a bottom inset.
//

import SwiftUI

struct ImportProgressCard: View {
    @ObservedObject var progress: ImportProgressState

    var body: some View {
        Group {
            if progress.isPresented {
                content
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: progress.isPresented)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(progress.title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)

                    if let subtitle = progress.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                if !progress.isIndeterminate, progress.totalUnitCount > 0 {
                    Text("\(progress.completedUnitCount)/\(progress.totalUnitCount)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            if progress.isIndeterminate {
                ProgressView()
                    .controlSize(.regular)
            } else {
                ProgressView(value: progress.fractionCompleted)
                    .controlSize(.regular)
            }

            if progress.failureCount > 0 {
                Text("\(progress.failureCount) fehlgeschlagen")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(.secondary.opacity(0.12))
        )
        .padding(.vertical, 6)
    }
}
