//
//  GeneralPreferencesViewController.swift
//  Shifty
//
//  Created by Nate Thompson on 11/10/17.
//

import Cocoa
import MASPreferences_Shifty
import SwiftLog


@objcMembers
class PrefGeneralViewController: NSViewController, MASPreferencesViewController {
    let integrations = SystemIntegration.shared
    let launcherAppIdentifier = "io.natethompson.ShiftyHelper"

    override var nibName: NSNib.Name {
        return "PrefGeneralViewController"
    }

    var viewIdentifier: String = "PrefGeneralViewController"

    var toolbarItemImage: NSImage? {
        NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
    }

    var toolbarItemLabel: String? {
        view.layoutSubtreeIfNeeded()
        return NSLocalizedString("prefs.general", comment: "General")
    }

    var hasResizableWidth = false
    var hasResizableHeight = false

    @IBOutlet weak var autoLaunchButton: NSButton!
    @IBOutlet weak var quickToggleButton: NSButton!
    @IBOutlet weak var iconSwitchingButton: NSButton!
    @IBOutlet weak var darkModeSyncButton: NSButton!
    @IBOutlet weak var websiteShiftingButton: NSButton!
    @IBOutlet weak var trueToneControlButton: NSButton!
    private var kelvinDisplayButton: NSButton?
    
    @IBOutlet weak var trueToneStackView: NSStackView!
    
    @IBOutlet weak var schedulePopup: NSPopUpButton!
    @IBOutlet weak var offMenuItem: NSMenuItem!
    @IBOutlet weak var customMenuItem: NSMenuItem!
    @IBOutlet weak var sunMenuItem: NSMenuItem!

    @IBOutlet weak var fromTimePicker: NSDatePicker!
    @IBOutlet weak var toTimePicker: NSDatePicker!
    @IBOutlet weak var fromLabel: NSTextField!
    @IBOutlet weak var toLabel: NSTextField!
    @IBOutlet weak var customTimeStackView: NSStackView!

    var appDelegate: AppDelegate!
    var prefWindow: NSWindow!
    
    var defaultDarkModeState: Bool!

    override func viewDidLoad() {
        super.viewDidLoad()

        appDelegate = NSApplication.shared.delegate as? AppDelegate
        prefWindow = appDelegate.preferenceWindowController.window
        
        NightShiftManager.shared.onNightShiftChange {
            self.updateSchedule()
        }

        //Hide True Tone settings on unsupported computers
        trueToneStackView.isHidden = integrations.trueTone.state == .unsupported
        
        defaultDarkModeState = integrations.appearance.darkModeEnabled

        configureKelvinDisplayCheckbox()
    }

    override func viewWillAppear() {
        super.viewWillAppear()

        let loginItemEnabled = integrations.loginItem.isEnabled(helperBundleIdentifier: launcherAppIdentifier)
        autoLaunchButton.state = loginItemEnabled ? .on : .off
        UserDefaults.standard.set(loginItemEnabled, forKey: Keys.isAutoLaunchEnabled)
        kelvinDisplayButton?.state = UserDefaults.standard.bool(forKey: Keys.showKelvinInMenuSlider) ? .on : .off
        updateSchedule()

        if let window = prefWindow {
            let targetSize = NSSize(width: 700, height: 560)
            if window.frame.size.width < targetSize.width || window.frame.size.height < targetSize.height {
                window.setContentSize(targetSize)
            }
        }
    }
    
    func updateSchedule() {
        switch NightShiftManager.shared.schedule {
        case .off:
            self.schedulePopup.select(self.offMenuItem)
            self.customTimeStackView.isHidden = true
        case .custom(start: let startTime, end: let endTime):
            self.schedulePopup.select(self.customMenuItem)
            let startDate = Date(startTime)
            let endDate = Date(endTime)
            
            self.fromTimePicker.dateValue = startDate
            self.toTimePicker.dateValue = endDate
            self.customTimeStackView.isHidden = false
        case .solar:
            self.schedulePopup.select(self.sunMenuItem)
            self.customTimeStackView.isHidden = true
        }
    }

