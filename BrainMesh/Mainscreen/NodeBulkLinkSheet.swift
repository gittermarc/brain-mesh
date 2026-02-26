//
//  NodeBulkLinkSheet.swift
//  BrainMesh
//
//  Created by Marc Fechner on 12.02.26.
//

import Foundation
import SwiftUI

struct NodeBulkLinkSheet: ViewModifier {
    @Binding var isPresented: Bool
    let source: NodeRef
    let graphID: UUID?

    @State private var toast: BMToast?

    func body(content: Content) -> some View {
        content
            .bmToast(toast: $toast, position: .top)
            .sheet(isPresented: $isPresented) {
                BulkLinkView(source: source, graphID: graphID) { completion in
                    withAnimation(.easeOut(duration: 0.2)) {
                        isPresented = false
                    }

                    let msg = toastMessage(for: completion)
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 250_000_000)
                        withAnimation(.easeOut(duration: 0.25)) {
                            toast = BMToast(kind: .success, message: msg)
                        }
                    }
                }
            }
    }

    private func toastMessage(for completion: BulkLinkCompletion) -> String {
        let c = completion.totalCreated
        if c == 0 {
            return "Keine neuen Links angelegt"
        }
        return "\(c) Link\(c == 1 ? "" : "s") erfolgreich angelegt"
    }
}

extension View {
    func bulkLinkSheet(isPresented: Binding<Bool>, source: NodeRef, graphID: UUID?) -> some View {
        modifier(NodeBulkLinkSheet(isPresented: isPresented, source: source, graphID: graphID))
    }
}

private enum BMToastPosition {
    case top
    case bottom
}

private struct BMToast: Identifiable, Equatable {
    enum Kind: Equatable {
        case success
        case info
        case warning
        case error
    }

    let id: UUID = UUID()
    let kind: Kind
    let message: String

    var iconName: String {
        switch kind {
        case .success:
            return "checkmark.circle.fill"
        case .info:
            return "info.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error:
            return "xmark.octagon.fill"
        }
    }
}

private struct BMToastView: View {
    let toast: BMToast

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.iconName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.tint)
            Text(toast.message)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .shadow(radius: 12)
        .accessibilityLabel(toast.message)
    }
}

private struct BMToastPresenter: ViewModifier {
    @Binding var toast: BMToast?
    let position: BMToastPosition
    let duration: TimeInterval

    @State private var dismissTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: position == .top ? .top : .bottom) {
                if let toast {
                    BMToastView(toast: toast)
                        .padding(.horizontal, 12)
                        .padding(position == .top ? .top : .bottom, 10)
                        .transition(
                            .move(edge: position == .top ? .top : .bottom)
                            .combined(with: .opacity)
                        )
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.2)) {
                                self.toast = nil
                            }
                        }
                        .zIndex(999)
                }
            }
            .onChange(of: toast?.id) { _, _ in
                scheduleDismissIfNeeded()
            }
            .onDisappear {
                dismissTask?.cancel()
                dismissTask = nil
            }
    }

    private func scheduleDismissIfNeeded() {
        dismissTask?.cancel()
        dismissTask = nil

        guard toast != nil else { return }
        dismissTask = Task { @MainActor in
            let nanos = UInt64(max(0.2, duration) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            withAnimation(.easeOut(duration: 0.25)) {
                toast = nil
            }
        }
    }
}

private extension View {
    func bmToast(toast: Binding<BMToast?>, position: BMToastPosition, duration: TimeInterval = 2.2) -> some View {
        modifier(BMToastPresenter(toast: toast, position: position, duration: duration))
    }
}
