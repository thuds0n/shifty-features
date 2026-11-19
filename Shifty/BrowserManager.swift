//
//  BrowserManager.swift
//  Shifty
//
//  Created by Enrico Ghirardi on 25/11/2017.
//

import Cocoa
import ScriptingBridge
import AXSwift
import DomainParser


typealias BundleIdentifier = String

enum SupportedBrowserID: BundleIdentifier {
    case safari = "com.apple.Safari"
    case safariTechnologyPreview = "com.apple.SafariTechnologyPreview"
    
    case chrome = "com.google.Chrome"
    case chromeCanary = "com.google.Chrome.canary"
    case chromium = "org.chromium.Chromium"
    
    case edge = "com.microsoft.edgemac"
    case edgeBeta = "com.microsoft.edgemac.Beta"
    
    case opera = "com.operasoftware.Opera"
    case operaBeta = "com.operasoftware.OperaNext"
    case operaDeveloper = "com.operasoftware.OperaDeveloper"
    
    case brave = "com.brave.Browser"
    case braveBeta = "com.brave.Browser.beta"
    
    case vivaldi = "com.vivaldi.Vivaldi"
    
    init?(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }
    
    init?(_ application: NSRunningApplication) {
        if let bundleIdentifier = application.bundleIdentifier {
            self.init(bundleIdentifier)
        } else {
            return nil
        }
    }
}


/// The website part of a browser URL that rules apply to.
struct WebsiteContext: Equatable {
    /// The registrable domain, e.g. "example.co.uk" for "docs.example.co.uk".
    var domain: String?
    /// The full host, e.g. "docs.example.co.uk".
    var subdomain: String?

    init(domain: String?, subdomain: String?) {
        self.domain = domain
        self.subdomain = subdomain
    }

    init(url: URL?, registrableDomain: (String) -> String?) {
        subdomain = url?.host
        domain = subdomain.flatMap(registrableDomain)
    }

    var hasValidDomain: Bool {
        domain != nil
    }

    /// A subdomain only counts when it differs from the domain and its "www." form,
    /// so rules aren't offered twice for the same site.
    var hasValidSubdomain: Bool {
        guard let subdomain else { return false }
        guard let domain else { return true }
        return subdomain != domain && subdomain != "www.\(domain)"
    }

    /// The Night Shift event that the website rules imply for this site.
    static func ruleEvent(subdomainRule: SubdomainRuleType, isDomainDisabled: Bool) -> NightShiftEvent {
        if subdomainRule == .enabled {
            return .nightShiftEnableRuleActivated
        } else if isDomainDisabled || subdomainRule == .disabled {
            return .nightShiftDisableRuleActivated
        } else {
            return .nightShiftDisableRuleDeactivated
        }
    }
}


class BrowserManager {
    static var shared = BrowserManager()
    private let currentApplication: () -> NSRunningApplication?
    private let isWebsiteShiftingEnabled: () -> Bool

    init(currentApplication: @escaping () -> NSRunningApplication? = { NSWorkspace.shared.menuBarOwningApplication },
         isWebsiteShiftingEnabled: @escaping () -> Bool = { UserDefaults.standard.bool(forKey: Keys.isWebsiteControlEnabled) }) {
        self.currentApplication = currentApplication
        self.isWebsiteShiftingEnabled = isWebsiteShiftingEnabled
    }

    private let domainParser = try? DomainParser()

    private var browserObserver: Observer?
    private var observedApp: Application?
    private var focusedWindow: UIElement?
    private var browserWatchID: UUID?
    private var refreshQueued = false

    private var cachedBrowsers: [SupportedBrowserID: (pid: pid_t, browser: BrowserProtocol)] = [:]
    
    
    var currentURL: URL? {
        if !isWebsiteShiftingEnabled() {
            return nil
        }
        guard let application = currentApplication(),
            let browserID = SupportedBrowserID(application) else {
                return nil
        }
        
        let pid = application.processIdentifier
        if let cached = cachedBrowsers[browserID], cached.pid == pid {
            return url(for: cached.browser, withBundleID: browserID)
            
        } else if let browser = SBApplication(processIdentifier: pid) {
            cachedBrowsers[browserID] = (pid, browser)
            return url(for: browser, withBundleID: browserID)
        } else {
            return nil
        }
    }
    
    
    
