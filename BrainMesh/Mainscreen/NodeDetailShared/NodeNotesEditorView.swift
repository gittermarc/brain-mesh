//
//  NodeNotesEditorView.swift
//  BrainMesh
//
//  Markdown-enabled notes editor for Entities & Attributes.
//

import SwiftUI
import Foundation

struct NodeNotesEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    let title: String
    private let onCommit: @MainActor (String) async throws -> Void

    @State private var commitState: NodeNotesCommitState
    @State private var selection = NSRange(location: 0, length: 0)
    @State private var isPreview = false
    @State private var isFirstResponder = false
    @State private var isCommitting = false
    @State private var errorMessage: String?

    init(
        title: String,
        initialNotes: String,
        onCommit: @escaping @MainActor (String) async throws -> Void
    ) {
        self.title = title
        self.onCommit = onCommit
        _commitState = State(
            initialValue: NodeNotesCommitState(initialNotes: initialNotes)
        )
    }

    private var notesBinding: Binding<String> {
        Binding(
            get: { commitState.draftNotes },
            set: { commitState.updateDraft($0) }
        )
    }

    private var trimmed: String {
        commitState.draftNotes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Group {
            if isPreview {
                previewBody
            } else {
                editorBody
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Fertig") {
                    Task { @MainActor in
                        await commitAndDismiss()
                    }
                }
                .disabled(isCommitting)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isPreview.toggle()
                    if isPreview {
                        isFirstResponder = false
                    } else {
                        isFirstResponder = true
                    }
                } label: {
                    Image(systemName: isPreview ? "pencil" : "eye")
                }
                .accessibilityLabel(isPreview ? "Bearbeiten" : "Vorschau")
            }
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .interactiveDismissDisabled(commitState.hasPendingChanges || isCommitting)
        .onAppear {
            isFirstResponder = true
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase != .active else { return }
            flushWithoutDismiss()
        }
        .onDisappear {
            flushWithoutDismiss()
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

    private var editorBody: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                MarkdownTextView(
                    text: notesBinding,
                    selection: $selection,
                    isFirstResponder: $isFirstResponder
                )
                .background(Color(uiColor: .secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                if trimmed.isEmpty {
                    Text("Notizen hinzufügen …")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
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
            .padding(.horizontal, 12)
            .padding(.top, 16)

            Spacer(minLength: 0)
        }
    }

    private var previewBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if trimmed.isEmpty {
                    Text("Noch keine Notiz hinterlegt.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    MarkdownRenderedText(markdown: trimmed)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
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
            .padding(.horizontal, 12)
            .padding(.top, 16)
        }
    }

    @MainActor
    private func commitAndDismiss() async {
        guard !isCommitting else { return }

        isFirstResponder = false
        isCommitting = true
        defer { isCommitting = false }

        // Give the UIKit-backed editor one main-actor turn to deliver its final binding update.
        await Task.yield()
        guard let candidate = commitState.commitCandidate else {
            dismiss()
            return
        }

        do {
            try await onCommit(candidate)
            commitState.markCommitted(candidate)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func flushWithoutDismiss() {
        guard commitState.hasPendingChanges else { return }
        guard !isCommitting else { return }

        isFirstResponder = false
        isCommitting = true
        Task { @MainActor in
            defer { isCommitting = false }

            // Scene and dismissal transitions can race the text-view callback by one run-loop turn.
            await Task.yield()
            guard let candidate = commitState.commitCandidate else { return }

            do {
                try await onCommit(candidate)
                commitState.markCommitted(candidate)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
