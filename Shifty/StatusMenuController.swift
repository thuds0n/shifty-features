//
//  StatusMenuController.swift
//  Shifty
//
//  Created by Nate Thompson on 5/3/17.
//
//

import Cocoa
import MASShortcut
import AXSwift
import SwiftLog

class StatusMenuController: NSObject, NSMenuDelegate {
    let integrations = SystemIntegration.shared

    private var circadianModeMenuItem = NSMenuItem()
    private var darkModeMenuItem = NSMenuItem()
    private var disableForMenuItem = NSMenuItem()
    private var disableFor10MenuItem = NSMenuItem()
    private var disableFor30MenuItem = NSMenuItem()
    private var disableFor60MenuItem = NSMenuItem()
    private var disableForCustomMenuItem = NSMenuItem()
    private var disableForResumeMenuItem = NSMenuItem()

    @IBOutlet weak var statusMenu: NSMenu!
    @IBOutlet weak var powerMenuItem: NSMenuItem!
    @IBOutlet weak var trueToneMenuItem: NSMenuItem!
    @IBOutlet weak var sliderMenuItem: NSMenuItem!
    @IBOutlet weak var descriptionMenuItem: NSMenuItem!
    @IBOutlet weak var disableCurrentAppMenuItem: NSMenuItem!
    @IBOutlet weak var disableRunningAppMenuItem: NSMenuItem!
    @IBOutlet weak var disableDomainMenuItem: NSMenuItem!
    @IBOutlet weak var disableSubdomainMenuItem: NSMenuItem!
    @IBOutlet weak var enableBrowserAutomationMenuItem: NSMenuItem!
    @IBOutlet weak var disableHourMenuItem: NSMenuItem!
    @IBOutlet weak var disableCustomMenuItem: NSMenuItem!
    @IBOutlet weak var preferencesMenuItem: NSMenuItem!
    @IBOutlet weak var quitMenuItem: NSMenuItem!
    @IBOutlet weak var sliderView: SliderView!
    @IBOutlet weak var sunIcon: NSImageView! {
        didSet {
            sunIcon.image?.isTemplate = true
        }
    }
    @IBOutlet weak var moonIcon: NSImageView! {
        didSet {
            moonIcon.image?.isTemplate = true
        }
    }

    var preferencesWindow: NSWindowController!
    var prefGeneral: PrefGeneralViewController!
    var prefShortcuts: PrefShortcutsViewController!
    var customTimeWindow: CustomTimeWindow!
    
    var nightShiftSwitchView: NSView?
    var trueToneSwitchView: NSView?
    var darkModeSwitchView: NSView?
    
    let calendar = NSCalendar(identifier: .gregorian)!
    

    //MARK: Menu life cycle

