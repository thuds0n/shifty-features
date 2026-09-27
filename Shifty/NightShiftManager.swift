//
//  NightShiftManager.swift
//  Shifty
//
//  Created by Saagar Jha on 1/13/18.
//

import Cocoa


class NightShiftManager {
    static let shared = NightShiftManager()
    let integrations = SystemIntegration.shared
    let client: NightShiftSystemControlling
    
    var nightShiftChangeListeners = [() -> Void]()

    var userSet: UserSet = .notSet
    var userInitiatedShift = false
    
    static var supportsNightShift: Bool {
        SystemIntegration.shared.nightShiftSystem.supportsNightShift
    }
    
    var isNightShiftEnabled: Bool {
        get {
            client.isNightShiftEnabled
        }
        set {
            setNightShiftEnabled(to: newValue)
        }
    }
    
    var colorTemperature: Float {
        get {
            client.colorTemperature
        }
        set {
            // A direct change (slider, shortcut, Shortcuts action) wins over a fade in progress.
            cancelStrengthRamp()
            client.colorTemperature = newValue
        }
    }

    private let rampScheduler: StrengthRampScheduling
    private var strengthRamp: WorkspaceRefreshTimer?
    
    var schedule: ScheduleType {
        get {
            client.schedule
        }
        set {
            client.schedule = newValue
        }
    }
    
    var nightShiftDisableTimerState = DisableTimer.off
    var nightShiftDisableTimer: Timer? {
        willSet {
            if let timer = nightShiftDisableTimer {
                timer.invalidate()
            }
        }
    }
    
    var isDisabledWithTimer: Bool {
        return nightShiftDisableTimerState != .off
    }

    /// The output last sent to CoreBrightness, so unchanged decisions aren't re-applied.
    private var appliedOutput: NightShiftOutput?

    var policyInputs: NightShiftPolicyInputs {
        NightShiftPolicyInputs(
            isPaused: isDisabledWithTimer,
            isDisableRuleActive: isDisableRuleActive,
            manualOverride: userSet)
    }
    
    /// When true, app or website rule has disabled Night Shift
    var isDisableRuleActive: Bool {
        return RuleManager.shared.disableRuleIsActive
    }

