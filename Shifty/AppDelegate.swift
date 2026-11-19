//
//  AppDelegate.swift
//  Shifty
//
//  Created by Nate Thompson on 5/3/17.
//
//

import Cocoa
import Intents
import SwiftUI

@NSApplicationMain
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {

    static let isUnitTestHost: Bool = {
        #if DEBUG
        ProcessInfo.processInfo.environment["SHIFTY_UNIT_TEST_HOST"] == "1"
        #else
        false
        #endif
    }()

    static var preferencesTestProfile: UUID? {
        #if DEBUG
        ProcessInfo.processInfo.environment["SHIFTY_PREFERENCES_TEST_PROFILE"].flatMap(UUID.init(uuidString:))
        #else
        nil
        #endif
    }

    let prefs = UserDefaults.standard
    lazy var integrations = SystemIntegration.shared
    @IBOutlet weak var statusMenu: NSMenu!
    lazy var statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var statusItemClicked: (() -> Void)?
    private var suppressStatusToggleUntil: Date = .distantPast
    private lazy var circadianCoordinator = CircadianWorkspaceCoordinator.shared
    #if DEBUG
    private var preferencesTestRuleKeyMonitor: Any?
    #endif

    lazy var preferenceWindowController: PrefWindowController = {
        // Every pane shares one size so switching tabs doesn't resize the window.
        let paneSize = PrefWindowController.paneSize

        let general = HostedPreferencePane(
            identifier: "general",
            image: NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil),
            label: NSLocalizedString("prefs.general", comment: "General"),
            size: paneSize,
            rootView: PrefGeneralView())

        let circadian = HostedPreferencePane(
            identifier: "circadian",
            image: NSImage(systemSymbolName: "sun.horizon", accessibilityDescription: nil),
            label: NSLocalizedString("prefs.circadian", comment: "Circadian"),
            size: paneSize,
            rootView: PrefCircadianView(coordinator: circadianCoordinator))

        let shortcuts = HostedPreferencePane(
            identifier: "shortcuts",
            image: NSImage(systemSymbolName: "command", accessibilityDescription: nil),
            label: NSLocalizedString("prefs.shortcuts", comment: "Shortcuts"),
            size: paneSize,
            rootView: PrefShortcutsView())

        let rules = makeRulesPane(content: PrefRulesView(ruleManager: .shared))

        let about = HostedPreferencePane(
            identifier: "about",
            image: NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil),
            label: NSLocalizedString("prefs.about", comment: "About"),
            size: paneSize,
            rootView: PrefAboutView())

        return PrefWindowController(
            viewControllers: [general, circadian, shortcuts, rules, about],
            title: NSLocalizedString("prefs.title", comment: "Preferences"))
    }()

    private func makeRulesPane<Content: View>(content: Content) -> NSViewController & PreferencesPane {
        HostedPreferencePane(
            identifier: "rules",
            image: NSImage(systemSymbolName: "list.bullet.rectangle", accessibilityDescription: nil),
            label: NSLocalizedString("prefs.rules", comment: "Rules"),
            size: PrefWindowController.paneSize,
            rootView: content)
    }

    var setupWindow: NSWindow!
    var setupWindowController: NSWindowController!

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        #if DEBUG
        if let profile = Self.preferencesTestProfile {
            showTestPreferences(profile: profile)
            return
        }
        #endif
        guard !Self.isUnitTestHost else { return }
        _ = PrefManager.shared

        UserDefaults.standard.register(defaults: ["NSApplicationCrashOnExceptions": true])
        
        let userDefaults = UserDefaults.standard
        
        // Initialize Sparkle
        integrations.updater.initialize()
        
        
        let versionObject = Bundle.main.infoDictionary?["CFBundleShortVersionString"]
        userDefaults.set(versionObject as? String ?? "", forKey: Keys.lastInstalledShiftyVersion)
        
        
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
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: nil
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self else { return }
                let isTrusted = self.integrations.permissions.isAccessibilityTrusted(prompt: false)
                logw("Accessibility permissions changed: \(isTrusted)")
                UserDefaults.standard.set(isTrusted, forKey: Keys.isWebsiteControlEnabled)
            }
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
        #if DEBUG
        if let monitor = preferencesTestRuleKeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
        #endif
        guard !Self.isUnitTestHost, Self.preferencesTestProfile == nil else { return }
        circadianCoordinator.stop()
        logw("App terminated")
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