    override func awakeFromNib() {
        Log.logger.directory = "~/Library/Logs/Shifty"
        #if DEBUG
            Log.logger.name = "Shifty-debug"
        #else
            Log.logger.name = "Shifty"
        #endif
        //Edit printToConsole parameter in Edit Scheme > Run > Arguments > Environment Variables
        Log.logger.printToConsole = ProcessInfo.processInfo.environment["print_log"] == "true"

        
        
        statusMenu.delegate = self
        customTimeWindow = CustomTimeWindow()
        
        

        let prefWindow = (NSApplication.shared.delegate as? AppDelegate)?.preferenceWindowController
        prefGeneral = prefWindow?.viewControllers.compactMap { childViewController in
            return childViewController as? PrefGeneralViewController
        }.first
        prefShortcuts = prefWindow?.viewControllers.compactMap { childViewController in
            return childViewController as? PrefShortcutsViewController
        }.first
        
        descriptionMenuItem.isEnabled = false
        sliderMenuItem.view = sliderView
        
        nightShiftSwitchView = SwitchView(title: "Night Shift", onSwitchToggle: { isSwitchEnabled in
            NightShiftManager.shared.isNightShiftEnabled = isSwitchEnabled
            self.updateMenuItems()
        })
        guard let nightShiftSwitchView = nightShiftSwitchView else { return }
        
        nightShiftSwitchView.frame = CGRect(
            x: 0, y: 0,
            width: statusMenu.size.width,
            height: nightShiftSwitchView.fittingSize.height)
        powerMenuItem.view = nightShiftSwitchView
        
        trueToneSwitchView = SwitchView(title: "True Tone", onSwitchToggle: { isSwitchEnabled in
            self.integrations.trueTone.isEnabled = isSwitchEnabled
            self.updateMenuItems()
        })
        guard let trueToneSwitchView = trueToneSwitchView else { return }
        
        trueToneSwitchView.frame = CGRect(
            x: 0, y: 0,
            width: statusMenu.size.width,
            height: trueToneSwitchView.fittingSize.height)

        darkModeSwitchView = SwitchView(title: "Dark Mode", onSwitchToggle: { isSwitchEnabled in
            self.integrations.appearance.darkModeEnabled = isSwitchEnabled
            self.updateMenuItems()
        })
        guard let darkModeSwitchView = darkModeSwitchView else { return }
        darkModeSwitchView.frame = CGRect(
            x: 0, y: 0,
            width: statusMenu.size.width,
            height: darkModeSwitchView.fittingSize.height)

        disableHourMenuItem.title = NSLocalizedString("menu.disable_hour", comment: "Disable for an hour")
        disableCustomMenuItem.title = NSLocalizedString("menu.disable_custom", comment: "Disable for custom time...")
        preferencesMenuItem.title = NSLocalizedString("menu.preferences", comment: "Preferences...")
        quitMenuItem.title = NSLocalizedString("menu.quit", comment: "Quit Shifty")
        configureMenuCleanupItems()
        configureCircadianMenuItems()

        (NSApp.delegate as? AppDelegate)?.statusItemClicked = {
            NightShiftManager.shared.isNightShiftEnabled.toggle()
        }

        prefShortcuts.bindShortcuts()
    }
    
    
    

