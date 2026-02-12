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
import SwiftLog

enum Keys {
    static let isStatusToggleEnabled = "isStatusToggleEnabled"
    static let isAutoLaunchEnabled = "isAutoLaunchEnabled"
    static let isIconSwitchingEnabled = "isIconSwitchingEnabled"
    static let isDarkModeSyncEnabled = "isDarkModeSyncEnabled"
    static let isWebsiteControlEnabled = "isWebsiteControlEnabled"
    static let trueToneControl = "trueToneControl"
    static let currentAppDisableRules = "disabledApps"
    static let runningAppDisableRules = "disabledRunningApps"
    static let browserRules = "browserRules"
    static let isCircadianModeEnabled = "isCircadianModeEnabled"

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
    static let showKelvinInMenuSlider = "showKelvinInMenuSlider"
    
    static let lastInstalledShiftyVersion = "lastInstalledShiftyVersion"
    static let hasSetupWindowShown = "hasSetupWindowShown"
}


class PrefManager {
    static let shared = PrefManager()

    private init() {
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
            Keys.currentAppDisableRules: NSData(),
            Keys.runningAppDisableRules: NSData(),
            Keys.browserRules: NSData(),
            Keys.isCircadianModeEnabled: NSNumber(value: false),
            Keys.showKelvinInMenuSlider: NSNumber(value: false),
            Keys.hasSetupWindowShown: NSNumber(value: false)
            ] as [String : Any]

        userDefaults.register(defaults: factoryDefaults)
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

final class AppServiceLoginItemController: LoginItemControlling {
    @discardableResult
    func setEnabled(_ enabled: Bool, helperBundleIdentifier: String) -> Bool {
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

    func isEnabled(helperBundleIdentifier: String) -> Bool {
        let service = SMAppService.loginItem(identifier: helperBundleIdentifier)
        switch service.status {
        case .enabled:
            return true
        default:
            return false
        }
    }
}

protocol DisplayAppearanceControlling: AnyObject {
    var darkModeEnabled: Bool { get set }
}

final class SystemDisplayAppearanceController: DisplayAppearanceControlling {
    var darkModeEnabled: Bool {
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
        CBTrueToneClient.shared.state
    }

    var isEnabled: Bool {
        get {
            CBTrueToneClient.shared.isTrueToneEnabled
        }
        set {
            CBTrueToneClient.shared.isTrueToneEnabled = newValue
        }
    }

