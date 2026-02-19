//
//  MarkdownTextView.swift
//  BrainMesh
//
//  UITextView wrapper for Markdown editing with selection access.
//

import SwiftUI
import UIKit

struct MarkdownTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange
    @Binding var isFirstResponder: Bool

    var contentInset: UIEdgeInsets = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator

        tv.backgroundColor = .clear
        tv.font = UIFont.preferredFont(forTextStyle: .body)
        tv.adjustsFontForContentSizeCategory = true

        tv.textContainerInset = contentInset
        tv.textContainer.lineFragmentPadding = 0

        tv.isScrollEnabled = true
        tv.alwaysBounceVertical = true
        tv.keyboardDismissMode = .interactive
        tv.autocorrectionType = .yes
        tv.autocapitalizationType = .sentences
        tv.smartDashesType = .yes
        tv.smartQuotesType = .yes
        tv.smartInsertDeleteType = .yes
        tv.text = text
        tv.selectedRange = selection
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }

        if uiView.selectedRange.location != selection.location || uiView.selectedRange.length != selection.length {
            uiView.selectedRange = selection
        }

        if isFirstResponder {
            if !uiView.isFirstResponder {
                uiView.becomeFirstResponder()
            }
        } else {
            if uiView.isFirstResponder {
                uiView.resignFirstResponder()
            }
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private let parent: MarkdownTextView

        init(_ parent: MarkdownTextView) {
            self.parent = parent
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if !parent.isFirstResponder {
                parent.isFirstResponder = true
            }
            parent.selection = textView.selectedRange
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if parent.isFirstResponder {
                parent.isFirstResponder = false
            }
            parent.selection = textView.selectedRange
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text ?? ""
            parent.selection = textView.selectedRange
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            parent.selection = textView.selectedRange
        }
    }
}
