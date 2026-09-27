//
//  PrefShortcutsViewController.swift
//  Shifty
//
//  Created by Nate Thompson on 11/10/17.
//

import Cocoa
import Carbon
import SwiftUI

// MARK: - PrefShortcutsView

struct PrefShortcutsView: View {
    private let integrations = SystemIntegration.shared

    var body: some View {
        Form {
            Section("prefs.shortcuts.section.night_shift") {
                ShortcutRow("prefs.shortcuts.toggle_night_shift", key: Keys.toggleNightShiftShortcut)
                ShortcutRow("prefs.shortcuts.warmer", key: Keys.incrementColorTempShortcut)
                ShortcutRow("prefs.shortcuts.cooler", key: Keys.decrementColorTempShortcut)
            }

            Section("prefs.shortcuts.section.disable_rules") {
                ShortcutRow("prefs.shortcuts.disable_app", key: Keys.disableAppShortcut)
                ShortcutRow("prefs.shortcuts.disable_domain", key: Keys.disableDomainShortcut)
                ShortcutRow("prefs.shortcuts.disable_subdomain", key: Keys.disableSubdomainShortcut)
                ShortcutRow("prefs.shortcuts.disable_hour", key: Keys.disableHourShortcut)
                ShortcutRow("prefs.shortcuts.disable_custom", key: Keys.disableCustomShortcut)
            }

            if integrations.trueTone.state != .unsupported {
                Section("prefs.shortcuts.section.true_tone") {
                    ShortcutRow("prefs.shortcuts.toggle_true_tone", key: Keys.toggleTrueToneShortcut)
                }
            }

            Section("prefs.shortcuts.section.dark_mode") {
                ShortcutRow("prefs.shortcuts.toggle_dark_mode", key: Keys.toggleDarkModeShortcut)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - ShortcutRow

private struct ShortcutRow: View {
    let labelKey: String
    let key: String

    init(_ labelKey: String, key: String) {
        self.labelKey = labelKey
        self.key = key
    }

    var body: some View {
        LabeledContent {
            ShortcutRecorderView(
                defaultsKey: key,
                accessibilityLabel: NSLocalizedString(labelKey, comment: "Shortcut action")
            )
                .frame(width: 160, height: 26)
        } label: {
            Text(LocalizedStringKey(labelKey))
        }
    }
}

// MARK: - ShortcutRecorderView (NSViewRepresentable)

struct ShortcutRecorderView: NSViewRepresentable {
    let defaultsKey: String
    let accessibilityLabel: String

    func makeNSView(context: Context) -> MASShortcutView {
        let view = MASShortcutView()
        view.accessibilityLabelText = accessibilityLabel
        view.setAssociatedUserDefaultsKey(defaultsKey, with: MASDictionaryTransformer())
        return view
    }

    func updateNSView(_ nsView: MASShortcutView, context: Context) {
        nsView.accessibilityLabelText = accessibilityLabel
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: MASShortcutView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 160, height: 26)
    }
}

// MARK: - PrefShortcutsViewController (shortcut binding manager, not a VC)

/// Manages global hotkey bindings for all shortcuts. Instantiated at launch by StatusMenuController.
@MainActor
final class PrefShortcutsViewController {
    let integrations = SystemIntegration.shared

    var statusMenuController: StatusMenuController? {
        (NSApplication.shared.delegate as? AppDelegate)?.statusMenu.delegate as? StatusMenuController
    }

    func bindShortcuts() {
        migrateLegacyShortcutDefaultsIfNeeded()

        MASShortcutBinder.shared().bindingOptions = [
            NSBindingOption.valueTransformer: MASDictionaryTransformer()
        ]

        MASShortcutBinder.shared().bindShortcut(withDefaultsKey: Keys.toggleNightShiftShortcut) {
            guard let menu = self.statusMenuController else { return }
            if !menu.powerMenuItem.isHidden && menu.powerMenuItem.isEnabled {
                self.statusMenuController?.power(self)
            } else {
                NSSound.beep()
            }
        }

        MASShortcutBinder.shared().bindShortcut(withDefaultsKey: Keys.incrementColorTempShortcut) {
            if NightShiftManager.shared.isNightShiftEnabled {
                if NightShiftManager.shared.colorTemperature == 1.0 {
                    NSSound.beep()
                }
                NightShiftManager.shared.colorTemperature += 0.1
            } else {
                NightShiftManager.shared.respond(to: .userEnabledNightShift)
                NightShiftManager.shared.colorTemperature = 0.1
            }
            CircadianWorkspaceCoordinator.shared.holdManualStrength()
        }

        MASShortcutBinder.shared().bindShortcut(withDefaultsKey: Keys.decrementColorTempShortcut) {
            if NightShiftManager.shared.isNightShiftEnabled {
                NightShiftManager.shared.colorTemperature -= 0.1
                CircadianWorkspaceCoordinator.shared.holdManualStrength()
                if NightShiftManager.shared.colorTemperature == 0.0 {
                    NSSound.beep()
                }
            } else {
                NSSound.beep()
            }
        }

        MASShortcutBinder.shared().bindShortcut(withDefaultsKey: Keys.disableAppShortcut) {
            guard let menu = self.statusMenuController else { return }
            if !menu.disableCurrentAppMenuItem.isHidden && menu.disableCurrentAppMenuItem.isEnabled {
                self.statusMenuController?.disableForCurrentApp(self)
            } else {
                NSSound.beep()
            }
        }

        MASShortcutBinder.shared().bindShortcut(withDefaultsKey: Keys.disableDomainShortcut) {
            guard let menu = self.statusMenuController else { return }
            if !menu.disableDomainMenuItem.isHidden && menu.disableDomainMenuItem.isEnabled {
                self.statusMenuController?.disableForDomain(self)
            } else {
                NSSound.beep()
            }
        }

        MASShortcutBinder.shared().bindShortcut(withDefaultsKey: Keys.disableSubdomainShortcut) {
            guard let menu = self.statusMenuController else { return }
            if !menu.disableSubdomainMenuItem.isHidden && menu.disableSubdomainMenuItem.isEnabled {
                self.statusMenuController?.disableForSubdomain(self)
            } else {
                NSSound.beep()
            }
        }

        MASShortcutBinder.shared().bindShortcut(withDefaultsKey: Keys.disableHourShortcut) {
            guard let menu = self.statusMenuController else { return }
            if !menu.disableHourMenuItem.isHidden && menu.disableHourMenuItem.isEnabled {
                self.statusMenuController?.disableHour(self)
            } else {
                NSSound.beep()
            }
        }

        MASShortcutBinder.shared().bindShortcut(withDefaultsKey: Keys.disableCustomShortcut) {
            guard let menu = self.statusMenuController else { return }
            if !menu.disableCustomMenuItem.isHidden && menu.disableCustomMenuItem.isEnabled {
                self.statusMenuController?.disableCustomTime(self)
            } else {
                NSSound.beep()
            }
        }

        MASShortcutBinder.shared().bindShortcut(withDefaultsKey: Keys.toggleTrueToneShortcut) {
            guard let menu = self.statusMenuController else { return }
            if !menu.trueToneMenuItem.isHidden && menu.trueToneMenuItem.isEnabled {
                self.statusMenuController?.toggleTrueTone(self)
            } else {
                NSSound.beep()
            }
        }

        MASShortcutBinder.shared().bindShortcut(withDefaultsKey: Keys.toggleDarkModeShortcut) {
            let current = self.integrations.appearance.darkModeEnabled
            self.integrations.appearance.darkModeEnabled = !current
        }
    }

    private var shortcutKeys: [String] {
        [
            Keys.toggleNightShiftShortcut,
            Keys.incrementColorTempShortcut,
            Keys.decrementColorTempShortcut,
            Keys.disableAppShortcut,
            Keys.disableDomainShortcut,
            Keys.disableSubdomainShortcut,
            Keys.disableHourShortcut,
            Keys.disableCustomShortcut,
            Keys.toggleTrueToneShortcut,
            Keys.toggleDarkModeShortcut
        ]
    }

    private func migrateLegacyShortcutDefaultsIfNeeded() {
        let defaults = UserDefaults.standard
        let transformer = MASDictionaryTransformer()

        for key in shortcutKeys {
            guard let value = defaults.object(forKey: key) else { continue }
            if value is [String: Any] { continue }
            guard let data = value as? Data else { continue }

            let shortcut = try? NSKeyedUnarchiver.unarchivedObject(ofClass: MASShortcut.self, from: data)

            guard let shortcut, let dictionary = transformer.reverseTransformedValue(shortcut) else {
                continue
            }
            defaults.set(dictionary, forKey: key)
        }
    }
}

// MARK: - MASShortcut

@objc(MASShortcut)
final class MASShortcut: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool { true }

    let keyCode: Int
    let modifierFlags: NSEvent.ModifierFlags

    init(keyCode: Int, modifierFlags: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags.intersection([.command, .option, .control, .shift])
    }

    required init?(coder: NSCoder) {
        let code = coder.decodeInteger(forKey: "KeyCode")
        let flags = coder.decodeInteger(forKey: "ModifierFlags")
        self.keyCode = code
        self.modifierFlags = NSEvent.ModifierFlags(rawValue: UInt(flags)).intersection([.command, .option, .control, .shift])
    }

    func encode(with coder: NSCoder) {
        coder.encode(keyCode, forKey: "KeyCode")
        coder.encode(Int(modifierFlags.rawValue), forKey: "ModifierFlags")
    }

    var keyCodeString: String {
        let keyCodeMap: [Int: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
            11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
            18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9",
            26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[",
            34: "I", 35: "P", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\",
            43: ",", 44: "/", 45: "N", 46: "M", 47: ".",
            36: "↩", 48: "⇥", 49: "␣", 51: "⌫", 53: "⎋",
            123: "←", 124: "→", 125: "↓", 126: "↑"
        ]
        return keyCodeMap[keyCode] ?? ""
    }

    var displayString: String {
        var parts = [String]()
        if modifierFlags.contains(.command) { parts.append("⌘") }
        if modifierFlags.contains(.option) { parts.append("⌥") }
        if modifierFlags.contains(.control) { parts.append("⌃") }
        if modifierFlags.contains(.shift) { parts.append("⇧") }
        let key = keyCodeString
        if !key.isEmpty { parts.append(key.uppercased()) }
        return parts.joined()
    }
}

// MARK: - MASDictionaryTransformer

@objc(MASDictionaryTransformer)
final class MASDictionaryTransformer: ValueTransformer {
    override class func transformedValueClass() -> AnyClass { NSDictionary.self }
    override class func allowsReverseTransformation() -> Bool { true }

    override func transformedValue(_ value: Any?) -> Any? {
        guard let dictionary = value as? [String: Any] else { return nil }

        let keyCode = (dictionary["KeyCode"] as? Int)
            ?? (dictionary["keyCode"] as? Int)
            ?? (dictionary["keyCode"] as? NSNumber)?.intValue
        let modifierFlagsRaw = (dictionary["ModifierFlags"] as? Int)
            ?? (dictionary["modifierFlags"] as? Int)
            ?? (dictionary["modifierFlags"] as? NSNumber)?.intValue

        guard let keyCode, let modifierFlagsRaw else { return nil }
        return MASShortcut(
            keyCode: keyCode,
            modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(modifierFlagsRaw)))
    }

    override func reverseTransformedValue(_ value: Any?) -> Any? {
        guard let shortcut = value as? MASShortcut else { return nil }
        return [
            "KeyCode": shortcut.keyCode,
            "ModifierFlags": Int(shortcut.modifierFlags.rawValue)
        ]
    }
}

// MARK: - MASShortcutView

@objc(MASShortcutView)
final class MASShortcutView: NSView {
    var accessibilityLabelText = "" {
        didSet { updateAccessibility() }
    }

    var shortcutValue: MASShortcut? {
        didSet {
            updateDisplay()
            saveShortcut()
        }
    }

    private var defaultsKey: String?
    private var transformer: ValueTransformer?
    private let label = NSTextField(labelWithString: "")
    private let clearButton = NSButton(title: "✕", target: nil, action: nil)
    private var recording = false {
        didSet { updateDisplay() }
    }

    override var acceptsFirstResponder: Bool { true }

    override var focusRingMaskBounds: NSRect { bounds }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6).fill()
    }

