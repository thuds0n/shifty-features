import Foundation

struct WorkspaceOutputState: Equatable {
    var isNightShiftEnabled: Bool
    var colorTemperature: Float
}

enum WorkspacePolicyDecision: Equatable {
    case noChange
    case applyStrength(Float)
}

/// Decides the circadian strength. Pauses and on/off are owned by `NightShiftPolicy`:
/// a paused or disabled Night Shift is simply left alone here.
final class WorkspacePolicy {
    func decision(
        isCircadianEnabled: Bool,
        targetStrength: Float,
        activityOverride: ActivityOverrideSnapshot,
        currentOutput: WorkspaceOutputState
    ) -> WorkspacePolicyDecision {
        guard isCircadianEnabled, !activityOverride.isSuspended, currentOutput.isNightShiftEnabled else {
            return .noChange
        }
        return .applyStrength(targetStrength)
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