    //MARK: IBActions

    @IBAction func setAutoLaunch(_ sender: NSButtonCell) {
        let shouldEnable = sender.state == .on
        let didSet = integrations.loginItem.setEnabled(shouldEnable, helperBundleIdentifier: launcherAppIdentifier)
        let actualEnabled = didSet
            ? shouldEnable
            : integrations.loginItem.isEnabled(helperBundleIdentifier: launcherAppIdentifier)

        sender.state = actualEnabled ? .on : .off
        UserDefaults.standard.set(actualEnabled, forKey: Keys.isAutoLaunchEnabled)

        if !didSet {
            NSSound.beep()
            logw("Failed to set auto launch on login state")
        } else {
            logw("Auto launch on login set to \(sender.state.rawValue)")
        }
    }

    @IBAction func quickToggle(_ sender: NSButtonCell) {
        let appDelegate = NSApplication.shared.delegate as! AppDelegate
        appDelegate.setStatusToggle()
        logw("Quick Toggle set to \(sender.state.rawValue)")
    }

    @IBAction func setIconSwitching(_ sender: NSButtonCell) {
        let appDelegate = NSApplication.shared.delegate as! AppDelegate
        appDelegate.updateMenuBarIcon()
        logw("Icon switching set to \(sender.state.rawValue)")
    }

    @IBAction func syncDarkMode(_ sender: NSButtonCell) {
        if sender.state == .on {
            defaultDarkModeState = integrations.appearance.darkModeEnabled
            NightShiftManager.shared.updateDarkMode()
        } else {
            integrations.appearance.darkModeEnabled = defaultDarkModeState
        }
        logw("Dark mode sync preference set to \(sender.state.rawValue)")
    }

    @IBAction func setWebsiteControl(_ sender: NSButtonCell) {
        logw("Website control preference clicked")
        if sender.state == .on {
            if !integrations.permissions.isAccessibilityTrusted(prompt: false) {
                logw("Accessibility permissions alert shown")

                UserDefaults.standard.set(false, forKey: Keys.isWebsiteControlEnabled)
                NSApp.runModal(for: AccessibilityWindow().window!)
            }
        } else {
            BrowserManager.shared.stopBrowserWatcher()
            logw("Website control disabled")
        }
    }
    
    @IBAction func setTrueToneControl(_ sender: NSButtonCell) {
        if integrations.trueTone.state != .unsupported {
            if sender.state == .on {
                if NightShiftManager.shared.isDisableRuleActive {
                    integrations.trueTone.isEnabled = false
                }
            } else {
                integrations.trueTone.isEnabled = true
            }
            logw("True Tone control set to \(sender.state.rawValue)")
        }
    }
    
    @IBAction func analyticsDetailClicked(_ sender: Any) {
        self.presentAsSheet(AnalyticsDetailViewController())
    }

    @objc private func setShowKelvinInMenuSlider(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: Keys.showKelvinInMenuSlider)
    }
    
    @IBAction func schedulePopup(_ sender: NSPopUpButton) {
        if schedulePopup.selectedItem == offMenuItem {
            NightShiftManager.shared.schedule = .off
            customTimeStackView.isHidden = true
        } else if schedulePopup.selectedItem == customMenuItem {
            scheduleTimePickers(self)
            customTimeStackView.isHidden = false
        } else if schedulePopup.selectedItem == sunMenuItem {
            NightShiftManager.shared.schedule = .solar
            customTimeStackView.isHidden = true
        }
    }

    @IBAction func scheduleTimePickers(_ sender: Any) {
        let fromTime = Time(fromTimePicker.dateValue)
        let toTime = Time(toTimePicker.dateValue)
        NightShiftManager.shared.schedule = .custom(start: fromTime, end: toTime)
    }

    override func viewWillDisappear() {
        Event.preferences(autoLaunch: autoLaunchButton.state == .on,
                          quickToggle: quickToggleButton.state == .on,
                          iconSwitching: iconSwitchingButton.state == .on,
                          syncDarkMode: darkModeSyncButton.state == .on,
                          websiteShifting: websiteShiftingButton.state == .on,
                          trueToneControl: trueToneControlButton.state == .on,
                          schedule: NightShiftManager.shared.schedule).record()
    }

    private func configureKelvinDisplayCheckbox() {
        let checkbox = NSButton(checkboxWithTitle: "Show Kelvin values in menu slider", target: self, action: #selector(setShowKelvinInMenuSlider(_:)))
        checkbox.translatesAutoresizingMaskIntoConstraints = false
        checkbox.state = UserDefaults.standard.bool(forKey: Keys.showKelvinInMenuSlider) ? .on : .off
        view.addSubview(checkbox)

        NSLayoutConstraint.activate([
            checkbox.leadingAnchor.constraint(equalTo: darkModeSyncButton.leadingAnchor),
            checkbox.topAnchor.constraint(greaterThanOrEqualTo: schedulePopup.bottomAnchor, constant: 48),
            checkbox.topAnchor.constraint(greaterThanOrEqualTo: customTimeStackView.bottomAnchor, constant: 16),
            checkbox.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20)
        ])

        kelvinDisplayButton = checkbox
    }
}

