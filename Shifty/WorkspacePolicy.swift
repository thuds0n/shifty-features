import Foundation

struct WorkspaceOutputState: Equatable {
    var isNightShiftEnabled: Bool
    var colorTemperature: Float
}

enum WorkspacePolicyDecision: Equatable {
    case noChange
    case applyStrength(Float)
    case neutralise
    case restore(WorkspaceOutputState)
}

/// Resolves circadian output and temporary activity overrides without changing
/// the user's persistent Night Shift intent.
final class WorkspacePolicy {
    private var suspendedOutput: WorkspaceOutputState?

    func decision(
        isCircadianEnabled: Bool,
        targetStrength: Float,
        activityOverride: ActivityOverrideSnapshot,
        currentOutput: WorkspaceOutputState
    ) -> WorkspacePolicyDecision {
        guard isCircadianEnabled else {
            return restoreSuspendedOutputIfNeeded() ?? .noChange
        }

        if activityOverride.isSuspended, activityOverride.reason == .temporaryPause {
            if suspendedOutput == nil {
                suspendedOutput = currentOutput
            }
            return currentOutput.isNightShiftEnabled ? .neutralise : .noChange
        }

        if activityOverride.isSuspended {
            return .noChange
        }

        if let restoration = restoreSuspendedOutputIfNeeded() {
            return restoration
        }

        guard currentOutput.isNightShiftEnabled else { return .noChange }
        return .applyStrength(targetStrength)
    }

    private func restoreSuspendedOutputIfNeeded() -> WorkspacePolicyDecision? {
        guard let suspendedOutput else { return nil }
        self.suspendedOutput = nil
        return .restore(suspendedOutput)
    }
}
