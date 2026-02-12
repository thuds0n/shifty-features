//
//  SwitchView.swift
//  Shifty
//
//  Created by Nate Thompson on 11/11/21.
//

import Cocoa

class SwitchView: NSView {
    private var toggleSwitch = NSSwitch()
    private let titleLabel = NSTextField()
    private let switchBackgroundView = NSView()
    private var onSwitchToggle: (Bool) -> Void
    
    var switchState: Bool {
        didSet {
            toggleSwitch.state = switchState ? .on : .off
            applyVisualState()
        }
    }
    
    init(title: String, onSwitchToggle: @escaping (Bool) -> Void) {
        self.switchState = false
        self.onSwitchToggle = onSwitchToggle
        super.init(frame: .zero)
        
        titleLabel.stringValue = title
        titleLabel.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        titleLabel.isEditable = false
        titleLabel.isBezeled = false
        titleLabel.backgroundColor = .clear

        switchBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        switchBackgroundView.wantsLayer = true
        switchBackgroundView.layer?.cornerRadius = 8

        toggleSwitch.target = self
        toggleSwitch.action = #selector(switchToggled)
        toggleSwitch.translatesAutoresizingMaskIntoConstraints = false

        switchBackgroundView.addSubview(toggleSwitch)
        NSLayoutConstraint.activate([
            toggleSwitch.leadingAnchor.constraint(equalTo: switchBackgroundView.leadingAnchor, constant: 2),
            toggleSwitch.trailingAnchor.constraint(equalTo: switchBackgroundView.trailingAnchor, constant: -2),
            toggleSwitch.topAnchor.constraint(equalTo: switchBackgroundView.topAnchor, constant: 2),
            toggleSwitch.bottomAnchor.constraint(equalTo: switchBackgroundView.bottomAnchor, constant: -2)
        ])

        let stackView = NSStackView(views: [titleLabel, switchBackgroundView])
        stackView.orientation = .horizontal
        stackView.distribution = .fill
        stackView.alignment = .centerY
        
        self.addSubviewAndConstrainToEqualSize(
            stackView,
            withInsets: NSEdgeInsets(top: 5, left: 12, bottom: 5, right: 12))
        switchBackgroundView.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        switchBackgroundView.widthAnchor.constraint(equalToConstant: 52).isActive = true
        switchBackgroundView.heightAnchor.constraint(equalToConstant: 30).isActive = true
        wantsLayer = true
        layer?.cornerRadius = 6
        applyVisualState()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc func switchToggled() {
        let isOn = (toggleSwitch.state == .on)
        switchState = isOn
        onSwitchToggle(isOn)
    }

    private func applyVisualState() {
        titleLabel.textColor = .labelColor
        switchBackgroundView.layer?.backgroundColor = switchState
            ? NSColor.systemBlue.withAlphaComponent(0.35).cgColor
            : NSColor.clear.cgColor
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}


extension NSView {
    func addSubviewAndConstrainToEqualSize(
        _ subview: NSView,
        withInsets insets: NSEdgeInsets,
        includeLayoutMargins: Bool = false)
    {
        subview.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(subview)
        
        NSLayoutConstraint.activate([
            subview.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: insets.left),
            subview.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -insets.right),
            subview.topAnchor.constraint(equalTo: self.topAnchor, constant: insets.top),
            subview.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -insets.bottom),
        ])
    }
}