    var isSupportedAndAvailable: Bool {
        CBTrueToneClient.shared.isTrueToneSupported && CBTrueToneClient.shared.isTrueToneAvailable
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

final class SystemIntegration {
    static let shared = SystemIntegration()

    let updater: UpdateChecking
    let loginItem: LoginItemControlling
    let appearance: DisplayAppearanceControlling
    let trueTone: TrueToneControlling
    let permissions: PermissionProviding
    let nightShiftSystem: NightShiftSystemControlling
    let circadianTransition: CircadianTransitioning
    let activityOverride: ActivityOverrideManaging
    let displayCalibration: DisplayCalibrationStoring
    let automationBridge: CircadianAutomationBridging
    let cliBridge: CLIBridgeControlling

    init(
        updater: UpdateChecking = SparkleUpdateClient(),
        loginItem: LoginItemControlling = AppServiceLoginItemController(),
        appearance: DisplayAppearanceControlling = SystemDisplayAppearanceController(),
        trueTone: TrueToneControlling = CoreBrightnessTrueToneController(),
        permissions: PermissionProviding = SystemPermissionProvider(),
        nightShiftSystem: NightShiftSystemControlling = CoreBrightnessNightShiftClient.shared,
        circadianTransition: CircadianTransitioning = CircadianTransitionEngine(),
        activityOverride: ActivityOverrideManaging = ActivityOverrideManager(),
        displayCalibration: DisplayCalibrationStoring = UserDefaultsDisplayCalibrationStore(),
        automationBridge: CircadianAutomationBridging = DisabledCircadianAutomationBridge(),
        cliBridge: CLIBridgeControlling = DistributedNotificationCLIBridge()
    ) {
        self.updater = updater
        self.loginItem = loginItem
        self.appearance = appearance
        self.trueTone = trueTone
        self.permissions = permissions
        self.nightShiftSystem = nightShiftSystem
        self.circadianTransition = circadianTransition
        self.activityOverride = activityOverride
        self.displayCalibration = displayCalibration
        self.automationBridge = automationBridge
        self.cliBridge = cliBridge
    }
}

enum CircadianPhase: String {
    case daylight
    case evening
    case deepNight
}

struct CircadianTarget: Equatable {
    var phase: CircadianPhase
    var kelvin: Int
    /// Normalized transition progress inside the current phase.
    var phaseProgress: Double
}

struct CircadianCurveConfiguration: Equatable {
    var bedtime: DateComponents
    var daylightKelvin: Int
    var eveningKelvin: Int
    var deepNightKelvin: Int
    var eveningLeadTime: TimeInterval
    var deepNightLeadTime: TimeInterval

    static let `default` = CircadianCurveConfiguration(
        bedtime: DateComponents(hour: 23, minute: 0),
        daylightKelvin: 6500,
        eveningKelvin: 4500,
        deepNightKelvin: 3200,
        eveningLeadTime: 2 * 3600,
        deepNightLeadTime: 45 * 60
    )
}

protocol CircadianTransitioning: AnyObject {
    var configuration: CircadianCurveConfiguration { get set }
    func target(for date: Date) -> CircadianTarget
}

final class CircadianTransitionEngine: CircadianTransitioning {
    var configuration: CircadianCurveConfiguration
    private let calendar: Calendar

    init(
        configuration: CircadianCurveConfiguration = .default,
        calendar: Calendar = .current
    ) {
        self.configuration = configuration
        self.calendar = calendar
    }

    func target(for date: Date) -> CircadianTarget {
        let bedtimeToday = calendar.date(
            bySettingHour: configuration.bedtime.hour ?? 23,
            minute: configuration.bedtime.minute ?? 0,
            second: 0,
            of: date) ?? date
        let bedtime = bedtimeToday > date ? bedtimeToday : calendar.date(byAdding: .day, value: 1, to: bedtimeToday) ?? bedtimeToday
        let secondsUntilBedtime = bedtime.timeIntervalSince(date)

        if secondsUntilBedtime > configuration.eveningLeadTime {
            return CircadianTarget(phase: .daylight, kelvin: configuration.daylightKelvin, phaseProgress: 0.0)
        }

        if secondsUntilBedtime > configuration.deepNightLeadTime {
            let span = configuration.eveningLeadTime - configuration.deepNightLeadTime
            let elapsed = configuration.eveningLeadTime - secondsUntilBedtime
            let progress = clamp(span == 0 ? 1.0 : elapsed / span, lower: 0.0, upper: 1.0)
            let kelvin = interpolate(from: configuration.daylightKelvin, to: configuration.eveningKelvin, progress: progress)
            return CircadianTarget(phase: .evening, kelvin: kelvin, phaseProgress: progress)
        }

        let span = max(configuration.deepNightLeadTime, 1.0)
        let elapsed = configuration.deepNightLeadTime - secondsUntilBedtime
        let progress = clamp(elapsed / span, lower: 0.0, upper: 1.0)
        let kelvin = interpolate(from: configuration.eveningKelvin, to: configuration.deepNightKelvin, progress: progress)
        return CircadianTarget(phase: .deepNight, kelvin: kelvin, phaseProgress: progress)
    }

    private func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        min(max(value, lower), upper)
    }

    private func interpolate(from: Int, to: Int, progress: Double) -> Int {
        Int((Double(from) + (Double(to - from) * progress)).rounded())
    }
}

enum ActivitySuspendReason: String {
    case fullscreenMedia
    case pictureInPicture
    case temporaryPause
}

struct ActivityOverrideSnapshot: Equatable {
    var isSuspended: Bool
    var reason: ActivitySuspendReason?
    var until: Date?

    static let none = ActivityOverrideSnapshot(isSuspended: false, reason: nil, until: nil)
}

protocol ActivityOverrideManaging: AnyObject {
    var currentOverride: ActivityOverrideSnapshot { get }
    var onChange: ((ActivityOverrideSnapshot) -> Void)? { get set }
    func start()
    func stop()
    func setTemporaryPause(minutes: Int)
    func clearTemporaryPause()
}

final class ActivityOverrideManager: ActivityOverrideManaging {
    var onChange: ((ActivityOverrideSnapshot) -> Void)?