    func setAssociatedUserDefaultsKey(_ key: String, with transformer: Any?) {
        defaultsKey = key
        self.transformer = transformer as? ValueTransformer
        loadShortcut()
    }

    override func mouseDown(with event: NSEvent) {
        _ = event
        window?.makeFirstResponder(self)
        startRecording()
    }

    override func keyDown(with event: NSEvent) {
        if recording {
            handleRecordingKey(event)
            return
        }

        switch Int(event.keyCode) {
        case kVK_Space, kVK_Return, kVK_ANSI_KeypadEnter:
            startRecording()
        case kVK_Delete, kVK_ForwardDelete:
            clearShortcut()
        default:
            super.keyDown(with: event)
        }
    }

    override func becomeFirstResponder() -> Bool {
        let becameFirstResponder = super.becomeFirstResponder()
        needsDisplay = true
        return becameFirstResponder
    }

    override func resignFirstResponder() -> Bool {
        stopRecording()
        let resigned = super.resignFirstResponder()
        needsDisplay = true
        return resigned
    }

    override func accessibilityPerformPress() -> Bool {
        window?.makeFirstResponder(self)
        startRecording()
        return true
    }

    private func configure() {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        focusRingType = .exterior
        setAccessibilityElement(true)
        setAccessibilityRole(.button)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center
        label.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        addSubview(label)

        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.isBordered = false
        clearButton.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        clearButton.contentTintColor = .secondaryLabelColor
        clearButton.target = self
        clearButton.action = #selector(clearShortcut)
        clearButton.focusRingType = .default
        clearButton.toolTip = NSLocalizedString(
            "prefs.shortcuts.recorder.clear",
            comment: "Clear the recorded shortcut"
        )
        clearButton.setAccessibilityLabel(clearButton.toolTip)
        addSubview(clearButton)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            clearButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            clearButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            clearButton.widthAnchor.constraint(equalToConstant: 14),
            clearButton.heightAnchor.constraint(equalToConstant: 14)
        ])

        updateDisplay()
    }

    @objc private func clearShortcut() {
        shortcutValue = nil
        stopRecording()
    }

    private func startRecording() {
        recording = true
    }

    private func stopRecording() {
        recording = false
    }

    private func handleRecordingKey(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            stopRecording()
            return
        }

        if event.keyCode == UInt16(kVK_Delete) || event.keyCode == UInt16(kVK_ForwardDelete) {
            clearShortcut()
            return
        }

        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !modifiers.isEmpty else {
            NSSound.beep()
            return
        }

        shortcutValue = MASShortcut(keyCode: Int(event.keyCode), modifierFlags: modifiers)
        stopRecording()
    }

    private func loadShortcut() {
        guard let defaultsKey else { return }
        let value = UserDefaults.standard.object(forKey: defaultsKey)

        if let dictionary = value as? [String: Any],
           let transformed = transformer?.transformedValue(dictionary) as? MASShortcut {
            shortcutValue = transformed
            return
        }
        if let data = value as? Data,
           let shortcut = try? NSKeyedUnarchiver.unarchivedObject(ofClass: MASShortcut.self, from: data) {
            shortcutValue = shortcut
            return
        }
        shortcutValue = nil
    }

    private func saveShortcut() {
        guard let defaultsKey else { return }
        if let shortcutValue, let dictionary = transformer?.reverseTransformedValue(shortcutValue) {
            UserDefaults.standard.set(dictionary, forKey: defaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        }
    }

    private func updateDisplay() {
        if recording {
            label.stringValue = NSLocalizedString(
                "prefs.shortcuts.recorder.type_shortcut",
                comment: "Prompt shown while recording a shortcut"
            )
            label.textColor = .labelColor
            layer?.borderColor = NSColor.systemBlue.cgColor
            layer?.backgroundColor = NSColor.selectedControlColor.withAlphaComponent(0.15).cgColor
            clearButton.isHidden = true
            updateAccessibility()
            return
        }

        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        if let shortcutValue {
            label.stringValue = shortcutValue.displayString
            label.textColor = .labelColor
            clearButton.isHidden = false
        } else {
            label.stringValue = NSLocalizedString(
                "prefs.shortcuts.recorder.record",
                comment: "Prompt to record a shortcut"
            )
            label.textColor = .placeholderTextColor
            clearButton.isHidden = true
        }
        updateAccessibility()
    }

    private func updateAccessibility() {
        setAccessibilityLabel(accessibilityLabelText)

        let helpFormat = NSLocalizedString(
            "prefs.shortcuts.recorder.help_format",
            comment: "Accessibility help for a shortcut recorder"
        )
        setAccessibilityHelp(String.localizedStringWithFormat(helpFormat, accessibilityLabelText))

        if recording {
            setAccessibilityValue(NSLocalizedString(
                "prefs.shortcuts.recorder.recording",
                comment: "Shortcut recorder is listening"
            ))
        } else if let shortcutValue {
            setAccessibilityValue(shortcutValue.displayString)
        } else {
            setAccessibilityValue(NSLocalizedString(
                "prefs.shortcuts.recorder.not_set",
                comment: "No shortcut is assigned"
            ))
        }
    }
}