    func menuWillOpen(_: NSMenu) {
        updateMenuItems()
        setDescriptionText()
        
        assignKeyboardShortcutToMenuItem(powerMenuItem, userDefaultsKey: Keys.toggleNightShiftShortcut)
        assignKeyboardShortcutToMenuItem(disableCurrentAppMenuItem, userDefaultsKey: Keys.disableAppShortcut)
        assignKeyboardShortcutToMenuItem(disableDomainMenuItem, userDefaultsKey: Keys.disableDomainShortcut)
        assignKeyboardShortcutToMenuItem(disableSubdomainMenuItem, userDefaultsKey: Keys.disableSubdomainShortcut)
        assignKeyboardShortcutToMenuItem(disableFor60MenuItem, userDefaultsKey: Keys.disableHourShortcut)
        assignKeyboardShortcutToMenuItem(disableForCustomMenuItem, userDefaultsKey: Keys.disableCustomShortcut)
        assignKeyboardShortcutToMenuItem(trueToneMenuItem, userDefaultsKey: Keys.toggleTrueToneShortcut)

        Event.menuOpened.record()
    }
    
    
    
    
    func updateMenuItems() {
        var currentAppName = RuleManager.shared.currentApp?.localizedName ?? ""
        var currentDomain = BrowserManager.shared.currentDomain
        var currentSubdomain = BrowserManager.shared.currentSubdomain
        
        setDescriptionText(keepVisible: true)
        
        // In languages that don't use spaces, we need to add spaces around app name if it's in Latin-script letters.
        // These languages should not include spaces around the "%@" in its Localizable.strings file.
        if Bundle.main.preferredLocalizations.first == "zh-Hans" {
            var normalizedName = currentAppName as NSString
            if normalizedName.length > 0 {
                let startingCharacter = normalizedName.character(at: 0)
                let endingCharacter = normalizedName.character(at: normalizedName.length - 1)
                if 0x4E00 > startingCharacter || startingCharacter > 0x9FA5 {
                    normalizedName = " \(normalizedName)" as NSString
                }
                if 0x4E00 > endingCharacter || endingCharacter > 0x9FA5 {
                    normalizedName = "\(normalizedName) " as NSString
                }
                currentAppName = normalizedName as String
            }
            
            currentDomain = " \(currentDomain ?? "") "
            currentSubdomain = " \(currentSubdomain ?? "") "
        }
        
        sliderView.shiftSlider.floatValue = NightShiftManager.shared.colorTemperature * 100
        sliderView.showsKelvinValue = UserDefaults.standard.bool(forKey: Keys.showKelvinInMenuSlider)
        sliderView.refreshKelvinLabel()
        
        
        // MARK: toggle Night Shift
        if NightShiftManager.shared.isNightShiftEnabled {
            powerMenuItem.title = NSLocalizedString("menu.toggle_off", comment: "Turn off Night Shift")
            sliderView.shiftSlider.isEnabled = true
        } else {
            powerMenuItem.title = NSLocalizedString("menu.toggle_on", comment: "Turn on Night Shift")
            sliderView.shiftSlider.isEnabled = false
        }
        
        if let nightShiftSwitchView = nightShiftSwitchView as? SwitchView {
            nightShiftSwitchView.switchState = NightShiftManager.shared.isNightShiftEnabled
        }
        if let darkModeSwitchView = darkModeSwitchView as? SwitchView {
            darkModeSwitchView.switchState = integrations.appearance.darkModeEnabled
            darkModeMenuItem.view = darkModeSwitchView
        } else {
            darkModeMenuItem.view = nil
        }
        if integrations.trueTone.isSupportedAndAvailable {
            trueToneMenuItem.view = trueToneSwitchView
            if let trueToneSwitchView = trueToneSwitchView as? SwitchView {
                trueToneSwitchView.switchState = integrations.trueTone.isEnabled
            }
        } else {
            trueToneMenuItem.view = nil
        }
        
        
        //MARK: disable for app
        if RuleManager.shared.isDisabledForCurrentApp {
            disableCurrentAppMenuItem.state = .on
            disableCurrentAppMenuItem.title = String(format: NSLocalizedString("menu.disabled_for", comment: "Disabled for %@"), currentAppName)
        } else {
            disableCurrentAppMenuItem.state = .off
            disableCurrentAppMenuItem.title = String(format: NSLocalizedString("menu.disable_for", comment: "Disable for %@"), currentAppName)
        }
        
        if let currentApp = RuleManager.shared.currentApp,
           RuleManager.shared.isDisabledWhenRunningApp(currentApp)
        {
            disableRunningAppMenuItem.state = .on
            disableRunningAppMenuItem.title = String(format: NSLocalizedString(
                "menu.disabled_for_running_app",
                comment: "Disabled when %@ is running"), currentAppName)
        } else {
            disableRunningAppMenuItem.state = .off
            disableRunningAppMenuItem.title = String(format: NSLocalizedString(
                "menu.disable_for_running_app",
                comment: "Disable when %@ is running"), currentAppName)
        }
        
        
        // MARK: disable for domain
        if BrowserManager.shared.hasValidDomain {
            disableDomainMenuItem.isHidden = false
            if RuleManager.shared.isDisabledForDomain {
                disableDomainMenuItem.state = .on
                disableDomainMenuItem.title = String(format: NSLocalizedString("menu.disabled_for", comment: "Disabled for %@"), currentDomain ?? "")
            } else {
                disableDomainMenuItem.state = .off
                disableDomainMenuItem.title = String(format: NSLocalizedString("menu.disable_for", comment: "Disable for %@"), currentDomain ?? "")
            }
        } else {
            disableDomainMenuItem.isHidden = true
        }
        
        
        // MARK: disable for subdomain
        if BrowserManager.shared.hasValidSubdomain {
            disableSubdomainMenuItem.isHidden = false
            if RuleManager.shared.ruleForCurrentSubdomain == .enabled {
                disableSubdomainMenuItem.state = .on
                disableSubdomainMenuItem.title = String(format: NSLocalizedString("menu.enabled_for", comment: "Enabled for %@"), currentSubdomain ?? "")
            } else if RuleManager.shared.ruleForCurrentSubdomain == .disabled {
                disableSubdomainMenuItem.state = .on
                disableSubdomainMenuItem.title = String(format: NSLocalizedString("menu.disabled_for", comment: "Disabled for %@"), currentSubdomain ?? "")
            } else if RuleManager.shared.isDisabledForDomain {
                disableSubdomainMenuItem.state = .off
                disableSubdomainMenuItem.title = String(format: NSLocalizedString("menu.enable_for", comment: "Enable for %@"), currentSubdomain ?? "")
            } else {
                disableSubdomainMenuItem.state = .off
                disableSubdomainMenuItem.title = String(format: NSLocalizedString("menu.disable_for", comment: "Disable for %@"), currentSubdomain ?? "")
            }
        } else {
            disableSubdomainMenuItem.isHidden = true
        }
        
        
        // MARK: enable browser automation
        if BrowserManager.shared.currentAppIsSupportedBrowser &&
            BrowserManager.shared.permissionToAutomateCurrentApp == .denied {
            
            enableBrowserAutomationMenuItem.isHidden = false
            enableBrowserAutomationMenuItem.title = String(format: NSLocalizedString("menu.allow_browser_automation",
                                                                                     comment: "Allow Website Shifting with Browser"), currentAppName)
        } else {
            enableBrowserAutomationMenuItem.isHidden = true
        }
        
        
        // MARK: disable timer
        updateDisableForSubmenuItems()
        updateCircadianMenuItems()
        
        
        // MARK: toggle True Tone
        if integrations.trueTone.state != .unsupported {
            trueToneMenuItem.isHidden = false
            trueToneMenuItem.isEnabled = true
            
            switch integrations.trueTone.state {
            case .unsupported:
                trueToneMenuItem.isHidden = true
            case .unavailable:
                trueToneMenuItem.isEnabled = false
                trueToneMenuItem.title = NSLocalizedString("menu.true_tone_unavailable", comment: "True Tone is not available")
            case .enabled:
                trueToneMenuItem.title = NSLocalizedString("menu.true_tone_off", comment: "Turn off True Tone")
            case .disabled:
                if NightShiftManager.shared.isDisableRuleActive {
                    trueToneMenuItem.isEnabled = false
                    if RuleManager.shared.isDisabledForDomain {
                        trueToneMenuItem.title = String(format: NSLocalizedString("menu.true_tone_disabled_for", comment: "True Tone is disabled for %@"), currentDomain ?? "")
                    } else if RuleManager.shared.ruleForCurrentSubdomain == .disabled {
                        trueToneMenuItem.title = String(format: NSLocalizedString("menu.true_tone_disabled_for", comment: "True Tone is disabled for %@"), currentSubdomain ?? "")
                    } else {
                        trueToneMenuItem.title = String(format: NSLocalizedString("menu.true_tone_disabled_for", comment: "True Tone is disabled for %@"), currentAppName)
                    }
                } else {
                    trueToneMenuItem.title = NSLocalizedString("menu.true_tone_on", comment: "Turn on True Tone")
                }
            }
        } else {
            trueToneMenuItem.isHidden = true
        }

        updateDarkModeMenuItem()
    }

