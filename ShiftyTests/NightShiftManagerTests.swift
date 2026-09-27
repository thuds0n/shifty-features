import XCTest
@testable import Shifty

final class NightShiftManagerTests: XCTestCase {
    private var defaults: UserDefaults { UserDefaults.standard }

    override func setUp() {
        super.setUp()
        defaults.set(false, forKey: Keys.trueToneControl)
        defaults.set(false, forKey: Keys.isDarkModeSyncEnabled)
    }

    func testUserEnabledNightShiftSetsClientStateAndUserSet() {
        let client = FakeNightShiftClient()
        let manager = NightShiftManager(client: client)

        manager.respond(to: .userEnabledNightShift)

        XCTAssertEqual(manager.userSet, .on)
        XCTAssertEqual(manager.nightShiftDisableTimerState, .off)
        XCTAssertEqual(client.setNightShiftEnabledCalls.last, true)
    }

    func testUserDisabledNightShiftSetsClientStateAndUserSet() {
        let client = FakeNightShiftClient()
        let manager = NightShiftManager(client: client)

        manager.respond(to: .userDisabledNightShift)

        XCTAssertEqual(manager.userSet, .off)
        XCTAssertEqual(client.setNightShiftEnabledCalls.last, false)
    }

    func testDisableRuleDeactivatedRestoresScheduleWhenUserNotSet() {
        let client = FakeNightShiftClient()
        let manager = NightShiftManager(client: client)
        manager.userSet = .notSet
        manager.nightShiftDisableTimerState = .off

        manager.respond(to: .nightShiftDisableRuleDeactivated)

        XCTAssertEqual(client.setToScheduleCallCount, 1)
    }

    func testInvalidatingDisableTimerCancelsItsLaterRestoreEvent() {
        let client = FakeNightShiftClient()
        let manager = NightShiftManager(client: client)
        let timerStarted = expectation(description: "Disable timer started")

        manager.setDisableTimer(forTimeInterval: 0.1)
        DispatchQueue.main.async {
            timerStarted.fulfill()
        }
        wait(for: [timerStarted], timeout: 1)

        manager.invalidateDisableTimer()

        XCTAssertNil(manager.nightShiftDisableTimer)
        XCTAssertEqual(manager.nightShiftDisableTimerState, .off)
        XCTAssertEqual(client.setToScheduleCallCount, 1)

        let timerWouldHaveFired = expectation(description: "Cancelled timer did not fire")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            timerWouldHaveFired.fulfill()
        }
        wait(for: [timerWouldHaveFired], timeout: 1)

