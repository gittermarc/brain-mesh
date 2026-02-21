//
//  MarkdownTextCoordinator.swift
//  BrainMesh
//
//  UITextViewDelegate + accessory actions for MarkdownTextView.
//

import SwiftUI
import UIKit

final class MarkdownTextCoordinator: NSObject, UITextViewDelegate {
    var parent: MarkdownTextView
    weak var textView: UITextView?
    var accessoryView: MarkdownAccessoryView?

    init(_ parent: MarkdownTextView) {
        self.parent = parent
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        if !parent.isFirstResponder {
            parent.isFirstResponder = true
        }
        parent.selection = textView.selectedRange

        updateUndoRedoButtons()

        // Ensure accessory is visible even after SwiftUI updates.
        textView.reloadInputViews()
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

        updateUndoRedoButtons()
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        parent.selection = textView.selectedRange
    }

    func handleAccessoryAction(_ action: MarkdownAccessoryView.Action) {
        guard let tv = textView else { return }

        if action == .dismissKeyboard {
            tv.resignFirstResponder()
            parent.isFirstResponder = false
            return
        }

        if action == .undo {
            tv.undoManager?.undo()
            syncFromTextView(tv)
            tv.reloadInputViews()
            return
        }

        if action == .redo {
            tv.undoManager?.redo()
            syncFromTextView(tv)
            tv.reloadInputViews()
            return
        }

        if action == .link {
            presentLinkPrompt(from: tv)
            return
        }

        applyMutation(action, on: tv)
    }

    private func applyMutation(_ action: MarkdownAccessoryView.Action, on tv: UITextView) {
        let beforeText = tv.text ?? ""
        var newText = beforeText
        var newSelection = tv.selectedRange

        switch action {
        case .bold:
            MarkdownCommands.bold(text: &newText, selection: &newSelection)
            setText(newText, selection: newSelection, actionName: "Fett")
        case .italic:
            MarkdownCommands.italic(text: &newText, selection: &newSelection)
            setText(newText, selection: newSelection, actionName: "Kursiv")
        case .inlineCode:
            MarkdownCommands.inlineCode(text: &newText, selection: &newSelection)
            setText(newText, selection: newSelection, actionName: "Code")
        case .heading1:
            MarkdownCommands.heading1(text: &newText, selection: &newSelection)
            setText(newText, selection: newSelection, actionName: "Überschrift")
        case .bulletList:
            MarkdownCommands.bulletList(text: &newText, selection: &newSelection)
            setText(newText, selection: newSelection, actionName: "Liste")
        case .numberedList:
            MarkdownCommands.numberedList(text: &newText, selection: &newSelection)
            setText(newText, selection: newSelection, actionName: "Nummerierte Liste")
        case .quote:
            MarkdownCommands.quote(text: &newText, selection: &newSelection)
            setText(newText, selection: newSelection, actionName: "Zitat")
        case .undo, .redo, .link, .dismissKeyboard:
            break
        }

        // Keep editing session alive.
        tv.becomeFirstResponder()
        tv.reloadInputViews()
    }

    private func syncFromTextView(_ tv: UITextView) {
        parent.text = tv.text ?? ""
        parent.selection = tv.selectedRange
        updateUndoRedoButtons()
    }

    private func updateUndoRedoButtons() {
        guard let tv = textView else { return }
        let canUndo = tv.undoManager?.canUndo ?? false
        let canRedo = tv.undoManager?.canRedo ?? false
        accessoryView?.setUndoRedo(canUndo: canUndo, canRedo: canRedo)
    }

    private func setText(_ newText: String, selection newSelection: NSRange, actionName: String?) {
        guard let tv = textView else { return }
        let oldText = tv.text ?? ""
        let oldSelection = tv.selectedRange

        // Avoid polluting the undo stack if nothing changed.
        if newText == oldText && NSEqualRanges(newSelection, oldSelection) {
            return
        }

        if let um = tv.undoManager {
            um.registerUndo(withTarget: self) { coordinator in
                coordinator.setText(oldText, selection: oldSelection, actionName: actionName)
            }
            if let actionName {
                um.setActionName(actionName)
            }
        }

        tv.text = newText
        tv.selectedRange = newSelection
        parent.text = newText
        parent.selection = newSelection
        updateUndoRedoButtons()
    }

    private func presentLinkPrompt(from tv: UITextView) {
        guard let presenter = nearestViewController(from: tv) else {
            // Fallback: insert empty link markers.
            var t = tv.text ?? ""
            var sel = tv.selectedRange
            MarkdownCommands.link(text: &t, selection: &sel)
            setText(t, selection: sel, actionName: "Link")
            tv.becomeFirstResponder()
            tv.reloadInputViews()
            return
        }

        let ns = (tv.text ?? "") as NSString
        let safeSel = NSRange(
            location: Swift.max(0, Swift.min(tv.selectedRange.location, ns.length)),
            length: Swift.max(
                0,
                Swift.min(
                    tv.selectedRange.length,
                    ns.length - Swift.max(0, Swift.min(tv.selectedRange.location, ns.length))
                )
            )
        )
        let selectedText = safeSel.length > 0 ? ns.substring(with: safeSel) : ""

        let alert = UIAlertController(title: "Link einfügen", message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "Text"
            field.text = selectedText
            field.autocorrectionType = .yes
            field.autocapitalizationType = .sentences
        }
        alert.addTextField { field in
            field.placeholder = "URL"
            field.keyboardType = .URL
            field.textContentType = .URL
            field.autocorrectionType = .no
            field.autocapitalizationType = .none
        }
        alert.addAction(UIAlertAction(title: "Abbrechen", style: .cancel))
        alert.addAction(UIAlertAction(title: "Einfügen", style: .default) { [weak self] _ in
            guard let self else { return }
            let textField = alert.textFields?[0]
            let urlField = alert.textFields?[1]

            let rawText = (textField?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let rawURL = (urlField?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

            guard let normalizedURL = self.normalizeURL(rawURL) else {
                tv.becomeFirstResponder()
                tv.reloadInputViews()
                return
            }

            let linkText = rawText.isEmpty ? (selectedText.isEmpty ? normalizedURL : selectedText) : rawText

            var t = tv.text ?? ""
            var sel = tv.selectedRange
            MarkdownCommands.insertLink(text: &t, selection: &sel, linkText: linkText, url: normalizedURL)
            self.setText(t, selection: sel, actionName: "Link")

            tv.becomeFirstResponder()
            tv.reloadInputViews()
        })

        presenter.present(alert, animated: true)
    }

    private func normalizeURL(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }

        let lower = trimmed.lowercased()
        if lower.hasPrefix("mailto:") { return trimmed }
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") { return trimmed }

        // Common case: user pasted/typed without scheme.
        return "https://" + trimmed
    }

    private func nearestViewController(from responder: UIResponder) -> UIViewController? {
        var r: UIResponder? = responder
        while let current = r {
            if let vc = current as? UIViewController {
                return vc
            }
            r = current.next
        }
        return nil
    }
}
