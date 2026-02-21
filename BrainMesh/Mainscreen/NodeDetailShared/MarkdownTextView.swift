//
//  MarkdownTextView.swift
//  BrainMesh
//
//  UITextView wrapper for Markdown editing with selection access and
//  a one-line formatting toolbar (inputAccessoryView) with subtle edge fades
//  to hint that more actions are available horizontally.
//

import SwiftUI
import UIKit

struct MarkdownTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange
    @Binding var isFirstResponder: Bool

    var contentInset: UIEdgeInsets = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)

    func makeCoordinator() -> MarkdownTextCoordinator {
        MarkdownTextCoordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let tv = AccessoryTextView()
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

        let accessory = MarkdownAccessoryView()
        accessory.onAction = { [weak coordinator = context.coordinator] action in
            coordinator?.handleAccessoryAction(action)
        }

        // Give the accessory an explicit height. UIKit can otherwise end up with a 0-height
        // accessory in some SwiftUI sheet/update timing scenarios.
        // Width will be resized by UIKit once attached to the text view / keyboard context.
        accessory.frame = CGRect(x: 0, y: 0, width: 1, height: 44)
        accessory.autoresizingMask = [.flexibleWidth]

        context.coordinator.textView = tv
        context.coordinator.accessoryView = accessory
        tv.customAccessoryView = accessory

        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.parent = self

        if uiView.text != text {
            uiView.text = text
        }

        if uiView.selectedRange.location != selection.location || uiView.selectedRange.length != selection.length {
            uiView.selectedRange = selection
        }

        if let tv = uiView as? AccessoryTextView {
            if tv.customAccessoryView == nil {
                tv.customAccessoryView = context.coordinator.accessoryView
                uiView.reloadInputViews()
            }
        }

        if isFirstResponder {
            if !uiView.isFirstResponder {
                // Defer until the view is in the window; otherwise becomeFirstResponder can fail
                // and the accessory may never attach.
                DispatchQueue.main.async {
                    uiView.becomeFirstResponder()
                    uiView.reloadInputViews()
                }
            } else {
                uiView.reloadInputViews()
            }
        } else {
            if uiView.isFirstResponder {
                uiView.resignFirstResponder()
            }
        }
    }
}

/// A UITextView subclass that returns a custom inputAccessoryView reliably.
///
/// SwiftUI sheet update timing can result in `inputAccessoryView` being ignored or
/// returning nil if it's only set as a stored property. Overriding makes UIKit query
/// the accessory every time.
final class AccessoryTextView: UITextView {
    var customAccessoryView: UIView?

    override var inputAccessoryView: UIView? {
        get { customAccessoryView }
        set { customAccessoryView = newValue }
    }
}
