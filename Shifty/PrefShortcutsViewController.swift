//
//  PrefShortcutsViewController.swift
//  Shifty
//
//  Created by Nate Thompson on 11/10/17.
//

import Cocoa
import MASPreferences_Shifty
import MASShortcut

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
