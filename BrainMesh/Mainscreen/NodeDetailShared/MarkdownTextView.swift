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

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
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
        accessory.frame = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 44)
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

    final class Coordinator: NSObject, UITextViewDelegate {
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

            var currentText = parent.text
            var currentSelection = tv.selectedRange

            switch action {
            case .bold:
                MarkdownCommands.bold(text: &currentText, selection: &currentSelection)
            case .italic:
                MarkdownCommands.italic(text: &currentText, selection: &currentSelection)
            case .inlineCode:
                MarkdownCommands.inlineCode(text: &currentText, selection: &currentSelection)
            case .heading1:
                MarkdownCommands.heading1(text: &currentText, selection: &currentSelection)
            case .bulletList:
                MarkdownCommands.bulletList(text: &currentText, selection: &currentSelection)
            case .numberedList:
                MarkdownCommands.numberedList(text: &currentText, selection: &currentSelection)
            case .quote:
                MarkdownCommands.quote(text: &currentText, selection: &currentSelection)
            case .link:
                MarkdownCommands.link(text: &currentText, selection: &currentSelection)
            case .dismissKeyboard:
                break
            }

            parent.text = currentText
            parent.selection = currentSelection
            tv.text = currentText
            tv.selectedRange = currentSelection

            // Keep editing session alive.
            tv.becomeFirstResponder()
            tv.reloadInputViews()
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

final class MarkdownAccessoryView: UIView, UIScrollViewDelegate {
    enum Action: Int {
        case bold = 1
        case italic = 2
        case inlineCode = 3
        case heading1 = 4
        case bulletList = 5
        case numberedList = 6
        case quote = 7
        case link = 8
        case dismissKeyboard = 9
    }

    var onAction: ((Action) -> Void)?

    private let topHairline = UIView()
    private let scrollView = UIScrollView()
    private let stack = UIStackView()

    private let leftFade = EdgeFadeView(edge: .left)
    private let rightFade = EdgeFadeView(edge: .right)

    private let boldButton = UIButton(type: .system)
    private let italicButton = UIButton(type: .system)
    private let codeButton = UIButton(type: .system)
    private let h1Button = UIButton(type: .system)
    private let bulletButton = UIButton(type: .system)
    private let numberButton = UIButton(type: .system)
    private let quoteButton = UIButton(type: .system)
    private let linkButton = UIButton(type: .system)
    private let dismissButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 44)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: size.width, height: 44)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateFadeVisibility()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateFadeVisibility()
    }

    private func setup() {
        backgroundColor = UIColor.secondarySystemBackground

        topHairline.translatesAutoresizingMaskIntoConstraints = false
        topHairline.backgroundColor = UIColor.separator.withAlphaComponent(0.5)
        addSubview(topHairline)
        NSLayoutConstraint.activate([
            topHairline.topAnchor.constraint(equalTo: topAnchor),
            topHairline.leadingAnchor.constraint(equalTo: leadingAnchor),
            topHairline.trailingAnchor.constraint(equalTo: trailingAnchor),
            topHairline.heightAnchor.constraint(equalToConstant: 0.5)
        ])

        scrollView.delegate = self
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        stack.axis = .horizontal
        stack.spacing = 10
        stack.alignment = .center
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(scrollView)
        scrollView.addSubview(stack)

        addSubview(dismissButton)
        dismissButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(leftFade)
        addSubview(rightFade)
        leftFade.translatesAutoresizingMaskIntoConstraints = false
        rightFade.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            dismissButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            dismissButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            scrollView.trailingAnchor.constraint(equalTo: dismissButton.leadingAnchor, constant: -10),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),

            leftFade.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            leftFade.topAnchor.constraint(equalTo: topAnchor),
            leftFade.bottomAnchor.constraint(equalTo: bottomAnchor),
            leftFade.widthAnchor.constraint(equalToConstant: 18),

            rightFade.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            rightFade.topAnchor.constraint(equalTo: topAnchor),
            rightFade.bottomAnchor.constraint(equalTo: bottomAnchor),
            rightFade.widthAnchor.constraint(equalToConstant: 18)
        ])

        configureButtons()
        layoutButtons()

        // Start with fades hidden until we know content size.
        leftFade.isHidden = true
        rightFade.isHidden = true
    }

    private func configureButtons() {
        configureSymbolButton(boldButton, systemName: "bold", action: .bold, label: "Fett")
        configureSymbolButton(italicButton, systemName: "italic", action: .italic, label: "Kursiv")
        configureSymbolButton(codeButton, systemName: "chevron.left.slash.chevron.right", action: .inlineCode, label: "Code")
        configureSymbolButton(linkButton, systemName: "link", action: .link, label: "Link")

        h1Button.tag = Action.heading1.rawValue
        h1Button.setTitle("H1", for: .normal)
        h1Button.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        h1Button.accessibilityLabel = "Überschrift"
        h1Button.addTarget(self, action: #selector(buttonTapped(_:)), for: .touchUpInside)
        styleButton(h1Button)

        configureSymbolButton(bulletButton, systemName: "list.bullet", action: .bulletList, label: "Liste")
        configureSymbolButton(numberButton, systemName: "list.number", action: .numberedList, label: "Nummerierte Liste")
        configureSymbolButton(quoteButton, systemName: "text.quote", action: .quote, label: "Zitat")

        configureSymbolButton(dismissButton, systemName: "keyboard.chevron.compact.down", action: .dismissKeyboard, label: "Tastatur ausblenden")
        dismissButton.tintColor = UIColor.secondaryLabel
        dismissButton.backgroundColor = UIColor.tertiarySystemBackground
        dismissButton.layer.cornerRadius = 10
        dismissButton.contentEdgeInsets = UIEdgeInsets(top: 7, left: 10, bottom: 7, right: 10)
        dismissButton.setContentHuggingPriority(.required, for: .horizontal)
        dismissButton.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    private func layoutButtons() {
        for v in stack.arrangedSubviews {
            stack.removeArrangedSubview(v)
            v.removeFromSuperview()
        }

        stack.addArrangedSubview(boldButton)
        stack.addArrangedSubview(italicButton)
        stack.addArrangedSubview(codeButton)
        stack.addArrangedSubview(linkButton)
        stack.addArrangedSubview(h1Button)
        stack.addArrangedSubview(bulletButton)
        stack.addArrangedSubview(numberButton)
        stack.addArrangedSubview(quoteButton)
    }

    private func configureSymbolButton(_ button: UIButton, systemName: String, action: Action, label: String) {
        button.tag = action.rawValue
        button.setImage(UIImage(systemName: systemName), for: .normal)
        button.accessibilityLabel = label
        button.addTarget(self, action: #selector(buttonTapped(_:)), for: .touchUpInside)
        styleButton(button)
    }

    private func styleButton(_ button: UIButton) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.contentEdgeInsets = UIEdgeInsets(top: 7, left: 10, bottom: 7, right: 10)
        button.layer.cornerRadius = 10
        button.backgroundColor = UIColor.tertiarySystemBackground
        button.tintColor = UIColor.label
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    private func updateFadeVisibility() {
        let contentWidth = scrollView.contentSize.width
        let visibleWidth = scrollView.bounds.width

        guard contentWidth > 0, visibleWidth > 0 else {
            leftFade.isHidden = true
            rightFade.isHidden = true
            return
        }

        if contentWidth <= visibleWidth + 1 {
            leftFade.isHidden = true
            rightFade.isHidden = true
            return
        }

        let x = scrollView.contentOffset.x
        leftFade.isHidden = x <= 1
        rightFade.isHidden = (x + visibleWidth) >= (contentWidth - 1)
    }

    @objc private func buttonTapped(_ sender: UIButton) {
        guard let action = Action(rawValue: sender.tag) else { return }
        onAction?(action)
    }
}

final class EdgeFadeView: UIView {
    enum Edge {
        case left
        case right
    }

    private let edge: Edge
    private let gradient = CAGradientLayer()

    init(edge: Edge) {
        self.edge = edge
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        layer.addSublayer(gradient)
        updateColors()
    }

    required init?(coder: NSCoder) {
        self.edge = .left
        super.init(coder: coder)
        isUserInteractionEnabled = false
        layer.addSublayer(gradient)
        updateColors()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateColors()
    }

    private func updateColors() {
        let bg = UIColor.secondarySystemBackground
        let opaque = bg.cgColor
        let transparent = bg.withAlphaComponent(0).cgColor

        switch edge {
        case .left:
            // Opaque at the very left edge, fading into content.
            gradient.colors = [opaque, transparent]
        case .right:
            // Fading out into the opaque right edge.
            gradient.colors = [transparent, opaque]
        }
    }
}
