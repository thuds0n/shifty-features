//
//  PrefManager.swift
//  Shifty
//
//  Created by Nate Thompson on 5/6/17.
//
//

import Cocoa
import ServiceManagement
import AXSwift
import Sparkle
import LetsMove
import SwiftLog

enum Keys {
    static let isStatusToggleEnabled = "isStatusToggleEnabled"
    static let isAutoLaunchEnabled = "isAutoLaunchEnabled"
    static let isIconSwitchingEnabled = "isIconSwitchingEnabled"
    static let isDarkModeSyncEnabled = "isDarkModeSyncEnabled"
    static let isWebsiteControlEnabled = "isWebsiteControlEnabled"
    static let trueToneControl = "trueToneControl"
    static let analyticsPermission = "analyticsPermission"
    static let legacyAnalyticsPermission = "fabricCrashlyticsPermission"
    static let currentAppDisableRules = "disabledApps"
    static let runningAppDisableRules = "disabledRunningApps"
    static let browserRules = "browserRules"

    static let toggleNightShiftShortcut = "toggleNightShiftShortcut"
    static let incrementColorTempShortcut = "incrementColorTempShortcut"
    static let decrementColorTempShortcut = "decrementColorTempShortcut"
    static let disableAppShortcut = "disableAppShortcut"
    static let disableDomainShortcut = "disableDomainShortcut"
    static let disableSubdomainShortcut = "disableSubdomainShortcut"
    static let disableHourShortcut = "disableHourShortcut"
    static let disableCustomShortcut = "disableCustomShortcut"
    static let toggleTrueToneShortcut = "toggleTrueToneShortcut"
    static let toggleDarkModeShortcut = "toggleDarkModeShortcut"
    
    static let lastInstalledShiftyVersion = "lastInstalledShiftyVersion"
    static let hasSetupWindowShown = "hasSetupWindowShown"
}


class PrefManager {
    static let shared = PrefManager()

    private init() {
        migrateLegacyPreferenceKeys()
        registerFactoryDefaults()
    }

    private var userDefaults: UserDefaults {
        return UserDefaults.standard
    }
        
    private func registerFactoryDefaults() {
        let factoryDefaults = [
            Keys.isAutoLaunchEnabled: NSNumber(value: false),
            Keys.isStatusToggleEnabled: NSNumber(value: false),
            Keys.isIconSwitchingEnabled: NSNumber(value: false),
            Keys.isDarkModeSyncEnabled: NSNumber(value: false),
            Keys.isWebsiteControlEnabled: NSNumber(value: false),
            Keys.trueToneControl: NSNumber(value: false),
            Keys.analyticsPermission: NSNumber(value: false),
            Keys.currentAppDisableRules: NSData(),
            Keys.runningAppDisableRules: NSData(),
            Keys.browserRules: NSData(),
            Keys.hasSetupWindowShown: NSNumber(value: false)
            ] as [String : Any]

        userDefaults.register(defaults: factoryDefaults)
    }

    private func migrateLegacyPreferenceKeys() {
        guard userDefaults.object(forKey: Keys.analyticsPermission) == nil else { return }
        guard userDefaults.object(forKey: Keys.legacyAnalyticsPermission) != nil else { return }

        let legacyValue = userDefaults.bool(forKey: Keys.legacyAnalyticsPermission)
        userDefaults.set(legacyValue, forKey: Keys.analyticsPermission)
    }
}

protocol TelemetryReporting {
    func start()
    func track(eventName: String, properties: [String: String]?)
}

final class DisabledTelemetryReporter: TelemetryReporting {
    func start() {
        logw("Telemetry provider disabled")
    }

    func track(eventName: String, properties: [String: String]?) {
        _ = eventName
        _ = properties
    }
}

protocol UpdateChecking {
    func initialize()
    func checkForUpdates(_ sender: Any)
}

final class SparkleUpdateClient: UpdateChecking {
    func initialize() {
        _ = SUUpdater.shared()
    }

    func checkForUpdates(_ sender: Any) {
        SUUpdater.shared().checkForUpdates(sender)
    }
}

protocol LoginItemControlling {
    @discardableResult
    func setEnabled(_ enabled: Bool, helperBundleIdentifier: String) -> Bool
    func isEnabled(helperBundleIdentifier: String) -> Bool
}

