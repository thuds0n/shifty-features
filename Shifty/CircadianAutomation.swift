import Foundation

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
