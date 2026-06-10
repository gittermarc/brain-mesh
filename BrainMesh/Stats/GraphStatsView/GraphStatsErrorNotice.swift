//
//  GraphStatsErrorNotice.swift
//  BrainMesh
//
//  Created by Marc Fechner on 10.06.26.
//

import SwiftUI

@MainActor
struct GraphStatsErrorNotice: View {
    let message: GraphStatsUserFacingErrorMessage
    let actionTitle: String?
    let action: (@MainActor () -> Void)?

    init(
        message: GraphStatsUserFacingErrorMessage,
        actionTitle: String? = nil,
        action: (@MainActor () -> Void)? = nil
    ) {
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: message.systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                Text(message.title)
                    .font(.headline)

                Spacer(minLength: 0)
            }

            Text(message.message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(message.recoverySuggestion)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let actionTitle, let action {
                Button(actionTitle) {
                    action()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}