        XCTAssertEqual(client.setToScheduleCallCount, 1)
    }

    // MARK: Policy precedence

    func testPolicyPrecedence() {
        func output(paused: Bool = false, rule: Bool = false, manual: UserSet = .notSet) -> NightShiftOutput {
            NightShiftPolicy.output(for: NightShiftPolicyInputs(isPaused: paused, isDisableRuleActive: rule, manualOverride: manual))
        }

        XCTAssertEqual(output(), .followSchedule)
        XCTAssertEqual(output(manual: .on), .on)
        XCTAssertEqual(output(manual: .off), .off)
        XCTAssertEqual(output(rule: true, manual: .on), .off, "A rule outranks a manual on")
        XCTAssertEqual(output(paused: true, manual: .on), .off, "A pause outranks a manual on")
        XCTAssertEqual(output(paused: true, rule: true), .off)
    }

    // MARK: Reconciliation

    func testScheduleStartDuringAPauseIsForcedBackOff() {
        let client = FakeNightShiftClient()
        let manager = NightShiftManager(client: client)
        manager.nightShiftDisableTimerState = .custom(endDate: Date().addingTimeInterval(600))
        manager.respond(to: .nightShiftDisableTimerStarted)

        client.isNightShiftEnabled = true
        client.scheduledState = true
        manager.respond(to: .enteredScheduledNightShift)

        XCTAssertEqual(client.setNightShiftEnabledCalls.last, false)
        XCTAssertFalse(client.isNightShiftEnabled)
    }

    func testUnchangedDecisionDoesNotCallCoreBrightnessAgain() {
        let client = FakeNightShiftClient()
        let manager = NightShiftManager(client: client)

        manager.respond(to: .userDisabledNightShift)
        manager.respond(to: .nightShiftEnableRuleDeactivated)
        manager.respond(to: .nightShiftDisableRuleDeactivated)

        XCTAssertEqual(client.setNightShiftEnabledCalls, [false])
        XCTAssertEqual(client.setToScheduleCallCount, 0)
    }

    func testScheduleChangeAlwaysHandsControlBackToTheSchedule() {
        let client = FakeNightShiftClient()
        let manager = NightShiftManager(client: client)
        manager.respond(to: .nightShiftDisableRuleDeactivated)

        manager.respond(to: .scheduleChanged)

        XCTAssertEqual(manager.userSet, .notSet)
        XCTAssertEqual(client.setToScheduleCallCount, 2)
    }

    func testTurningNightShiftOnCancelsARunningPause() {
        let client = FakeNightShiftClient()
        let manager = NightShiftManager(client: client)
        let timerStarted = expectation(description: "Disable timer started")
        manager.setDisableTimer(forTimeInterval: 600)
        DispatchQueue.main.async { timerStarted.fulfill() }
        wait(for: [timerStarted], timeout: 1)

        manager.respond(to: .userEnabledNightShift)

        XCTAssertNil(manager.nightShiftDisableTimer)
        XCTAssertEqual(manager.nightShiftDisableTimerState, .off)
        XCTAssertEqual(client.setNightShiftEnabledCalls.last, true)
    }

    func testPauseHoldsAgainstOtherEventsAndEndsBackOnTheManualChoice() {
        let client = FakeNightShiftClient()
        let manager = NightShiftManager(client: client)
        manager.respond(to: .userEnabledNightShift)
        let paused = expectation(description: "Pause started")
        manager.pause(for: 600)
        DispatchQueue.main.async { paused.fulfill() }
        wait(for: [paused], timeout: 1)
        XCTAssertTrue(manager.isPaused)
        XCTAssertFalse(client.isNightShiftEnabled)

        manager.respond(to: .nightShiftDisableRuleDeactivated)
        XCTAssertFalse(client.isNightShiftEnabled, "Other events must not end the pause early")

        manager.resumeFromPause()
        XCTAssertFalse(manager.isPaused)
        XCTAssertTrue(client.isNightShiftEnabled, "The manual on made before the pause still applies")
    }

    // MARK: Strength ramp

    func testRampEasesToTheExactTargetAndSkipsSmallChanges() {
        let values = StrengthRamp.values(from: 0.2, to: 0.8)
        XCTAssertEqual(values.count, 90)
        XCTAssertEqual(values.last, 0.8)
        XCTAssertEqual(values, values.sorted(), "Moves in one direction")
        XCTAssertTrue(StrengthRamp.values(from: 0.5, to: 0.51).isEmpty)
    }

    func testLargeStrengthChangeFadesWithPreviewsAndCommitsOnce() {
        let client = FakeNightShiftClient()
        client.isNightShiftEnabled = true
        client.colorTemperature = 0.2
        client.clearRecordedWrites()
        let manager = NightShiftManager(client: client, rampScheduler: ImmediateRampScheduler())

        manager.applyWorkspacePolicyDecision(.applyStrength(0.8))

        XCTAssertEqual(client.previewValues.count, 89)
        XCTAssertEqual(client.colorTemperature, 0.8)
        XCTAssertEqual(client.colorTemperatureWrites, [0.8])
    }

    func testSmallStrengthChangeIsAppliedDirectly() {
        let client = FakeNightShiftClient()
        client.isNightShiftEnabled = true
        client.colorTemperature = 0.5
        client.clearRecordedWrites()
        let manager = NightShiftManager(client: client, rampScheduler: ImmediateRampScheduler())

        manager.applyWorkspacePolicyDecision(.applyStrength(0.51))

        XCTAssertTrue(client.previewValues.isEmpty)
        XCTAssertEqual(client.colorTemperatureWrites, [0.51])
    }

    func testFadeStopsWhenNightShiftTurnsOff() {
        let client = FakeNightShiftClient()
        client.isNightShiftEnabled = true
        client.colorTemperature = 0.2
        client.onPreview = { if client.previewValues.count == 10 { client.isNightShiftEnabled = false } }
        client.clearRecordedWrites()
        let manager = NightShiftManager(client: client, rampScheduler: ImmediateRampScheduler())

        manager.applyWorkspacePolicyDecision(.applyStrength(0.8))

        XCTAssertEqual(client.previewValues.count, 10)
        XCTAssertTrue(client.colorTemperatureWrites.isEmpty, "An interrupted fade commits nothing")
    }
}

private final class FakeNightShiftClient: NightShiftSystemControlling {
    var supportsNightShift: Bool = true
    var isNightShiftEnabled: Bool = false
    var colorTemperature: Float = 0 {
        didSet { colorTemperatureWrites.append(colorTemperature) }
    }
    private(set) var colorTemperatureWrites: [Float] = []
    private(set) var previewValues: [Float] = []
    var onPreview: (() -> Void)?

    func clearRecordedWrites() {
        colorTemperatureWrites.removeAll()
    }
    var schedule: ScheduleType = .off
    var scheduledState: Bool = false

    private(set) var setNightShiftEnabledCalls: [Bool] = []
    private(set) var setToScheduleCallCount: Int = 0

    func previewColorTemperature(_ value: Float) {
        previewValues.append(value)
        onPreview?()
    }

    func setNightShiftEnabled(_ newValue: Bool) {
        isNightShiftEnabled = newValue
        setNightShiftEnabledCalls.append(newValue)
    }

    func setToSchedule() {
        setToScheduleCallCount += 1
    }

    func setStatusNotificationBlock(_ block: @escaping () -> Void) {
        _ = block
    }
}

private final class ImmediateRampScheduler: StrengthRampScheduling {
    private final class Handle: WorkspaceRefreshTimer {
        func invalidate() {}
    }

    func run(_ values: [Float], interval: TimeInterval, step: @escaping (Float) -> Bool) -> WorkspaceRefreshTimer {
        for value in values where !step(value) {
            break
        }
        return Handle()
    }
}