    private func configureMenuCleanupItems() {
        configureDarkModeMenuItem()
        configureDisableForSubmenu()
    }

    private func configureDarkModeMenuItem() {
        guard statusMenu.index(of: darkModeMenuItem) == -1 else { return }

        darkModeMenuItem = NSMenuItem(
            title: "Dark Mode",
            action: #selector(toggleDarkModeFromMenu(_:)),
            keyEquivalent: "")
        darkModeMenuItem.target = self

        let insertIndex = max(statusMenu.index(of: trueToneMenuItem) + 1, 0)
        statusMenu.insertItem(darkModeMenuItem, at: insertIndex)
        updateDarkModeMenuItem()
    }

    private func updateDarkModeMenuItem() {
        let isDark = integrations.appearance.darkModeEnabled
        darkModeMenuItem.title = "Dark Mode"
        darkModeMenuItem.state = isDark ? .on : .off
    }

    private func configureDisableForSubmenu() {
        guard statusMenu.index(of: disableForMenuItem) == -1 else { return }

        disableForMenuItem = NSMenuItem(title: "Disable", action: nil, keyEquivalent: "")
        let disableSubmenu = NSMenu(title: "Disable")

        disableFor10MenuItem = NSMenuItem(title: "10 Minutes", action: #selector(disableTenMinutes(_:)), keyEquivalent: "")
        disableFor30MenuItem = NSMenuItem(title: "30 Minutes", action: #selector(disableThirtyMinutes(_:)), keyEquivalent: "")
        disableFor60MenuItem = NSMenuItem(title: "60 Minutes", action: #selector(disableSixtyMinutes(_:)), keyEquivalent: "")
        disableForCustomMenuItem = NSMenuItem(title: "Custom Time", action: #selector(disableCustomTime(_:)), keyEquivalent: "")
        disableForResumeMenuItem = NSMenuItem(title: "Resume Now", action: #selector(resumeNightShiftNow(_:)), keyEquivalent: "")
        [disableFor10MenuItem, disableFor30MenuItem, disableFor60MenuItem, disableForCustomMenuItem, disableForResumeMenuItem].forEach {
            $0.target = self
        }

        disableSubmenu.addItem(disableFor10MenuItem)
        disableSubmenu.addItem(disableFor30MenuItem)
        disableSubmenu.addItem(disableFor60MenuItem)
        disableSubmenu.addItem(.separator())
        disableSubmenu.addItem(disableForCustomMenuItem)
        disableSubmenu.addItem(.separator())
        disableSubmenu.addItem(disableForResumeMenuItem)
        disableForMenuItem.submenu = disableSubmenu

        let insertionIndex = max(statusMenu.index(of: disableHourMenuItem), 0)
        statusMenu.insertItem(disableForMenuItem, at: insertionIndex)
        disableHourMenuItem.isHidden = true
        disableCustomMenuItem.isHidden = true
        updateDisableForSubmenuItems()
    }

    private func updateDisableForSubmenuItems() {
        disableFor10MenuItem.state = .off
        disableFor30MenuItem.state = .off
        disableFor60MenuItem.state = .off
        disableForCustomMenuItem.state = .off

        switch NightShiftManager.shared.nightShiftDisableTimerState {
        case .off:
            disableForResumeMenuItem.isEnabled = false
            disableForMenuItem.title = "Disable"
        case .hour:
            disableFor60MenuItem.state = .on
            disableForResumeMenuItem.isEnabled = true
            disableForMenuItem.title = "Disable"
        case .custom:
            disableForCustomMenuItem.state = .on
            disableForResumeMenuItem.isEnabled = true
            disableForMenuItem.title = "Disable"
        }
    }

    private func configureCircadianMenuItems() {
        guard statusMenu.index(of: circadianModeMenuItem) == -1 else { return }

        circadianModeMenuItem = NSMenuItem(
            title: "Circadian Mode",
            action: #selector(toggleCircadianMode(_:)),
            keyEquivalent: "")
        circadianModeMenuItem.target = self

        let insertionIndex = max(statusMenu.index(of: disableHourMenuItem), 0)
        statusMenu.insertItem(.separator(), at: insertionIndex)
        statusMenu.insertItem(circadianModeMenuItem, at: insertionIndex + 1)

        updateCircadianMenuItems()
    }

    private func updateCircadianMenuItems() {
        let enabled = UserDefaults.standard.bool(forKey: Keys.isCircadianModeEnabled)
        circadianModeMenuItem.state = enabled ? .on : .off
    }
    
    
    
    
    func setDescriptionText(keepVisible: Bool = false) {
        if NightShiftManager.shared.isDisabledWithTimer {
            var disabledUntilDate: Date
            
            switch NightShiftManager.shared.nightShiftDisableTimerState {
            case .hour(endDate: let date), .custom(endDate: let date):
                disabledUntilDate = date
            case .off:
                return
            }
            
            let nowDate = Date()
            let dateComponentsFormatter = DateComponentsFormatter()
            dateComponentsFormatter.allowedUnits = [.second]
            let disabledTimeLeftComponents = calendar.components([.second], from: nowDate, to: disabledUntilDate, options: [])
            var disabledHoursLeft = (Double(disabledTimeLeftComponents.second!) / 3600.0).rounded(.down)
            var disabledMinutesLeft = (Double(disabledTimeLeftComponents.second!) / 60.0).truncatingRemainder(dividingBy: 60.0).rounded(.toNearestOrEven)
            
            if disabledMinutesLeft == 60.0 {
                disabledMinutesLeft = 0.0
                disabledHoursLeft += 1.0
            }
            
            if disabledHoursLeft > 0 {
                descriptionMenuItem.title = String(format: NSLocalizedString("description.disabled_hours_minutes", comment: "Disabled for %02d:%02d"), Int(disabledHoursLeft), Int(disabledMinutesLeft))
            } else {
                descriptionMenuItem.title = localizedPlural("menu.disabled_time", count: Int(disabledMinutesLeft), comment: "The number of minutes left when disabled for a set amount of time.")
            }
            descriptionMenuItem.isHidden = false
            return
        }
        
        switch NightShiftManager.shared.schedule {
        case .off:
            if keepVisible {
                descriptionMenuItem.title = NSLocalizedString("description.enabled", comment: "Enabled")
            } else {
                descriptionMenuItem.isHidden = true
            }
        case .solar:
            if !keepVisible {
                descriptionMenuItem.isHidden = !NightShiftManager.shared.isNightShiftEnabled
            }
            if NightShiftManager.shared.isNightShiftEnabled {
                descriptionMenuItem.title = NSLocalizedString("description.enabled_sunrise", comment: "Enabled until sunrise")
            } else {
                descriptionMenuItem.title = NSLocalizedString("description.disabled", comment: "Disabled")
            }
        case .custom(_, let endTime):
            if !keepVisible {
                descriptionMenuItem.isHidden = !NightShiftManager.shared.isNightShiftEnabled
            }
            if NightShiftManager.shared.isNightShiftEnabled {
                let dateFormatter = DateFormatter()
                
                if Bundle.main.preferredLocalizations.first == "zh-Hans" {
                    dateFormatter.dateFormat = "a hh:mm "
                } else {
                    dateFormatter.dateStyle = .none
                    dateFormatter.timeStyle = .short
                }
                
                let date = dateFormatter.string(from: Date(endTime))
                
                descriptionMenuItem.title = String(format: NSLocalizedString("description.enabled_time", comment: "Enabled until %@"), date)
            } else {
                descriptionMenuItem.title = NSLocalizedString("description.disabled", comment: "Disabled")
            }
        }
    }
    
    
    
    
    
    func localizedPlural(_ key: String, count: Int, comment: String) -> String {
        let format = NSLocalizedString(key, comment: comment)
        return String(format: format, locale: .current, arguments: [count])
    }
    
    
    
    
    
    func assignKeyboardShortcutToMenuItem(_ menuItem: NSMenuItem, userDefaultsKey: String) {
        let shortcut = shortcutFromDefaults(forKey: userDefaultsKey)

        if let shortcut = shortcut {
            let flags = shortcut.modifierFlags
            menuItem.keyEquivalentModifierMask = flags
            menuItem.keyEquivalent = shortcut.keyCodeString.lowercased()
        } else {
            menuItem.keyEquivalentModifierMask = []
            menuItem.keyEquivalent = ""
        }
    }

    private func shortcutFromDefaults(forKey key: String) -> MASShortcut? {
        let value = UserDefaults.standard.value(forKey: key)

        if let dictionary = value as? [String: Any] {
            return MASDictionaryTransformer().transformedValue(dictionary) as? MASShortcut
        }

        if let data = value as? Data {
            return try? NSKeyedUnarchiver.unarchivedObject(ofClass: MASShortcut.self, from: data)
        }

        return nil
    }
    
    

    // MARK: User Interaction

    @IBAction func power(_ sender: Any) {
        NightShiftManager.shared.isNightShiftEnabled.toggle()
    }

    @objc private func toggleDarkModeFromMenu(_ sender: Any) {
        let currentState = integrations.appearance.darkModeEnabled
        integrations.appearance.darkModeEnabled = !currentState
        updateDarkModeMenuItem()
    }
    
    
    
    @IBAction func disableForCurrentApp(_ sender: Any) {
        guard let currentApp = RuleManager.shared.currentApp else { return }
        
        if RuleManager.shared.isDisabledForCurrentApp {
            RuleManager.shared.removeCurrentAppDisableRule(forApp: currentApp)
        } else {
            RuleManager.shared.addCurrentAppDisableRule(forApp: currentApp)
        }
        Event.disableForCurrentApp(state: (sender as? NSMenuItem)?.state == .on).record()
    }
    
    @IBAction func disableForRunningApp(_ sender: Any) {
        guard let currentApp = RuleManager.shared.currentApp else { return }
        
        if RuleManager.shared.isDisabledForRunningApp {
            RuleManager.shared.removeRunningAppDisableRule(forApp: currentApp)
        } else {
            RuleManager.shared.addRunningAppDisableRule(forApp: currentApp)
        }
    }

    @IBAction func disableForDomain(_ sender: Any) {
        guard let currentDomain = BrowserManager.shared.currentDomain else { return }
        
        if RuleManager.shared.isDisabledForDomain {
            RuleManager.shared.removeDomainDisableRule(forDomain: currentDomain)
        } else {
            RuleManager.shared.addDomainDisableRule(forDomain: currentDomain)
        }
    }
    
    

    @IBAction func disableForSubdomain(_ sender: Any) {
        guard let currentSubdomain = BrowserManager.shared.currentSubdomain else { return }
        
        if RuleManager.shared.ruleForCurrentSubdomain == .none {
            if RuleManager.shared.isDisabledForDomain {
                RuleManager.shared.setSubdomainRule(.enabled, forSubdomain: currentSubdomain)
            } else {
                RuleManager.shared.setSubdomainRule(.disabled, forSubdomain: currentSubdomain)
            }
        } else {
            RuleManager.shared.setSubdomainRule(.none, forSubdomain: currentSubdomain)
        }
    }
    
    
    
    @IBAction func enableBrowserAutomation(_ sender: Any) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
    }
    
    
    
    @IBAction func disableHour(_ sender: Any) {
        if disableHourMenuItem.state == .off {
            NightShiftManager.shared.setDisableTimer(forTimeInterval: 3600)
        } else {
            NightShiftManager.shared.invalidateDisableTimer()
        }
    }

    @objc private func disableTenMinutes(_ sender: Any) {
        NightShiftManager.shared.setDisableTimer(forTimeInterval: 10 * 60)
    }

    @objc private func disableThirtyMinutes(_ sender: Any) {
        NightShiftManager.shared.setDisableTimer(forTimeInterval: 30 * 60)
    }

    @objc private func disableSixtyMinutes(_ sender: Any) {
        NightShiftManager.shared.setDisableTimer(forTimeInterval: 60 * 60)
    }

    @objc private func resumeNightShiftNow(_ sender: Any) {
        NightShiftManager.shared.invalidateDisableTimer()
    }
    
    

    @IBAction func disableCustomTime(_ sender: Any) {
        if disableCustomMenuItem.state == .off {
            NSApp.activate(ignoringOtherApps: true)
            
            customTimeWindow.showWindow(nil)
            customTimeWindow.window?.orderFrontRegardless()
            
            customTimeWindow.disableCustomTime = { seconds in
                NightShiftManager.shared.setDisableTimer(forTimeInterval: TimeInterval(seconds))
            }
        } else {
            NightShiftManager.shared.invalidateDisableTimer()
        }
    }
    
    
    
    @IBAction func toggleTrueTone(_ sender: Any) {
        if integrations.trueTone.state != .unsupported {
            let enabled = integrations.trueTone.isEnabled
            integrations.trueTone.isEnabled = !enabled
        }
    }

    @objc private func toggleCircadianMode(_ sender: Any) {
        let currentlyEnabled = UserDefaults.standard.bool(forKey: Keys.isCircadianModeEnabled)
        UserDefaults.standard.set(!currentlyEnabled, forKey: Keys.isCircadianModeEnabled)
        CircadianWorkspaceCoordinator.shared.applyNow()
        updateCircadianMenuItems()
    }

    

    @IBAction func preferencesClicked(_ sender: NSMenuItem) {
        NSApp.activate(ignoringOtherApps: true)
        (NSApp.delegate as? AppDelegate)?.preferenceWindowController.showWindow(sender)

        Event.preferencesWindowOpened.record()
    }
    
    

    @IBAction func quitClicked(_ sender: NSMenuItem) {
        NightShiftManager.shared.respond(to: .nightShiftDisableTimerEnded)
        NightShiftManager.shared.respond(to: .nightShiftDisableRuleDeactivated)

        Event.quitShifty.record()
        NotificationCenter.default.post(name: .terminateApp, object: self)
        
        NSApp.terminate(self)
    }
}