// MARK: - MASShortcutBinder

final class MASShortcutBinder {
    static let sharedBinder = MASShortcutBinder()

    class func shared() -> MASShortcutBinder { sharedBinder }

    var bindingOptions: [NSBindingOption: Any] = [:]

    private var actions = [String: () -> Void]()
    private var hotKeyRefs = [String: EventHotKeyRef]()
    private var hotKeyIDs = [String: UInt32]()
    private var idToDefaultsKey = [UInt32: String]()
    private var nextID: UInt32 = 1
    private var eventHandlerRef: EventHandlerRef?
    private var defaultsObserver: NSObjectProtocol?
    private let signature: OSType = 0x53484659 // SHFY

    private init() {
        installEventHandlerIfNeeded()
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.reloadAll()
        }
    }

    deinit {
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
    }

    func bindShortcut(withDefaultsKey key: String, toAction action: @escaping () -> Void) {
        actions[key] = action
        registerHotKey(for: key)
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(noErr) }
                let binder = Unmanaged<MASShortcutBinder>.fromOpaque(userData).takeUnretainedValue()
                return binder.handleHotKeyEvent(event)
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
    }

    private func handleHotKeyEvent(_ event: EventRef) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr,
              let defaultsKey = idToDefaultsKey[hotKeyID.id],
              let action = actions[defaultsKey] else { return OSStatus(noErr) }
        DispatchQueue.main.async(execute: action)
        return OSStatus(noErr)
    }

    private func reloadAll() {
        for key in actions.keys { registerHotKey(for: key) }
    }

    private func registerHotKey(for defaultsKey: String) {
        if let ref = hotKeyRefs[defaultsKey] {
            UnregisterEventHotKey(ref)
            hotKeyRefs.removeValue(forKey: defaultsKey)
        }

        guard let shortcut = shortcutFromDefaults(forKey: defaultsKey) else { return }
        let id = hotKeyIDs[defaultsKey] ?? allocateID(for: defaultsKey)

        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            shortcut.modifierFlags.carbonFlags,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr, let hotKeyRef else { return }
        hotKeyRefs[defaultsKey] = hotKeyRef
    }

    private func allocateID(for defaultsKey: String) -> UInt32 {
        let id = nextID
        nextID += 1
        hotKeyIDs[defaultsKey] = id
        idToDefaultsKey[id] = defaultsKey
        return id
    }

    private func shortcutFromDefaults(forKey key: String) -> MASShortcut? {
        let defaults = UserDefaults.standard
        if let dictionary = defaults.object(forKey: key) as? [String: Any] {
            return MASDictionaryTransformer().transformedValue(dictionary) as? MASShortcut
        }
        if let data = defaults.object(forKey: key) as? Data {
            return try? NSKeyedUnarchiver.unarchivedObject(ofClass: MASShortcut.self, from: data)
        }
        return nil
    }
}

// MARK: - NSEvent.ModifierFlags + Carbon

private extension NSEvent.ModifierFlags {
    var carbonFlags: UInt32 {
        var flags: UInt32 = 0
        if contains(.command) { flags |= UInt32(cmdKey) }
        if contains(.option) { flags |= UInt32(optionKey) }
        if contains(.control) { flags |= UInt32(controlKey) }
        if contains(.shift) { flags |= UInt32(shiftKey) }
        return flags
    }
}
