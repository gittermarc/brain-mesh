//
//  NodeDetailShared+Core.Hero.swift
//  BrainMesh
//
//  Hero card + async preview image loader.
//

import SwiftUI
import UIKit

// MARK: - Hero

struct NodeHeroCard: View {
    let kindTitle: String
    let placeholderIcon: String

    let imageData: Data?
    let imagePath: String?

    @Binding var title: String
    let subtitle: String?
    let pills: [NodeStatPill]

    let isTitleEditable: Bool

    /// Controls the image area height (when `showsImage` is true).
    var imageHeight: CGFloat = 210

    /// Optional fixed height for the entire card.
    /// Set to `nil` to let the card size itself based on content.
    var cardHeight: CGFloat? = 210

    /// Whether to render the image/placeholder area at all.
    var showsImage: Bool = true

    @State private var resolvedImage: UIImage? = nil

    private var hasResolvedImage: Bool {
        resolvedImage != nil
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.secondary.opacity(0.12))
                )

            if showsImage {
                NodeAsyncPreviewImageView(
                    imagePath: imagePath,
                    imageData: imageData,
                    resolvedImage: $resolvedImage
                ) { ui in
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: imageHeight)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .overlay(
                            LinearGradient(
                                colors: [Color.black.opacity(0.55), Color.black.opacity(0.15), Color.clear],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        )
                } placeholder: {
                    VStack(spacing: 8) {
                        Image(systemName: placeholderIcon)
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(.tint)
                        Text(kindTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: imageHeight)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(kindTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(hasResolvedImage ? Color.white.opacity(0.85) : Color.secondary)

                if isTitleEditable {
                    TextField("Name", text: $title)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(hasResolvedImage ? Color.white : Color.primary)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled(false)
                } else {
                    Text(title.isEmpty ? "Ohne Namen" : title)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(hasResolvedImage ? Color.white : Color.primary)
                        .lineLimit(2)
                }

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(hasResolvedImage ? Color.white.opacity(0.85) : Color.secondary)
                        .lineLimit(2)
                }

                if !pills.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(pills) { pill in
                            Label(pill.title, systemImage: pill.systemImage)
                                .font(.caption.weight(.semibold))
                                .labelStyle(.titleAndIcon)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    (hasResolvedImage
                                     ? AnyShapeStyle(.ultraThinMaterial)
                                     : AnyShapeStyle(Color(uiColor: .tertiarySystemGroupedBackground))),
                                    in: Capsule()
                                )
                                .foregroundStyle(hasResolvedImage ? Color.white : Color.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(16)
        }
        .frame(height: cardHeight)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Async preview image loader

/// Loads an image from the local `ImageStore` (disk/memory) asynchronously.
/// If no image exists at `imagePath`, it falls back to decoding `imageData` (off-main).
///
/// Use this to keep `ImageStore.loadUIImage(path:)` out of SwiftUI `body` / computed properties.
struct NodeAsyncPreviewImageView<Content: View, Placeholder: View>: View {
    let imagePath: String?
    let imageData: Data?

    /// Optional external binding to expose the resolved image to the parent.
    /// Useful when the parent needs to adjust styling based on whether an image exists.
    var resolvedImage: Binding<UIImage?>? = nil

    @ViewBuilder let content: (UIImage) -> Content
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var internalImage: UIImage? = nil

    private struct LoadKey: Hashable {
        let path: String
        let dataHash: Int
    }

    private var loadKey: LoadKey {
        LoadKey(
            path: imagePath ?? "",
            dataHash: imageData?.hashValue ?? 0
        )
    }

    private var currentImage: UIImage? {
        resolvedImage?.wrappedValue ?? internalImage
    }

    var body: some View {
        Group {
            if let ui = currentImage {
                content(ui)
            } else {
                placeholder()
            }
        }
        .task(id: loadKey) {
            await loadImage()
        }
    }

    @MainActor
    private func setResolvedImage(_ image: UIImage?) {
        if let binding = resolvedImage {
            binding.wrappedValue = image
        } else {
            internalImage = image
        }
    }

    private func loadImage() async {
        await MainActor.run {
            setResolvedImage(nil)
        }

        if Task.isCancelled { return }

        if let path = imagePath, !path.isEmpty {
            if let ui = await ImageStore.loadUIImageAsync(path: path) {
                if Task.isCancelled { return }
                await MainActor.run {
                    setResolvedImage(ui)
                }
                return
            }
        }

        if let data = imageData, !data.isEmpty {
            let dataCopy = data
            let decoded: UIImage? = await Task.detached(priority: .userInitiated) {
                autoreleasepool {
                    UIImage(data: dataCopy)
                }
            }.value

            if Task.isCancelled { return }
            await MainActor.run {
                setResolvedImage(decoded)
            }
        }
    }
}
