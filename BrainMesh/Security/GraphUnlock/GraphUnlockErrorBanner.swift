//
//  GraphUnlockErrorBanner.swift
//  BrainMesh
//

import SwiftUI

struct GraphUnlockErrorBanner: View {
    let message: String
    let shakeTrigger: Int

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.red)

            Text(message)
                .font(.footnote)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.quaternary)
        }
        .modifier(GraphUnlockShakeEffect(trigger: shakeTrigger))
        .animation(.snappy(duration: 0.22), value: shakeTrigger)
    }
}
