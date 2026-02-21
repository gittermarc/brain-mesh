//
//  MarkdownAccessoryView.swift
//  BrainMesh
//
//  One-line formatting toolbar used as UITextView.inputAccessoryView.
//

import Foundation
import UIKit

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

        case undo = 10
        case redo = 11
    }

    var onAction: ((Action) -> Void)?

    private let topHairline = UIView()
    private let scrollView = UIScrollView()
    private let stack = UIStackView()

    private let leftFade = EdgeFadeView(edge: .left)
    private let rightFade = EdgeFadeView(edge: .right)

    private let undoButton = UIButton(type: .system)
    private let redoButton = UIButton(type: .system)
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
        configureSymbolButton(undoButton, systemName: "arrow.uturn.backward", action: .undo, label: "Rückgängig")
        configureSymbolButton(redoButton, systemName: "arrow.uturn.forward", action: .redo, label: "Wiederholen")

        configureSymbolButton(boldButton, systemName: "bold", action: .bold, label: "Fett")
        configureSymbolButton(italicButton, systemName: "italic", action: .italic, label: "Kursiv")
        configureSymbolButton(codeButton, systemName: "chevron.left.slash.chevron.right", action: .inlineCode, label: "Code")
        configureSymbolButton(linkButton, systemName: "link", action: .link, label: "Link")

        configureTextButton(h1Button, title: "H1", titleFont: UIFont.systemFont(ofSize: 15, weight: .semibold), action: .heading1, label: "Überschrift")

        configureSymbolButton(bulletButton, systemName: "list.bullet", action: .bulletList, label: "Liste")
        configureSymbolButton(numberButton, systemName: "list.number", action: .numberedList, label: "Nummerierte Liste")
        configureSymbolButton(quoteButton, systemName: "text.quote", action: .quote, label: "Zitat")

        configureSymbolButton(
            dismissButton,
            systemName: "keyboard.chevron.compact.down",
            action: .dismissKeyboard,
            label: "Tastatur ausblenden",
            foregroundColor: UIColor.secondaryLabel
        )

        setUndoRedo(canUndo: false, canRedo: false)
    }

    private func layoutButtons() {
        for v in stack.arrangedSubviews {
            stack.removeArrangedSubview(v)
            v.removeFromSuperview()
        }

        stack.addArrangedSubview(undoButton)
        stack.addArrangedSubview(redoButton)
        stack.addArrangedSubview(boldButton)
        stack.addArrangedSubview(italicButton)
        stack.addArrangedSubview(codeButton)
        stack.addArrangedSubview(linkButton)
        stack.addArrangedSubview(h1Button)
        stack.addArrangedSubview(bulletButton)
        stack.addArrangedSubview(numberButton)
        stack.addArrangedSubview(quoteButton)
    }

    func setUndoRedo(canUndo: Bool, canRedo: Bool) {
        undoButton.isEnabled = canUndo
        redoButton.isEnabled = canRedo

        undoButton.alpha = canUndo ? 1.0 : 0.35
        redoButton.alpha = canRedo ? 1.0 : 0.35
    }

    private func makeButtonConfiguration(
        foregroundColor: UIColor,
        backgroundColor: UIColor = UIColor.tertiarySystemBackground
    ) -> UIButton.Configuration {
        var config = UIButton.Configuration.plain()
        config.baseForegroundColor = foregroundColor
        config.background.backgroundColor = backgroundColor
        config.background.cornerRadius = 10
        config.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 10, bottom: 7, trailing: 10)
        return config
    }

    private func applyCommonPriorities(_ button: UIButton) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    private func configureSymbolButton(
        _ button: UIButton,
        systemName: String,
        action: Action,
        label: String,
        foregroundColor: UIColor = UIColor.label
    ) {
        button.tag = action.rawValue
        button.accessibilityLabel = label
        button.addTarget(self, action: #selector(buttonTapped(_:)), for: .touchUpInside)

        var config = makeButtonConfiguration(foregroundColor: foregroundColor)
        config.image = UIImage(systemName: systemName)
        button.configuration = config

        applyCommonPriorities(button)
    }

    private func configureTextButton(
        _ button: UIButton,
        title: String,
        titleFont: UIFont,
        action: Action,
        label: String
    ) {
        button.tag = action.rawValue
        button.accessibilityLabel = label
        button.addTarget(self, action: #selector(buttonTapped(_:)), for: .touchUpInside)

        var config = makeButtonConfiguration(foregroundColor: UIColor.label)
        var attr = AttributedString(title)
        attr.font = titleFont
        config.attributedTitle = attr
        button.configuration = config

        applyCommonPriorities(button)
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
        registerForTraitChanges([UITraitUserInterfaceStyle.self], handler: { (self: EdgeFadeView, previousTraitCollection: UITraitCollection) in
            self.updateColors()
        })
    }

    required init?(coder: NSCoder) {
        self.edge = .left
        super.init(coder: coder)
        isUserInteractionEnabled = false
        layer.addSublayer(gradient)
        updateColors()
        registerForTraitChanges([UITraitUserInterfaceStyle.self], handler: { (self: EdgeFadeView, previousTraitCollection: UITraitCollection) in
            self.updateColors()
        })
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
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
