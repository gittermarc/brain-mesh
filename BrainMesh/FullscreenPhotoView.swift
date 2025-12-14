//
//  FullscreenPhotoView.swift
//  BrainMesh
//
//  Created by Marc Fechner on 14.12.25.
//

import SwiftUI
import UIKit

struct FullscreenPhotoView: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .padding(16)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(14)
        }
        .onTapGesture { dismiss() }
    }
}