    private(set) var currentOverride: ActivityOverrideSnapshot = .none {
        didSet {
            onChange?(currentOverride)
        }
    }

    private var temporaryPauseTimer: Timer?
    private var observers = [NSObjectProtocol]()

    private let mediaBundleIdentifiers: Set<String> = [
        "org.videolan.vlc",
        "com.colliderli.iina",
        "com.apple.QuickTimePlayerX"
    ]

    func start() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: nil) { _ in
            self.evaluateMediaContext()
        })
        observers.append(center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: nil) { _ in
            self.evaluateMediaContext()
        })
        evaluateMediaContext()
    }

    func stop() {
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
        temporaryPauseTimer?.invalidate()
        temporaryPauseTimer = nil
        currentOverride = .none
    }

    func setTemporaryPause(minutes: Int) {
        let clampedMinutes = min(max(minutes, 1), 30)
        temporaryPauseTimer?.invalidate()
        let endDate = Date().addingTimeInterval(TimeInterval(clampedMinutes * 60))
        currentOverride = ActivityOverrideSnapshot(isSuspended: true, reason: .temporaryPause, until: endDate)
        temporaryPauseTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(clampedMinutes * 60), repeats: false) { _ in
            self.temporaryPauseTimer = nil
            self.evaluateMediaContext()
        }
    }

    func clearTemporaryPause() {
        temporaryPauseTimer?.invalidate()
        temporaryPauseTimer = nil
        evaluateMediaContext()
    }

    private func evaluateMediaContext() {
        if temporaryPauseTimer != nil, let until = currentOverride.until {
            currentOverride = ActivityOverrideSnapshot(isSuspended: true, reason: .temporaryPause, until: until)
            return
        }

        guard
            let activeApp = NSWorkspace.shared.menuBarOwningApplication,
            let bundleID = activeApp.bundleIdentifier,
            mediaBundleIdentifiers.contains(bundleID)
        else {
            currentOverride = .none
            return
        }

        currentOverride = ActivityOverrideSnapshot(
            isSuspended: true,
            reason: .fullscreenMedia,
            until: nil
        )
    }
}

protocol DisplayCalibrationStoring: AnyObject {
    var selectiveShiftDisplayIDs: Set<String> { get set }
    func warmthOffset(for displayIdentifier: String) -> Int
    func setWarmthOffset(_ offset: Int, for displayIdentifier: String)
}

final class UserDefaultsDisplayCalibrationStore: DisplayCalibrationStoring {
    private enum Keys {
        static let offsets = "displayWarmthOffsets"
        static let selectiveIDs = "selectiveShiftDisplayIDs"
    }

    private var defaults: UserDefaults { .standard }

    var selectiveShiftDisplayIDs: Set<String> {
        get {
            Set(defaults.stringArray(forKey: Keys.selectiveIDs) ?? [])
        }
        set {
            defaults.set(Array(newValue), forKey: Keys.selectiveIDs)
        }
    }

    func warmthOffset(for displayIdentifier: String) -> Int {
        let offsets = defaults.dictionary(forKey: Keys.offsets) as? [String: Int] ?? [:]
        return offsets[displayIdentifier] ?? 0
    }

    func setWarmthOffset(_ offset: Int, for displayIdentifier: String) {
        var offsets = defaults.dictionary(forKey: Keys.offsets) as? [String: Int] ?? [:]
        offsets[displayIdentifier] = offset
        defaults.set(offsets, forKey: Keys.offsets)
    }
}

struct CircadianAutomationState: Equatable {
    var phase: CircadianPhase
    var kelvin: Int
    var isSuspended: Bool
}

protocol CircadianAutomationBridging: AnyObject {
    func publish(state: CircadianAutomationState)
    func triggerDeepNightSceneIfNeeded(previous: CircadianAutomationState?, current: CircadianAutomationState)
}

final class DisabledCircadianAutomationBridge: CircadianAutomationBridging {
    func publish(state: CircadianAutomationState) {
        _ = state
    }

    func triggerDeepNightSceneIfNeeded(previous: CircadianAutomationState?, current: CircadianAutomationState) {
        _ = previous
        _ = current
    }
}

enum CLICommand: String {
    case queryState
    case setTemporaryPause
    case clearTemporaryPause
    case toggleEnabled
}