#if DEBUG
private extension AppDelegate {
    func showTestPreferences(profile: UUID) {
        let environment = ProcessInfo.processInfo.environment
        let suite = "ShiftyUITests.\(profile.uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        if environment["SHIFTY_RESET_TEST_PROFILE"] == "1" {
            defaults.removePersistentDomain(forName: suite)
        }
        let pane: NSViewController & PreferencesPane
        switch environment["SHIFTY_PREFERENCES_TEST_PANE"] {
        case "shortcuts":
            pane = HostedPreferencePane(
                identifier: "shortcuts", image: NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil),
                label: NSLocalizedString("prefs.shortcuts", comment: "Shortcuts"), size: PrefWindowController.paneSize,
                rootView: PrefShortcutsView(defaults: defaults, showsTrueTone: true))
        case "rules":
            let ruleManager = RuleManager(
                defaults: defaults, context: PreferencesTestRuleContext(),
                notificationCenter: NotificationCenter(), nightShiftEventHandler: { _ in })
            pane = makeRulesPane(content: PrefRulesView(ruleManager: ruleManager))
            if let domain = environment["SHIFTY_PREFERENCES_TEST_DOMAIN"] {
                // Route a local test keystroke to the manager while the Rules pane is open.
                preferencesTestRuleKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command, .shift],
                          event.charactersIgnoringModifiers?.lowercased() == "d" else { return event }
                    ruleManager.addDomainDisableRule(forDomain: domain)
                    return nil
                }
            }
        case "live-chrome-rules":
            let pid = environment["SHIFTY_LIVE_CHROME_PID"].flatMap(Int32.init)
            let fixture = LiveChromeRulesFixture(defaults: defaults, chromePID: pid)
            pane = makeRulesPane(content: LiveChromeRulesView(fixture: fixture))
        default:
            pane = makeTestCircadianPane(defaults: defaults)
        }
        preferenceWindowController = PrefWindowController(
            viewControllers: [pane], title: NSLocalizedString("prefs.title", comment: "Preferences"),
            remembersPosition: false)
        preferenceWindowController.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func makeTestCircadianPane(defaults: UserDefaults) -> NSViewController & PreferencesPane {
        defaults.register(defaults: [Keys.isCircadianModeEnabled: true])
        let coordinator = CircadianWorkspaceCoordinator(
            transition: CircadianTransitionEngine(),
            activityOverride: ActivityOverrideManager(notificationCenter: NotificationCenter(), frontmostBundleIdentifier: { nil }),
            automationBridge: DisabledCircadianAutomationBridge(),
            nightShift: PreferencesTestDisplay(),
            modeStore: UserDefaultsCircadianModeStore(defaults: defaults),
            configurationStore: UserDefaultsCircadianConfigurationStore(defaults: defaults),
            clock: PreferencesTestClock())
        return HostedPreferencePane(
            identifier: "circadian", image: NSImage(systemSymbolName: "sun.horizon", accessibilityDescription: nil),
            label: NSLocalizedString("prefs.circadian", comment: "Circadian"), size: PrefWindowController.paneSize,
            rootView: PrefCircadianView(coordinator: coordinator).defaultAppStorage(defaults))
    }
}

private final class PreferencesTestRuleContext: RuleContextProviding {
    private let readWebsite: () -> WebsiteContext
    let frontmostBundleIdentifier: String? = nil
    let runningBundleIdentifiers: [String] = []
    var website: WebsiteContext { readWebsite() }
    let isSupportedBrowserInFront = false

    init(readWebsite: @escaping () -> WebsiteContext = { WebsiteContext(domain: nil, subdomain: nil) }) {
        self.readWebsite = readWebsite
    }

    func stopBrowserWatcher() {}
    func updateForSupportedBrowser() {}
}

private struct LiveChromeRulesView: View {
    @ObservedObject var fixture: LiveChromeRulesFixture

    var body: some View {
        VStack {
            PrefRulesView(ruleManager: fixture.ruleManager)
            Text(verbatim: fixture.status)
                .accessibilityIdentifier("liveChrome.status")
            Button("Toggle Chrome domain rule", action: fixture.toggleDomainRule)
                .accessibilityIdentifier("liveChrome.toggleDomainRule")
                .disabled(!fixture.isOnRuleDomain)
                .padding(.bottom)
        }
        .onAppear(perform: fixture.start)
    }
}

