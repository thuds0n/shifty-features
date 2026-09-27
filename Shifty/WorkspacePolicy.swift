import Foundation

struct WorkspaceOutputState: Equatable {
    var isNightShiftEnabled: Bool
    var colorTemperature: Float
}

enum WorkspacePolicyDecision: Equatable {
    case noChange
    case applyStrength(Float)
}

// MARK: - Night Shift strength policy

/// Every input that can change Night Shift's strength.
struct NightShiftStrengthInputs: Equatable {
    /// Night Shift is on (so not paused, disabled by a rule or switched off).
    var isNightShiftOn: Bool
    var isCircadianEnabled: Bool
    /// A video app is in front, so strength changes would be visible mid-playback.
    var isActivitySuspended: Bool
    /// The user set a strength by hand and it holds until the next phase change.
    var isManualStrengthHeld: Bool
    /// The strength the circadian schedule wants now.
    var circadianTarget: Float
}

/// Resolves Night Shift strength from every state source, in one place.
///
/// Precedence, highest first:
/// 1. While Night Shift is off or paused, strength is left alone.
/// 2. A hand-set strength holds until the next circadian phase change.
/// 3. A foreground video app holds the current strength.
/// 4. Circadian Mode applies its target.
/// 5. Otherwise the user's strength is left alone.
enum NightShiftStrengthPolicy {
    static func decision(for inputs: NightShiftStrengthInputs) -> WorkspacePolicyDecision {
        guard
            inputs.isNightShiftOn,
            !inputs.isManualStrengthHeld,
            !inputs.isActivitySuspended,
            inputs.isCircadianEnabled
        else {
            return .noChange
        }
        return .applyStrength(inputs.circadianTarget)
    }
}

// MARK: - Night Shift on/off policy

/// Who decides whether Night Shift is on.
enum NightShiftOutput: Equatable {
    case on
    case off
    /// Hand control back to the macOS Night Shift schedule.
    case followSchedule
}

/// Every input that can turn Night Shift on or off.
struct NightShiftPolicyInputs: Equatable {
    /// A timed pause is running (menu, Shortcuts action, shortcut or CLI).
    var isPaused: Bool
    /// An app or website rule is disabling Night Shift for the current context.
    var isDisableRuleActive: Bool
    /// The user's last manual on/off choice since the schedule last started or ended.
    var manualOverride: UserSet
}

/// Resolves Night Shift on/off from every state source, in one place.
///
/// Precedence, highest first:
/// 1. A pause turns Night Shift off.
/// 2. An app or website disable rule turns it off. A subdomain exception is
///    already folded into `isDisableRuleActive` by `RuleManager`.
/// 3. A manual on/off holds until the next scheduled start or end.
/// 4. Otherwise the macOS schedule decides.
enum NightShiftPolicy {
    static func output(for inputs: NightShiftPolicyInputs) -> NightShiftOutput {
        if inputs.isPaused || inputs.isDisableRuleActive {
            return .off
        }
        switch inputs.manualOverride {
        case .on:
            return .on
        case .off:
            return .off
        case .notSet:
            return .followSchedule
        }
    }
}

// MARK: - Strength ramp

/// Runs a sequence of ramp steps over time. Injected so tests can run steps immediately.
protocol StrengthRampScheduling: AnyObject {
    /// Calls `step` for each value in order, `interval` apart, stopping early when it
    /// returns false. Returns a handle that cancels the remaining steps.
    func run(_ values: [Float], interval: TimeInterval, step: @escaping (Float) -> Bool) -> WorkspaceRefreshTimer
}

final class TimerStrengthRampScheduler: StrengthRampScheduling {
    func run(_ values: [Float], interval: TimeInterval, step: @escaping (Float) -> Bool) -> WorkspaceRefreshTimer {
        var remaining = values[...]
        let timer = Timer(timeInterval: interval, repeats: true) { timer in
            guard let value = remaining.popFirst(), step(value), !remaining.isEmpty else {
                timer.invalidate()
                return
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}

/// Fades circadian strength changes instead of jumping, so launches, phase boundaries
/// and the end of a hold don't visibly snap the display's colour.
enum StrengthRamp {
    static let duration: TimeInterval = 3
    static let stepInterval: TimeInterval = 1.0 / 30
    /// Changes smaller than this are applied directly; the minute-by-minute circadian
    /// updates fall well under it.
    static let threshold: Float = 0.02

    /// The intermediate values from `start` to `end`, ending exactly on `end`.
    /// Empty when the change is small enough to apply directly.
    static func values(from start: Float, to end: Float) -> [Float] {
        guard abs(end - start) >= threshold else { return [] }
        let count = Int((duration / stepInterval).rounded())
        return (1...count).map { index in
            let t = Float(index) / Float(count)
            let eased = t * t * (3 - 2 * t)
            return index == count ? end : start + ((end - start) * eased)
        }
    }
}