    var currentWebsite: WebsiteContext {
        WebsiteContext(url: currentURL) { [domainParser] host in
            domainParser?.parse(host: host)?.domain
        }
    }

    var currentDomain: String? {
        currentWebsite.domain
    }
    
    var currentSubdomain: String? {
        currentWebsite.subdomain
    }
    
    
    
    var currentAppIsSupportedBrowser: Bool {
        if !isWebsiteShiftingEnabled() {
            return false
        }
        
        guard let currentApp = currentApplication() else { return false }
        return SupportedBrowserID(currentApp) != nil
    }
    
    
    
    /// Returns the AppleEvent Automation permission state of the current app.
    /// Blocks main thread if user is prompted for consent.
    /// I don't think this is currently an issue since the prompt will appear when the browser becomes the current app.
    var permissionToAutomateCurrentApp: PrivacyConsentState {
        guard let bundleID = currentApplication()?.bundleIdentifier else { return .undetermined }

        return SystemIntegration.shared.permissions.automationConsent(forBundleIdentifier: bundleID)
    }
    
    
    
    var hasValidDomain: Bool {
        currentWebsite.hasValidDomain
    }
    
    
    
    var hasValidSubdomain: Bool {
        currentWebsite.hasValidSubdomain
    }
    
    
    
    func updateForSupportedBrowser() {
        watchCurrentBrowser { [weak self] in self?.fireNightShiftEvent() }
    }

    func watchCurrentBrowser(onWebsiteChange: @escaping () -> Void) {
        stopBrowserWatcher()
        guard isWebsiteShiftingEnabled(), let app = currentApplication(), let browser = SupportedBrowserID(app) else { return }
        let watchID = UUID()
        browserWatchID = watchID
        tryStartBrowserWatcher(watchID, browser: browser, pid: app.processIdentifier, retries: 10, onWebsiteChange)
        onWebsiteChange()
    }
    
    private func fireNightShiftEvent() {
        NightShiftManager.shared.respond(to: WebsiteContext.ruleEvent(
            subdomainRule: RuleManager.shared.ruleForCurrentSubdomain,
            isDomainDisabled: RuleManager.shared.isDisabledForDomain))
    }
    
    
    
