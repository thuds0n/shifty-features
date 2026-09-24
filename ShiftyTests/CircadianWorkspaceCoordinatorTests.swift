import XCTest
@testable import Shifty

final class CircadianWorkspaceCoordinatorTests: XCTestCase {
    @MainActor
    func testStartIsIdempotentAndSchedulesARefresh() {
        let fixture = makeFixture()

        fixture.coordinator.start()
        fixture.coordinator.start()

        XCTAssertTrue(fixture.coordinator.isRunning)
        XCTAssertEqual(fixture.activity.startCount, 1)
        XCTAssertEqual(fixture.scheduler.intervals, [60])
        XCTAssertEqual(fixture.backend.decisions, [.applyStrength(1)])
        XCTAssertEqual(fixture.automation.published.count, 1)
    }

    @MainActor
    func testStopTearsDownActivityAndRefreshTimer() {
        let fixture = makeFixture()
        fixture.coordinator.start()

        fixture.coordinator.stop()

        XCTAssertFalse(fixture.coordinator.isRunning)
        XCTAssertEqual(fixture.activity.stopCount, 1)
        XCTAssertNil(fixture.activity.onChange)
        XCTAssertTrue(fixture.scheduler.timers[0].isInvalidated)
    }

    @MainActor
    func testTemporaryPauseNeutralisesThenRestoresExactOutput() {
        let originalOutput = WorkspaceOutputState(isNightShiftEnabled: true, colorTemperature: 0.64)
        let fixture = makeFixture(output: originalOutput)
        fixture.activity.currentOverride = ActivityOverrideSnapshot(
            isSuspended: true,
            reason: .temporaryPause,
            until: fixture.clock.now.addingTimeInterval(300)
        )

        fixture.coordinator.applyNow()
        fixture.activity.currentOverride = .none
        fixture.coordinator.applyNow()

        XCTAssertEqual(fixture.backend.decisions, [.neutralise, .restore(originalOutput)])
        XCTAssertEqual(fixture.backend.currentWorkspaceOutput, originalOutput)
    }

    @MainActor
    func testDisabledModeDoesNotPublishAutomationOrChangeOutput() {
        let fixture = makeFixture(isEnabled: false)

        fixture.coordinator.applyNow()

        XCTAssertEqual(fixture.backend.decisions, [.noChange])
        XCTAssertTrue(fixture.automation.published.isEmpty)
    }

    @MainActor
    func testCLIStateAndToggleUseInjectedConfigurationAndClock() {
        let fixture = makeFixture(isEnabled: false)

        let response = fixture.coordinator.handleCLICommand(.toggleEnabled, payload: [:])

        XCTAssertTrue(fixture.modeStore.isCircadianModeEnabled)
        XCTAssertEqual(response?["circadianEnabled"] as? Bool, true)
        XCTAssertEqual(response?["phase"] as? String, CircadianPhase.deepNight.rawValue)
        XCTAssertEqual(fixture.transition.requestedDates, [fixture.clock.now, fixture.clock.now])
        XCTAssertTrue(PropertyListSerialization.propertyList(response as Any, isValidFor: .binary))
    }

    @MainActor
    func testStoredConfigurationIsLoadedIntoTheTransitionAtInit() {
        var configuration = CircadianCurveConfiguration.default
        configuration.bedtime = DateComponents(hour: 22, minute: 30)

        let fixture = makeFixture(configuration: configuration)

        XCTAssertEqual(fixture.transition.configuration, configuration)
        XCTAssertEqual(fixture.coordinator.configuration, configuration)
    }

    @MainActor
    func testUpdatingConfigurationValidatesPersistsAndApplies() {
        let fixture = makeFixture()
        var configuration = CircadianCurveConfiguration.default
        configuration.bedtime = DateComponents(hour: 22, minute: 0)
        configuration.deepNightKelvin = 1000

        fixture.coordinator.updateConfiguration(configuration)

        let expected = configuration.validated()
        XCTAssertEqual(expected.deepNightKelvin, CircadianCurveConfiguration.kelvinRange.lowerBound)
        XCTAssertEqual(fixture.configurationStore.configuration, expected)
        XCTAssertEqual(fixture.transition.configuration, expected)
        XCTAssertEqual(fixture.transition.requestedDates, [fixture.clock.now])
    }

    @MainActor
    func testCurrentStatusReportsTargetNextTransitionAndSuspension() {
        let fixture = makeFixture()
        fixture.activity.currentOverride = ActivityOverrideSnapshot(isSuspended: true, reason: nil, until: nil)

        let status = fixture.coordinator.currentStatus()

        XCTAssertEqual(status.target.phase, .deepNight)
        XCTAssertEqual(status.nextTransition, CircadianTransition(phase: .daylight, date: fixture.clock.now.addingTimeInterval(3600)))
        XCTAssertTrue(status.isSuspended)
    }

