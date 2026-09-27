import Foundation

protocol WorkspaceClock {
    var now: Date { get }
}

struct SystemWorkspaceClock: WorkspaceClock {
    var now: Date { Date() }
}

protocol CircadianModeStoring: AnyObject {
    var isCircadianModeEnabled: Bool { get set }
}

final class UserDefaultsCircadianModeStore: CircadianModeStoring {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isCircadianModeEnabled: Bool {
        get { defaults.bool(forKey: Keys.isCircadianModeEnabled) }
        set { defaults.set(newValue, forKey: Keys.isCircadianModeEnabled) }
    }
}

protocol CircadianConfigurationStoring: AnyObject {
    var configuration: CircadianCurveConfiguration { get set }
}

/// Persists the circadian curve as versioned JSON so the format can evolve.
/// Missing, unreadable or newer-versioned data falls back to the defaults.
final class UserDefaultsCircadianConfigurationStore: CircadianConfigurationStoring {
    private struct StoredConfiguration: Codable {
        static let currentVersion = 1

        var version: Int
        var bedtimeMinute: Int
        var wakeTimeMinute: Int
        var daylightKelvin: Int
        var eveningKelvin: Int
        var deepNightKelvin: Int
        var eveningLeadMinutes: Int
        var deepNightLeadMinutes: Int
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var configuration: CircadianCurveConfiguration {
        get {
            guard
                let data = defaults.data(forKey: Keys.circadianConfiguration),
                let stored = try? JSONDecoder().decode(StoredConfiguration.self, from: data),
                stored.version == StoredConfiguration.currentVersion
            else {
                return .default
            }
            return CircadianCurveConfiguration(
                bedtime: DateComponents(hour: stored.bedtimeMinute / 60, minute: stored.bedtimeMinute % 60),
                wakeTime: DateComponents(hour: stored.wakeTimeMinute / 60, minute: stored.wakeTimeMinute % 60),
                daylightKelvin: stored.daylightKelvin,
                eveningKelvin: stored.eveningKelvin,
                deepNightKelvin: stored.deepNightKelvin,
                eveningLeadTime: TimeInterval(stored.eveningLeadMinutes * 60),
                deepNightLeadTime: TimeInterval(stored.deepNightLeadMinutes * 60)
            ).validated()
        }
        set {
            let configuration = newValue.validated()
            let stored = StoredConfiguration(
                version: StoredConfiguration.currentVersion,
                bedtimeMinute: CircadianCurveConfiguration.minuteOfDay(configuration.bedtime),
                wakeTimeMinute: CircadianCurveConfiguration.minuteOfDay(configuration.wakeTime),
                daylightKelvin: configuration.daylightKelvin,
                eveningKelvin: configuration.eveningKelvin,
                deepNightKelvin: configuration.deepNightKelvin,
                eveningLeadMinutes: Int((configuration.eveningLeadTime / 60).rounded()),
                deepNightLeadMinutes: Int((configuration.deepNightLeadTime / 60).rounded())
            )
            guard let data = try? JSONEncoder().encode(stored) else { return }
            defaults.set(data, forKey: Keys.circadianConfiguration)
        }
    }
}

/// A snapshot of the schedule for display: where it is now and what comes next.
struct CircadianStatus: Equatable {
    var target: CircadianTarget
    var nextTransition: CircadianTransition?
    var isSuspended: Bool
}

protocol WorkspaceRefreshTimer: AnyObject {
    func invalidate()
}

extension Timer: WorkspaceRefreshTimer {}

protocol WorkspaceRefreshScheduling: AnyObject {
    func scheduleRepeating(every interval: TimeInterval, action: @escaping () -> Void) -> WorkspaceRefreshTimer
}

final class FoundationWorkspaceRefreshScheduler: WorkspaceRefreshScheduling {
    func scheduleRepeating(every interval: TimeInterval, action: @escaping () -> Void) -> WorkspaceRefreshTimer {
        Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in action() }
    }
}

protocol WorkspaceNightShiftControlling: AnyObject {
    var currentWorkspaceOutput: WorkspaceOutputState { get }
    func applyWorkspacePolicyDecision(_ decision: WorkspacePolicyDecision)
}

extension NightShiftManager: WorkspaceNightShiftControlling {
    var currentWorkspaceOutput: WorkspaceOutputState {
        WorkspaceOutputState(
            isNightShiftEnabled: isNightShiftEnabled,
            colorTemperature: colorTemperature
        )
    }
}

@MainActor
final class CircadianWorkspaceCoordinator {
    static let shared: CircadianWorkspaceCoordinator = {
        let integrations = SystemIntegration.shared
        return CircadianWorkspaceCoordinator(
            transition: integrations.circadianTransition,
            activityOverride: integrations.activityOverride,
            automationBridge: integrations.automationBridge,
            nightShift: NightShiftManager.shared
        )
    }()

    private let transition: CircadianTransitioning
    private let activityOverride: ActivityOverrideManaging
    private let automationBridge: CircadianAutomationBridging
    private let nightShift: WorkspaceNightShiftControlling
    private let modeStore: CircadianModeStoring
    private let configurationStore: CircadianConfigurationStoring
    private let clock: WorkspaceClock
    private let refreshScheduler: WorkspaceRefreshScheduling
    private let workspacePolicy: WorkspacePolicy

    private var updateTimer: WorkspaceRefreshTimer?
    private var previousAutomationState: CircadianAutomationState?
    /// While set, circadian refreshes leave a hand-set strength alone.
    private(set) var manualStrengthHoldUntil: Date?
    private(set) var isRunning = false