    // A newly launched browser may not expose its accessibility elements yet.
    private func tryStartBrowserWatcher(
        _ watchID: UUID, browser: SupportedBrowserID, pid: pid_t, retries: Int, _ callback: @escaping () -> Void
    ) {
        guard isCurrentWatch(watchID, pid: pid) else { return }
        do {
            try startBrowserWatcher(watchID, browser: browser, pid: pid, callback)
        } catch {
            if retries > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.tryStartBrowserWatcher(watchID, browser: browser, pid: pid, retries: retries - 1, callback)
                }
            } else {
                logw("Error: Could not watch app [\(pid)]: \(error)")
            }
        }
    }
    
    
    
    private func startBrowserWatcher(
        _ watchID: UUID, browser: SupportedBrowserID, pid: pid_t, _ callback: @escaping () -> Void
    ) throws {
        guard let app = Application(forProcessID: pid) else { return }
        let observer = try Observer(processID: pid) { [weak self] _, element, event, _ in
            guard let self, self.isCurrentWatch(watchID, pid: pid) else { return }
            guard event == .focusedWindowChanged || element == self.focusedWindow
                    || (try? element.role()) == .staticText
                    || (event == .valueChanged && self.isChromeToolbarField(element, browser: browser)) else { return }

            self.focusedWindow = try? app.attribute(.focusedWindow)
            guard !self.refreshQueued else { return }
            self.refreshQueued = true
            DispatchQueue.main.async { [weak self] in
                guard let self, self.browserWatchID == watchID else { return }
                self.refreshQueued = false
                guard self.isCurrentWatch(watchID, pid: pid) else { return }
                callback()
            }
        }
        try observer.addNotification(.valueChanged, forElement: app)
        try observer.addNotification(.focusedWindowChanged, forElement: app)
        try observer.addNotification(.uiElementDestroyed, forElement: app)
        focusedWindow = try app.attribute(.focusedWindow)
        observedApp = app
        browserObserver = observer
    }

    private func isCurrentWatch(_ watchID: UUID, pid: pid_t) -> Bool {
        browserWatchID == watchID && isWebsiteShiftingEnabled() && currentApplication()?.processIdentifier == pid
    }

    private func isChromeToolbarField(_ element: UIElement, browser: SupportedBrowserID) -> Bool {
        switch browser {
        case .chrome, .chromeCanary, .chromium: break
        default: return false
        }
        guard let role = try? element.role(), role == .textField || role == .comboBox else { return false }

        // Chrome updates the toolbar field when the selected tab changes.
        // Ignore fields inside a page, including those in web toolbars.
        var node = element
        var inToolbar = false
        for _ in 0..<8 {
            guard let parent: UIElement = try? node.attribute(.parent),
                  let role: String = try? parent.attribute(.role),
                  role != "AXWebArea" else { return false }
            if role == Role.window.rawValue { return inToolbar }
            inToolbar = inToolbar || role == Role.toolbar.rawValue
            node = parent
        }
        return false
    }
    
    
    
    func stopBrowserWatcher() {
        browserWatchID = nil
        refreshQueued = false
        focusedWindow = nil
        guard let browserObserver = browserObserver else { return }
        
        if let observedApp = observedApp {
            do {
                try browserObserver.removeNotification(.valueChanged, forElement: observedApp)
                try browserObserver.removeNotification(.focusedWindowChanged, forElement: observedApp)
                try browserObserver.removeNotification(.uiElementDestroyed, forElement: observedApp)
            } catch let error {
                logw("Error: Couldn't remove notifications: \(error)")
            }
            self.observedApp = nil
        }
        browserObserver.stop()
        self.browserObserver = nil
    }
    
    
    
    enum BrowserError: Error {
        case closedApp
        case noWindow
        case axError
        case notFullScreen
    }
    
    
    
    private func url(for browser: BrowserProtocol, withBundleID browserID: SupportedBrowserID) -> URL? {
        if !browser.isRunning {
            logw("Error: Could not get url, app already closed")
            return nil
        }
        guard let windows = browser.windows?(), let window = windows.firstObject as? Window else {
            logw("Error: Could not get url, there are no windows")
            return nil
        }
        
        let tab: Tab?
        switch browserID {
        case .chrome, .chromeCanary, .chromium,
                .edge, .edgeBeta,
                .opera, .operaBeta, .operaDeveloper,
                .brave, .braveBeta, .vivaldi:
            tab = window.activeTab
        case .safari, .safariTechnologyPreview:
            do {
                // Try to get URL from special full screen window (i.e. full screen video)
                return try safariFullScreenURL(for: browser)
                
            } catch BrowserError.notFullScreen {
                tab = window.currentTab
                
            } catch BrowserError.axError {
                logw("Error: Could not get url using AX API")
                tab = window.currentTab
                
            } catch {
                logw("Error: Could not get url, \(error)")
                return nil
            }
        }
        return tab?.URL.flatMap(URL.init(string:))
    }
    
    
    
    private func safariFullScreenURL(for browser: BrowserProtocol) throws -> URL? {
        guard let app = currentApplication(),
            let axapp = Application(app),
            let axwin: UIElement = try axapp.attribute(.focusedWindow),
            let axwin_children: [UIElement] = try axwin.arrayAttribute(.children)
            else { throw BrowserError.axError }
        
        if axwin_children.count == 1 {
            // Special fullscreen win
            var axchild = axwin_children[0]
            for _ in 1...3 {
                guard let children: [UIElement] = try axchild.arrayAttribute(.children) else { throw BrowserError.axError }
                if !children.isEmpty {
                    axchild = children[0]
                }
            }
            return try axchild.attribute("AXURL")
        } else {
            throw BrowserError.notFullScreen
        }
    }
}