final class HybridLoginItemController: LoginItemControlling {
    @discardableResult
    func setEnabled(_ enabled: Bool, helperBundleIdentifier: String) -> Bool {
        if #available(macOS 13.0, *) {
            let service = SMAppService.loginItem(identifier: helperBundleIdentifier)
            do {
                if enabled {
                    try service.register()
                } else {
                    try service.unregister()
                }
                return true
            } catch {
                logw("Failed to set login item state for \(helperBundleIdentifier): \(error.localizedDescription)")
                return false
            }
        }

        return SMLoginItemSetEnabled(helperBundleIdentifier as CFString, enabled)
    }

    func isEnabled(helperBundleIdentifier: String) -> Bool {
        if #available(macOS 13.0, *) {
            let service = SMAppService.loginItem(identifier: helperBundleIdentifier)
            switch service.status {
            case .enabled:
                return true
            default:
                return false
            }
        }
        return UserDefaults.standard.bool(forKey: Keys.isAutoLaunchEnabled)
    }
}

protocol DisplayAppearanceControlling: AnyObject {
    var legacyDarkModeEnabled: Bool { get set }
}

final class LegacyDisplayAppearanceController: DisplayAppearanceControlling {
    var legacyDarkModeEnabled: Bool {
        get { SLSGetAppearanceThemeLegacy() }
        set { SLSSetAppearanceThemeLegacy(newValue) }
    }
}

protocol TrueToneControlling: AnyObject {
    var state: State { get }
    var isEnabled: Bool { get set }
    var isSupportedAndAvailable: Bool { get }
}

final class CoreBrightnessTrueToneController: TrueToneControlling {
    var state: State {
        if #available(macOS 10.14, *) {
            return CBTrueToneClient.shared.state
        }
        return .unsupported
    }

    var isEnabled: Bool {
        get {
            if #available(macOS 10.14, *) {
                return CBTrueToneClient.shared.isTrueToneEnabled
            }
            return false
        }
        set {
            if #available(macOS 10.14, *) {
                CBTrueToneClient.shared.isTrueToneEnabled = newValue
            }
        }
    }

    var isSupportedAndAvailable: Bool {
        if #available(macOS 10.14, *) {
            return CBTrueToneClient.shared.isTrueToneSupported && CBTrueToneClient.shared.isTrueToneAvailable
        }
        return false
    }
}

protocol PermissionProviding {
    func isAccessibilityTrusted(prompt: Bool) -> Bool
    func automationConsent(forBundleIdentifier bundleIdentifier: String) -> PrivacyConsentState
}

final class SystemPermissionProvider: PermissionProviding {
    func isAccessibilityTrusted(prompt: Bool) -> Bool {
        UIElement.isProcessTrusted(withPrompt: prompt)
    }

    func automationConsent(forBundleIdentifier bundleIdentifier: String) -> PrivacyConsentState {
        AppleEventsManager.automationConsent(forBundleIdentifier: bundleIdentifier)
    }
}

protocol AppInstallControlling {
    func moveToApplicationsFolderIfNecessary()
}

final class LetsMoveController: AppInstallControlling {
    func moveToApplicationsFolderIfNecessary() {
        PFMoveToApplicationsFolderIfNecessary()
    }
}

final class SystemIntegration {
    static let shared = SystemIntegration()

    let telemetry: TelemetryReporting
    let updater: UpdateChecking
    let loginItem: LoginItemControlling
    let appearance: DisplayAppearanceControlling
    let trueTone: TrueToneControlling
    let permissions: PermissionProviding
    let nightShiftSystem: NightShiftSystemControlling
    let appInstall: AppInstallControlling

    init(
        telemetry: TelemetryReporting = DisabledTelemetryReporter(),
        updater: UpdateChecking = SparkleUpdateClient(),
        loginItem: LoginItemControlling = HybridLoginItemController(),
        appearance: DisplayAppearanceControlling = LegacyDisplayAppearanceController(),
        trueTone: TrueToneControlling = CoreBrightnessTrueToneController(),
        permissions: PermissionProviding = SystemPermissionProvider(),
        nightShiftSystem: NightShiftSystemControlling = CoreBrightnessNightShiftClient.shared,
        appInstall: AppInstallControlling = LetsMoveController()
    ) {
        self.telemetry = telemetry
        self.updater = updater
        self.loginItem = loginItem
        self.appearance = appearance
        self.trueTone = trueTone
        self.permissions = permissions
        self.nightShiftSystem = nightShiftSystem
        self.appInstall = appInstall
    }
}
