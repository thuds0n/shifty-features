import Cocoa
import ServiceManagement
import ApplicationServices
import Sparkle

protocol UpdateChecking {
    func initialize()
    func checkForUpdates(_ sender: Any)
}

final class SparkleUpdateClient: UpdateChecking {
    private let controller = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    func initialize() {
        do {
            try controller.updater.start()
        } catch {
            logw("Sparkle updater failed to start: \(error)")
        }
    }

    func checkForUpdates(_ sender: Any) {
        controller.checkForUpdates(sender)
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
        return service.status == .enabled
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
    var state: TrueToneState { get }
    var isEnabled: Bool { get set }
    var isSupportedAndAvailable: Bool { get }
}

final class CoreBrightnessTrueToneController: TrueToneControlling {
    var state: TrueToneState { CBTrueToneClient.shared.state }

    var isEnabled: Bool {
        get { CBTrueToneClient.shared.isTrueToneEnabled }
        set { CBTrueToneClient.shared.isTrueToneEnabled = newValue }
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
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
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
