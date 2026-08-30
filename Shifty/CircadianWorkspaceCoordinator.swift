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
    private let clock: WorkspaceClock
    private let refreshScheduler: WorkspaceRefreshScheduling
    private let workspacePolicy: WorkspacePolicy

    private var updateTimer: WorkspaceRefreshTimer?
    private var previousAutomationState: CircadianAutomationState?
    private(set) var isRunning = false

    init(
        transition: CircadianTransitioning,
        activityOverride: ActivityOverrideManaging,
        automationBridge: CircadianAutomationBridging,
        nightShift: WorkspaceNightShiftControlling,
        modeStore: CircadianModeStoring = UserDefaultsCircadianModeStore(),
        clock: WorkspaceClock = SystemWorkspaceClock(),
        refreshScheduler: WorkspaceRefreshScheduling = FoundationWorkspaceRefreshScheduler(),
        workspacePolicy: WorkspacePolicy = WorkspacePolicy()
    ) {
        self.transition = transition
        self.activityOverride = activityOverride
        self.automationBridge = automationBridge
        self.nightShift = nightShift
        self.modeStore = modeStore
        self.clock = clock
        self.refreshScheduler = refreshScheduler
        self.workspacePolicy = workspacePolicy
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

        applyWorkspacePolicy(isCircadianEnabled: true, target: target, activityOverride: override)
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