@objcMembers
class PrefWhitelistViewController: NSViewController, MASPreferencesViewController {
    override var nibName: NSNib.Name? { nil }

    var viewIdentifier: String = "PrefWhitelistViewController"

    var toolbarItemImage: NSImage? {
        NSImage(systemSymbolName: "list.bullet.rectangle", accessibilityDescription: nil)
    }

    var toolbarItemLabel: String? {
        "Whitelist"
    }

    var hasResizableWidth = false
    var hasResizableHeight = false

    private let textView = NSTextView()
    private let minimumVisibleRows = 10

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 560))
        preferredContentSize = NSSize(width: 700, height: 560)

        let title = NSTextField(labelWithString: "Apps and websites currently excluded from shifting")
        title.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.borderType = .bezelBorder
        scroll.hasVerticalScroller = true
        scroll.documentView = textView

        textView.isEditable = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.string = ""

        view.addSubview(title)
        view.addSubview(scroll)

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            title.topAnchor.constraint(equalTo: view.topAnchor, constant: 18),

            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            scroll.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 10),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20)
        ])
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        if let window = view.window {
            let targetSize = NSSize(width: 700, height: 560)
            if window.frame.size.width < targetSize.width || window.frame.size.height < targetSize.height {
                window.setContentSize(targetSize)
            }
        }
        refreshWhitelistText()
    }

    private func refreshWhitelistText() {
        let manager = RuleManager.shared
        var lines = [String]()

        lines.append("Applications")
        let appRules = manager.currentAppDisableRuleSnapshot
        let appLines = appRules.map { "- \($0.bundleIdentifier)" }
        lines.append(contentsOf: appLines)
        if appLines.count < minimumVisibleRows {
            lines.append(contentsOf: Array(repeating: "-", count: minimumVisibleRows - appLines.count))
        }

        lines.append("")
        lines.append("When Running")
        let runningRules = manager.runningAppDisableRuleSnapshot
        let runningLines = runningRules.map { "- \($0.bundleIdentifier)" }
        lines.append(contentsOf: runningLines)
        if runningLines.count < minimumVisibleRows {
            lines.append(contentsOf: Array(repeating: "-", count: minimumVisibleRows - runningLines.count))
        }

        lines.append("")
        lines.append("Websites")
        let browserRules = manager.browserRuleSnapshot
        let browserLines = browserRules.map { "- \($0.type.rawValue): \($0.host)" }
        lines.append(contentsOf: browserLines)
        if browserLines.count < minimumVisibleRows {
            lines.append(contentsOf: Array(repeating: "-", count: minimumVisibleRows - browserLines.count))
        }

        textView.string = lines.joined(separator: "\n")
    }
}


class PrefWindowController: MASPreferencesWindowController {
    override func windowDidLoad() {
        super.windowDidLoad()
        window?.styleMask = [.titled, .closable]
        window?.toolbarStyle = .preference
    }
    
    
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 13 && event.modifierFlags.contains(.command) {
            window?.close()
        }
    }
}
