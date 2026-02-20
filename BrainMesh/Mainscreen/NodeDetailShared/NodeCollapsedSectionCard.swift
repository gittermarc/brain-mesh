//
//  NodeCollapsedSectionCard.swift
//  BrainMesh
//
//  PR 06: Compact placeholder for sections that start "collapsed".
//

import SwiftUI

struct NodeCollapsedSectionCard: View {
    let title: String
    let systemImage: String

    var subtitle: String? = nil
    var actionTitle: String = "Anzeigen"

    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 22)
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    } else {
                        Text("Eingeklappt")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)

                Text(actionTitle)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.tint)

                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.secondary.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) anzeigen")
    }
}
