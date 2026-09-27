//
//  RuleManager.swift
//
//
//  Created by Saagar Jha on 1/14/18.
//

import Cocoa
import ScriptingBridge


/// What the rules are evaluated against: the frontmost app, running apps and
/// current website. Injected so rule behaviour can be tested without real apps.
protocol RuleContextProviding: AnyObject {
    var frontmostBundleIdentifier: String? { get }
    var runningBundleIdentifiers: [String] { get }
    var website: WebsiteContext { get }
    var isSupportedBrowserInFront: Bool { get }
    func stopBrowserWatcher()
    func updateForSupportedBrowser()
}

final class SystemRuleContext: RuleContextProviding {
    var frontmostBundleIdentifier: String? {
        NSWorkspace.shared.menuBarOwningApplication?.bundleIdentifier
    }

    var runningBundleIdentifiers: [String] {
        NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
    }

    var website: WebsiteContext {
        BrowserManager.shared.currentWebsite
    }

    var isSupportedBrowserInFront: Bool {
        BrowserManager.shared.currentAppIsSupportedBrowser
    }

    func stopBrowserWatcher() {
        BrowserManager.shared.stopBrowserWatcher()
    }

    func updateForSupportedBrowser() {
        BrowserManager.shared.updateForSupportedBrowser()
    }
}


class RuleManager {
    /// Posted on the main queue whenever any stored rule is added or removed.
    static let rulesDidChangeNotification = Notification.Name("RuleManagerRulesDidChange")

    static var shared = RuleManager()
    private let nightShiftEventHandler: (NightShiftEvent) -> Void
    /// Store used to load and persist the app and browser rule sets
    private let defaults: UserDefaults
    private let context: RuleContextProviding
    