protocol CLIBridgeControlling: AnyObject {
    static var notificationName: Notification.Name { get }
    func post(command: CLICommand, payload: [String: Any])
}

final class DistributedNotificationCLIBridge: CLIBridgeControlling {
    static let notificationName = Notification.Name("io.natethompson.Shifty.cli")
    static let responseNotificationName = Notification.Name("io.natethompson.Shifty.cli.response")

    func post(command: CLICommand, payload: [String: Any] = [:]) {
        var userInfo = payload
        userInfo["command"] = command.rawValue
        DistributedNotificationCenter.default().postNotificationName(
            Self.notificationName,
            object: Bundle.main.bundleIdentifier,
            userInfo: userInfo,
            deliverImmediately: true
        )
    }
}

final class CircadianWorkspaceCoordinator {
    static let shared = CircadianWorkspaceCoordinator()

    private let integrations = SystemIntegration.shared
    private var updateTimer: Timer?
    private var previousAutomationState: CircadianAutomationState?
    private(set) var isRunning = false

    private init() {}

    func start() {
        guard !isRunning else { return }
        isRunning = true

        integrations.activityOverride.onChange = { [weak self] _ in
            self?.applyNow()
        }
        integrations.activityOverride.start()
        schedulePeriodicRefresh()
        applyNow()
    }

    func stop() {
        isRunning = false
        updateTimer?.invalidate()
        updateTimer = nil
        integrations.activityOverride.stop()
    }

    @discardableResult
    func handleCLICommand(_ command: CLICommand, payload: [String: Any]) -> [String: Any]? {
        switch command {
        case .queryState:
            return currentCLIStatePayload()
        case .setTemporaryPause:
            if let minutes = payload["minutes"] as? Int {
                integrations.activityOverride.setTemporaryPause(minutes: minutes)
            }
            applyNow()
            return currentCLIStatePayload()
        case .clearTemporaryPause:
            integrations.activityOverride.clearTemporaryPause()
            applyNow()
            return currentCLIStatePayload()
        case .toggleEnabled:
            let current = UserDefaults.standard.bool(forKey: Keys.isCircadianModeEnabled)
            UserDefaults.standard.set(!current, forKey: Keys.isCircadianModeEnabled)
            applyNow()
            return currentCLIStatePayload()
        }
    }

    func currentCLIStatePayload() -> [String: Any] {
        let target = integrations.circadianTransition.target(for: Date())
        let override = integrations.activityOverride.currentOverride
        return [
            "circadianEnabled": UserDefaults.standard.bool(forKey: Keys.isCircadianModeEnabled),
            "phase": target.phase.rawValue,
            "kelvin": target.kelvin,
            "isSuspended": override.isSuspended,
            "suspendReason": override.reason?.rawValue as Any
        ]
    }

    func applyNow() {
        guard UserDefaults.standard.bool(forKey: Keys.isCircadianModeEnabled) else { return }

        let target = integrations.circadianTransition.target(for: Date())
        let override = integrations.activityOverride.currentOverride
        let state = CircadianAutomationState(
            phase: target.phase,
            kelvin: target.kelvin,
            isSuspended: override.isSuspended
        )

        integrations.automationBridge.publish(state: state)
        integrations.automationBridge.triggerDeepNightSceneIfNeeded(previous: previousAutomationState, current: state)
        previousAutomationState = state

        guard !override.isSuspended else { return }
        guard NightShiftManager.shared.isNightShiftEnabled else { return }

        NightShiftManager.shared.colorTemperature = strength(fromKelvin: target.kelvin)
    }

    private func schedulePeriodicRefresh() {
        updateTimer?.invalidate()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            self.applyNow()
        }
    }

    private func strength(fromKelvin kelvin: Int) -> Float {
        let config = integrations.circadianTransition.configuration
        let minKelvin = min(config.deepNightKelvin, config.daylightKelvin)
        let maxKelvin = max(config.deepNightKelvin, config.daylightKelvin)
        let clamped = min(max(kelvin, minKelvin), maxKelvin)
        let span = max(Double(maxKelvin - minKelvin), 1.0)
        let normalized = 1.0 - ((Double(clamped - minKelvin)) / span)
        return Float(min(max(normalized, 0.0), 1.0))
    }
}
