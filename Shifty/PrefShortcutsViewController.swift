//
//  PrefShortcutsViewController.swift
//  Shifty
//
//  Created by Nate Thompson on 11/10/17.
//

import Cocoa
import MASPreferences_Shifty
import Carbon

@objcMembers
class PrefShortcutsViewController: NSViewController, MASPreferencesViewController {
    let integrations = SystemIntegration.shared

    let statusMenuController = (NSApplication.shared.delegate as? AppDelegate)?.statusMenu.delegate as? StatusMenuController

    override var nibName: NSNib.Name {
        return "PrefShortcutsViewController"
    }

    var viewIdentifier: String = "PrefShortcutsViewController"

    var toolbarItemImage: NSImage? {
        NSImage(systemSymbolName: "command", accessibilityDescription: nil)
    }

    var toolbarItemLabel: String? {
        view.layoutSubtreeIfNeeded()
        return NSLocalizedString("prefs.shortcuts", comment: "Shortcuts")
    }

    var hasResizableWidth = false
    var hasResizableHeight = false
    
    @IBOutlet weak var toggleTrueToneLabel: NSTextField!
    
    @IBOutlet weak var toggleNightShiftShortcut: MASShortcutView!
    @IBOutlet weak var incrementColorTempShortcut: MASShortcutView!
    @IBOutlet weak var decrementColorTempShortcut: MASShortcutView!
    @IBOutlet weak var disableAppShortcut: MASShortcutView!
    @IBOutlet weak var disableDomainShortcut: MASShortcutView!
    @IBOutlet weak var disableSubdomainShortcut: MASShortcutView!
    @IBOutlet weak var disableHourShortcut: MASShortcutView!
    @IBOutlet weak var disableCustomShortcut: MASShortcutView!
    @IBOutlet weak var toggleTrueToneShortcut: MASShortcutView!
    @IBOutlet weak var toggleDarkModeShortcut: MASShortcutView!

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

    private let shortcutDefaultsTransformer = MASDictionaryTransformer()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        //Hide True Tone settings on unsupported computers
        let trueToneUnsupported = integrations.trueTone.state == .unsupported
        toggleTrueToneLabel.isHidden = trueToneUnsupported
        toggleTrueToneShortcut.isHidden = trueToneUnsupported

        migrateLegacyShortcutDefaultsIfNeeded()

        toggleNightShiftShortcut.setAssociatedUserDefaultsKey(
            Keys.toggleNightShiftShortcut,
            with: shortcutDefaultsTransformer)
        incrementColorTempShortcut.setAssociatedUserDefaultsKey(
            Keys.incrementColorTempShortcut,
            with: shortcutDefaultsTransformer)
        decrementColorTempShortcut.setAssociatedUserDefaultsKey(
            Keys.decrementColorTempShortcut,
            with: shortcutDefaultsTransformer)
        disableAppShortcut.setAssociatedUserDefaultsKey(
            Keys.disableAppShortcut,
            with: shortcutDefaultsTransformer)
        disableDomainShortcut.setAssociatedUserDefaultsKey(
            Keys.disableDomainShortcut,
            with: shortcutDefaultsTransformer)
        disableSubdomainShortcut.setAssociatedUserDefaultsKey(
            Keys.disableSubdomainShortcut,
            with: shortcutDefaultsTransformer)
        disableHourShortcut.setAssociatedUserDefaultsKey(
            Keys.disableHourShortcut,
            with: shortcutDefaultsTransformer)
        disableCustomShortcut.setAssociatedUserDefaultsKey(
            Keys.disableCustomShortcut,
            with: shortcutDefaultsTransformer)
        toggleTrueToneShortcut.setAssociatedUserDefaultsKey(
            Keys.toggleTrueToneShortcut,
            with: shortcutDefaultsTransformer)
        toggleDarkModeShortcut.setAssociatedUserDefaultsKey(
            Keys.toggleDarkModeShortcut,
            with: shortcutDefaultsTransformer)

