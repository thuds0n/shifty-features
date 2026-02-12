//
//  AppDelegate.swift
//  Shifty
//
//  Created by Nate Thompson on 5/3/17.
//
//

import Cocoa
import MASPreferences_Shifty
import SwiftLog
import Intents

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    let prefs = UserDefaults.standard
    let integrations = SystemIntegration.shared
    @IBOutlet weak var statusMenu: NSMenu!
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var statusItemClicked: (() -> Void)?
    private var suppressStatusToggleUntil: Date = .distantPast
    private let circadianCoordinator = CircadianWorkspaceCoordinator.shared
    private var cliCommandObserver: NSObjectProtocol?

    lazy var preferenceWindowController: PrefWindowController = {
        return PrefWindowController(
            viewControllers: [
                PrefGeneralViewController(),
                PrefShortcutsViewController(),
                PrefWhitelistViewController(),
                PrefAboutViewController()],
            title: NSLocalizedString("prefs.title", comment: "Preferences"))
    }()

    var setupWindow: NSWindow!
    var setupWindowController: NSWindowController!

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        _ = PrefManager.shared

        #if !DEBUG
        integrations.appInstall.moveToApplicationsFolderIfNecessary()
        #endif
        
        UserDefaults.standard.register(defaults: ["NSApplicationCrashOnExceptions": true])
        
        let userDefaults = UserDefaults.standard
        
        if userDefaults.bool(forKey: Keys.analyticsPermission) {
            integrations.telemetry.start()
        }
        
        // Initialize Sparkle
        integrations.updater.initialize()
        
        
        let versionObject = Bundle.main.infoDictionary?["CFBundleShortVersionString"]
        userDefaults.set(versionObject as? String ?? "", forKey: Keys.lastInstalledShiftyVersion)
        
        
        Event.appLaunched(preferredLocalization: Bundle.main.preferredLocalizations.first ?? "").record()

        logw("")
        logw("App launched")
        logw("macOS \(ProcessInfo().operatingSystemVersionString)")
        logw("Shifty Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")

        verifySupportsNightShift()

        let launcherAppIdentifier = "io.natethompson.ShiftyHelper"

        let startedAtLogin = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == launcherAppIdentifier
        }

        if startedAtLogin {
            DistributedNotificationCenter.default().post(name: .terminateApp, object: Bundle.main.bundleIdentifier!)
        }

        //Show alert if accessibility permissions have been revoked while app is not running
        if UserDefaults.standard.bool(forKey: Keys.isWebsiteControlEnabled)
            && !integrations.permissions.isAccessibilityTrusted(prompt: false)
        {
            Event.accessibilityRevokedAlertShown.record()
            logw("Accessibility permissions revoked while app was not running")
            showAccessibilityDeniedAlert()
            UserDefaults.standard.set(false, forKey: Keys.isWebsiteControlEnabled)
        }
        
        observeAccessibilityApiNotifications()
        
        logw("Night Shift state: \(NightShiftManager.shared.isNightShiftEnabled)")
        logw("Schedule: \(NightShiftManager.shared.schedule)")
        logw("")

        updateMenuBarIcon()
        setStatusToggle()
        observeCLICommands()
        circadianCoordinator.start()
        
        NightShiftManager.shared.onNightShiftChange {
            self.updateMenuBarIcon()
        }
        
        statusItem.behavior = .terminationOnRemoval
        statusItem.isVisible = true
        
        let hasSetupWindowShown = userDefaults.bool(forKey: Keys.hasSetupWindowShown)

        if (!hasSetupWindowShown && !integrations.permissions.isAccessibilityTrusted(prompt: false))
            || ProcessInfo.processInfo.environment["show_setup"] == "true"
        {
            showSetupWindow()
        }
    }
    
    
    
    //MARK: Called after application launch
    
    func verifySupportsNightShift() {
        if !integrations.nightShiftSystem.supportsNightShift {
            Event.unsupportedHardware.record()
            logw("System does not support Night Shift")
            NSApplication.shared.activate(ignoringOtherApps: true)
            
            let alert: NSAlert = NSAlert()
            alert.messageText = NSLocalizedString("alert.hardware_message", comment: "Your Mac does not support Night Shift")
            alert.informativeText = NSLocalizedString("alert.hardware_informative", comment: "A newer Mac is required to use Shifty.")
            alert.alertStyle = NSAlert.Style.warning
            alert.addButton(withTitle: NSLocalizedString("general.ok", comment: "OK"))
            alert.runModal()
            
            NSApplication.shared.terminate(self)
        }
    }
    
    func showAccessibilityDeniedAlert() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        
        let alert: NSAlert = NSAlert()
        alert.messageText = NSLocalizedString("alert.accessibility_disabled_message", comment: "Accessibility permissions for Shifty have been disabled")
        alert.informativeText = NSLocalizedString("alert.accessibility_disabled_informative", comment: "Accessibility must be allowed to enable website shifting. Grant access to Shifty in Security & Privacy preferences, located in System Preferences.")
        alert.alertStyle = NSAlert.Style.warning
        alert.addButton(withTitle: NSLocalizedString("alert.open_preferences", comment: "Open System Preferences"))
        alert.addButton(withTitle: NSLocalizedString("alert.not_now", comment: "Not now"))
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            logw("Open System Preferences button clicked")
        } else {
            logw("Not now button clicked")
        }
    }
    
    func showSetupWindow() {
        let storyboard = NSStoryboard(name: "Setup", bundle: nil)
        setupWindowController = storyboard.instantiateInitialController() as? NSWindowController
        setupWindow = setupWindowController.window
        
        NSApplication.shared.activate(ignoringOtherApps: true)
        setupWindowController.showWindow(self)
        setupWindow.makeMain()
        
        UserDefaults.standard.set(true, forKey: Keys.hasSetupWindowShown)
    }
    
    func observeAccessibilityApiNotifications() {
        DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.apple.accessibility.api"), object: nil, queue: nil) { _ in
            logw("Accessibility permissions changed: \(self.integrations.permissions.isAccessibilityTrusted(prompt: false))")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: {
                if self.integrations.permissions.isAccessibilityTrusted(prompt: false) {
                    UserDefaults.standard.set(true, forKey: Keys.isWebsiteControlEnabled)
                } else {
                    UserDefaults.standard.set(false, forKey: Keys.isWebsiteControlEnabled)
                }
            })
        }
    }
    
    
    
    //MARK: Status menu item

    func updateMenuBarIcon() {
        var icon: NSImage
        if UserDefaults.standard.bool(forKey: Keys.isIconSwitchingEnabled),
           NightShiftManager.shared.isNightShiftEnabled == false
        {
            icon = #imageLiteral(resourceName: "sunOpenIcon")
        } else {
            icon = #imageLiteral(resourceName: "shiftyMenuIcon")
        }
        icon.isTemplate = true
        DispatchQueue.main.async {
            self.statusItem.button?.image = icon
        }
    }

    func setStatusToggle() {
        statusItem.menu = nil
        if let button = statusItem.button {
            button.action = #selector(statusBarButtonClicked)
            button.sendAction(on: [.leftMouseUp, .leftMouseDown, .rightMouseUp, .rightMouseDown])
        }
    }

    @objc func statusBarButtonClicked(sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        let shouldSuppressToggle = Date() < suppressStatusToggleUntil
        
        if UserDefaults.standard.bool(forKey: Keys.isStatusToggleEnabled) {
            if event.type == .rightMouseDown
                || event.type == .rightMouseUp
                || event.modifierFlags.contains(.control)
            {
                statusItem.menu = statusMenu
                statusItem.button?.performClick(sender)
                statusItem.menu = nil
                suppressStatusToggleUntil = Date().addingTimeInterval(0.25)
            } else if event.type == .leftMouseUp {
                if shouldSuppressToggle { return }
                statusItemClicked?()
            }
        } else {
            if event.type == .rightMouseUp
                || (event.type == .leftMouseUp
                    && event.modifierFlags.contains(.control))
            {
                statusItemClicked?()
            } else if event.type == .leftMouseDown
                && !event.modifierFlags.contains(.control)
            {
                statusItem.menu = statusMenu
                statusItem.button?.performClick(sender)
                statusItem.menu = nil
                suppressStatusToggleUntil = Date().addingTimeInterval(0.25)
            }
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        if let cliCommandObserver {
            DistributedNotificationCenter.default().removeObserver(cliCommandObserver)
            self.cliCommandObserver = nil
        }
        circadianCoordinator.stop()
        logw("App terminated")
    }

    private func observeCLICommands() {
        cliCommandObserver = DistributedNotificationCenter.default().addObserver(
            forName: DistributedNotificationCLIBridge.notificationName,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let self else { return }
            let payload = notification.userInfo as? [String: Any] ?? [:]
            guard
                let commandName = payload["command"] as? String,
                let command = CLICommand(rawValue: commandName)
            else { return }

            let response = self.circadianCoordinator.handleCLICommand(command, payload: payload)
            guard let response else { return }

            var responsePayload = response
            responsePayload["command"] = command.rawValue
            if let requestID = payload["requestID"] {
                responsePayload["requestID"] = requestID
            }

            DistributedNotificationCenter.default().postNotificationName(
                DistributedNotificationCLIBridge.responseNotificationName,
                object: Bundle.main.bundleIdentifier,
                userInfo: responsePayload,
                deliverImmediately: true
            )
        }
    }
    
    
    func application(_ application: NSApplication, handlerFor intent: INIntent) -> Any? {
        if intent is GetNightShiftStateIntent {
            return GetNightShiftStateIntentHandler()
        }
        if intent is SetNightShiftStateIntent {
            return SetNightShiftStateIntentHandler()
        }
        if intent is GetColorTemperatureIntent {
            return GetColorTemperatureIntentHandler()
        }
        if intent is SetColorTemperatureIntent {
            return SetColorTemperatureIntentHandler()
        }
        if intent is SetDisableTimerIntent {
            return SetDisableTimerIntentHandler()
        }
        if intent is GetTrueToneStateIntent {
            return GetTrueToneStateIntentHandler()
        }
        if intent is SetTrueToneStateIntent {
            return SetTrueToneStateIntentHandler()
        }
        return nil
    }
}