    @MainActor
    private func makeFixture(
        isEnabled: Bool = true,
        configuration: CircadianCurveConfiguration = .default,
        output: WorkspaceOutputState = WorkspaceOutputState(isNightShiftEnabled: true, colorTemperature: 0.3)
    ) -> Fixture {
        let transition = FakeCircadianTransition()
        let activity = FakeActivityOverrideManager()
        let automation = FakeAutomationBridge()
        let backend = FakeNightShiftBackend(output: output)
        let modeStore = FakeCircadianModeStore(isEnabled: isEnabled)
        let configurationStore = FakeCircadianConfigurationStore(configuration: configuration)
        let clock = FakeWorkspaceClock(now: Date(timeIntervalSince1970: 1_786_258_800))
        let scheduler = FakeRefreshScheduler()
        let coordinator = CircadianWorkspaceCoordinator(
            transition: transition,
            activityOverride: activity,
            automationBridge: automation,
            nightShift: backend,
            modeStore: modeStore,
            configurationStore: configurationStore,
            clock: clock,
            refreshScheduler: scheduler
        )
        return Fixture(
            coordinator: coordinator,
            transition: transition,
            activity: activity,
            automation: automation,
            backend: backend,
            modeStore: modeStore,
            configurationStore: configurationStore,
            clock: clock,
            scheduler: scheduler
        )
    }
}

private struct Fixture {
    let coordinator: CircadianWorkspaceCoordinator
    let transition: FakeCircadianTransition
    let activity: FakeActivityOverrideManager
    let automation: FakeAutomationBridge
    let backend: FakeNightShiftBackend
    let modeStore: FakeCircadianModeStore
    let configurationStore: FakeCircadianConfigurationStore
    let clock: FakeWorkspaceClock
    let scheduler: FakeRefreshScheduler
}

private final class FakeCircadianTransition: CircadianTransitioning {
    var configuration = CircadianCurveConfiguration.default
    private(set) var requestedDates = [Date]()

    func target(for date: Date) -> CircadianTarget {
        requestedDates.append(date)
        return CircadianTarget(phase: .deepNight, kelvin: configuration.deepNightKelvin, phaseProgress: 1)
    }

    func nextTransition(after date: Date) -> CircadianTransition? {
        CircadianTransition(phase: .daylight, date: date.addingTimeInterval(3600))
    }
}

private final class FakeCircadianConfigurationStore: CircadianConfigurationStoring {
    var configuration: CircadianCurveConfiguration

    init(configuration: CircadianCurveConfiguration) {
        self.configuration = configuration
    }
}

private final class FakeActivityOverrideManager: ActivityOverrideManaging {
    var currentOverride = ActivityOverrideSnapshot.none
    var onChange: ((ActivityOverrideSnapshot) -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start() { startCount += 1 }
    func stop() { stopCount += 1 }

    func setTemporaryPause(minutes: Int) {
        currentOverride = ActivityOverrideSnapshot(isSuspended: true, reason: .temporaryPause, until: nil)
    }

    func clearTemporaryPause() {
        currentOverride = .none
    }
}

private final class FakeAutomationBridge: CircadianAutomationBridging {
    private(set) var published = [CircadianAutomationState]()
    private(set) var transitions = [(CircadianAutomationState?, CircadianAutomationState)]()

    func publish(state: CircadianAutomationState) {
        published.append(state)
    }

    func triggerDeepNightSceneIfNeeded(previous: CircadianAutomationState?, current: CircadianAutomationState) {
        transitions.append((previous, current))
    }
}

private final class FakeNightShiftBackend: WorkspaceNightShiftControlling {
    private(set) var currentWorkspaceOutput: WorkspaceOutputState
    private(set) var decisions = [WorkspacePolicyDecision]()

    init(output: WorkspaceOutputState) {
        currentWorkspaceOutput = output
    }

    func applyWorkspacePolicyDecision(_ decision: WorkspacePolicyDecision) {
        decisions.append(decision)
        switch decision {
        case .applyStrength(let strength):
            currentWorkspaceOutput.colorTemperature = strength
        case .neutralise:
            currentWorkspaceOutput.isNightShiftEnabled = false
        case .restore(let output):
            currentWorkspaceOutput = output
        case .noChange:
            break
        }
    }
}

private final class FakeCircadianModeStore: CircadianModeStoring {
    var isCircadianModeEnabled: Bool

    init(isEnabled: Bool) {
        isCircadianModeEnabled = isEnabled
    }
}

private final class FakeWorkspaceClock: WorkspaceClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}

private final class FakeRefreshTimer: WorkspaceRefreshTimer {
    private(set) var isInvalidated = false

    func invalidate() {
        isInvalidated = true
    }
}

private final class FakeRefreshScheduler: WorkspaceRefreshScheduling {
    private(set) var intervals = [TimeInterval]()
    private(set) var timers = [FakeRefreshTimer]()
    private(set) var actions = [() -> Void]()

    func scheduleRepeating(every interval: TimeInterval, action: @escaping () -> Void) -> WorkspaceRefreshTimer {
        let timer = FakeRefreshTimer()
        intervals.append(interval)
        timers.append(timer)
        actions.append(action)
        return timer
    }
}
