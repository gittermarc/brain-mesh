//
//  GraphUnlockBackgroundView.swift
//  BrainMesh
//

import SwiftUI

struct GraphUnlockBackgroundView: View {
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size

            ZStack {
                LinearGradient(
                    colors: [
                        Color(.systemBackground),
                        Color(.secondarySystemBackground)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.75)

                GraphUnlockMeshBlobs(size: size)
            }
            .ignoresSafeArea()
        }
    }
}

private struct GraphUnlockMeshBlobs: View {
    let size: CGSize

    var body: some View {
        ZStack {
            blob(
                diameter: min(size.width, size.height) * 0.72,
                x: size.width * 0.18,
                y: size.height * 0.12,
                style: AnyShapeStyle(.tint)
            )

            blob(
                diameter: min(size.width, size.height) * 0.55,
                x: size.width * 0.86,
                y: size.height * 0.22,
                style: AnyShapeStyle(.tint)
            )

            blob(
                diameter: min(size.width, size.height) * 0.62,
                x: size.width * 0.78,
                y: size.height * 0.78,
                style: AnyShapeStyle(.secondary)
            )

            blob(
                diameter: min(size.width, size.height) * 0.44,
                x: size.width * 0.16,
                y: size.height * 0.82,
                style: AnyShapeStyle(.secondary)
            )

            blob(
                diameter: min(size.width, size.height) * 0.30,
                x: size.width * 0.52,
                y: size.height * 0.54,
                style: AnyShapeStyle(.tertiary)
            )
        }
        .opacity(0.22)
        .blur(radius: 44)
        .allowsHitTesting(false)
    }

    private func blob(diameter: CGFloat, x: CGFloat, y: CGFloat, style: AnyShapeStyle) -> some View {
        Circle()
            .fill(style)
            .frame(width: diameter, height: diameter)
            .position(x: x, y: y)
    }
}