    init(defaults: UserDefaults = .standard,
         context: RuleContextProviding = SystemRuleContext(),
         notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
         nightShiftEventHandler: @escaping (NightShiftEvent) -> Void = { NightShiftManager.shared.respond(to: $0) }) {
        self.defaults = defaults
        self.context = context
        self.nightShiftEventHandler = nightShiftEventHandler

        if let appData = defaults.value(forKey: Keys.currentAppDisableRules) as? Data {
            do {
                currentAppDisableRules = try PropertyListDecoder().decode(Set<AppRule>.self, from: appData)
            } catch {
                logw("Error: \(error.localizedDescription)")
            }
        }
        
        if let appData = defaults.value(forKey: Keys.runningAppDisableRules) as? Data {
            do {
                runningAppDisableRules = try PropertyListDecoder().decode(Set<AppRule>.self, from: appData)
            } catch let error {
                logw("Error: \(error.localizedDescription)")
            }
        }
        
        if let browserData = defaults.value(forKey: Keys.browserRules) as? Data {
            do {
                browserRules = try PropertyListDecoder().decode(Set<BrowserRule>.self, from: browserData)
            } catch let error {
                logw("Error: \(error.localizedDescription)")
            }
        }
        
        for name in [NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            notificationCenter.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                self?.evaluateCurrentContext()
            }
        }
    }
    
    private var currentAppDisableRules = Set<AppRule>() {
        didSet {
            defaults.set(try? PropertyListEncoder().encode(currentAppDisableRules), forKey: Keys.currentAppDisableRules)
            postRulesDidChange()
        }
    }
    
    private var runningAppDisableRules = Set<AppRule>() {
        didSet {
            defaults.set(try? PropertyListEncoder().encode(runningAppDisableRules), forKey: Keys.runningAppDisableRules)
            postRulesDidChange()
        }
    }
    
    var browserRules = Set<BrowserRule>() {
        didSet(newValue) {
            defaults.set(try? PropertyListEncoder().encode(browserRules), forKey: Keys.browserRules)
            postRulesDidChange()
        }
    }
    
    var currentApp: NSRunningApplication? {
        NSWorkspace.shared.menuBarOwningApplication
    }
    
    var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
    }

    var currentAppDisableRuleSnapshot: [AppRule] {
        currentAppDisableRules.sorted { $0.bundleIdentifier.localizedCaseInsensitiveCompare($1.bundleIdentifier) == .orderedAscending }
    }

    var runningAppDisableRuleSnapshot: [AppRule] {
        runningAppDisableRules.sorted { $0.bundleIdentifier.localizedCaseInsensitiveCompare($1.bundleIdentifier) == .orderedAscending }
    }

    var browserRuleSnapshot: [BrowserRule] {
        browserRules.sorted { lhs, rhs in
            if lhs.type.rawValue == rhs.type.rawValue {
                return lhs.host.localizedCaseInsensitiveCompare(rhs.host) == .orderedAscending
            }
            return lhs.type.rawValue < rhs.type.rawValue
        }
    }

    private func postRulesDidChange() {
        let post = { NotificationCenter.default.post(name: Self.rulesDidChangeNotification, object: self) }
        if Thread.isMainThread {
            post()
        } else {
            DispatchQueue.main.async(execute: post)
        }
    }

    // MARK: Removing stored rules

    func removeCurrentAppDisableRule(_ rule: AppRule) {
        guard currentAppDisableRules.remove(rule) != nil else { return }
        sendNightShiftEvent(.nightShiftDisableRuleDeactivated)
    }

    func removeRunningAppDisableRule(_ rule: AppRule) {
        guard runningAppDisableRules.remove(rule) != nil else { return }
        sendNightShiftEvent(.nightShiftDisableRuleDeactivated)
    }

    func removeBrowserRule(_ rule: BrowserRule) {
        guard browserRules.remove(rule) != nil else { return }
        switch rule.type {
        case .domain, .subdomainDisabled:
            sendNightShiftEvent(.nightShiftDisableRuleDeactivated)
        case .subdomainEnabled:
            sendNightShiftEvent(.nightShiftEnableRuleDeactivated)
        }
    }

    private func sendNightShiftEvent(_ event: NightShiftEvent) {
        nightShiftEventHandler(event)
    }
    
    
    var isDisabledForCurrentApp: Bool {
        guard let bundleIdentifier = context.frontmostBundleIdentifier else {
            logw("Could not obtain bundle identifier of current application")
            return false
        }
        return currentAppDisableRules.contains { $0.bundleIdentifier == bundleIdentifier }
    }
    
    func addCurrentAppDisableRule(forApp app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier else { return }
        addCurrentAppDisableRule(bundleIdentifier: bundleID)
    }

    func addCurrentAppDisableRule(bundleIdentifier: BundleIdentifier) {
        currentAppDisableRules.insert(AppRule(bundleIdentifier: bundleIdentifier, fullScreenOnly: false))
        sendNightShiftEvent(.nightShiftDisableRuleActivated)
    }
    
    func removeCurrentAppDisableRule(forApp app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier else { return }
        removeCurrentAppDisableRule(bundleIdentifier: bundleID)
    }

    func removeCurrentAppDisableRule(bundleIdentifier: BundleIdentifier) {
        guard let rule = currentAppDisableRules.first(where: { $0.bundleIdentifier == bundleIdentifier }) else { return }
        removeCurrentAppDisableRule(rule)
    }
    
    
    var isDisabledForRunningApp: Bool {
        !disabledRunningBundleIdentifiers.isEmpty
    }
    
    /// The running apps that Night Shift is disabled for
    var disabledRunningBundleIdentifiers: [BundleIdentifier] {
        let disabledBundleIDs = Set(runningAppDisableRules.map { $0.bundleIdentifier })
        return context.runningBundleIdentifiers.filter(disabledBundleIDs.contains)
    }
    
    func isDisabledWhenRunningApp(_ app: NSRunningApplication) -> Bool {
        guard let bundleID = app.bundleIdentifier else { return false }
        return runningAppDisableRules.contains(where: { $0.bundleIdentifier == bundleID })
    }
    
    func addRunningAppDisableRule(forApp app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier else { return }
        addRunningAppDisableRule(bundleIdentifier: bundleID)
    }

    func addRunningAppDisableRule(bundleIdentifier: BundleIdentifier) {
        runningAppDisableRules.insert(AppRule(bundleIdentifier: bundleIdentifier, fullScreenOnly: false))
        sendNightShiftEvent(.nightShiftDisableRuleActivated)
    }
    
    func removeRunningAppDisableRule(forApp app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier else { return }
        removeRunningAppDisableRule(bundleIdentifier: bundleID)
    }

    func removeRunningAppDisableRule(bundleIdentifier: BundleIdentifier) {
        guard let rule = runningAppDisableRules.first(where: { $0.bundleIdentifier == bundleIdentifier }) else { return }
        removeRunningAppDisableRule(rule)
    }
    
    
    var isDisabledForDomain: Bool {
        guard let currentDomain = context.website.domain else { return false }
        let disabledDomain = browserRules.filter {
            $0.type == .domain && $0.host == currentDomain }.count > 0
        return disabledDomain
    }
    
    func addDomainDisableRule(forDomain domain: String) {
        let rule = BrowserRule(type: .domain, host: domain)
        browserRules.insert(rule)
        
        sendNightShiftEvent(.nightShiftDisableRuleActivated)
    }
    
    func removeDomainDisableRule(forDomain domain: String) {
        let rule = BrowserRule(type: .domain, host: domain)
        guard let index = browserRules.firstIndex(of: rule) else { return }
        browserRules.remove(at: index)
        
        if let currentSubdomain = context.website.subdomain,
           getSubdomainRule(forSubdomain: currentSubdomain) == .enabled
        {
            setSubdomainRule(.none, forSubdomain: currentSubdomain)
        }
        
        sendNightShiftEvent(.nightShiftDisableRuleDeactivated)
    }
    
    
    func getSubdomainRule(forSubdomain subdomain: String) -> SubdomainRuleType {
        if isDisabledForDomain {
            let isEnabled = (browserRules.filter {
                $0.type == .subdomainEnabled
                && $0.host == subdomain
            }.count > 0)
            if isEnabled {
                return .enabled
            }
        } else {
            let isDisabled = (browserRules.filter {
                $0.type == .subdomainDisabled
                && $0.host == subdomain
            }.count > 0)
            if isDisabled {
                return .disabled
            }
        }
        return .none
    }
    
    var ruleForCurrentSubdomain: SubdomainRuleType {
        guard let currentSubdomain = context.website.subdomain else { return .none }
        return getSubdomainRule(forSubdomain: currentSubdomain)
    }
    
    func setSubdomainRule(_ ruleType: SubdomainRuleType, forSubdomain subdomain: String) {
        switch ruleType {
        case .disabled:
            let rule = BrowserRule(type: .subdomainDisabled, host: subdomain)
            browserRules.insert(rule)
            sendNightShiftEvent(.nightShiftDisableRuleActivated)
        case .enabled:
            let rule = BrowserRule(type: .subdomainEnabled, host: subdomain)
            browserRules.insert(rule)
            sendNightShiftEvent(.nightShiftEnableRuleActivated)
        case .none:
            var rule: BrowserRule
            let prevValue = getSubdomainRule(forSubdomain: subdomain)
            
            //Remove rule from set before triggering NightShiftEvent
            switch prevValue {
            case .disabled:
                rule = BrowserRule(type: .subdomainDisabled, host: subdomain)
            case .enabled:
                rule = BrowserRule(type: .subdomainEnabled, host: subdomain)
            case .none:
                return
            }
            guard let index = browserRules.firstIndex(of: rule) else { return }
            browserRules.remove(at: index)
            
            switch prevValue {
            case .disabled:
                sendNightShiftEvent(.nightShiftDisableRuleDeactivated)
            case .enabled:
                sendNightShiftEvent(.nightShiftEnableRuleDeactivated)
            case .none:
                break
            }
        }
    }
    
    
    var disableRuleIsActive: Bool {
        return isDisabledForCurrentApp || isDisabledForRunningApp ||
        (isDisabledForDomain && ruleForCurrentSubdomain != .enabled) ||
        ruleForCurrentSubdomain == .disabled
    }
    
    
    func removeRulesForCurrentState() {
        if let bundleIdentifier = context.frontmostBundleIdentifier {
            removeCurrentAppDisableRule(bundleIdentifier: bundleIdentifier)
            for runningBundleIdentifier in disabledRunningBundleIdentifiers {
                removeRunningAppDisableRule(bundleIdentifier: runningBundleIdentifier)
            }
        }
        let website = context.website
        if let domain = website.domain {
            removeDomainDisableRule(forDomain: domain)
        }
        if let subdomain = website.subdomain {
            setSubdomainRule(.none, forSubdomain: subdomain)
        }
    }
    
    
    /// Re-evaluates app rules after the frontmost or running apps change, and hands
    /// supported browsers to the website watcher.
    func evaluateCurrentContext() {
        context.stopBrowserWatcher()
        if isDisabledForCurrentApp || isDisabledForRunningApp {
            sendNightShiftEvent(.nightShiftDisableRuleActivated)
        } else if context.isSupportedBrowserInFront {
            context.updateForSupportedBrowser()
        } else {
            sendNightShiftEvent(.nightShiftDisableRuleDeactivated)
        }
    }

}

enum RuleType: String, Codable {
    case domain
    case subdomainDisabled
    case subdomainEnabled
}

enum SubdomainRuleType: String, Codable {
    case none
    case disabled
    case enabled
}

struct AppRule: CustomStringConvertible, Hashable, Codable {
    var bundleIdentifier: BundleIdentifier
    /// Retained for Codable compatibility with persisted rules. Not evaluated in rule logic.
    var fullScreenOnly: Bool
    
    var description: String {
        return "Rule for \(bundleIdentifier); full screen only: \(fullScreenOnly)"
    }
    
    static func == (lhs: AppRule, rhs: AppRule) -> Bool {
        return lhs.bundleIdentifier == rhs.bundleIdentifier
            && lhs.fullScreenOnly == rhs.fullScreenOnly
    }
}

struct BrowserRule: CustomStringConvertible, Hashable, Codable {
    var type: RuleType
    var host: String

    var description: String {
        return "Rule type: \(type) for host: \(host)"
    }

    static func == (lhs: BrowserRule, rhs: BrowserRule) -> Bool {
        return lhs.type == rhs.type
            && lhs.host == rhs.host
    }
}
