//
//  PrefGeneralViewController.swift
//  Shifty
//
//  Created by Nate Thompson on 11/10/17.
//

import Cocoa
import SwiftUI

// MARK: - PreferencesPane protocol

protocol PreferencesPane: AnyObject {
    var viewIdentifier: String { get }
    var toolbarItemImage: NSImage? { get }
    var toolbarItemLabel: String? { get }
}

// MARK: - HostedPreferencePane

/// Wraps a SwiftUI view as a preferences pane tab, conforming to PreferencesPane.
final class HostedPreferencePane<Content: View>: NSHostingController<Content>, PreferencesPane {
    let viewIdentifier: String
    let toolbarItemImage: NSImage?
    let toolbarItemLabel: String?
    private let contentSize: NSSize

    init(
        identifier: String,
        image: NSImage?,
        label: String,
        size: NSSize,
        rootView: Content
    ) {
        self.viewIdentifier = identifier
        self.toolbarItemImage = image
        self.toolbarItemLabel = label
        self.contentSize = size
        super.init(rootView: rootView)
    }

    @MainActor required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        preferredContentSize = contentSize
    }
}

// MARK: - PreferencesTabViewController

private final class PreferencesTabViewController: NSTabViewController {
    init(panes: [NSViewController & PreferencesPane]) {
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar

        for pane in panes {
            pane.title = pane.toolbarItemLabel ?? ""
            addChild(pane)
            if let item = tabViewItems.last {
                item.label = pane.toolbarItemLabel ?? ""
                item.image = pane.toolbarItemImage
                item.identifier = pane.viewIdentifier
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - PrefWindowController

class PrefWindowController: NSWindowController {
    static let paneSize = NSSize(width: 520, height: 560)

    private let paneViewControllers: [NSViewController & PreferencesPane]
    private let preferencesTitle: String
    private let tabController: PreferencesTabViewController
    var viewControllers: [NSViewController] { paneViewControllers }

    init(viewControllers: [NSViewController & PreferencesPane], title: String) {
        self.paneViewControllers = viewControllers
        self.preferencesTitle = title
        self.tabController = PreferencesTabViewController(panes: viewControllers)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.paneSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false)
        window.contentViewController = tabController
        super.init(window: window)

        // Start centred, then remember wherever the user moves it.
        window.center()
        window.setFrameAutosaveName("PreferencesWindow")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func windowDidLoad() {
        super.windowDidLoad()
        guard let window else { return }
        window.title = preferencesTitle
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
    }
}

// MARK: - PrefGeneralView

struct PrefGeneralView: View {
    private let integrations = SystemIntegration.shared
    private let launcherAppIdentifier = "io.natethompson.ShiftyHelper"

    @AppStorage(Keys.isStatusToggleEnabled) private var quickToggle = false
    @AppStorage(Keys.isIconSwitchingEnabled) private var iconSwitching = false
    @AppStorage(Keys.isDarkModeSyncEnabled) private var darkModeSync = false
    @AppStorage(Keys.trueToneControl) private var trueToneControl = false
    @AppStorage(Keys.showKelvinInMenuSlider) private var showKelvin = false

    @State private var autoLaunch = false
    @State private var websiteControl = false
    @State private var trueToneAvailable = false
    @State private var scheduleMode: ScheduleMode = .off
    @State private var fromTime = Date()
    @State private var toTime = Date()

    var body: some View {
        Form {
            // MARK: Application
            Section("prefs.general.section.application") {
                Toggle("prefs.general.launch_at_login", isOn: $autoLaunch)
                    .onChange(of: autoLaunch) { _, newValue in
                        handleAutoLaunchChange(newValue)
                    }
                Toggle("prefs.general.quick_toggle", isOn: $quickToggle)
                    .onChange(of: quickToggle) { _, _ in
                        (NSApp.delegate as? AppDelegate)?.setStatusToggle()
                    }
                Toggle("prefs.general.switch_icon", isOn: $iconSwitching)
                    .onChange(of: iconSwitching) { _, _ in
                        (NSApp.delegate as? AppDelegate)?.updateMenuBarIcon()
                    }
            }

            // MARK: Display
            Section("prefs.general.section.display") {
                Toggle("prefs.general.sync_dark_mode", isOn: $darkModeSync)
                    .onChange(of: darkModeSync) { _, newValue in
                        handleDarkModeSyncChange(newValue)
                    }
                Toggle("prefs.general.show_kelvin", isOn: $showKelvin)
            }

            // MARK: Website Shifting
            Section {
                Toggle("prefs.general.enable_website_shifting", isOn: $websiteControl)
                    .onChange(of: websiteControl) { _, newValue in
                        handleWebsiteControlChange(newValue)
                    }
            } header: {
                Text("prefs.general.section.website_shifting")
            } footer: {
                Text("prefs.general.website_shifting_footer")
            }

            // MARK: True Tone (conditional)
            if trueToneAvailable {
                Section {
                    Toggle("prefs.general.disable_true_tone", isOn: $trueToneControl)
                        .onChange(of: trueToneControl) { _, newValue in
                            handleTrueToneControlChange(newValue)
                        }
                } header: {
                    Text("prefs.general.section.true_tone")
                } footer: {
                    Text("prefs.general.true_tone_footer")
                }
            }

            // MARK: Night Shift Schedule
            Section("prefs.general.section.night_shift_schedule") {
                Picker("prefs.general.schedule", selection: $scheduleMode) {
                    Text("prefs.general.schedule.off").tag(ScheduleMode.off)
                    Text("prefs.general.schedule.solar").tag(ScheduleMode.solar)
                    Text("prefs.general.schedule.custom").tag(ScheduleMode.custom)
                }
                .pickerStyle(.menu)
                .onChange(of: scheduleMode) { _, _ in applySchedule() }

                if scheduleMode == .custom {
                    DatePicker("prefs.general.schedule.from", selection: $fromTime, displayedComponents: .hourAndMinute)
                        .onChange(of: fromTime) { _, _ in applySchedule() }
                    DatePicker("prefs.general.schedule.to", selection: $toTime, displayedComponents: .hourAndMinute)
                        .onChange(of: toTime) { _, _ in applySchedule() }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: loadState)
    }

    // MARK: State loading

    private func loadState() {
        let loginItemEnabled = integrations.loginItem.isEnabled(helperBundleIdentifier: launcherAppIdentifier)
        autoLaunch = loginItemEnabled
        UserDefaults.standard.set(loginItemEnabled, forKey: Keys.isAutoLaunchEnabled)

        websiteControl = UserDefaults.standard.bool(forKey: Keys.isWebsiteControlEnabled)
        trueToneAvailable = integrations.trueTone.state != .unsupported

        switch NightShiftManager.shared.schedule {
        case .off:
            scheduleMode = .off
        case .solar:
            scheduleMode = .solar
        case .custom(let start, let end):
            scheduleMode = .custom
            fromTime = Date(start)
            toTime = Date(end)
        }
    }

    // MARK: Action handlers

    private func handleAutoLaunchChange(_ enabled: Bool) {
        let didSet = integrations.loginItem.setEnabled(enabled, helperBundleIdentifier: launcherAppIdentifier)
        let actual = didSet ? enabled : integrations.loginItem.isEnabled(helperBundleIdentifier: launcherAppIdentifier)
        if actual != enabled {
            autoLaunch = actual
            NSSound.beep()
        }
        UserDefaults.standard.set(actual, forKey: Keys.isAutoLaunchEnabled)
        logw("Auto launch on login set to \(actual)")
    }

    private func handleDarkModeSyncChange(_ enabled: Bool) {
        if enabled {
            NightShiftManager.shared.updateDarkMode()
        } else {
            integrations.appearance.darkModeEnabled = false
        }
        logw("Dark mode sync set to \(enabled)")
    }

    private func handleWebsiteControlChange(_ enabled: Bool) {
        if enabled {
            if !integrations.permissions.isAccessibilityTrusted(prompt: false) {
                websiteControl = false
                UserDefaults.standard.set(false, forKey: Keys.isWebsiteControlEnabled)
                logw("Accessibility permissions alert shown")
                NSApp.runModal(for: AccessibilityWindow().window!)
            } else {
                UserDefaults.standard.set(true, forKey: Keys.isWebsiteControlEnabled)
                logw("Website control enabled")
            }
        } else {
            UserDefaults.standard.set(false, forKey: Keys.isWebsiteControlEnabled)
            BrowserManager.shared.stopBrowserWatcher()
            logw("Website control disabled")
        }
    }

    private func handleTrueToneControlChange(_ enabled: Bool) {
        guard integrations.trueTone.state != .unsupported else { return }
        if enabled {
            if NightShiftManager.shared.isDisableRuleActive {
                integrations.trueTone.isEnabled = false
            }
        } else {
            integrations.trueTone.isEnabled = true
        }
        logw("True Tone control set to \(enabled)")
    }

    private func applySchedule() {
        switch scheduleMode {
        case .off:
            NightShiftManager.shared.schedule = .off
        case .solar:
            NightShiftManager.shared.schedule = .solar
        case .custom:
            NightShiftManager.shared.schedule = .custom(start: Time(fromTime), end: Time(toTime))
        }
    }
}

private enum ScheduleMode: Hashable {
    case off, solar, custom
}

// MARK: - PrefRulesView

struct PrefRulesView: View {
    @State private var currentAppRules: [AppRule] = []
    @State private var runningAppRules: [AppRule] = []
    @State private var browserRules: [BrowserRule] = []

    private var hasRules: Bool {
        !(currentAppRules.isEmpty && runningAppRules.isEmpty && browserRules.isEmpty)
    }

    var body: some View {
        Group {
            if hasRules {
                rulesForm
            } else {
                ContentUnavailableView {
                    Label("prefs.rules.empty_title", systemImage: "list.bullet.rectangle")
                } description: {
                    Text("prefs.rules.empty_message")
                }
            }
        }
        .onAppear(perform: loadRules)
        .onReceive(NotificationCenter.default.publisher(for: RuleManager.rulesDidChangeNotification)) { _ in
            loadRules()
        }
    }

    private var rulesForm: some View {
        Form {
            if !currentAppRules.isEmpty {
                Section {
                    ForEach(currentAppRules, id: \.bundleIdentifier) { rule in
                        appRuleRow(rule) { RuleManager.shared.removeCurrentAppDisableRule(rule) }
                    }
                } header: {
                    Label("prefs.rules.active_app", systemImage: "macwindow")
                } footer: {
                    Text("prefs.rules.active_app_footer")
                }
            }

            if !runningAppRules.isEmpty {
                Section {
                    ForEach(runningAppRules, id: \.bundleIdentifier) { rule in
                        appRuleRow(rule) { RuleManager.shared.removeRunningAppDisableRule(rule) }
                    }
                } header: {
                    Label("prefs.rules.when_running", systemImage: "app.badge")
                } footer: {
                    Text("prefs.rules.when_running_footer")
                }
            }

            if !browserRules.isEmpty {
                Section {
                    ForEach(browserRules, id: \.self) { rule in
                        browserRuleRow(rule)
                    }
                } header: {
                    Label("prefs.rules.websites", systemImage: "globe")
                } footer: {
                    Text("prefs.rules.websites_footer")
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func appRuleRow(_ rule: AppRule, remove: @escaping () -> Void) -> some View {
        let name = displayName(for: rule.bundleIdentifier)
        HStack(spacing: 10) {
            appIconView(for: rule.bundleIdentifier)
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                Text(rule.bundleIdentifier)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            removeButton(for: name, action: remove)
        }
        .contextMenu { removeMenuItem(action: remove) }
    }

    @ViewBuilder
    private func browserRuleRow(_ rule: BrowserRule) -> some View {
        let remove = { RuleManager.shared.removeBrowserRule(rule) }
        HStack(spacing: 10) {
            Image(systemName: iconName(for: rule.type))
                .foregroundStyle(tint(for: rule.type))
                .frame(width: 22)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(rule.host)
                Text(ruleDescription(for: rule.type))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            removeButton(for: rule.host, action: remove)
        }
        .contextMenu { removeMenuItem(action: remove) }
    }

    private func removeButton(for subject: String, action: @escaping () -> Void) -> some View {
        Button(role: .destructive, action: action) {
            Image(systemName: "minus.circle")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help(Text("prefs.rules.remove"))
        .accessibilityLabel(Text("prefs.rules.remove"))
        .accessibilityValue(Text(verbatim: subject))
    }

    private func removeMenuItem(action: @escaping () -> Void) -> some View {
        Button(role: .destructive, action: action) {
            Label("prefs.rules.remove", systemImage: "minus.circle")
        }
    }

    @ViewBuilder
    private func appIconView(for bundleIdentifier: String) -> some View {
        if let icon = resolveIcon(for: bundleIdentifier) {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "app.dashed")
                .foregroundStyle(.secondary)
        }
    }

    private func loadRules() {
        currentAppRules = RuleManager.shared.currentAppDisableRuleSnapshot
        runningAppRules = RuleManager.shared.runningAppDisableRuleSnapshot
        browserRules = RuleManager.shared.browserRuleSnapshot
    }

    private func resolveIcon(for bundleIdentifier: String) -> NSImage? {
        if let running = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
            return running.icon
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return nil
    }

    private func displayName(for bundleIdentifier: String) -> String {
        if let running = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleIdentifier }),
           let name = running.localizedName {
            return name
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return url.deletingPathExtension().lastPathComponent
        }
        return bundleIdentifier
    }

    private func iconName(for type: RuleType) -> String {
        switch type {
        case .domain: return "minus.circle.fill"
        case .subdomainDisabled: return "minus.circle"
        case .subdomainEnabled: return "checkmark.circle.fill"
        }
    }

    private func tint(for type: RuleType) -> Color {
        switch type {
        case .domain: return .red
        case .subdomainDisabled: return .orange
        case .subdomainEnabled: return .green
        }
    }

    private func ruleDescription(for type: RuleType) -> String {
        switch type {
        case .domain:
            return NSLocalizedString("prefs.rules.domain_disabled", comment: "Domain rule is disabled")
        case .subdomainDisabled:
            return NSLocalizedString("prefs.rules.subdomain_disabled", comment: "Subdomain rule is disabled")
        case .subdomainEnabled:
            return NSLocalizedString("prefs.rules.subdomain_enabled", comment: "Subdomain rule is enabled")
        }
    }
}
