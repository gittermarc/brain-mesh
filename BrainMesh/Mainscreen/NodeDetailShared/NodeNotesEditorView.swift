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

    let title: String
    @Binding var notes: String

    @State private var selection: NSRange = NSRange(location: 0, length: 0)
    @State private var isPreview = false
    @State private var isFirstResponder = false

    private var trimmed: String {
        notes.trimmingCharacters(in: .whitespacesAndNewlines)
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
                    isFirstResponder = false
                    dismiss()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isPreview.toggle()
                    if isPreview { isFirstResponder = false }
                    else { isFirstResponder = true }
                } label: {
                    Image(systemName: isPreview ? "pencil" : "eye")
                }
                .accessibilityLabel(isPreview ? "Bearbeiten" : "Vorschau")
            }
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .onAppear {
            isFirstResponder = true
        }
    }

    private var editorBody: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                MarkdownTextView(text: $notes, selection: $selection, isFirstResponder: $isFirstResponder)
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
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
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
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.secondary.opacity(0.12))
            )
            .padding(.horizontal, 12)
            .padding(.top, 16)
        }
    }
}