@MainActor
private final class LiveChromeRulesFixture: ObservableObject {
    @Published private(set) var status = "Starting Chrome check"
    private let defaults: UserDefaults
    private let chromePID: pid_t?
    private var chrome: NSRunningApplication?
    private let display = LiveChromeTestDisplay()
    private lazy var browser = BrowserManager(currentApplication: { [weak self] in self?.chrome },
                                               isWebsiteShiftingEnabled: { true })
    private lazy var nightShift = NightShiftManager(
        client: display, defaults: defaults, wakeNotificationCenter: NotificationCenter(),
        ruleManager: { [unowned self] in self.ruleManager })
    lazy var ruleManager = RuleManager(
        defaults: defaults,
        context: PreferencesTestRuleContext { [weak self] in
            self?.testWebsite ?? WebsiteContext(domain: nil, subdomain: nil)
        },
        notificationCenter: NotificationCenter(),
        nightShiftEventHandler: { [weak self] in self?.respond(to: $0) })

    var isOnRuleDomain: Bool { status.hasPrefix("example.com · ") }

    init(defaults: UserDefaults, chromePID: pid_t?) {
        self.defaults = defaults
        self.chromePID = chromePID
    }

    func start() {
        guard status == "Starting Chrome check" else { return }
        guard AXIsProcessTrusted() else {
            status = "Accessibility permission required for this Shifty build"
            return
        }
        let bundleID = SupportedBrowserID.chrome.rawValue
        guard let chromePID, let runningChrome = NSRunningApplication(processIdentifier: chromePID),
              runningChrome.bundleIdentifier == bundleID else {
            status = "The Chrome test process is unavailable"
            return
        }
        guard AppleEventsManager.automationConsent(forBundleIdentifier: bundleID, allowPrompt: false) == .granted else {
            status = "Chrome Automation permission required for this Shifty build"
            return
        }
        chrome = runningChrome
        browser.watchCurrentBrowser { [weak self] in
            guard let self else { return }
            self.respond(to: WebsiteContext.ruleEvent(
                subdomainRule: self.ruleManager.ruleForCurrentSubdomain,
                isDomainDisabled: self.ruleManager.isDisabledForDomain))
        }
    }

    func toggleDomainRule() {
        guard testWebsite.domain == "example.com" else { return }
        ruleManager.toggleCurrentDomainDisableRule()
    }

    private var testWebsite: WebsiteContext {
        let website = browser.currentWebsite
        if website.domain == "example.com" || website.domain == "example.org" { return website }
        return WebsiteContext(domain: nil, subdomain: nil)
    }

    private func respond(to event: NightShiftEvent) {
        nightShift.respond(to: event)
        let state = display.isNightShiftEnabled ? "on" : "off"
        status = "\(testWebsite.domain ?? "Waiting for a test domain") · simulated Night Shift \(state)"
    }
}

private final class LiveChromeTestDisplay: NightShiftSystemControlling {
    let supportsNightShift = true
    let scheduledState = true
    private(set) var isNightShiftEnabled = true
    var colorTemperature: Float = 0.5
    var schedule: ScheduleType = .solar

    func previewColorTemperature(_ value: Float) {}
    func setNightShiftEnabled(_ newValue: Bool) { isNightShiftEnabled = newValue }
    func setToSchedule() { setNightShiftEnabled(scheduledState) }
    func setStatusNotificationBlock(_ block: @escaping () -> Void) {}
}

private struct PreferencesTestClock: WorkspaceClock {
    let now = Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 9, hour: 21))!
}

private final class PreferencesTestDisplay: WorkspaceNightShiftControlling {
    var currentWorkspaceOutput = WorkspaceOutputState(isNightShiftEnabled: true, colorTemperature: 0.5)
    var isPaused = false

    func applyWorkspacePolicyDecision(_ decision: WorkspacePolicyDecision) {
        if case .applyStrength(let strength) = decision { currentWorkspaceOutput.colorTemperature = strength }
    }

    func pause(for duration: TimeInterval) { isPaused = true }
    func resumeFromPause() { isPaused = false }
}
#endif
