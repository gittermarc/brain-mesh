//
//  DetailSectionHeader.swift
//  BrainMesh
//
//  Created by Marc Fechner on 10.02.26.
//

import SwiftUI

struct DetailSectionHeader<Trailing: View>: View {
    let title: String
    let systemImage: String
    var subtitle: String? = nil

    @ViewBuilder var trailing: () -> Trailing

    init(
        title: String,
        systemImage: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.systemImage = systemImage
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .textCase(nil)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
            }

            Spacer(minLength: 0)

            trailing()
        }
        .padding(.top, 6)
        .padding(.bottom, 2)
    }
}