    init(
        transition: CircadianTransitioning,
        activityOverride: ActivityOverrideManaging,
        automationBridge: CircadianAutomationBridging,
        nightShift: WorkspaceNightShiftControlling,
        modeStore: CircadianModeStoring = UserDefaultsCircadianModeStore(),
        configurationStore: CircadianConfigurationStoring = UserDefaultsCircadianConfigurationStore(),
        clock: WorkspaceClock = SystemWorkspaceClock(),
        refreshScheduler: WorkspaceRefreshScheduling = FoundationWorkspaceRefreshScheduler(),
        workspacePolicy: WorkspacePolicy = WorkspacePolicy()
    ) {
        self.transition = transition
        self.activityOverride = activityOverride
        self.automationBridge = automationBridge
        self.nightShift = nightShift
        self.modeStore = modeStore
        self.configurationStore = configurationStore
        self.clock = clock
        self.refreshScheduler = refreshScheduler
        self.workspacePolicy = workspacePolicy
        transition.configuration = configurationStore.configuration
    }

    var configuration: CircadianCurveConfiguration {
        transition.configuration
    }

    /// Validates, persists and immediately applies a new schedule.
    func updateConfiguration(_ configuration: CircadianCurveConfiguration) {
        let configuration = configuration.validated()
        configurationStore.configuration = configuration
        transition.configuration = configuration
        manualStrengthHoldUntil = nil
        applyNow()
    }

    /// Keeps a strength the user set by hand (menu slider, shortcut or Shortcuts action)
    /// until the schedule's next phase change, instead of overwriting it on the next refresh.
    func holdManualStrength() {
        manualStrengthHoldUntil = transition.nextTransition(after: clock.now)?.date
    }

    func currentStatus() -> CircadianStatus {
        let now = clock.now
        return CircadianStatus(
            target: transition.target(for: now),
            nextTransition: transition.nextTransition(after: now),
            isSuspended: activityOverride.currentOverride.isSuspended
        )
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true

        activityOverride.onChange = { [weak self] _ in
            DispatchQueue.main.async { self?.applyNow() }
        }
        activityOverride.start()
        schedulePeriodicRefresh()
        applyNow()
    }

    func stop() {
        isRunning = false
        updateTimer?.invalidate()
        updateTimer = nil
        activityOverride.onChange = nil
        activityOverride.stop()
        applyWorkspacePolicy(isCircadianEnabled: false)
    }

    @discardableResult
    func handleCLICommand(_ command: CLICommand, payload: [String: Any]) -> [String: Any]? {
        switch command {
        case .queryState:
            return currentCLIStatePayload()
        case .setTemporaryPause:
            if let minutes = payload["minutes"] as? Int {
                activityOverride.setTemporaryPause(minutes: minutes)
            }
        case .clearTemporaryPause:
            activityOverride.clearTemporaryPause()
        case .toggleEnabled:
            modeStore.isCircadianModeEnabled.toggle()
        }

        applyNow()
        return currentCLIStatePayload()
    }

    func currentCLIStatePayload() -> [String: Any] {
        let target = transition.target(for: clock.now)
        let override = activityOverride.currentOverride
        var payload: [String: Any] = [
            "circadianEnabled": modeStore.isCircadianModeEnabled,
            "phase": target.phase.rawValue,
            "kelvin": target.kelvin,
            "isSuspended": override.isSuspended
        ]
        if let reason = override.reason {
            payload["suspendReason"] = reason.rawValue
        }
        return payload
    }

    func applyNow() {
        let isCircadianEnabled = modeStore.isCircadianModeEnabled
        let target = transition.target(for: clock.now)
        let override = activityOverride.currentOverride

        guard isCircadianEnabled else {
            applyWorkspacePolicy(isCircadianEnabled: false, target: target, activityOverride: override)
            return
        }

        let state = CircadianAutomationState(
            phase: target.phase,
            kelvin: target.kelvin,
            isSuspended: override.isSuspended
        )
        automationBridge.publish(state: state)
        automationBridge.triggerDeepNightSceneIfNeeded(previous: previousAutomationState, current: state)
        previousAutomationState = state

        if let holdUntil = manualStrengthHoldUntil, clock.now >= holdUntil {
            manualStrengthHoldUntil = nil
        }
        let strengthTarget = manualStrengthHoldUntil == nil ? target : nil
        applyWorkspacePolicy(isCircadianEnabled: true, target: strengthTarget, activityOverride: override)
    }

    private func applyWorkspacePolicy(
        isCircadianEnabled: Bool,
        target: CircadianTarget? = nil,
        activityOverride: ActivityOverrideSnapshot = .none
    ) {
        let currentOutput = nightShift.currentWorkspaceOutput
        let targetStrength = target.map { strength(fromKelvin: $0.kelvin) } ?? currentOutput.colorTemperature
        let decision = workspacePolicy.decision(
            isCircadianEnabled: isCircadianEnabled,
            targetStrength: targetStrength,
            activityOverride: activityOverride,
            currentOutput: currentOutput
        )
        nightShift.applyWorkspacePolicyDecision(decision)
    }

    private func schedulePeriodicRefresh() {
        updateTimer?.invalidate()
        updateTimer = refreshScheduler.scheduleRepeating(every: 60) { [weak self] in
            DispatchQueue.main.async { self?.applyNow() }
        }
    }

    private func strength(fromKelvin kelvin: Int) -> Float {
        let configuration = transition.configuration
        let minimumKelvin = min(configuration.deepNightKelvin, configuration.daylightKelvin)
        let maximumKelvin = max(configuration.deepNightKelvin, configuration.daylightKelvin)
        let clampedKelvin = min(max(kelvin, minimumKelvin), maximumKelvin)
        let span = max(Double(maximumKelvin - minimumKelvin), 1)
        let normalised = 1 - (Double(clampedKelvin - minimumKelvin) / span)
        return Float(min(max(normalised, 0), 1))
    }
}