    init(
        client: NightShiftSystemControlling = SystemIntegration.shared.nightShiftSystem,
        rampScheduler: StrengthRampScheduling = TimerStrengthRampScheduler()
    ) {
        self.client = client
        self.rampScheduler = rampScheduler
        var prevSchedule = client.schedule
        
        updateDarkMode()
        
        // @convention block called by CoreBrightness
        client.setStatusNotificationBlock {
            if self.schedule == prevSchedule {
                self.respond(to: self.isNightShiftEnabled
                        ? .enteredScheduledNightShift : .exitedScheduledNightShift)
            } else {
                self.respond(to: .scheduleChanged)
                prevSchedule = self.client.schedule
            }
            
            self.updateDarkMode()
            
            for listener in self.nightShiftChangeListeners {
                DispatchQueue.main.async {
                    listener()
                }
            }
        }
        
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: nil) { _ in
            logw("Wake from sleep notification posted")
            
            if self.client.scheduledState != self.client.isNightShiftEnabled
            {
                self.respond(to: self.client.scheduledState
                        ? .enteredScheduledNightShift : .exitedScheduledNightShift)
            }
            
            self.updateDarkMode()
        }
    }
    
    func onNightShiftChange(_ listener: @escaping () -> Void) {
        nightShiftChangeListeners.append(listener)
    }
    
    func updateDarkMode() {
        if UserDefaults.standard.bool(forKey: Keys.isDarkModeSyncEnabled) {
            let scheduledState = client.scheduledState
            
            switch client.schedule {
            case .off:
                let darkModeState = isNightShiftEnabled || isDisableRuleActive || isDisabledWithTimer || userSet == .on
                integrations.appearance.darkModeEnabled = darkModeState
                logw("Dark mode set to \(darkModeState)")
            case .solar:
                integrations.appearance.darkModeEnabled = scheduledState
                logw("Dark mode set to \(scheduledState)")
            case .custom(start: _, end: _):
                integrations.appearance.darkModeEnabled = scheduledState
                logw("Dark mode set to \(scheduledState)")
            }
        }
    }
    
    func setNightShiftEnabled(to state: Bool) {
        respond(to: state ? .userEnabledNightShift : .userDisabledNightShift)
    }

    func previewColorTemperature(_ value: Float) {
        client.previewColorTemperature(value)
    }

    /// Records what an event changed, then applies the single policy decision.
    func respond(to event: NightShiftEvent) {
        // CoreBrightness reports every change, including the ones Shifty just made.
        // `reconcile` flags those so their echo isn't mistaken for a schedule change.
        if event == .enteredScheduledNightShift || event == .exitedScheduledNightShift {
            if userInitiatedShift {
                userInitiatedShift = false
                return
            }
        }

        switch event {
        case .enteredScheduledNightShift, .exitedScheduledNightShift, .scheduleChanged:
            userSet = .notSet
        case .userEnabledNightShift:
            userSet = .on
            cancelDisableTimer()
            if isDisableRuleActive {
                RuleManager.shared.removeRulesForCurrentState()
            }
        case .userDisabledNightShift:
            userSet = .off
        case .nightShiftDisableRuleActivated:
            if UserDefaults.standard.bool(forKey: Keys.trueToneControl) {
                integrations.trueTone.isEnabled = false
            }
        case .nightShiftDisableRuleDeactivated:
            if !isDisableRuleActive && UserDefaults.standard.bool(forKey: Keys.trueToneControl) {
                integrations.trueTone.isEnabled = true
            }
        case .nightShiftEnableRuleActivated, .nightShiftEnableRuleDeactivated,
             .nightShiftDisableTimerStarted, .nightShiftDisableTimerEnded:
            break
        }

        reconcile(force: event == .scheduleChanged)
        logw("Responded to event: \(event)")
    }

    /// Applies `NightShiftPolicy` to CoreBrightness when the decision changes, or when
    /// the system has drifted from a forced on/off (for example, a schedule start
    /// during a pause).
    private func reconcile(force: Bool = false) {
        let output = NightShiftPolicy.output(for: policyInputs)
        let expectedState: Bool
        switch output {
        case .on:
            expectedState = true
        case .off:
            expectedState = false
        case .followSchedule:
            expectedState = client.scheduledState
        }

        let clientMatches = output == .followSchedule || client.isNightShiftEnabled == expectedState
        guard force || output != appliedOutput || !clientMatches else { return }
        appliedOutput = output

        if client.isNightShiftEnabled != expectedState {
            userInitiatedShift = true
        }
        switch output {
        case .on:
            client.setNightShiftEnabled(true)
        case .off:
            client.setNightShiftEnabled(false)
        case .followSchedule:
            client.setToSchedule()
        }
    }
    
    
    func setDisableTimer(forTimeInterval timeInterval: TimeInterval) {
        DispatchQueue.main.async {
            let disableTimer = Timer.scheduledTimer(
                withTimeInterval: timeInterval,
                repeats: false,
                block: { _ in
                    self.nightShiftDisableTimer = nil
                    self.nightShiftDisableTimerState = .off
                    self.respond(to: .nightShiftDisableTimerEnded)
                })
            
            // For longer timers, increase the tolerance to save resources
            if timeInterval > 1800 {
                disableTimer.tolerance = 60
            } else if timeInterval > 300 {
                disableTimer.tolerance = 10
            }
            
            if timeInterval.rounded() == 3600 {
                self.nightShiftDisableTimerState = .hour(endDate: disableTimer.fireDate)
            } else {
                self.nightShiftDisableTimerState = .custom(endDate: disableTimer.fireDate)
            }
            
            self.nightShiftDisableTimer = disableTimer
            self.respond(to: .nightShiftDisableTimerStarted)
        }
    }
    
    func invalidateDisableTimer() {
        guard cancelDisableTimer() else { return }
        respond(to: .nightShiftDisableTimerEnded)
    }

    /// Stops any running pause timer without reapplying the policy.
    @discardableResult
    private func cancelDisableTimer() -> Bool {
        guard nightShiftDisableTimer != nil || nightShiftDisableTimerState != .off else { return false }
        nightShiftDisableTimer = nil
        nightShiftDisableTimerState = .off
        return true
    }

    func applyWorkspacePolicyDecision(_ decision: WorkspacePolicyDecision) {
        switch decision {
        case .noChange:
            return
        case .applyStrength(let strength):
            rampStrength(to: strength)
        }
    }

    /// Fades to `target` using previews for the in-between steps and commits only the
    /// final value. The fade stops if Night Shift turns off or pauses part-way through.
    private func rampStrength(to target: Float) {
        cancelStrengthRamp()
        let values = StrengthRamp.values(from: client.colorTemperature, to: target)
        guard !values.isEmpty else {
            client.colorTemperature = target
            return
        }
        strengthRamp = rampScheduler.run(values, interval: StrengthRamp.stepInterval) { [weak self] value in
            guard let self, self.client.isNightShiftEnabled else {
                self?.strengthRamp = nil
                return false
            }
            if value == values.last {
                self.client.colorTemperature = value
                self.strengthRamp = nil
            } else {
                self.client.previewColorTemperature(value)
            }
            return true
        }
    }

    private func cancelStrengthRamp() {
        strengthRamp?.invalidate()
        strengthRamp = nil
    }

    var isPaused: Bool {
        isDisabledWithTimer
    }

    func pause(for duration: TimeInterval) {
        setDisableTimer(forTimeInterval: duration)
    }

    func resumeFromPause() {
        invalidateDisableTimer()
    }
}

enum NightShiftEvent {
    case enteredScheduledNightShift
    case exitedScheduledNightShift
    case userEnabledNightShift
    case userDisabledNightShift
    case nightShiftDisableTimerStarted
    case nightShiftDisableTimerEnded
    case nightShiftDisableRuleActivated
    case nightShiftDisableRuleDeactivated
    case nightShiftEnableRuleActivated
    case nightShiftEnableRuleDeactivated
    case scheduleChanged
}

enum UserSet {
    case notSet
    case on
    case off
}

enum DisableTimer: Equatable {
    case off
    case hour(endDate: Date)
    case custom(endDate: Date)
}
