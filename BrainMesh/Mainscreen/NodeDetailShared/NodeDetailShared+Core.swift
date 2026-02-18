//
//  NodeDetailShared+Core.swift
//  BrainMesh
//
//  Shared building blocks for Entity/Attribute detail screens.
//

import SwiftUI
import UIKit

// MARK: - Anchors

enum NodeDetailAnchor: String {
    case notes
    case connections
    case media
    case attributes
}

// MARK: - Pills

struct NodeStatPill: Identifiable, Hashable {
    let id: String
    let title: String
    let systemImage: String

    init(title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
        self.id = systemImage + "|" + title
    }
}

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

            NodeAsyncPreviewImageView(
                imagePath: imagePath,
                imageData: imageData,
                resolvedImage: $resolvedImage
            ) { ui in
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 210)
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
                .frame(height: 210)
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
        .frame(height: 210)
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

// MARK: - Toolbelt

struct NodeToolbelt<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 10) {
            content()
        }
    }
}

struct NodeToolbeltButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.secondary.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shared Card UI

struct NodeCardHeader: View {
    let title: String
    let systemImage: String

    var trailingTitle: String? = nil
    var trailingSystemImage: String? = nil
    var trailingAction: (() -> Void)? = nil

    init(
        title: String,
        systemImage: String,
        trailingTitle: String? = nil,
        trailingSystemImage: String? = nil,
        trailingAction: (() -> Void)? = nil
    ) {
        self.title = title
        self.systemImage = systemImage
        self.trailingTitle = trailingTitle
        self.trailingSystemImage = trailingSystemImage
        self.trailingAction = trailingAction
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.tint)

            Text(title)
                .font(.headline)

            Spacer(minLength: 0)

            if let trailingTitle, let trailingSystemImage, let trailingAction {
                Button(action: trailingAction) {
                    Label(trailingTitle, systemImage: trailingSystemImage)
                        .font(.callout.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

struct NodeEmptyStateRow: View {
    let text: String
    let ctaTitle: String
    let ctaSystemImage: String
    let ctaAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text)
                .foregroundStyle(.secondary)

            Button(action: ctaAction) {
                Label(ctaTitle, systemImage: ctaSystemImage)
                    .font(.callout.weight(.semibold))
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct NodeAppearanceCard: View {
    @Binding var iconSymbolName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NodeCardHeader(title: "Darstellung", systemImage: "paintbrush")

            IconPickerRow(title: "Icon", symbolName: $iconSymbolName)
                .padding(12)
                .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.secondary.opacity(0.12))
        )
    }
}


// MARK: - Rename Sheet (Entity / Attribute)

/// Minimal, focused rename UI used from the detail screens.
///
/// We keep renaming explicit (via the `…` menu) and update link labels after saving,
/// so the Connections UI stays consistent.


@MainActor
struct NodeRenameSheet: View {
    @Environment(\.dismiss) private var dismiss

    let kindTitle: String
    let originalName: String
    let helpText: String

    let onSave: (String) async throws -> Void

    @State private var name: String
    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil

    init(
        kindTitle: String,
        originalName: String,
        helpText: String = "Aktualisiert auch bestehende Verbindungen.",
        onSave: @escaping (String) async throws -> Void
    ) {
        self.kindTitle = kindTitle
        self.originalName = originalName
        self.helpText = helpText
        self.onSave = onSave
        _name = State(initialValue: originalName)
    }

    private var cleaned: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var originalCleaned: String {
        originalName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !cleaned.isEmpty && cleaned != originalCleaned
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled(false)
                        .submitLabel(.done)
                        .disabled(isSaving)
                        .onSubmit {
                            Task { @MainActor in await commitIfPossible() }
                        }
                } footer: {
                    Text(helpText)
                }
            }
            .navigationTitle("\(kindTitle) umbenennen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Speichern") {
                            Task { @MainActor in await commitIfPossible() }
                        }
                        .disabled(!canSave)
                    }
                }
            }
            .alert("BrainMesh", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func commitIfPossible() async {
        guard canSave else { return }
        isSaving = true
        defer { isSaving = false }

        do {
            try await onSave(cleaned)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