        applyLayoutPolishForShortcutRows()
    }

    override func viewWillDisappear() {
        Event.shortcuts(toggleNightShift: toggleNightShiftShortcut.shortcutValue != nil,
                        increaseColorTemp: incrementColorTempShortcut.shortcutValue != nil,
                        decreaseColorTemp: decrementColorTempShortcut.shortcutValue != nil,
                        disableApp: disableAppShortcut.shortcutValue != nil,
                        disableDomain: disableDomainShortcut.shortcutValue != nil,
                        disableSubdomain: disableSubdomainShortcut.shortcutValue != nil,
                        disableHour: disableHourShortcut.shortcutValue != nil,
                        disableCustom: disableCustomShortcut.shortcutValue != nil,
                        toggleTrueTone: toggleTrueToneShortcut.shortcutValue != nil,
                        toggleDarkMode: toggleDarkModeShortcut.shortcutValue != nil).record()
    }

    func bindShortcuts() {
        MASShortcutBinder.shared().bindingOptions = [
            NSBindingOption.valueTransformer: shortcutDefaultsTransformer
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
        }

        MASShortcutBinder.shared().bindShortcut(withDefaultsKey: Keys.decrementColorTempShortcut) {
            if NightShiftManager.shared.isNightShiftEnabled {
                NightShiftManager.shared.colorTemperature -= 0.1
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
        
        MASShortcutBinder.shared().bindShortcut(withDefaultsKey: Keys.toggleDarkModeShortcut, toAction: {
            let currentState = self.integrations.appearance.darkModeEnabled
            self.integrations.appearance.darkModeEnabled = !currentState
        })
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

    private func applyLayoutPolishForShortcutRows() {
        // Prevent localized labels from visually colliding with shortcut recorders.
        for subview in view.subviews {
            guard let label = subview as? NSTextField else { continue }
            guard !label.isEditable else { continue }
            label.maximumNumberOfLines = 1
            label.lineBreakMode = .byTruncatingTail
            label.cell?.truncatesLastVisibleLine = true
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
    }
}

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
        if !key.isEmpty {
            parts.append(key.uppercased())
        }
        return parts.joined()
    }
}

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

@objc(MASShortcutView)
final class MASShortcutView: NSView {
    var shortcutValue: MASShortcut? {
        didSet {
            updateDisplay()
            saveShortcut()
        }
    }

    private var defaultsKey: String?
    private var transformer: ValueTransformer?
    private let label = NSTextField(labelWithString: "")
    private let clearButton = NSButton(title: "x", target: nil, action: nil)
    private var localMonitor: Any?
    private var recording = false {
        didSet { updateDisplay() }
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    deinit {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
    }

    func setAssociatedUserDefaultsKey(_ key: String, with transformer: Any?) {
        defaultsKey = key
        self.transformer = transformer as? ValueTransformer
        loadShortcut()
    }

    override func mouseDown(with event: NSEvent) {
        _ = event
        startRecording()
    }

    private func configure() {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center
        label.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        addSubview(label)

        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.isBordered = false
        clearButton.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        clearButton.contentTintColor = .secondaryLabelColor
        clearButton.target = self
        clearButton.action = #selector(clearShortcut)
        clearButton.focusRingType = .none
        addSubview(clearButton)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            clearButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            clearButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            clearButton.widthAnchor.constraint(equalToConstant: 14),
            clearButton.heightAnchor.constraint(equalToConstant: 14)
        ])

        updateDisplay()
    }

    @objc
    private func clearShortcut() {
        shortcutValue = nil
        stopRecording()
    }

    private func startRecording() {
        recording = true
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])

            if event.keyCode == UInt16(kVK_Escape) {
                self.shortcutValue = nil
                self.stopRecording()
                return nil
            }

            guard !modifiers.isEmpty else {
                NSSound.beep()
                return nil
            }

            self.shortcutValue = MASShortcut(keyCode: Int(event.keyCode), modifierFlags: modifiers)
            self.stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        recording = false
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    private func loadShortcut() {
        guard let defaultsKey else { return }
        let defaults = UserDefaults.standard
        let value = defaults.object(forKey: defaultsKey)

        if let dictionary = value as? [String: Any], let transformed = transformer?.transformedValue(dictionary) as? MASShortcut {
            shortcutValue = transformed
            return
        }

        if let data = value as? Data, let shortcut = try? NSKeyedUnarchiver.unarchivedObject(ofClass: MASShortcut.self, from: data) {
            shortcutValue = shortcut
            return
        }

        shortcutValue = nil
    }

    private func saveShortcut() {
        guard let defaultsKey else { return }
        let defaults = UserDefaults.standard
        if let shortcutValue, let dictionary = transformer?.reverseTransformedValue(shortcutValue) {
            defaults.set(dictionary, forKey: defaultsKey)
        } else {
            defaults.removeObject(forKey: defaultsKey)
        }
    }

    private func updateDisplay() {
        if recording {
            label.stringValue = "Type Shortcut..."
            layer?.borderColor = NSColor.systemBlue.cgColor
            clearButton.isHidden = true
            return
        }

        layer?.borderColor = NSColor.separatorColor.cgColor
        if let shortcutValue {
            label.stringValue = shortcutValue.displayString
            clearButton.isHidden = false
        } else {
            label.stringValue = "Record Shortcut"
            clearButton.isHidden = true
        }
    }
}

final class MASShortcutBinder {
    static let sharedBinder = MASShortcutBinder()

    class func shared() -> MASShortcutBinder {
        sharedBinder
    }

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

        guard status == noErr, let defaultsKey = idToDefaultsKey[hotKeyID.id], let action = actions[defaultsKey] else {
            return OSStatus(noErr)
        }

        DispatchQueue.main.async(execute: action)
        return OSStatus(noErr)
    }

    private func reloadAll() {
        for key in actions.keys {
            registerHotKey(for: key)
        }
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
